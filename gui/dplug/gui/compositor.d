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

import dplug.gui.ransac;

import inteli.math;

// Only deals with rendering tiles.
// If you don't like Dplug default compositing, just make another Compositor
// and assign the 'compositor' field in GUIGraphics.
// However for now mipmaps are not negotiable, they will get generated outside this compositor.
interface ICompositor
{
nothrow:
@nogc:
    void compositeTile(ImageRef!RGBA wfb, 
                       WindowPixelFormat pf, 
                       box2i area,
                       Mipmap!RGBA diffuseMap,
                       Mipmap!RGBA materialMap,
                       Mipmap!L16 depthMap,
                       Mipmap!RGBA skybox);

    void resizeBuffers(int width, int height);
}

/// "Physically Based"-style rendering
class PBRCompositor : ICompositor
{
    enum DEPTH_BORDER = 1; // MUST be kept in sync with the one in GUIGraphics

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

        _normalBuffer = mallocNew!(OwnedImage!RGBf)();
        _accumBuffer = mallocNew!(OwnedImage!RGBAf)();
    }

    ~this()
    {
        _normalBuffer.destroyFree();
        _accumBuffer.destroyFree();
    }

    override void resizeBuffers(int width, int height)
    {
        _normalBuffer.size(width, height);
        _accumBuffer.size(width, height);
    }

    /// Don't like this rendering? Feel free to override this method.
    override void compositeTile(ImageRef!RGBA wfb, WindowPixelFormat pf, box2i area,
                                Mipmap!RGBA diffuseMap,
                                Mipmap!RGBA materialMap,
                                Mipmap!L16 depthMap,
                                Mipmap!RGBA skybox)
    {
        int w = diffuseMap.levels[0].w;
        int h = diffuseMap.levels[0].h;

        OwnedImage!L16 depthLevel0 = depthMap.levels[0];
        int depthPitch = depthLevel0.pitchInSamples(); // pitch of depth buffer, in L16 units

        // Compute normals (read depth, write to _normalBuffer)
        {            
            for (int j = area.min.y; j < area.max.y; ++j)
            {
                RGBf* normalScan = _normalBuffer.scanline(j).ptr;
                const(L16*) depthScan = depthLevel0.scanline(j + DEPTH_BORDER).ptr;

                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    const(L16)* depthHere = depthScan + i + DEPTH_BORDER;
                    version(futurePBRNormals)
                    {
                        // Tuned once by hand to match the other normal computation algorithm
                        enum float FACTOR_Z = 4655.0f;
                        enum float multUshort = 1.0 / FACTOR_Z;
                        float[9] depthNeighbourhood = void;
                        depthNeighbourhood[0] = depthHere[-depthPitch-1].l * multUshort;
                        depthNeighbourhood[1] = depthHere[-depthPitch  ].l * multUshort;
                        depthNeighbourhood[2] = depthHere[-depthPitch+1].l * multUshort;
                        depthNeighbourhood[3] = depthHere[           -1].l * multUshort;
                        depthNeighbourhood[4] = depthHere[            0].l * multUshort;
                        depthNeighbourhood[5] = depthHere[           +1].l * multUshort;
                        depthNeighbourhood[6] = depthHere[+depthPitch-1].l * multUshort;
                        depthNeighbourhood[7] = depthHere[+depthPitch  ].l * multUshort;
                        depthNeighbourhood[8] = depthHere[+depthPitch+1].l * multUshort;
                        vec3f normal = computeRANSACNormal(depthNeighbourhood.ptr);
                    }
                    else
                    {
                        // compute normal
                        float sx = depthHere[-depthPitch-1].l
                                 + depthHere[           -1].l * 2
                                 + depthHere[+depthPitch-1].l
                             - (   depthHere[-depthPitch+1].l
                                 + depthHere[           +1].l * 2
                                 + depthHere[+depthPitch+1].l  );

                        float sy = depthHere[ depthPitch-1].l 
                                 + depthHere[ depthPitch  ].l * 2 
                                 + depthHere[ depthPitch+1].l
                             - (   depthHere[-depthPitch-1].l 
                                 + depthHere[-depthPitch  ].l * 2 
                                 + depthHere[-depthPitch+1].l);

                        // this factor basically tweak normals to make the UI flatter or not
                        // if you change normal filtering, retune this
                        enum float sz = 260.0f * 257.0f / 1.8f; 

                        vec3f normal = vec3f(sx, sy, sz);
                        normal.fastNormalize(); // this makes very, very little difference in output vs normalize
                    }
                    normalScan[i] = RGBf(normal.x, normal.y, normal.z);
                }
            }
        }

        static immutable float div255 = 1 / 255.0f;

        // Add ambient component
        {
            for (int j = area.min.y; j < area.max.y; ++j)
            {
                RGBA* diffuseScan = diffuseMap.levels[0].scanlinePtr(j);
                const(L16*) depthScan = depthLevel0.scanlinePtr(j + DEPTH_BORDER);
                RGBAf* accumScan = _accumBuffer.scanlinePtr(j);

                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    RGBA ibaseColor = diffuseScan[i];
                    vec3f baseColor = vec3f(ibaseColor.r, ibaseColor.g, ibaseColor.b) * div255;
                    const(L16)* depthHere = depthScan + i + DEPTH_BORDER;

                    float px = DEPTH_BORDER + i + 0.5f;
                    float py = DEPTH_BORDER + j + 0.5f;

                    float avgDepthHere =
                        ( depthMap.linearSample(1, px, py)
                        + depthMap.linearSample(2, px, py)
                        + depthMap.linearSample(3, px, py)
                        + depthMap.linearSample(4, px, py) ) * 0.25f;

                    float diff = (*depthHere).l - avgDepthHere;
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
                    vec4f color = vec4f(baseColor, 0.0f) * (cavity * ambientLight);
                    accumScan[i] = RGBAf(color.r, color.g, color.b, color.a);
                }
            }
        }

        // Add a primary light that cast shadows
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

            for (int j = area.min.y; j < area.max.y; ++j)
            {
                RGBA* diffuseScan = diffuseMap.levels[0].scanlinePtr(j);

                const(L16*) depthScan = depthLevel0.scanlinePtr(j + DEPTH_BORDER);
                RGBAf* accumScan = _accumBuffer.scanlinePtr(j);

                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    const(L16)* depthHere = depthScan + i + DEPTH_BORDER;
                    RGBA ibaseColor = diffuseScan[i];
                    vec3f baseColor = vec3f(ibaseColor.r, ibaseColor.g, ibaseColor.b) * div255;

                    float lightPassed = 0.0f;

                    int depthCenter = (*depthHere).l;
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
                        int z = depthCenter + sample; // ???
                        L16* scan = depthLevel0.scanline(y + DEPTH_BORDER).ptr;
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
                    vec3f color = baseColor * light1Color * (lightPassed * invTotalWeights);
                    accumScan[i] += RGBAf(color.r, color.g, color.b, 0.0f);
                }
            }
        }

        // Other passes

        float invW = 1.0f / w;
        float invH = 1.0f / h;

        for (int j = area.min.y; j < area.max.y; ++j)
        {
            RGBA* wfb_scan = wfb.scanline(j).ptr;
            RGBA* materialScan = materialMap.levels[0].scanline(j).ptr;
            RGBA* diffuseScan = diffuseMap.levels[0].scanline(j).ptr;
            RGBf* normalScan = _normalBuffer.scanline(j).ptr;
            RGBAf* accumScan = _accumBuffer.scanlinePtr(j);
            const(L16*) depthScan = depthLevel0.scanline(j + DEPTH_BORDER).ptr;

            for (int i = area.min.x; i < area.max.x; ++i)
            {
                const(L16)* depthHere = depthScan + i + DEPTH_BORDER;

                RGBA materialHere = materialScan[i];
                RGBf normalFromBuf = normalScan[i];
                vec3f normal = vec3f(normalFromBuf.r, normalFromBuf.g, normalFromBuf.b);

                RGBA ibaseColor = diffuseScan[i];
                vec3f baseColor = vec3f(ibaseColor.r, ibaseColor.g, ibaseColor.b) * div255;

                vec3f toEye = vec3f(0.5f - i * invW, j * invH - 0.5f, 1.0f);
                toEye.fastNormalize(); // this makes very, very little difference in output vs normalize

                vec3f color = vec3f(0.0f);

                float roughness = materialHere.r * div255;
                float metalness = materialHere.g * div255;
                float specular  = materialHere.b * div255;


                // secundary light
                {
                    float diffuseFactor = 0.5f + 0.5f * dot(normal, light2Dir);

                    diffuseFactor = linmap!float(diffuseFactor, 0.24f - roughness * 0.5f, 1, 0, 1.0f);

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
                        specularFactor = _mm_pow_ss(specularFactor, exponent);
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

                    float[3][3] depthPatch;
                    for (int row = 0; row < 3; ++row)
                        for (int col = 0; col < 3; ++col)
                        {
                            depthPatch[row][col] = depthHere[(row-1) * depthPitch - 1 + col].l;
                        }

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

                RGBAf accum = accumScan[i];
                color += vec3f(accum.r, accum.g, accum.b);

                // Show depth
                {
                    //    float depthColor = depthPatch[1][1] / 65535.0f;
                    //    color = vec3f(depthColor);
                }

                // Show diffuse
                //color = baseColor;

                //  color = toEye;
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
    OwnedImage!RGBf _normalBuffer;
    OwnedImage!RGBAf _accumBuffer;
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



