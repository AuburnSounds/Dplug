/// Normal from depth estimation
module dplug.gui.ransac;

import gfm.math.vector;
import dplug.core.math;



alias RansacMode = int;

nothrow @nogc:

/**
 * From 9 depth values centered on a pixels, compute a normal in this space using the RANSAC method.
 * From an idea from Maxime Boucher. Implementation by Andrey Penechko and Guillaume Piolat.
 */
vec3f computeRANSACNormal(float* depth9Pixels,     // Must point at 9 floats containing depth of pixels. Normal will be computed in this pixel space.
                          out RansacMode ransacMode,      // choosen mode
                          out int numRansacInliers, float tune0) // number of inliers
{
    immutable ubyte[3][] LUT = depthSampleLUT;
    
    static immutable int[9] indexToX = [0,1,2, 0,1,2, 0,1,2];
    static immutable int[9] indexToY = [0,0,0, 1,1,1, 2,2,2];    

    // Maximum plane distance for a point to be considered on that plane.
    enum float INLIER_THRESHOLD = 0.343f; // Tuned once, not easy and depends on rendering.

    vec3f bestNormal = void;
    RansacMode bestMode = void;
    int bestNumInliers = 0;

    vec3f accumulatedNormal = vec3f(0);
    float accumulatedConfidence = 0.01f;

    foreach(size_t iter, ubyte[3] indicies; LUT)
    {
        // plane point indicies upacked
        int i0 = indicies[0];
        int i1 = indicies[1];
        int i2 = indicies[2];

        // x, y, z of plane points
        int x0 = indexToX[i0];
        int x1 = indexToX[i1];
        int x2 = indexToX[i2];
        int y0 = indexToY[i0];
        int y1 = indexToY[i1];
        int y2 = indexToY[i2];
        float z0 = depth9Pixels[i0];
        float z1 = depth9Pixels[i1];
        float z2 = depth9Pixels[i2];

        vec3f vecA = vec3f(x1 - x0, y1 - y0, z1 - z0);
        vec3f vecB = vec3f(x2 - x0, y2 - y0, z2 - z0);
        vec3f n = cross(vecA, vecB); // plane normal
        n.fastNormalize();

        // distance from plane to origin (this can be any point of the 3 by the way)
        float d = dot(n, vec3f(x0, y0, z0));

        // number of points that are on the plane (max 9 points)
        int numInliers = 0;

        // check the distance between each of 9 points to the plane
        foreach(int y; 0..3)
        {
            foreach(int x; 0..3)
            {
                float z = depth9Pixels[y*3 + x];
                float distance = fast_fabs(dot(n, vec3f(x, y, z)) - d);
                if (distance < INLIER_THRESHOLD)
                    ++numInliers;
            }
        }

        // min of numInliers is 3, so this branch executes at least once
        if (numInliers > bestNumInliers)
        {
            bestNumInliers = numInliers;
            bestNormal = n;
            bestMode = cast(RansacMode)iter; // for debug
        }

        // early exit
        if (numInliers == 9) 
            break;

        // Confidence that this is a good normal (0 to 1)
        float confidence = (numInliers - 3) / 6.0f;
        confidence = confidence * confidence; // can probably be up to pow3
        accumulatedNormal += n * confidence;
        accumulatedConfidence += confidence;
    }
  
    ransacMode = bestMode;
    numRansacInliers = bestNumInliers;

    {
        if (bestNumInliers != 9)
        {
            // We iterated all kind of normals, use a weighted sum of them
            bestNormal = accumulatedNormal / accumulatedConfidence;
            bestNormal.fastNormalize();
        }
    }

    // For some unknown reason, I guess it's because left-handed vs right-handed?
    bestNormal.y = -bestNormal.y;

    return bestNormal;
}

vec3f convertRansacModeToColor(RansacMode mode)
{
    if (mode < 4) 
        return vec3f(0, 0, 1); // blue 
    if (mode < 12) 
        return vec3f(1, 1, 1); // white 
    if (mode < 12 + 4) 
        return vec3f(0, 1, 1); // cyan
    if (mode < 12 + 4 + 8) 
        return vec3f(0, 1, 0); // green
    else
        assert(false);
}

vec3f convertRansacNumInlierToColor(int numInliers)
{
    float grey = (numInliers - 3) / 6.0f;
    return vec3f(grey, grey, grey);
}

// Look-up table for sampling 3 points out of 3x3 pixels
// 24 modes.
// All triangles here MUST be in clockwise order
immutable ubyte[3][24] depthSampleLUT = 
[
    // .#.
    // .##
    // ...
    // center and 2 middle points
    [1,4,3], // 000011010
    [1,5,4], // 000110010
    [3,4,7], // 010011000
    [4,5,7], // 010110000

    // ##.
    // .#.
    // ...
    // center, one middle point, one diagonal
    [0,1,4], // 000010011
    [0,4,3], // 000011001
    [1,2,4], // 000010110
    [2,5,4], // 000110100
    [3,4,6], // 001011000
    [4,5,8], // 100110000
    [4,7,6], // 011010000
    [4,8,7], // 110010000

    // #..
    // .#.
    // #..
    // has center pixel
    [0,2,4], // 000010101
    [0,4,6], // 001010001
    [2,8,4], // 100010100
    [4,8,6], // 101010000

    // #..
    // .#.
    // .#.
    // has center pixel
    [0,5,4], // 000110001
    [0,4,7], // 010010001
    [1,4,6], // 001010010
    [1,8,4], // 100010010
    [2,4,3], // 000011100
    [2,7,4], // 010010100
    [3,4,8], // 100011000
    [4,5,6], // 001110000  
];