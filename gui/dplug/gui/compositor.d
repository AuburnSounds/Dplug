/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.compositor;

import std.math;

import ae.utils.graphics;

import gfm.core.memory;
import gfm.math.vector;
import gfm.math.box;
import gfm.math.funcs;

import dplug.core.nogc;
import dplug.core.math;
import dplug.window.window;
import dplug.gui.mipmap;
import dplug.gui.drawex;

// Only deals with rendering tiles.
// If you don't like dplug default compositing, just make another Compositor
// and assign the 'compositor' field in GUIGraphics.
// However for now mipmaps and are not negotiable.
interface Compositor
{
    void compositeTile(ImageRef!RGBA wfb, WindowPixelFormat pf, box2i area,
                       Mipmap!RGBA diffuseMap,
                       Mipmap!RGBA materialMap,
                       Mipmap!L16 depthMap,
                       Mipmap!RGBA skybox) nothrow @nogc;
}

/// "Physically Based"-style rendering
class PBRCompositor : Compositor
{
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
        // defaults
        light1Color = vec3f(0.25f, 0.25f, 0.25f);

        light2Dir = vec3f(0.0f, 1.0f, 0.1f).normalized;
        light2Color = vec3f(0.37f, 0.37f, 0.37f);

        light3Dir = vec3f(0.0f, 1.0f, 0.1f).normalized;
        light3Color = vec3f(0.2f, 0.2f, 0.2f);

        ambientLight = 0.0625f;
        skyboxAmount = 0.4f;

        for (int roughByte = 0; roughByte < 256; ++roughByte)
        {
            _exponentTable[roughByte] = 0.8f * exp( (1-roughByte / 255.0f) * 5.5f);
        }

        // Set standard tables
        int alignment = 256; // this is necessary for asm optimization of look-up
        _tableArea.reallocBuffer(256 * 3, alignment);
        _redTransferTable = _tableArea.ptr;
        _greenTransferTable = _tableArea.ptr + 256;
        _blueTransferTable = _tableArea.ptr + 512;

        foreach(i; 0..256)
        {
            _redTransferTable[i] = cast(ubyte)i;
            _greenTransferTable[i] = cast(ubyte)i;
            _blueTransferTable[i] = cast(ubyte)i;
        }
    }

    ~this()
    {
        debug ensureNotInGC("PBRCompositor");
        _tableArea.reallocBuffer(0);
    }

    /// Calling this setup color correction table, with the well
    /// known lift-gamma-gain formula.
    void setLiftGammaGainContrast(float lift = 0.0f, float gamma = 1.0f, float gain = 1.0f, float contrast = 0.0f)
    {
        setLiftGammaGainContrastRGB(lift, gamma, gain, contrast,
                                    lift, gamma, gain, contrast,
                                    lift, gamma, gain, contrast);
    }

    /// Calling this setup color correction table, with the well
    /// known lift-gamma-gain formula, per channel.
    void setLiftGammaGainRGB(float rLift = 0.0f, float rGamma = 1.0f, float rGain = 1.0f,
                             float gLift = 0.0f, float gGamma = 1.0f, float gGain = 1.0f,
                             float bLift = 0.0f, float bGamma = 1.0f, float bGain = 1.0f)
    {
        setLiftGammaGainContrastRGB(rLift, rGamma, rGain, 0.0f,
                                    gLift, gGamma, gGain, 0.0f,
                                    bLift, bGamma, bGain, 0.0f);
    }

    /// Calling this setup color correction table, with the well
    /// known lift-gamma-gain formula + contrast addition, per channel.
    void setLiftGammaGainContrastRGB(
            float rLift = 0.0f, float rGamma = 1.0f, float rGain = 1.0f, float rContrast = 0.0f,
            float gLift = 0.0f, float gGamma = 1.0f, float gGain = 1.0f, float gContrast = 0.0f,
            float bLift = 0.0f, float bGamma = 1.0f, float bGain = 1.0f, float bContrast = 0.0f)
    {
        static float safePow(float a, float b)
        {
            if (a < 0)
                a = 0;
            if (a > 1)
                a = 1;
            return a ^^ b;
        }

        for (int b = 0; b < 256; ++b)
        {
            float inp = b / 255.0f;
            float outR = rGain*(inp + rLift*(1-inp));
            float outG = gGain*(inp + gLift*(1-inp));
            float outB = bGain*(inp + bLift*(1-inp));

            outR = safePow(outR, 1.0f / rGamma );
            outG = safePow(outG, 1.0f / gGamma );
            outB = safePow(outB, 1.0f / bGamma );

            if (outR < 0)
                outR = 0;
            if (outG < 0)
                outG = 0;
            if (outB < 0)
                outB = 0;
            if (outR > 1)
                outR = 1;
            if (outG > 1)
                outG = 1;
            if (outB > 1)
                outB = 1;

            outR = lerp!float(outR, smoothStep!float(0, 1, outR), rContrast);
            outG = lerp!float(outG, smoothStep!float(0, 1, outG), gContrast);
            outB = lerp!float(outB, smoothStep!float(0, 1, outB), bContrast);

            _redTransferTable[b] = cast(ubyte)(0.5f + outR * 255.0f);
            _greenTransferTable[b] = cast(ubyte)(0.5f + outG * 255.0f);
            _blueTransferTable[b] = cast(ubyte)(0.5f + outB * 255.0f);
        }
    }

    /// Don't like this rendering? Feel free to override this method.
    override void compositeTile(ImageRef!RGBA wfb, WindowPixelFormat pf, box2i area,
                                Mipmap!RGBA diffuseMap,
                                Mipmap!RGBA materialMap,
                                Mipmap!L16 depthMap,
                                Mipmap!RGBA skybox) nothrow @nogc
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

                // Bypass PBR if Physical == 0
                if (materialHere.a == 0)
                {
                    wfb_scan[i] = diffuseScan[i];
                }
                else
                {
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

                    vec3f normal = vec3f(sx, sy, sz);
                    normal.fastNormalize(); // this makes very, very little difference in output vs normalize

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
                        enum float invTotalWeights = 1 / totalWeights;

                        float lightPassed = 0.0f;

                        OwnedImage!L16 depthLevel0 = depthMap.levels[0];

                        int depthHere = depthPatch[1][1];
                        for (int sample = 1; sample < samples; ++sample)
                        {
                            int x = i + sample;
                            if (x >= w)
                                x = w - 1;
                            int y = j - sample;
                            if (y < 0)
                                y = 0;
                            int z = depthHere + sample;
                            int diff = z - depthLevel0.scanline(y)[x].l; // TODO: use pointer offsets here instead of opIndex

                            float contrib = void;
                            if (diff >= 0)
                                contrib = 1;
                            else if (diff < -15360)
                            {
                                contrib = 0;
                                continue;
                            }
                            else
                            {
                                static immutable float divider15360 = 1.0f / 15360;
                                contrib = (diff + 15360) * divider15360;
                            }

                            lightPassed += contrib * weights[sample];
                        }
                        color += baseColor * light1Color * (lightPassed * invTotalWeights);
                    }

                    // secundary light
                    {
                        float diffuseFactor = 0.5f + 0.5f * dot(normal, light2Dir);// + roughness;

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

                        float skyx = 0.5f + ((0.5f + pureReflection.x *0.5f) * (skybox.width - 1));
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

                    // Partial blending of PBR with diffuse
                    if (materialHere.a != 255)
                    {
                        float physical  = materialHere.a * div255;
                        color += (baseColor - color) * (1 - physical);
                    }

                    // Show normals
                    // color = normal;//vec3f(0.5f) + normal * 0.5f;

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

        // Look-up table for color-correction and ordering of output
        {
            ubyte* red = _redTransferTable;
            ubyte* green = _greenTransferTable;
            ubyte* blue = _blueTransferTable;

            final switch (pf) with (WindowPixelFormat)
            {
                case ARGB8:
                    applyColorCorrectionARGB8(wfb, area, red, green, blue);
                    break;

                case BGRA8:
                    applyColorCorrectionBGRA8(wfb, area, red, green, blue);
                    break;

                case RGBA8: 
                    applyColorCorrectionRGBA8(wfb, area, red, green, blue);
                    break;
            }
        }
    }

