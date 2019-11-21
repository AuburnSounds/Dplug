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
import inteli.emmintrin;

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
    deprecated enum DEPTH_BORDER = 1; // MUST be kept in sync with the one in GUIGraphics

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
        float[] _specularFactor;
        float[] _exponentFactor;
    }

    ~this()
    {
        _normalBuffer.destroyFree();
        _accumBuffer.destroyFree();
        _specularFactor.reallocBuffer(0);
        _exponentFactor.reallocBuffer(0);
    }

    override void resizeBuffers(int width, int height)
    {
        _specularFactor.reallocBuffer(width);
        _exponentFactor.reallocBuffer(width);

        int border_0 = 0;
        int rowAlign_1 = 1;
        int rowAlign_16 = 16;
        _normalBuffer.size(width, height, border_0, rowAlign_1);
        _accumBuffer.size(width, height, border_0, rowAlign_16);
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
        int depthPitchBytes = depthLevel0.pitchInBytes(); // pitch of depth buffer, in bytes

        // Compute normals (read depth, write to _normalBuffer)
        {
            for (int j = area.min.y; j < area.max.y; ++j)
            {
                RGBf* normalScan = _normalBuffer.scanline(j).ptr;
                const(L16*) depthScan = depthLevel0.scanline(j).ptr;

                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    const(L16)* depthHere = depthScan + i;
                    const(L16)* depthHereM1 = cast(const(L16)*) ( cast(const(ubyte)*)depthHere - depthPitchBytes );
                    const(L16)* depthHereP1 = cast(const(L16)*) ( cast(const(ubyte)*)depthHere + depthPitchBytes );
                    version(futurePBRNormals)
                    {
                        // Tuned once by hand to match the other normal computation algorithm
                        enum float FACTOR_Z = 4655.0f;
                        enum float multUshort = 1.0 / FACTOR_Z;
                        float[9] depthNeighbourhood = void;
                        depthNeighbourhood[0] = depthHereM1[-1].l * multUshort;
                        depthNeighbourhood[1] = depthHereM1[ 0].l * multUshort;
                        depthNeighbourhood[2] = depthHereM1[+1].l * multUshort;
                        depthNeighbourhood[3] = depthHere[-1].l * multUshort;
                        depthNeighbourhood[4] = depthHere[ 0].l * multUshort;
                        depthNeighbourhood[5] = depthHere[+1].l * multUshort;
                        depthNeighbourhood[6] = depthHereP1[-1].l * multUshort;
                        depthNeighbourhood[7] = depthHereP1[ 0].l * multUshort;
                        depthNeighbourhood[8] = depthHereP1[+1].l * multUshort;
                        vec3f normal = computeRANSACNormal(depthNeighbourhood.ptr);
                    }
                    else
                    {
                        // compute normal
                        float sx = depthHereM1[-1].l
                                 + depthHere[  -1].l * 2
                                 + depthHereP1[-1].l
                             - (   depthHereM1[+1].l
                                 + depthHere[  +1].l * 2
                                 + depthHereP1[+1].l  );

                        float sy = depthHereP1[-1].l 
                                 + depthHereP1[ 0].l * 2 
                                 + depthHereP1[+1].l
                             - (   depthHereM1[-1].l 
                                 + depthHereM1[ 0].l * 2 
                                 + depthHereM1[+1].l);

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
                const(L16*) depthScan = depthLevel0.scanlinePtr(j);
                RGBAf* accumScan = _accumBuffer.scanlinePtr(j);

                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    __m128 baseColor = convertBaseColorToFloat4(diffuseScan[i]);

                    const(L16)* depthHere = depthScan + i;

                    float px = i + 0.5f;
                    float py = j + 0.5f;

                    float avgDepthHere =
                        ( depthMap.linearSample(1, px, py)
                        + depthMap.linearSample(2, px, py)
                        + depthMap.linearSample(3, px, py)
                        + depthMap.linearSample(4, px, py) ) * 0.25f;

                    float diff = (*depthHere).l - avgDepthHere;

                    enum float divider23040 = 1.0f / 23040;
                    float cavity = (diff + 23040.0f) * divider23040;
                    if (cavity >= 1)
                        cavity = 1;
                    else if (cavity < 0)
                        cavity = 0;

                    __m128 color = baseColor * _mm_set1_ps(cavity * ambientLight);
                    _mm_store_ps(cast(float*)&accumScan[i], color);
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

                const(L16*) depthScan = depthLevel0.scanlinePtr(j);
                RGBAf* accumScan = _accumBuffer.scanlinePtr(j);

                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    const(L16)* depthHere = depthScan + i;
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
                        L16* scan = depthLevel0.scanlinePtr(y);
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
                    __m128 mmColor = _mm_setr_ps(color.r, color.g, color.b, 0.0f);
                    _mm_store_ps(cast(float*)(&accumScan[i]), _mm_load_ps(cast(float*)(&accumScan[i])) + mmColor);
                }
            }
        }

        // secundary light
        {
            for (int j = area.min.y; j < area.max.y; ++j)
            {
                RGBA* materialScan = materialMap.levels[0].scanlinePtr(j);
                RGBA* diffuseScan = diffuseMap.levels[0].scanlinePtr(j);
                RGBf* normalScan = _normalBuffer.scanlinePtr(j);
                RGBAf* accumScan = _accumBuffer.scanlinePtr(j);

                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    RGBf normalFromBuf = normalScan[i];
                    RGBA materialHere = materialScan[i];
                    float roughness = materialHere.r * div255;
                    RGBA ibaseColor = diffuseScan[i];
                    vec3f baseColor = vec3f(ibaseColor.r, ibaseColor.g, ibaseColor.b) * div255;
                    vec3f normal = vec3f(normalFromBuf.r, normalFromBuf.g, normalFromBuf.b);
                    float diffuseFactor = 0.5f + 0.5f * dot(normal, light2Dir);
                    diffuseFactor = linmap!float(diffuseFactor, 0.24f - roughness * 0.5f, 1, 0, 1.0f);
                    vec3f color = baseColor * light2Color * diffuseFactor;
                    accumScan[i] += RGBAf(color.r, color.g, color.b, 0.0f);
                }
            }
        }

        immutable float invW = 1.0f / w;
        immutable float invH = 1.0f / h;

        // Specular highlight
        {
            __m128 mmlight3Dir = _mm_setr_ps(-light3Dir.x, -light3Dir.y, -light3Dir.z, 0.0f);
            for (int j = area.min.y; j < area.max.y; ++j)
            {
                RGBA* materialScan = materialMap.levels[0].scanlinePtr(j);
                RGBA* diffuseScan = diffuseMap.levels[0].scanlinePtr(j);
                RGBf* normalScan = _normalBuffer.scanlinePtr(j);
                RGBAf* accumScan = _accumBuffer.scanlinePtr(j);

                float* pSpecular = _specularFactor.ptr;
                float* pExponent = _exponentFactor.ptr;


                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    RGBA materialHere = materialScan[i];
                    RGBf normalFromBuf = normalScan[i];
                    __m128 normal = convertNormalToFloat4(normalScan[i]);

                    // TODO: this should be tuned interactively, maybe it's annoying to feel
                    __m128 toEye = _mm_setr_ps(0.5f - i * invW, j * invH - 0.5f, 1.0f, 0.0f);

                    toEye = _mm_fast_normalize_ps(toEye);
                    __m128 lightReflect = _mm_reflectnormal_ps(mmlight3Dir, normal);
                    float specularFactor = _mm_dot_ps(toEye, lightReflect);
                    if (specularFactor < 1e-3f) 
                        specularFactor = 1e-3f;
                    pSpecular[i] = specularFactor;
                    pExponent[i] = _exponentTable[materialHere.r];
                }

                // Just the pow operation for this line
                {
                    int i = area.min.x;
                    for (; i + 3 < area.max.x; i += 4)
                    {
                        _mm_storeu_ps(&pSpecular[i], _mm_pow_ps(_mm_loadu_ps(&pSpecular[i]), _mm_loadu_ps(&pExponent[i])));
                    }
                    for (; i < area.max.x; ++i)
                    {
                        pSpecular[i] = _mm_pow_ss(pSpecular[i], pExponent[i]);
                    }
                }

                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    float specularFactor = pSpecular[i];

                    __m128 material = convertMaterialToFloat4(materialScan[i]);
                    RGBA materialHere = materialScan[i];
                    float roughness = material.array[0];
                    float metalness = material.array[1];
                    float specular  = material.array[2];
                    __m128 baseColor = convertBaseColorToFloat4(diffuseScan[i]);
                    __m128 mmLight3Color = _mm_setr_ps(light3Color.x, light3Color.y, light3Color.z, 0.0f);

                    float roughFactor = 10 * (1.0f - roughness) * (1 - metalness * 0.5f);
                    specularFactor = specularFactor * roughFactor;
                    __m128 color = baseColor * mmLight3Color * _mm_set1_ps(specularFactor * specular);

                    _mm_store_ps(cast(float*)(&accumScan[i]), _mm_load_ps(cast(float*)(&accumScan[i])) + color);
                }
            }
        }

        // skybox reflection (use the same shininess as specular)
        if (skybox !is null)
        {
            for (int j = area.min.y; j < area.max.y; ++j)
            {
                RGBA* materialScan = materialMap.levels[0].scanlinePtr(j);
                RGBA* diffuseScan = diffuseMap.levels[0].scanlinePtr(j);
                RGBf* normalScan = _normalBuffer.scanlinePtr(j);
                RGBAf* accumScan = _accumBuffer.scanlinePtr(j);
                const(L16*) depthScan = depthLevel0.scanlinePtr(j);

                // First compute the needed mipmap level for this line

                immutable float amountOfSkyboxPixels = skybox.width * skybox.height;
                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    // TODO optimize this crap
                    const(L16)* depthHere = depthScan + i;
                    float[3][3] depthPatch;
                    for (int row = 0; row < 3; ++row)
                    {
                        const(L16)* depthLine = cast(const(L16)*)((cast(const(ubyte)*)depthHere) + (row-1) * depthPitchBytes);
                        for (int col = 0; col < 3; ++col)
                        {                            
                            depthPatch[row][col] = depthLine[(col - 1)].l;
                        }
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

                    _skyMimapLevel[i] = (depthDX * depthDX + depthDY * depthDY) * amountOfSkyboxPixels;
                }

                // Compute mipmap level
                {
                    // cooking here
                    // log2 scaling + threshold
                    enum float ROUGH_FACT = 6.0f / 255.0f;
                    int i = area.min.x;
                    for (; i + 3 < area.max.x; i += 4)
                    {
                        // We only want the first byte of each material sample, the roughness one
                        __m128i material4 = _mm_loadu_si128(cast(__m128i*) &materialScan[i]);
                        material4 = _mm_and_si128(material4, _mm_set1_epi32(255));
                        __m128 roughness = _mm_cvtepi32_ps(material4);
                        __m128 derivativeSquared = _mm_loadu_ps(&_skyMimapLevel[i]);
                        __m128 level = _mm_set1_ps(0.5f) * _mm_fastlog2_ps(_mm_set1_ps(1.0f) + derivativeSquared * _mm_set1_ps(0.00001f))
                                       + _mm_set1_ps(ROUGH_FACT) * roughness;
                        _mm_storeu_ps(&_skyMimapLevel[i], level);
                    }
                    for (; i < area.max.x; ++i)
                    {
                        float roughness = materialScan[i].r;
                        _skyMimapLevel[i] = 0.5f * fastlog2(1.0f + _skyMimapLevel[i] * 0.00001f) + ROUGH_FACT * roughness;
                    }
                }

                immutable float fskyX = (skybox.width - 1.0f);
                immutable float fSkyY = (skybox.height - 1.0f);

                immutable float amount = skyboxAmount * div255;

                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    // TODO: same remark than above about toEye, something to think about
                    __m128 toEye = _mm_setr_ps(0.5f - i * invW, j * invH - 0.5f, 1.0f, 0.0f);
                    toEye = _mm_fast_normalize_ps(toEye);

                    __m128 normal = convertNormalToFloat4(normalScan[i]);
                    __m128 pureReflection = _mm_reflectnormal_ps(toEye, normal);
                    __m128 material = convertMaterialToFloat4(materialScan[i]);
                    float metalness = material.array[1];
                    __m128 baseColor = convertBaseColorToFloat4(diffuseScan[i]);
                    float skyx = 0.5f + ((0.5f - pureReflection.array[0] * 0.5f) * fskyX);
                    float skyy = 0.5f + ((0.5f + pureReflection.array[1] * 0.5f) * fSkyY);
                    __m128 skyColorAtThisPoint = convertVec4fToFloat4( skybox.linearMipmapSample(_skyMimapLevel[i], skyx, skyy) );
                    __m128 color = baseColor * skyColorAtThisPoint * _mm_set1_ps(metalness * amount);
                    _mm_store_ps(cast(float*)(&accumScan[i]), _mm_load_ps(cast(float*)(&accumScan[i])) + color);
                }
            }
        }

        // Add light emitted by neighbours
        // Bloom-like.
        {
            for (int j = area.min.y; j < area.max.y; ++j)
            {
                RGBA* materialScan = materialMap.levels[0].scanlinePtr(j);
                RGBA* diffuseScan = diffuseMap.levels[0].scanlinePtr(j);
                RGBf* normalScan = _normalBuffer.scanlinePtr(j);
                RGBAf* accumScan = _accumBuffer.scanlinePtr(j);
                const(L16*) depthScan = depthLevel0.scanlinePtr(j);

                for (int i = area.min.x; i < area.max.x; ++i)
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
                    accumScan[i] += RGBAf(emitted.r, emitted.g, emitted.b, emitted.a);
                }
            }
        }

        // Final pass, clamp, convert to ubyte
        for (int j = area.min.y; j < area.max.y; ++j)
        {
            RGBA* wfb_scan = wfb.scanline(j).ptr;
            RGBAf* accumScan = _accumBuffer.scanlinePtr(j);

            for (int i = area.min.x; i < area.max.x; ++i)
            {
                RGBAf accum = accumScan[i];
                vec3f color = vec3f(accum.r, accum.g, accum.b);

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

    // For the specular highlight pass
    float[] _specularFactor;
    float[] _exponentFactor;

    // Reused temporary buffer for the mipmap level
    alias _skyMimapLevel = _specularFactor;
}

private:

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

// log2 approximation by Laurent de Soras
// http://www.flipcode.com/archives/Fast_log_Function.shtml
// Same but 4x at once
__m128 _mm_fastlog2_ps(__m128 val) pure nothrow @nogc
{
    __m128i x = _mm_castps_si128(val);
    __m128i m128 = _mm_set1_epi32(128);
    __m128i m255 = _mm_set1_epi32(255);
    __m128i log_2 = _mm_and_si128(_mm_srai_epi32(x, 23), m255) - m128;
    x = _mm_and_si128(x, _mm_set1_epi32(~(255 << 23)));
    x = x + _mm_set1_epi32(127 << 23);
    __m128 fif = _mm_castsi128_ps(x);
    return fif + _mm_cvtepi32_ps(log_2);
}



alias convertMaterialToFloat4 = convertBaseColorToFloat4;

// Convert a 8-bit color to a normalized 4xfloat color
__m128 convertBaseColorToFloat4(RGBA rgba) nothrow @nogc pure
{
    int asInt = *cast(int*)(&rgba);
    __m128i packed = _mm_cvtsi32_si128(asInt);
    __m128i mmZero = _mm_setzero_si128();
    __m128i shorts = _mm_unpacklo_epi8(packed, mmZero);
    __m128i ints = _mm_unpacklo_epi16(shorts, mmZero);
    enum float div255 = 1 / 255.0f;
    return _mm_cvtepi32_ps(ints) * _mm_set1_ps(div255);
}

__m128 convertNormalToFloat4(RGBf normal) nothrow @nogc pure
{
    return _mm_setr_ps(normal.r, normal.g, normal.b, 0.0f);
}

__m128 convertVec4fToFloat4(vec4f vec) nothrow @nogc pure
{
    return _mm_setr_ps(vec.x, vec.y, vec.z, vec.w);
}


