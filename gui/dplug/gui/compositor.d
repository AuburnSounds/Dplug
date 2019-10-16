/**
* PBR rendering, custom rendering.
*
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.compositor;

import std.math;

import gfm.math.vector;
import gfm.math.box;
import gfm.math.matrix;

import dplug.core.vec;
import dplug.core.nogc;
import dplug.core.math;

import dplug.window.window;

import dplug.graphics.mipmap;
import dplug.graphics.drawex;
import dplug.graphics.image;
import dplug.graphics.view;

// Only deals with rendering tiles.
// If you don't like Dplug default compositing, just make another Compositor
// and assign the 'compositor' field in GUIGraphics.
// However for now mipmaps are not negotiable, they will get generated outside this compositor.
interface ICompositor
{
    void compositeTile(ImageRef!RGBA wfb, WindowPixelFormat pf, box2i area,
                       Mipmap!RGBA diffuseMap,
                       Mipmap!RGBA materialMap,
                       Mipmap!L16 depthMap,
                       Mipmap!RGBA skybox) nothrow @nogc;
}

version = newNormal;

/// "Physically Based"-style rendering
class PBRCompositor : ICompositor
{
nothrow @nogc:
    // light 1 used for key lighting and shadows
    // always coming from top-right
    vec3f light1Color;

    // light 2 used for diffuse lighting
    vec3f light2Dir;
    vec3f light2Color;

    // light 3 used for specular highlights
    vec3f light3Dir;
    vec3f light3Color;

    float ambientLight;
    float skyboxAmount;

    this()
    {
        float globalLightFactor = 1.3f;
        // defaults
        light1Color = vec3f(0.25f, 0.25f, 0.25f) * globalLightFactor;

        light2Dir = vec3f(0.0f, 1.0f, 0.1f).normalized;
        light2Color = vec3f(0.37f, 0.37f, 0.37f) * globalLightFactor;

        light3Dir = vec3f(0.0f, 1.0f, 0.1f).normalized;
        light3Color = vec3f(0.2f, 0.2f, 0.2f) * globalLightFactor;

        ambientLight = 0.0625f * globalLightFactor;
        skyboxAmount = 0.4f * globalLightFactor;

        for (int roughByte = 0; roughByte < 256; ++roughByte)
        {
            _exponentTable[roughByte] = 0.8f * exp( (1-roughByte / 255.0f) * 5.5f);
        }
    }

    /// Don't like this rendering? Feel free to override this method.
    override void compositeTile(ImageRef!RGBA wfb, WindowPixelFormat pf, box2i area,
                                Mipmap!RGBA diffuseMap,
                                Mipmap!RGBA materialMap,
                                Mipmap!L16 depthMap,
                                Mipmap!RGBA skybox)
    {
        ushort[3][3] depthPatch = void;
        L16*[3] depth_scan = void;

        int w = diffuseMap.levels[0].w;
        int h = diffuseMap.levels[0].h;
        float invW = 1.0f / w;
        float invH = 1.0f / h;
        static immutable float div255 = 1 / 255.0f;

        for (int j = area.min.y; j < area.max.y; ++j)
        {
            RGBA* wfb_scan = wfb.scanline(j).ptr;

            // clamp to existing lines
            {
                OwnedImage!L16 depthLevel0 = depthMap.levels[0];
                for (int line = 0; line < 3; ++line)
                {
                    int lineIndex = j - 1 + line;
                    if (lineIndex < 0)
                        lineIndex = 0;
                    if (lineIndex > h - 1)
                        lineIndex = h - 1;
                    depth_scan[line] = depthLevel0.scanline(lineIndex).ptr;
                }
            }

            RGBA* materialScan = materialMap.levels[0].scanline(j).ptr;
            RGBA* diffuseScan = diffuseMap.levels[0].scanline(j).ptr;

            for (int i = area.min.x; i < area.max.x; ++i)
            {
                RGBA materialHere = materialScan[i];

                // clamp to existing columns

                {
                    // Get depth for a 3x3 patch
                    // Turns out DMD like hand-unrolling:(
                    for (int k = 0; k < 3; ++k)
                    {
                        int colIndex = i - 1 + k;
                        if (colIndex < 0)
                            colIndex = 0;
                        if (colIndex > w - 1)
                            colIndex = w - 1;

                        depthPatch[0][k] = depth_scan.ptr[0][colIndex].l;
                        depthPatch[1][k] = depth_scan.ptr[1][colIndex].l;
                        depthPatch[2][k] = depth_scan.ptr[2][colIndex].l;
                    }
                }

                // defined here for visualization below
                uint bestNumInliers = 0;
                uint bestIter = 0;
                uint numIters = 0;

                vec3f normal = void;
                version(newNormal)
                {
                    immutable ubyte[3][] LUT = depthSampleLUT[0..24]; // only with center pixel
                    //immutable ubyte[3][] LUT = depthSampleLUT; // full table
                    static immutable ubyte[9] indexToX = [0,1,2,0,1,2,0,1,2,];
                    static immutable ubyte[9] indexToY = [0,0,0,1,1,1,2,2,2,];

                    float[9] depth9 = void;
                    enum float multUshort = 1 / 65535.0f;
                    depth9[0] = depthPatch[0][0] * multUshort;
                    depth9[1] = depthPatch[0][1] * multUshort;
                    depth9[2] = depthPatch[0][2] * multUshort;
                    depth9[3] = depthPatch[1][0] * multUshort;
                    depth9[4] = depthPatch[1][1] * multUshort;
                    depth9[5] = depthPatch[1][2] * multUshort;
                    depth9[6] = depthPatch[2][0] * multUshort;
                    depth9[7] = depthPatch[2][1] * multUshort;
                    depth9[8] = depthPatch[2][2] * multUshort;

                    foreach(uint iter, ubyte[3] indicies; LUT)
                    {
                        // plane point indicies upacked
                        ubyte i0 = indicies[0];
                        ubyte i1 = indicies[1];
                        ubyte i2 = indicies[2];

                        // x, y, z of plane points
                        byte x0 = indexToX[i0];
                        byte x1 = indexToX[i1];
                        byte x2 = indexToX[i2];
                        byte y0 = indexToY[i0];
                        byte y1 = indexToY[i1];
                        byte y2 = indexToY[i2];
                        float z0 = depth9[i0];
                        float z1 = depth9[i1];
                        float z2 = depth9[i2];

                        vec3f vecA = vec3f(x1 - x0, y1 - y0, z1 - z0);
                        vec3f vecB = vec3f(x2 - x0, y2 - y0, z2 - z0);
                        vec3f n = cross(vecA, vecB); // plane normal
                        if (n.z < 0) n = -n; // can be removed if all points in LUT are in CW/CCW order
                        n.fastNormalize();

                        // distance from plane to origin
                        float d = dot(n, vec3f(x0, y0, z0));

                        // max distance for point to be considered on the plane
                        enum float threshold = 0.001f;

                        // number of points that are on the plane (max 9 points)
                        uint numInliers = 0;

                        // check the distance between each of 9 points to the plane
                        foreach(ubyte y; 0..3)
                        foreach(ubyte x; 0..3)
                        {
                            float z = depth9[y*3 + x];
                            float distance = abs(dot(n, vec3f(x, y, z)) - d);
                            if (distance < threshold)
                                ++numInliers;
                        }

                        // min of numInliers is 3, so this branch executes at least once
                        if (numInliers > bestNumInliers)
                        {
                            bestNumInliers = numInliers;
                            normal = n;
                            bestIter = iter; // for debug
                        }
                        numIters = iter; // for debug

                        // early exit
                        if (numInliers == 9) break;
                    }
                }
                else
                {
                    // compute normal
                    float sx = depthPatch[0][0]
                        + depthPatch[1][0] * 2
                        + depthPatch[2][0]
                        - ( depthPatch[0][2]
                            + depthPatch[1][2] * 2
                            + depthPatch[2][2]);

                    float sy = depthPatch[2][0] + depthPatch[2][1] * 2 + depthPatch[2][2]
                        - ( depthPatch[0][0] + depthPatch[0][1] * 2 + depthPatch[0][2]);

                    // this factor basically tweak normals to make the UI flatter or not
                    // if you change normal filtering, retune this
                    enum float sz = 260.0f * 257.0f / 1.8f; 

                    normal = vec3f(sx, sy, sz);
                    normal.fastNormalize(); // this makes very, very little difference in output vs normalize
                }

                RGBA ibaseColor = diffuseScan[i];
                vec3f baseColor = vec3f(ibaseColor.r, ibaseColor.g, ibaseColor.b) * div255;

                vec3f toEye = vec3f(0.5f - i * invW, j * invH - 0.5f, 1.0f);
                toEye.fastNormalize(); // this makes very, very little difference in output vs normalize

                vec3f color = vec3f(0.0f);

                float roughness = materialHere.r * div255;
                float metalness = materialHere.g * div255;
                float specular  = materialHere.b * div255;

                // Add ambient component
                {
                    float px = i + 0.5f;
                    float py = j + 0.5f;

                    float avgDepthHere =
                        ( depthMap.linearSample(1, px, py)
                            + depthMap.linearSample(2, px, py)
                            + depthMap.linearSample(3, px, py)
                            + depthMap.linearSample(4, px, py) ) * 0.25f;

                    float diff = depthPatch[1][1] - avgDepthHere;
                    float cavity = void;
                    if (diff >= 0)
                        cavity = 1;
                    else if (diff < -23040)
                        cavity = 0;
                    else
                    {
                        static immutable float divider23040 = 1.0f / 23040;
                        cavity = (diff + 23040) * divider23040;
                    }
                    if (cavity > 0)
                        color += baseColor * (cavity * ambientLight);
                }

                // cast shadows, ie. enlight what isn't in shadows
                {
                    enum float fallOff = 0.78f;

                    int samples = 11;

                    static immutable float[11] weights =
                    [
                        1.0f,
                        fallOff,
                        fallOff ^^ 2,
                        fallOff ^^ 3,
                        fallOff ^^ 4,
                        fallOff ^^ 5,
                        fallOff ^^ 6,
                        fallOff ^^ 7,
                        fallOff ^^ 8,
                        fallOff ^^ 9,
                        fallOff ^^ 10
                    ];

                    enum float totalWeights = (1.0f - (fallOff ^^ 11)) / (1.0f - fallOff) - 1;
                    enum float invTotalWeights = 1 / (1.7f * totalWeights);

                    float lightPassed = 0.0f;

                    OwnedImage!L16 depthLevel0 = depthMap.levels[0];

                    int depthHere = depthPatch[1][1];
                    for (int sample = 1; sample < samples; ++sample)
                    {
                        int x1 = i + sample;
                        if (x1 >= w)
                            x1 = w - 1;
                        int x2 = i - sample;
                        if (x2 < 0)
                            x2 = 0;
                        int y = j - sample;
                        if (y < 0)
                            y = 0;
                        int z = depthHere + sample; // ???
                        L16* scan = depthLevel0.scanline(y).ptr;
                        int diff1 = z - scan[x1].l; // FUTURE: use pointer offsets here instead of opIndex
                        int diff2 = z - scan[x2].l;

                        float contrib1 = void, 
                              contrib2 = void;

                        static immutable float divider15360 = 1.0f / 15360;

                        if (diff1 >= 0)
                            contrib1 = 1;
                        else if (diff1 < -15360)
                            contrib1 = 0;
                        else
                            contrib1 = (diff1 + 15360) * divider15360;

                        if (diff2 >= 0)
                            contrib2 = 1;
                        else if (diff2 < -15360)
                            contrib2 = 0;
                        else
                            contrib2 = (diff2 + 15360) * divider15360;

                        lightPassed += (contrib1 + contrib2 * 0.7f) * weights[sample];
                    }
                    color += baseColor * light1Color * (lightPassed * invTotalWeights);
                }

                // secundary light
                {
                    float diffuseFactor = 0.5f + 0.5f * dot(normal, light2Dir);

                    diffuseFactor = /*cavity * */ linmap!float(diffuseFactor, 0.24f - roughness * 0.5f, 1, 0, 1.0f);

                    if (diffuseFactor > 0)
                        color += baseColor * light2Color * diffuseFactor;
                }

                // specular reflection
                if (specular != 0)
                {
                    vec3f lightReflect = reflect(-light3Dir, normal);
                    float specularFactor = dot(toEye, lightReflect);
                    if (specularFactor > 1e-3f)
                    {
                        float exponent = _exponentTable[materialHere.r];
                        specularFactor = specularFactor ^^ exponent;
                        float roughFactor = 10 * (1.0f - roughness) * (1 - metalness * 0.5f);
                        specularFactor = specularFactor * roughFactor;
                        if (specularFactor != 0)
                            color += baseColor * light3Color * (specularFactor * specular);
                    }
                }

                // skybox reflection (use the same shininess as specular)
                if (metalness != 0)
                {
                    vec3f pureReflection = reflect(toEye, normal);

                    float skyx = 0.5f + ((0.5f - pureReflection.x *0.5f) * (skybox.width - 1));
                    float skyy = 0.5f + ((0.5f + pureReflection.y *0.5f) * (skybox.height - 1));

                    // 2nd order derivatives
                    float depthDX = depthPatch[2][0] + depthPatch[2][1] + depthPatch[2][2]
                        + depthPatch[0][0] + depthPatch[0][1] + depthPatch[0][2]
                        - 2 * (depthPatch[1][0] + depthPatch[1][1] + depthPatch[1][2]);

                    float depthDY = depthPatch[0][2] + depthPatch[1][2] + depthPatch[2][2]
                        + depthPatch[0][0] + depthPatch[1][0] + depthPatch[2][0]
                        - 2 * (depthPatch[0][1] + depthPatch[1][1] + depthPatch[2][1]);

                    depthDX *= (1 / 256.0f);
                    depthDY *= (1 / 256.0f);

                    float depthDerivSqr = depthDX * depthDX + depthDY * depthDY;
                    float indexDeriv = depthDerivSqr * skybox.width * skybox.height;

                    // cooking here
                    // log2 scaling + threshold
                    float mipLevel = 0.5f * fastlog2(1.0f + indexDeriv * 0.00001f) + 6 * roughness;

                    vec3f skyColor = skybox.linearMipmapSample(mipLevel, skyx, skyy).rgb * (div255 * metalness * skyboxAmount);
                    color += skyColor * baseColor;
                }

                // Add light emitted by neighbours
                {
                    float ic = i + 0.5f;
                    float jc = j + 0.5f;

                    // Get alpha-premultiplied, avoids to have to do alpha-aware mipmapping
                    vec4f colorLevel1 = diffuseMap.linearSample(1, ic, jc);
                    vec4f colorLevel2 = diffuseMap.linearSample(2, ic, jc);
                    vec4f colorLevel3 = diffuseMap.linearSample(3, ic, jc);
                    vec4f colorLevel4 = diffuseMap.linearSample(4, ic, jc);
                    vec4f colorLevel5 = diffuseMap.linearSample(5, ic, jc);
                      
                    vec4f emitted = colorLevel1 * 0.00117647f;
                    emitted += colorLevel2      * 0.00176471f;
                    emitted += colorLevel3      * 0.00147059f;
                    emitted += colorLevel4      * 0.00088235f;
                    emitted += colorLevel5      * 0.00058823f;
                    color += emitted.rgb;
                }

                // Show normals
                // color = normal;//vec3f(0.5f) + normal * 0.5f;

                static vec3f[7] colorPalette = [
                    vec3f(0x00/255f,0x26/255f,0xFF/255f),
                    vec3f(0x00/255f,0x94/255f,0xFF/255f),
                    vec3f(0x00/255f,0xFF/255f,0xFF/255f),
                    vec3f(0x00/255f,0xFF/255f,0x90/255f),
                    vec3f(0xFF/255f,0xD8/255f,0x00/255f),
                    vec3f(0xFF/255f,0x6A/255f,0x00/255f),
                    vec3f(0xFF/255f,0x00/255f,0x00/255f),
                ];

                //color = colorPalette[bestNumInliers - 3];

                // Show depth
                {
                    //    float depthColor = depthPatch[1][1] / 65535.0f;
                    //    color = vec3f(depthColor);
                }

                // Show diffuse
                //color = baseColor;

                //  color = toEye;
                //color = vec3f(cavity);
                assert(color.x >= 0);
                assert(color.y >= 0);
                assert(color.z >= 0);

                if (color.x > 1)
                    color.x = 1;
                if (color.y > 1)
                    color.y = 1;
                if (color.z > 1)
                    color.z = 1;

                int r = cast(int)(color.x * 255.99f);
                int g = cast(int)(color.y * 255.99f);
                int b = cast(int)(color.z * 255.99f);

                // write composited color
                wfb_scan[i] = RGBA(cast(ubyte)r, cast(ubyte)g, cast(ubyte)b, 255);
            }
        }
    }