private:
    // Assign those to use lookup tables.
    ubyte[] _tableArea = null;
    ubyte* _redTransferTable = null;
    ubyte* _greenTransferTable = null;
    ubyte* _blueTransferTable = null;

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

// Apply color correction and convert RGBA8 to ARGB8
void applyColorCorrectionARGB8(ImageRef!RGBA wfb, box2i area, ubyte* red, ubyte* green, ubyte* blue) nothrow @nogc
{
    for (int j = area.min.y; j < area.max.y; ++j)
    {
        RGBA* wfb_scan = wfb.scanline(j).ptr;
        for (int i = area.min.x; i < area.max.x; ++i)
        {
            immutable RGBA color = wfb_scan[i];
            wfb_scan[i] = RGBA(255, red[color.r], green[color.g], blue[color.b]);
        }
    }
}

// Apply color correction and convert RGBA8 to BGRA8
void applyColorCorrectionBGRA8(ImageRef!RGBA wfb, box2i area, ubyte* red, ubyte* green, ubyte* blue) nothrow @nogc
{
    int width = area.width();
    for (int j = area.min.y; j < area.max.y; ++j)
    {
        RGBA* wfb_scan = wfb.scanline(j).ptr;
        for (int i = area.min.x; i < area.max.x; ++i)
        {
            immutable RGBA color = wfb_scan[i];
            wfb_scan[i] = RGBA(blue[color.b], green[color.g], red[color.r], 255);
        }
    }
}

// Apply color correction and do nothing about color order
void applyColorCorrectionRGBA8(ImageRef!RGBA wfb, box2i area, ubyte* red, ubyte* green, ubyte* blue) nothrow @nogc
{
    for (int j = area.min.y; j < area.max.y; ++j)
    {
        RGBA* wfb_scan = wfb.scanline(j).ptr;
        for (int i = area.min.x; i < area.max.x; ++i)
        {
            immutable RGBA color = wfb_scan[i];
            wfb_scan[i] = RGBA(red[color.r], green[color.g], blue[color.b], 255);
        }
    }
}
