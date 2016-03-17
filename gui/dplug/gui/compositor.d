/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.compositor;

import std.math;

import ae.utils.graphics;

import gfm.math.vector;
import gfm.math.box;
import gfm.math.funcs;

import dplug.core.funcs;
import dplug.window.window;
import dplug.gui.mipmap;

// Only deals with rendering tiles.
// If you don't like dplug default compositing, just make another Compositor
// and assign the 'compositor' field in GUIGraphics.
// However for now mipmaps and are not negotiable.
interface Compositor
{
    void compositeTile(ImageRef!RGBA wfb, WindowPixelFormat pf, box2i area,
                       Mipmap!RGBA* diffuseMap,
                       Mipmap!RGBA* materialMap,
                       Mipmap!L16* depthMap,
                       Mipmap!RGBA* skybox) nothrow @nogc;
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
        light1Color = vec3f(0.54f, 0.50f, 0.46f) * 0.4f;

        light2Dir = vec3f(0.0f, 1.0f, 0.1f).normalized;
        light2Color = vec3f(0.378f, 0.35f, 0.322f) * 0.85f;

        light3Dir = vec3f(0.0f, 1.0f, 0.1f).normalized;
        light3Color = vec3f(0.378f, 0.35f, 0.322f);

        ambientLight = 0.10f;
        skyboxAmount = 0.4f;