private:
    float[256] _exponentTable;
}

private:

// cause smoothStep wasn't needed
float ctLinearStep(float a, float b)(float t) pure nothrow @nogc
{
    if (t <= a)
        return 0.0f;
    else if (t >= b)
        return 1.0f;
    else
    {
        static immutable divider = 1.0f / (b - a);
        return (t - a) * divider;
    }
}

private:

// cause smoothStep wasn't needed
float linearStep(float a, float b, float t) pure nothrow @nogc
{
    if (t <= a)
        return 0.0f;
    else if (t >= b)
        return 1.0f;
    else
    {
        float divider = 1.0f / (b - a);
        return (t - a) * divider;
    }
}

// log2 approximation by Laurent de Soras
// http://www.flipcode.com/archives/Fast_log_Function.shtml
float fastlog2(float val) pure nothrow @nogc
{
    union fi_t
    {
        int i;
        float f;
    }

    fi_t fi;
    fi.f = val;
    int x = fi.i;
    int log_2 = ((x >> 23) & 255) - 128;
    x = x & ~(255 << 23);
    x += 127 << 23;
    fi.i = x;
    return fi.f + log_2;
}

// Look-up table for sampling 3 points out of 3x3 pixels
// First 24 contain center pixel
immutable ubyte[3][76] depthSampleLUT = [
    // Red
    // ##.
    // .#.
    // ...
    // has center pixel
    [0,1,4], // 000010011
    [0,3,4], // 000011001
    [1,2,4], // 000010110
    [1,3,4], // 000011010
    [1,4,5], // 000110010
    [2,4,5], // 000110100
    [3,4,6], // 001011000
    [3,4,7], // 010011000
    [4,5,7], // 010110000
    [4,5,8], // 100110000
    [4,6,7], // 011010000
    [4,7,8], // 110010000

    // Pink
    // #..
    // .#.
    // #..
    // has center pixel
    [0,2,4], // 000010101
    [0,4,6], // 001010001
    [2,4,8], // 100010100
    [4,6,8], // 101010000

    // Yellow
    // #..
    // .#.
    // .#.
    // has center pixel
    [0,4,5], // 000110001
    [0,4,7], // 010010001
    [1,4,6], // 001010010
    [1,4,8], // 100010010
    [2,3,4], // 000011100
    [2,4,7], // 010010100
    [3,4,8], // 100011000
    [4,5,6], // 001110000

    // Red
    // ##.
    // #..
    // ...
    // no center pixel
    [0,1,3], // 000001011
    [1,2,5], // 000100110
    [3,6,7], // 011001000
    [5,7,8], // 110100000
    
    // Pink
    // .#.
    // ..#
    // .#.
    // no center pixel
    [1,3,5], // 000101010
    [1,3,7], // 010001010
    [1,5,7], // 010100010
    [3,5,7], // 010101000
    
    // Yellow
    // .#.
    // ..#
    // ..#
    // no center pixel
    [0,1,5], // 000100011
    [0,3,7], // 010001001
    [1,2,3], // 000001110
    [1,3,6], // 001001010
    [1,5,8], // 100100010
    [2,5,7], // 010100100
    [5,6,7], // 011100000
    [3,7,8], // 110001000

    // Green
    // #..
    // ...
    // #.#
    // only corners
    [0,2,6], // 001000101
    [0,2,8], // 100000101
    [0,6,8], // 101000001
    [2,6,8], // 101000100
    // .#.
    // ...
    // #.#
    // corners + side
    [0,2,7], // 010000101
    [0,5,6], // 001100001
    [1,6,8], // 101000010
    [2,3,8], // 100001100

    // Orange
    // #..
    // ..#
    // .#.
    [0,5,7], // 010100001
    [1,3,8], // 100001010
    [1,5,6], // 001100010
    [2,3,7], // 010001100

    // Blue
    // #..
    // ...
    // ##.
    // same corner
    [0,1,6], // 001000011
    [0,2,3], // 000001101
    [0,2,5], // 000100101
    [0,6,7], // 011000001
    [1,2,8], // 100000110
    [2,7,8], // 110000100
    [3,6,8], // 101001000
    [5,6,8], // 101100000
    // .#.
    // ...
    // ##.
    // middle
    [0,1,7], // 010000011
    [0,3,5], // 000101001
    [1,2,7], // 010000110
    [1,6,7], // 011000010
    [1,7,8], // 110000010
    [2,3,5], // 000101100
    [3,5,6], // 001101000
    [3,5,8], // 100101000
    // ..#
    // ...
    // ##.
    // opposite corner
    [0,1,8], // 100000011
    [0,3,8], // 100001001
    [0,5,8], // 100100001
    [0,7,8], // 110000001
    [1,2,6], // 001000110
    [2,3,6], // 001001100
    [2,5,6], // 001100100
    [2,6,7], // 011000100
];