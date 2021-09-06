/// Normal from depth estimation
module dplug.gui.ransac;

import dplug.math.vector;
import dplug.core.math;

import inteli.emmintrin;

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

// Plane-fitting method for finding normals.
// This has superseded the previous "RANSAC" method, thanks to being much faster, and also gives better results thanks to being anisotropic.
// There could be a tiny bit of visual quality to be extracted by tuning sigma a bit. 
// Method from http://www.ilikebigbits.com/2015_03_04_plane_from_points.html
// Courtesy of Emil Ernerfeldt.
vec3f computePlaneFittingNormal(
    // Must point at 12 floats containing depth of pixels in the neighbourhood, and 3 more for padding. Normal will be computed in this pixel space.
    // c c c
    // c c c     <--- x is padding, and E is the center pixel depth
    // c c c 
    // x x x
    float* depthNeighbourhood) pure // number of inliers
{
    // sigma 0.6
    // use this page to change the filter: https://observablehq.com/@jobleonard/gaussian-kernel-calculater
    // Probably a tiny bit more visual quality to gain if tuning that sigma, but 0.7 looks worse.
    //static immutable float[3] sigma = [0.19858494730562265, 0.6028301053887546, 0.19858494730562265];
    align(16) static immutable float[8] WEIGHTS =
    [
        0.03943598129, 0.11971298471, 0.03943598129,
        0.11971298471, /* 0.36340413596, */ 0.11971298471,
        0.03943598129, 0.11971298471, 0.03943598129,
    ];

    __m128 mmDepth_0_3 = _mm_loadu_ps(&depthNeighbourhood[0]);
    __m128 mmDepth_5_8 = _mm_loadu_ps(&depthNeighbourhood[5]);
    __m128 mmWeights_0_3 = _mm_load_ps(&WEIGHTS[0]);
    __m128 mmWeights_5_8 = _mm_load_ps(&WEIGHTS[4]);
    __m128 meanDepth = mmDepth_0_3 * mmWeights_0_3 + mmDepth_5_8 * mmWeights_5_8;
    float filtDepth = depthNeighbourhood[4] * 0.36340413596f + meanDepth.array[0] + meanDepth.array[1] + meanDepth.array[2] + meanDepth.array[3];

    // PERF: eventually possible to take filtDepth = depthNeighbourhood[4] directly but at the cost of quality. Difficult tradeoff visually.

    // Compute mean weighted depth
    __m128 mmFiltDepth = _mm_set1_ps(filtDepth);

    mmDepth_0_3 = mmDepth_0_3 - mmFiltDepth;
    mmDepth_5_8 = mmDepth_5_8 - mmFiltDepth;
    
    // We are supposed to compute a full 3x3 covariance matrix, excluding symmetries.
    // However it simplifies a lot thanks to being a grid with known x and y.
    // Only xz and yz factors in the matrix need to be computed.

    align(16) static immutable float[8] XZ_WEIGHTS = // those are derived from the above WEIGHTS kernel
    [
        -0.03943598129,         0.0f, 0.03943598129,
        -0.11971298471,               0.11971298471,
        -0.03943598129,         0.0f, 0.03943598129,
    ];

    align(16) static immutable float[8] YZ_WEIGHTS = // those are derived from the above WEIGHTS kernel
    [
         -0.03943598129, -0.11971298471, -0.03943598129,
                   0.0f,                           0.0f,
          0.03943598129,  0.11971298471,  0.03943598129,
    ];

    __m128 mmXZ = mmDepth_0_3 * _mm_load_ps(&XZ_WEIGHTS[0]) + mmDepth_5_8 * _mm_load_ps(&XZ_WEIGHTS[4]);
    __m128 mmYZ = mmDepth_0_3 * _mm_load_ps(&YZ_WEIGHTS[0]) + mmDepth_5_8 * _mm_load_ps(&YZ_WEIGHTS[4]);


    float xz = mmXZ.array[0] + mmXZ.array[1] + mmXZ.array[2] + mmXZ.array[3];
    float yz = mmYZ.array[0] + mmYZ.array[1] + mmYZ.array[2] + mmYZ.array[3];

    // Y inversion happens here.
    __m128 mmNormal = _mm_setr_ps(-xz, 
                                   yz, 
                                   0.39716989458f, // this depends on sigma, expected value for xx * yy (4 * WEIGHTS[0] + 2 * WEIGHTS[1])
                                                   // Note that we use the normalization step to factor by xx (which is equal to yy)
                                   0.0f);
    mmNormal = _mm_fast_normalize_ps(mmNormal);
    return vec3f(mmNormal.array[0], mmNormal.array[1], mmNormal.array[2]);
}