/// Normal from depth estimation
module dplug.gui.ransac;

import gfm.math.vector;
import dplug.core.math;

import inteli.emmintrin;

alias RansacMode = int;

nothrow @nogc:


// Note: these functions should move to intel-intrinsics #BONUS

/// 4D dot product
package float _mm_dot_ps(__m128 a, __m128 b) pure
{
    __m128 m = a * b;
    return m.array[0] + m.array[1] + m.array[2] + m.array[3];
}

// Note: .w element is undefined
package __m128 _mm_crossproduct_ps(__m128 a, __m128 b) pure
{
    enum ubyte SHUF1 = _MM_SHUFFLE(3, 0, 2, 1);
    enum ubyte SHUF2 = _MM_SHUFFLE(3, 1, 0, 2);
    return _mm_sub_ps(
                      _mm_mul_ps(_mm_shuffle_ps!SHUF1(a, a), _mm_shuffle_ps!SHUF2(b, b)), 
                      _mm_mul_ps(_mm_shuffle_ps!SHUF2(a, a), _mm_shuffle_ps!SHUF1(b, b))
                      );
}

package __m128 _mm_reflectnormal_ps(__m128 normalA, __m128 normalB) pure // W must be zero
{
    __m128 dotBA = normalB * normalA;
    float sum = 2 * _mm_dot_ps(normalA, normalB);
    return normalA - _mm_set1_ps(sum) * normalB;
}

package __m128 _mm_fast_normalize_ps(__m128 v) pure
{
    __m128 squared = _mm_mul_ps(v, v);
    float squaredLength = squared.array[0] + squared.array[1] + squared.array[2] + squared.array[3];
    __m128 invRoot = _mm_rsqrt_ss(_mm_set_ss(squaredLength));
    invRoot = _mm_shuffle_ps!0(invRoot, invRoot);
    return _mm_mul_ps(v, invRoot);
}

/**
 * From 9 depth values centered on a pixels, compute a normal in this space using the RANSAC method.
 * From an idea from Maxime Boucher. Implementation by Andrey Penechko and Guillaume Piolat.
 */