        for (int roughByte = 0; roughByte < 256; ++roughByte)
        {
            _exponentTable[roughByte] = 0.8f * exp( (1-roughByte / 255.0f) * 5.5f);
        }
    }

    /// Calling this setup color correction table, with the well
    /// known lift-gamma-gain formula.
    void setLiftGammaGain(float lift = 0.0f, float gamma = 1.0f, float gain = 1.0f)
    {
        setLiftGammaGainRGB(lift, gamma, gain,
                            lift, gamma, gain,
                            lift, gamma, gain);
    }

    /+ Does not work like that

    /// Calling this setup color correction tables, that you can get from GIMP curve tool.
    void setColorCorrectionGIMP(const(double[]) valueTable, const(double[]) rTable,
                                const(double[]) gTable, const(double[]) bTable)
    {

        _useTransferTables = true;
        _redTransferTable = new ubyte[256];
        _greenTransferTable = new ubyte[256];
        _blueTransferTable = new ubyte[256];

        for (int b = 0; b < 256; ++b)
        {
            double inp = b / 255.0;
            double value = valueTable[b] - inp;
            double outR = rTable[b] + value;
            double outG = gTable[b] + value;
            double outB = bTable[b] + value;
            outR = std.algorithm.clamp!double(outR, 0.0, 1.0);
            outG = std.algorithm.clamp!double(outG, 0.0, 1.0);
            outB = std.algorithm.clamp!double(outB, 0.0, 1.0);
            _redTransferTable[b] = cast(ubyte)(0.5 + outR * 255);
            _greenTransferTable[b] = cast(ubyte)(0.5 + outG * 255);
            _blueTransferTable[b] = cast(ubyte)(0.5 + outB * 255);
        }
    }

    +/

    /// Calling this setup color correction table, with the well
    /// known lift-gamma-gain formula.
    void setLiftGammaGainRGB(float rLift = 0.0f, float rGamma = 1.0f, float rGain = 1.0f,
                             float gLift = 0.0f, float gGamma = 1.0f, float gGain = 1.0f,
                             float bLift = 0.0f, float bGamma = 1.0f, float bGain = 1.0f)
    {
        _useTransferTables = true;
        _redTransferTable = new ubyte[256];
        _greenTransferTable = new ubyte[256];
        _blueTransferTable = new ubyte[256];

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

            outR = gfm.math.clamp!float(outR, 0.0f, 1.0f);
            outG = gfm.math.clamp!float(outG, 0.0f, 1.0f);
            outB = gfm.math.clamp!float(outB, 0.0f, 1.0f);
            _redTransferTable[b] = cast(ubyte)(0.5f + outR * 255.0f);
            _greenTransferTable[b] = cast(ubyte)(0.5f + outG * 255.0f);
            _blueTransferTable[b] = cast(ubyte)(0.5f + outB * 255.0f);
        }
    }

    /// Don't like this rendering? Feel free to override this method.
    override void compositeTile(ImageRef!RGBA wfb, WindowPixelFormat pf, box2i area,
                                Mipmap!RGBA* diffuseMap,
                                Mipmap!RGBA* materialMap,
                                Mipmap!L16* depthMap,
                                Mipmap!RGBA* skybox) nothrow @nogc
    {
        ushort[5][5] depthPatch = void;
        L16*[5] depth_scan = void;

        //Mipmap!RGBA* skybox = &context.skybox;
        int w = diffuseMap.levels[0].w;
        int h = diffuseMap.levels[0].h;
        float invW = 1.0f / w;
        float invH = 1.0f / h;
        float div255 = 1 / 255.0f;

        for (int j = area.min.y; j < area.max.y; ++j)
        {
            RGBA* wfb_scan = wfb.scanline(j).ptr;

            // clamp to existing lines
            for (int l = 0; l < 5; ++l)
            {
                int lineIndex = gfm.math.clamp!int(j - 2 + l, 0, h - 1);
                depth_scan[l] = depthMap.levels[0].scanline(lineIndex).ptr;
            }

            RGBA* materialScan = materialMap.levels[0].scanline(j).ptr;

            for (int i = area.min.x; i < area.max.x; ++i)
            {
                RGBA materialHere = materialScan[i];

                // Bypass PBR if Physical == 0
                if (materialHere.a == 0)
                {

                    RGBA diffuse = diffuseMap.levels[0][i, j];
                    RGBA finalColor = void;
                    final switch (pf) with (WindowPixelFormat)
                    {
                        case ARGB8:
                            finalColor = RGBA(255, diffuse.r, diffuse.g, diffuse.b);
                            break;
                        case BGRA8:
                            finalColor = RGBA(diffuse.b, diffuse.g, diffuse.r, 255);
                            break;
                        case RGBA8:
                            finalColor = RGBA(diffuse.r, diffuse.g, diffuse.b, 255);
                            break;
                    }

                    // write composited color
                    wfb_scan[i] = finalColor;
                }
                else
                {
                    // clamp to existing columns

                    {
                        // Get depth for a 5x5 patch
                        // Turns out DMD like hand-unrolling:(
                        for (int k = 0; k < 5; ++k)
                        {
                            int col_index = gfm.math.clamp(i - 2 + k, 0, w - 1);
                            depthPatch[0][k] = depth_scan.ptr[0][col_index].l;
                            depthPatch[1][k] = depth_scan.ptr[1][col_index].l;
                            depthPatch[2][k] = depth_scan.ptr[2][col_index].l;
                            depthPatch[3][k] = depth_scan.ptr[3][col_index].l;
                            depthPatch[4][k] = depth_scan.ptr[4][col_index].l;
                        }
                    }

                    // compute normal
                    float sx = depthPatch[1][1]
                        + depthPatch[2][1] * 2
                        + depthPatch[3][1]
                        - ( depthPatch[1][3]
                            + depthPatch[2][3] * 2
                           + depthPatch[3][3]);

                   float sy = depthPatch[3][1] + depthPatch[3][2] * 2 + depthPatch[3][3]
                        - ( depthPatch[1][1] + depthPatch[1][2] * 2 + depthPatch[1][3]);

                    // this factor basically tweak normals to make the UI flatter or not
                    // if you change normal filtering, retune this
                    enum float sz = 260.0f * 257.0f / 1.8f; 

                    vec3f normal = vec3f(sx, sy, sz);
                    normal.normalize();

                    RGBA ibaseColor = diffuseMap.levels[0][i, j];
                    vec3f baseColor = vec3f(ibaseColor.r, ibaseColor.g, ibaseColor.b) * div255;

                    vec3f toEye = vec3f(0.5f - i * invW, j * invH - 0.5f, 1.0f);
                    toEye.normalize();

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

                        float diff = depthPatch[2][2] - avgDepthHere;
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

                        int depthHere = depthPatch[2][2];
                        for (int sample = 1; sample < samples; ++sample)
                        {
                            int x = i + sample;
                            if (x >= w)
                                x = w - 1;
                            int y = j - sample;
                            if (y < 0)
                                y = 0;
                            int z = depthHere + sample;
                            int diff = z - depthMap.levels[0][x, y].l;

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
                        float depthDX = depthPatch[3][1] + depthPatch[3][2] + depthPatch[3][3]
                            + depthPatch[1][1] + depthPatch[1][2] + depthPatch[1][3]
                            - 2 * (depthPatch[2][1] + depthPatch[2][2] + depthPatch[2][3]);

                        float depthDY = depthPatch[1][3] + depthPatch[2][3] + depthPatch[3][3]
                            + depthPatch[1][1] + depthPatch[2][1] + depthPatch[3][1]
                            - 2 * (depthPatch[1][2] + depthPatch[2][2] + depthPatch[3][2]);

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

                        // Get alpha-premultiplied, avoids some white highlights
                        // Maybe we could solve the white highlights by having the whole mipmap premultiplied
                        vec4f colorLevel1 = diffuseMap.linearSample!true(1, ic, jc);
                        vec4f colorLevel2 = diffuseMap.linearSample!true(2, ic, jc);
                        vec4f colorLevel3 = diffuseMap.linearSample!true(3, ic, jc);
                        vec4f colorLevel4 = diffuseMap.linearSample!true(4, ic, jc);
                        vec4f colorLevel5 = diffuseMap.linearSample!true(5, ic, jc);

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
                        //    float depthColor = depthPatch[2][2] / 65535.0f;
                        //    color = vec3f(depthColor);
                    }

                    // Show diffuse
                    //color = baseColor;

                    //  color = toEye;
                    //color = vec3f(cavity);

                    color.x = gfm.math.clamp(color.x, 0.0f, 1.0f);
                    color.y = gfm.math.clamp(color.y, 0.0f, 1.0f);
                    color.z = gfm.math.clamp(color.z, 0.0f, 1.0f);

                    int r = cast(int)(color.x * 255.99f);
                    int g = cast(int)(color.y * 255.99f);
                    int b = cast(int)(color.z * 255.99f);

                    RGBA finalColor = void;

                    final switch (pf) with (WindowPixelFormat)
                    {
                        case ARGB8:
                            finalColor = RGBA(255, cast(ubyte)r, cast(ubyte)g, cast(ubyte)b);
                            break;
                        case BGRA8:
                            finalColor = RGBA(cast(ubyte)b, cast(ubyte)g, cast(ubyte)r, 255);
                            break;
                        case RGBA8:
                            finalColor = RGBA(cast(ubyte)r, cast(ubyte)g, cast(ubyte)b, 255);
                            break;
                    }

                    // write composited color
                    wfb_scan[i] = finalColor;
                }
            }
        }

        // Optional look-up table for color-correction
        if (_useTransferTables)
        {
            ubyte* red = _redTransferTable.ptr;
            ubyte* green = _greenTransferTable.ptr;
            ubyte* blue = _blueTransferTable.ptr;
            

            for (int j = area.min.y; j < area.max.y; ++j)
            {
                RGBA* wfb_scan = wfb.scanline(j).ptr;

                final switch (pf) with (WindowPixelFormat)
                {
                    case ARGB8:
                        for (int i = area.min.x; i < area.max.x; ++i)
                        {
                            RGBA color = wfb_scan[i];
                            color.g = red[color.g];
                            color.b = green[color.b];
                            color.a = blue[color.a];
                            wfb_scan[i] = color;
                        }
                        break;
                    case BGRA8:
                        for (int i = area.min.x; i < area.max.x; ++i)
                        {
                            RGBA color = wfb_scan[i];
                            color.r = blue[color.r];
                            color.g = green[color.g];
                            color.b = red[color.b];
                            wfb_scan[i] = color;
                        }
                        break;
                    case RGBA8:
                        for (int i = area.min.x; i < area.max.x; ++i)
                        {
                            RGBA color = wfb_scan[i];
                            color.r = red[color.r];
                            color.g = green[color.g];
                            color.b = blue[color.b];
                            wfb_scan[i] = color;
                        }
                        break;
                }                
            }
        }
    }

private:
    // Assign those to use lookup tables.
    bool _useTransferTables = false;
    ubyte[] _redTransferTable = null;
    ubyte[] _greenTransferTable = null;
    ubyte[] _blueTransferTable = null;

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


