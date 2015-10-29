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
                       Mipmap!RGBA* _diffuseMap,
                       Mipmap!RGBA* _materialMap,
                       Mipmap!L16* _depthMap,
                       Mipmap!RGBA* skybox);
}

/// "Physically Based"-style rendering
class PBRCompositor : Compositor
{
    // light 1 used for key lighting and shadows
    // always coming from top-right
    vec3f light1Color;

    // light 2 used for things using the normal
    vec3f light2Dir;
    vec3f light2Color;

    float ambientLight;

    // Assign those to use lookup tables.
    bool useTransferTables = false;
    ubyte[] redTransferTable = null;
    ubyte[] greenTransferTable = null;
    ubyte[] blueTransferTable = null;

    this()
    {
        // defaults
        light1Color = vec3f(0.54f, 0.50f, 0.46f) * 0.4f;

        light2Dir = vec3f(0.0f, 1.0f, 0.1f).normalized;
        light2Color = vec3f(0.378f, 0.35f, 0.322f);
        ambientLight = 0.15f;
    }

    /// Don't like this rendering? Feel free to override this method.
    override void compositeTile(ImageRef!RGBA wfb, WindowPixelFormat pf, box2i area,
                                Mipmap!RGBA* _diffuseMap,
                                Mipmap!RGBA* _materialMap,
                                Mipmap!L16* _depthMap,
                                Mipmap!RGBA* skybox)
    {
        int[5] line_index = void;
        ushort[5][5] depthPatch = void;
        int[5] col_index = void;
        L16*[5] depth_scan = void;

        //Mipmap!RGBA* skybox = &context.skybox;
        int w = _diffuseMap.levels[0].w;
        int h = _diffuseMap.levels[0].h;
        float invW = 1.0f / w;
        float invH = 1.0f / h;
        float div255 = 1 / 255.0f;

        for (int j = area.min.y; j < area.max.y; ++j)
        {
            RGBA* wfb_scan = wfb.scanline(j).ptr;

            // clamp to existing lines

            for (int l = 0; l < 5; ++l)
                line_index[l] = gfm.math.clamp(j - 2 + l, 0, h - 1);


            for (int l = 0; l < 5; ++l)
                depth_scan[l] = _depthMap.levels[0].scanline(line_index[l]).ptr;

            RGBA* materialScan = _materialMap.levels[0].scanline(j).ptr;

            for (int i = area.min.x; i < area.max.x; ++i)
            {
                RGBA materialHere = materialScan[i];

                // Bypass PBR if Physical == 0
                if (materialHere.a == 0)
                {

                    RGBA diffuse = _diffuseMap.levels[0][i, j];
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

                    for (int k = 0; k < 5; ++k)
                        col_index[k] = gfm.math.clamp(i - 2 + k, 0, w - 1);

                    // Get depth for a 5x5 patch

                    for (int l = 0; l < 5; ++l)
                    {
                        for (int k = 0; k < 5; ++k)
                        {
                            ushort depthSample = depth_scan.ptr[l][col_index[k]].l;
                            depthPatch.ptr[l].ptr[k] = depthSample;
                        }
                    }

                    // compute normal
                    float sx = depthPatch[1][0]     + depthPatch[1][1] * 2
                        + depthPatch[2][0] * 2 + depthPatch[2][1] * 4
                        + depthPatch[3][0]     + depthPatch[3][1] * 2
                        - ( depthPatch[1][3] * 2 + depthPatch[1][4]
                            + depthPatch[2][3] * 4 + depthPatch[2][4] * 2
                           + depthPatch[3][3] * 2 + depthPatch[3][4] );

                    float sy = depthPatch[3][1] * 2 + depthPatch[3][2] * 4 + depthPatch[3][3] * 2
                        + depthPatch[4][1]     + depthPatch[4][2] * 2 + depthPatch[4][3]
                        - ( depthPatch[0][1]     + depthPatch[0][2] * 2 + depthPatch[0][3]
                            + depthPatch[1][1] * 2 + depthPatch[1][2] * 4 + depthPatch[1][3] * 2);

                    enum float sz = 260.0f * 257.0f; // this factor basically tweak normals to make the UI flatter or not

                    vec3f normal = vec3f(sx, sy, sz);
                    normal.normalize();

                    RGBA ibaseColor = _diffuseMap.levels[0][i, j];
                    vec3f baseColor = vec3f(ibaseColor.r, ibaseColor.g, ibaseColor.b) * div255;

                    vec3f toEye = vec3f(0.5f - i * invW, j * invH - 0.5f, 1.0f);
                    toEye.normalize();

                    vec3f color = vec3f(0.0f);

                    float roughness = materialHere.r * div255;
                    float metalness = materialHere.g * div255;
                    float specular  = materialHere.b * div255;                

                    float cavity;

                    // Add ambient component
                    {
                        float px = i + 0.5f;
                        float py = j + 0.5f;

                        float avgDepthHere =
                            ( _depthMap.linearSample(1, px, py)
                              + _depthMap.linearSample(2, px, py)
                             + _depthMap.linearSample(3, px, py)
                             + _depthMap.linearSample(4, px, py) ) * 0.25f;

                        cavity = ctLinearStep!(-90.0f * 256.0f, 0.0f)(depthPatch[2][2] - avgDepthHere);

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
                            int diff = z - _depthMap.levels[0][x, y].l;
                            lightPassed += ctLinearStep!(-60.0f * 256.0f, 0.0f)(diff) * weights.ptr[sample];
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
                        vec3f lightReflect = reflect(-light2Dir, normal);
                        float specularFactor = dot(toEye, lightReflect);
                        if (specularFactor > 0)
                        {
                            float exponent = 0.8f * exp( (1-roughness) * 5.5f);
                            specularFactor = specularFactor ^^ exponent;
                            float roughFactor = 10 * (1.0f - roughness) * (1 - metalness * 0.5f);
                            specularFactor = /* cavity * */ specularFactor * roughFactor;
                            if (specularFactor != 0)
                                color += baseColor * light2Color * (specularFactor * specular);
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

                        vec3f skyColor = skybox.linearMipmapSample(mipLevel, skyx, skyy).rgb * (div255 * metalness * 0.4f);
                        color += skyColor * baseColor;
                    }

                    // Add light emitted by neighbours
                    {
                        float ic = i + 0.5f;
                        float jc = j + 0.5f;

                        // Get alpha-premultiplied, avoids some white highlights
                        // Maybe we could solve the white highlights by having the whole mipmap premultiplied
                        vec4f colorLevel1 = _diffuseMap.linearSample!true(1, ic, jc);
                        vec4f colorLevel2 = _diffuseMap.linearSample!true(2, ic, jc);
                        vec4f colorLevel3 = _diffuseMap.linearSample!true(3, ic, jc);
                        vec4f colorLevel4 = _diffuseMap.linearSample!true(4, ic, jc);
                        vec4f colorLevel5 = _diffuseMap.linearSample!true(5, ic, jc);

                        vec4f emitted = colorLevel1 * 0.2f;
                        emitted += colorLevel2 * 0.3f;
                        emitted += colorLevel3 * 0.25f;
                        emitted += colorLevel4 * 0.15f;
                        emitted += colorLevel5 * 0.10f;

                        emitted *= (div255 * 1.5f);

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

        // Optional look-up table
        if (useTransferTables)
        {
            ubyte* red = redTransferTable.ptr;
            ubyte* green = greenTransferTable.ptr;
            ubyte* blue = blueTransferTable.ptr;
            for (int j = area.min.y; j < area.max.y; ++j)
            {
                RGBA* wfb_scan = wfb.scanline(j).ptr;

                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    RGBA color = wfb_scan[i];
                    color.r = red[color.r];
                    color.g = green[color.g];
                    color.b = blue[color.b];
                    wfb_scan[i] = color;
                }
            }
        }
    }
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
float fastlog2(float val)
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