vec3f computeRANSACNormal(
                          // Must point at 12 floats containing depth of pixels in the neighbourhood, and 3 more for padding. Normal will be computed in this pixel space.
                          // A B C
                          // D E F     <--- x is padding, and E is the center pixel depth
                          // G H I 
                          // x x x
                          float* depthNeighbourhood) pure // number of inliers
{
    immutable int[2][] LUT = depthSampleLUT;
    
    static immutable align(16) float[12] indexToX = [-1.0f, 0.0f, 1.0f, 
                                                     -1.0f, 0.0f, 1.0f, 
                                                     -1.0f, 0.0f, 1.0f,
                                                     0, 0, 0];
    static immutable align(16) float[12] indexToY = [-1.0f, -1.0f, -1.0f, 
                                                      0.0f,  0.0f,  0.0f, 
                                                      1.0f,  1.0f,  1.0f,
                                                         0,     0,    0];

    // Maximum plane distance for a point to be considered on that plane.
    enum float INLIER_THRESHOLD = 0.343f; // Tuned twice, not very easy

    __m128 accumulatedNormal = _mm_setzero_ps();

    foreach(size_t iter, int[2] indicies; LUT)
    {
        // plane point indicies upacked
        int i1 = indicies[0];
        int i2 = indicies[1];

        // x, y, z of plane points
        float x1 = indexToX[i1];
        float x2 = indexToX[i2];
        float y1 = indexToY[i1];
        float y2 = indexToY[i2];
        float z0 = depthNeighbourhood[4];
        float z1 = depthNeighbourhood[i1];
        float z2 = depthNeighbourhood[i2];

        __m128 vecA = _mm_setr_ps(x1, y1, z1 - z0, 0.0f);
        __m128 vecB = _mm_setr_ps(x2, y2, z2 - z0, 0.0f);
        __m128 planeNormal = _mm_crossproduct_ps(vecA, vecB);
        planeNormal.ptr[3] = 0;

        planeNormal = _mm_fast_normalize_ps(planeNormal);

        // distance from plane to origin (this could be any point of the 3)
        float planeOriginDistance = planeNormal.array[2] * z0;
        // check the distance between each of 9 points to the plane

        __m128 normalX = _mm_set1_ps(planeNormal.array[0]);
        __m128 normalY = _mm_set1_ps(planeNormal.array[1]);
        __m128 normalZ = _mm_set1_ps(planeNormal.array[2]);

        // Compute all dot products with 8 neibourhood points, and see which ones are on the plane
        __m128 depthAD = _mm_loadu_ps(&depthNeighbourhood[0]);
        __m128 mmX_AD = _mm_load_ps(&indexToX[0]); 
        __m128 mmY_AD = _mm_load_ps(&indexToY[0]);
        __m128 dotProductAD = _mm_add_ps( _mm_add_ps( _mm_mul_ps(normalX, mmX_AD), 
                                                      _mm_mul_ps(normalY, mmY_AD)),
                                         _mm_mul_ps(normalZ, depthAD));

        __m128 depthFG = _mm_loadu_ps(&depthNeighbourhood[5]);
        __m128 mmX_FG = _mm_loadu_ps(&indexToX[5]);
        __m128 mmY_FG = _mm_loadu_ps(&indexToY[5]);
        __m128 dotProductFG = _mm_add_ps( _mm_add_ps( _mm_mul_ps(normalX, mmX_FG), 
                                                      _mm_mul_ps(normalY, mmY_FG)),
                                          _mm_mul_ps(normalZ, depthFG));

        __m128 mmOriginDistance = _mm_set1_ps(planeOriginDistance);
        immutable __m128 absMask = _mm_castsi128_ps(_mm_set1_epi32(0x7fff_ffff));
        dotProductAD = _mm_and_ps(absMask, _mm_sub_ps(dotProductAD, mmOriginDistance));
        dotProductFG = _mm_and_ps(absMask, _mm_sub_ps(dotProductFG, mmOriginDistance));
   

        immutable __m128 mmThreshold = _mm_set1_ps(INLIER_THRESHOLD);

        immutable int isInlierAD = _mm_movemask_ps( _mm_cmplt_ps(dotProductAD, mmThreshold) ); // 0xffffffff where inlier
        immutable int isInlierFG = _mm_movemask_ps( _mm_cmplt_ps(dotProductFG, mmThreshold) );

        // now we have 3 4-bit numbers that give an outlier number each
        static immutable int[16] bitCount = [0, 1, 1, 2,  // 0 1 2 3
                                             1, 2, 2, 3,  // 4 5 6 7
                                             1, 2, 2, 3,  // 8 9 10 11
                                             2, 3, 3, 4]; // 12 13 14 15
        int numInliers = bitCount[isInlierAD] + bitCount[isInlierFG]; // Center point E is always on the plane

        assert(numInliers >= 2 && numInliers <= 8);

        // early exit
        if (numInliers == 8)
        {
            planeNormal.ptr[1] = -planeNormal.array[1];
            return vec3f(planeNormal.array[0], planeNormal.array[1], planeNormal.array[2]);
        }
        
        // These factors (n/N)^^exp sets the factor of non-linearity.
        // Full non-linearity is achieved with infinite exponent,
        // else it's a blend between most successful planes
        // Note: this can probably be tuned more BUT it's difficult
        static immutable float[7] confidenceFor_N_minus_3_inliners =
        [
            // Should not be zero, else it breaks normalization in case no plane ever scores more than 3 inliners (Issue #455)
            // Could also probably be tuned
            0.01f, 

            0.056879f,
            0.17242f,
            0.3299f,
            0.52279f,
            0.7469f,
            1.0f
        ];

        // Confidence that this is a good normal (0 to 1)
        float confidence = confidenceFor_N_minus_3_inliners[numInliers - 2];

        accumulatedNormal = accumulatedNormal + planeNormal * _mm_set1_ps(confidence);
    }
  

    // We iterated all kind of normals, use a weighted sum of them
    __m128 resultNormal = accumulatedNormal;
    resultNormal = _mm_fast_normalize_ps(resultNormal);

    // For some unknown reason Y is inverted, I guess it's because left-handed vs right-handed?
    resultNormal.ptr[1] = -resultNormal.array[1];

    return vec3f(resultNormal.array[0], resultNormal.array[1], resultNormal.array[2]);
}

// Look-up table for sampling 3 points out of 3x3 pixels
// 24 modes.
// All triangles here MUST be in clockwise order
// First item is always implicitely 4 (center pixel)
immutable int[2][12] depthSampleLUT = 
[
    // .#.
    // .##
    // ...
    // center and 2 middle points
    [3,1], // 000011010
    [1,5], // 000110010
    [7,3], // 010011000
    [5,7], // 010110000

    // ##.
    // .#.
    // ...
    // center, one middle point, one diagonal
    [0,1], // 000010011
    [3,0], // 000011001
    [1,2], // 000010110
    [2,5], // 000110100
    [6,3], // 001011000
    [5,8], // 100110000
    [7,6], // 011010000
    [8,7], // 110010000

// Adds a little something when enabled, but not the biggest limitation
/+
    // #..
    // .#.
    // #..
    // has center pixel
    [0,2], // 000010101
    [6,0], // 001010001
    [2,8], // 100010100
    [8,6], // 101010000

    // #..
    // .#.
    // .#.
    // has center pixel
    [0,5], // 000110001
    [7,0], // 010010001
    [6,1], // 001010010
    [1,8], // 100010010
    [3,2], // 000011100
    [2,7], // 010010100
    [8,3], // 100011000
    [5,6], // 001110000 
+/
];
