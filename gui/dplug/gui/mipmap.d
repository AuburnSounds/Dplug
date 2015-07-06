/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.mipmap;

import std.algorithm;

import ae.utils.graphics;

import gfm.core;
import gfm.math.vector;
import gfm.math.box;



version( D_InlineAsm_X86 )
{
    version = AsmX86;
}
else version( D_InlineAsm_X86_64 )
{
    version = AsmX86;
}


/// Mipmapped images.
/// Supports non power-of-two textures.
/// Size of the i+1-th mipmap is { (width)/2, (height)/2 }
struct Mipmap
{
    enum Quality
    {
        box,          // simple 2x2 filter, creates phase problems with NPOT. For higher levels, automatically uses cubic.
        boxAlphaCov,  // ditto but alpha is used as weight
        polyphase,    // From the "NPOT2 Mipmap Creation" paper from NVIDIA. Not useful.
        cubic,        // Very smooth kernel [1 2 1] x [1 2 1]
        cubicAlphaCov // ditto but alpha is used as weight
    }

    Image!RGBA[] levels;

    @disable this(this);

    /// Set number of levels and size
    /// maxLevel = 0 => only one image
    /// maxLevel = 1 => one image + one 2x downsampled mipmap
    void size(int maxLevel, int w, int h)
    {
        levels.length = 0;

        for (int level = 0; level <= maxLevel; ++level)
        {
            if (w == 0 || h == 0)
                break;
            levels.length = levels.length + 1;
            levels[level].size(w, h);
            w  = (w + 0) >> 1;
            h  = (h + 0) >> 1;
        }
    }

    /// Interpolates a color between mipmap levels.  Floating-point level, spatial linear interpolation.
    /// x and y are in base level coordinates (top-left pixel is on (0.5, 0.5) coordinates).
    /// Clamped to borders.
    vec4f linearMipmapSample(bool premultiplied = false)(float level, float x, float y)
    {
        int ilevel = cast(int)level;
        float flevel = level - ilevel;
        vec4f levelN = linearSample!premultiplied(ilevel, x, y);
        if (flevel == 0)
            return levelN;

        vec4f levelNp1 = linearSample!premultiplied(ilevel + 1, x, y);

        return levelN * (1 - flevel) + levelNp1 * flevel;
    }


    /// Interpolates a color.  Integer level, spatial linear interpolation.
    /// x and y are in base level coordinates (top-left pixel is on (0.5, 0.5) coordinates).
    /// Clamped to borders.
    vec4f linearSample(bool premultiplied = false)(int level, float x, float y)
    {
        if (level < 0)
            level = 0;
        int numLevels = cast(int)levels.length;
        if (level >= numLevels)
            level = numLevels - 1;

        Image!RGBA* image = &levels[level];


        static immutable float[14] factors = [ 1.0f, 0.5f, 0.25f, 0.125f, 
                                               0.0625f, 0.03125f, 0.015625f, 0.0078125f, 
                                               0.00390625f, 0.001953125f, 0.0009765625f, 0.00048828125f,
                                               0.000244140625f, 0.0001220703125f];

        float divider = factors[level];
        x = x * divider - 0.5f;
        y = y * divider - 0.5f;

        float maxX = image.w - 1.001f; // avoids an edge case with truncation
        float maxY = image.h - 1.001f;

        if (x < 0)
            x = 0;
        if (y < 0)
            y = 0;
        if (x > maxX)
            x = maxX;
        if (y > maxY)
            y = maxY;

        int ix = cast(int)x;
        int iy = cast(int)y;
        float fx = x - ix;

        int ixp1 = ix + 1;
        if (ixp1 >= image.w)
            ixp1 = image.w - 1;
        int iyp1 = iy + 1;
        if (iyp1 >= image.h)
            iyp1 = image.h - 1;

        float fxm1 = 1 - fx;
        float fy = y - iy;
        float fym1 = 1 - fy;

        RGBA[] L0 = image.scanline(iy);
        RGBA[] L1 = image.scanline(iyp1);

        RGBA A = L0.ptr[ix];
        RGBA B = L0.ptr[ixp1];
        RGBA C = L1.ptr[ix];
        RGBA D = L1.ptr[ixp1];

        float inv255 = 1 / 255.0f;

        version( Asm_X86 )
        {
            vec4f result;

            asm
            {
                movd XMM0, A;
                movd XMM1, B;
                movd XMM2, C;
                movd XMM3, D;
                pxor XMM4, XMM4;

                punpcklbw XMM0, XMM4;
                punpcklbw XMM1, XMM4;
                punpcklbw XMM2, XMM4;
                punpcklbw XMM3, XMM4;
      
                punpcklwd XMM0, XMM4;
                punpcklwd XMM1, XMM4;
                punpcklwd XMM2, XMM4;
                punpcklwd XMM3, XMM4;

                mov ECX, premultiplied;

                cvtdq2ps XMM0, XMM0;
                cvtdq2ps XMM1, XMM1;

                cvtdq2ps XMM2, XMM2;
                cvtdq2ps XMM3, XMM3;

                cmp ECX, 0;
                jz not_premultiplied;

                    movaps XMM5, XMM0;
                    pshufd XMM5, XMM5, 0; // A.a A.a A.a A.a
                    mulps XMM0, XMM5;

                    movaps XMM5, XMM1;
                    pshufd XMM5, XMM5, 0; // B.a B.a B.a B.a
                    mulps XMM1, XMM5;

                    movaps XMM5, XMM2;
                    pshufd XMM5, XMM5, 0; // C.a C.a C.a C.a
                    mulps XMM2, XMM5;

                    movaps XMM5, XMM3;
                    pshufd XMM5, XMM5, 0; // D.a D.a D.a D.a
                    mulps XMM3, XMM5;

                    movss XMM4, inv255;
                    pshufd XMM4, XMM4, 0;

                    mulps XMM0, XMM4;
                    mulps XMM1, XMM4;
                    mulps XMM2, XMM4;
                    mulps XMM3, XMM4;

                not_premultiplied:

                movss XMM4, fxm1;
                pshufd XMM4, XMM4, 0;
                movss XMM5, fx;
                pshufd XMM5, XMM5, 0;

                mulps XMM0, XMM4;
                mulps XMM1, XMM5;
                mulps XMM2, XMM4;
                mulps XMM3, XMM5;

                movss XMM4, fym1;
                pshufd XMM4, XMM4, 0;
                movss XMM5, fy;
                pshufd XMM5, XMM5, 0;

                addps XMM0, XMM1;
                addps XMM2, XMM3;

                mulps XMM0, XMM4;
                mulps XMM2, XMM5;

                addps XMM0, XMM2;

                movups result, XMM0;
            }

            return result;
        }
        else
        {
            vec4f vA = vec4f(A.r, A.g, A.b, A.a);
            vec4f vB = vec4f(B.r, B.g, B.b, B.a);
            vec4f vC = vec4f(C.r, C.g, C.b, C.a);
            vec4f vD = vec4f(D.r, D.g, D.b, D.a);

            static if (premultiplied)
            {
                vA *= vec4f(vA.a * inv255);
                vB *= vec4f(vB.a * inv255);
                vC *= vec4f(vC.a * inv255);
                vD *= vec4f(vD.a * inv255);
            }

            vec4f up = vA * fxm1 + vB * fx;
            vec4f down = vC * fxm1 + vD * fx;
            vec4f dResult = up * fym1 + down * fy;

          //  assert(dResult.distanceTo(asmResult) < 1.0f);

            return dResult;
        }
    }

    /// Returns: Width of the base level.
    int width() pure const nothrow @nogc
    {
        return levels[0].w;
    }

    /// Returns: Height of the base level.
    int height() pure const nothrow @nogc
    {
        return levels[0].h;
    }

    /// Returns: Number of levels. The maximum level is numLevels() - 1.
    int numLevels() pure const nothrow @nogc
    {
        return cast(int)levels.length;
    }

    /// Regenerates the whole upper levels.
    void generateMipmaps(Quality quality) nothrow @nogc
    {
        box2i updateRect = box2i(0, 0, width(), height());
        for (int level = 1; level < numLevels(); ++level)
        {
            // HACK: Force cubic filter past a level else it makes ugly looking mipmaps
            if (level >= 3 && quality == Quality.box)
                quality = Quality.cubic;

            updateRect = generateNextLevel(quality, updateRect, level);
        }
    }

    /// Regenerates a single mipmap level based on changes in the provided rectangle (expressed in level 0 coordinates).
    /// updateRect expressed in level 0 coordinates
    /// In general if you have several subparts of mipmaps to update, make sure a level is fully completed
    /// before computing the next one.
    box2i generateNextLevel(Quality quality, box2i updateRectPreviousLevel, int level) nothrow @nogc
    {
        Image!RGBA* previousLevel = &levels[level - 1];
        box2i updateRect = impactOnNextLevel(quality, updateRectPreviousLevel, previousLevel.w, previousLevel.h);
        generateLevel(level, quality, updateRect);
        return updateRect;
    }

    /// Regenerates one level
    /// updateRect expressed in level i-th coordinates
    void generateLevel(int level, Quality quality, box2i updateRect) nothrow @nogc
    {
        assert(level > 0);
        Image!RGBA* thisLevel = &levels[level];
        Image!RGBA* previousLevel = &levels[level - 1];

        final switch (quality) with (Quality)
        {
        case box:
            for (int y = updateRect.min.y; y < updateRect.max.y; ++y)
            {
                RGBA[] L0 = previousLevel.scanline(y * 2);
                RGBA[] L1 = previousLevel.scanline(y * 2 + 1);
                RGBA[] dest = thisLevel.scanline(y);

                for (int x = updateRect.min.x; x < updateRect.max.x; ++x)
                {
                    // A B
                    // C D
                    RGBA A = L0.ptr[2 * x];
                    RGBA B = L0.ptr[2 * x + 1];
                    RGBA C = L1.ptr[2 * x];
                    RGBA D = L1.ptr[2 * x + 1];
                    dest.ptr[x] = RGBA.op!q{(a + b + c + d + 2) >> 2}(A, B, C, D);
                }
            }
            break;
            
        case boxAlphaCov:
            for (int y = updateRect.min.y; y < updateRect.max.y; ++y)
            {
                RGBA[] L0 = previousLevel.scanline(y * 2);
                RGBA[] L1 = previousLevel.scanline(y * 2 + 1);
                RGBA[] dest = thisLevel.scanline(y);

                for (int x = updateRect.min.x; x < updateRect.max.x; ++x)
                {
                    // A B
                    // C D
                    RGBA A = L0.ptr[2 * x];
                    RGBA B = L0.ptr[2 * x + 1];
                    RGBA C = L1.ptr[2 * x];
                    RGBA D = L1.ptr[2 * x + 1];

                    int alphaA = A.a;
                    int alphaB = B.a;
                    int alphaC = C.a;
                    int alphaD = D.a;
                    int sum = alphaA + alphaB + alphaC + alphaD;
                    if (sum == 0)
                    {
                        dest.ptr[x] = A;
                    }
                    else
                    {
                        int destAlpha = cast(ubyte)( (alphaA + alphaB + alphaC + alphaD + 2) >> 2 );
                        int red =   (A.r * alphaA + B.r * alphaB + C.r * alphaC + D.r * alphaD);
                        int green = (A.g * alphaA + B.g * alphaB + C.g * alphaC + D.g * alphaD);
                        int blue =  (A.b * alphaA + B.b* alphaB + C.b * alphaC + D.b * alphaD);
                        int offset = sum >> 1;

                        RGBA finalColor = RGBA( cast(ubyte)( (red + offset) / sum),
                                                cast(ubyte)( (green + offset) / sum),
                                                cast(ubyte)( (blue + offset) / sum),
                                                cast(ubyte)destAlpha );
                        dest.ptr[x] = finalColor;
                    }
                }
            }
            break;

        case polyphase:
    
            int ny = thisLevel.h;
            int nx = thisLevel.w;
            int dividerx = (2 * nx + 1);
            int dividery = (2 * ny + 1);
            float invDivider = 1.0f / (cast(float)dividerx * dividery);

            for (int y = updateRect.min.y; y < updateRect.max.y; ++y)
            {
                RGBA[] L0 = previousLevel.scanline(y * 2);
                RGBA[] L1 = previousLevel.scanline(y * 2 + 1);
                RGBA[] L2 = previousLevel.scanline(min(y * 2 + 2, previousLevel.h - 1));
                RGBA[] dest = thisLevel.scanline(y);


                int w0y = (ny - y);
                int w1y = ny;
                int w2y = 1 + y;

                for (int x = updateRect.min.x; x < updateRect.max.x; ++x)
                {
                    // A B C
                    // D E F
                    // G H I

                    int x2p0 = 2 * x;
                    int x2p1 = 2 * x + 1;
                    int x2p2 = min(2 * x + 2, previousLevel.w - 1);

                    RGBA A = L0.ptr[x2p0];
                    RGBA B = L0.ptr[x2p1];
                    RGBA C = L0.ptr[x2p2];

                    RGBA D = L1.ptr[x2p0];
                    RGBA E = L1.ptr[x2p1];
                    RGBA F = L1.ptr[x2p2];

                    RGBA G = L2.ptr[x2p0];
                    RGBA H = L2.ptr[x2p1];
                    RGBA I = L2.ptr[x2p2];

                    // filter horizontally first
                    int w0x = (nx - x);
                    int w1x = nx;
                    int w2x = 1 + x;

                    float rL0 = A.r * w0x + B.r * w1x + C.r * w2x;
                    float gL0 = A.g * w0x + B.g * w1x + C.g * w2x;
                    float bL0 = A.b * w0x + B.b * w1x + C.b * w2x;
                    float aL0 = A.a * w0x + B.a * w1x + C.a * w2x;

                    float rL1 = D.r * w0x + E.r * w1x + F.r * w2x;
                    float gL1 = D.g * w0x + E.g * w1x + F.g * w2x;
                    float bL1 = D.b * w0x + E.b * w1x + F.b * w2x;
                    float aL1 = D.a * w0x + E.a * w1x + F.a * w2x;

                    float rL2 = G.r * w0x + H.r * w1x + I.r * w2x;
                    float gL2 = G.g * w0x + H.g * w1x + I.g * w2x;
                    float bL2 = G.b * w0x + H.b * w1x + I.b * w2x;
                    float aL2 = G.a * w0x + H.a * w1x + I.a * w2x;

                    float r = (rL0 * w0y + rL1 * w1y + rL2 * w2y) * invDivider;
                    float g = (gL0 * w0y + gL1 * w1y + gL2 * w2y) * invDivider;
                    float b = (bL0 * w0y + bL1 * w1y + bL2 * w2y) * invDivider;
                    float a = (aL0 * w0y + aL1 * w1y + aL2 * w2y) * invDivider;

                    // then filter vertically
                    dest.ptr[x] = RGBA(cast(ubyte)(r + 0.5f), cast(ubyte)(g + 0.5f), cast(ubyte)(b + 0.5f), cast(ubyte)(a + 0.5f));
                }
            }
            break;

        case cubic:
        case cubicAlphaCov:
            for (int y = updateRect.min.y; y < updateRect.max.y; ++y)
            {
                RGBA[] LM1 = previousLevel.scanline(max(y * 2 - 1, 0));
                RGBA[] L0 = previousLevel.scanline(y * 2);
                RGBA[] L1 = previousLevel.scanline(y * 2 + 1);
                RGBA[] L2 = previousLevel.scanline(min(y * 2 + 2, previousLevel.h - 1));
                RGBA[] dest = thisLevel.scanline(y);

                for (int x = updateRect.min.x; x < updateRect.max.x; ++x)
                {
                    // A B C D
                    // E F G H
                    // I J K L
                    // M N O P

                    int x2m1 = max(0, 2 * x - 1);
                    int x2p0 = 2 * x;
                    int x2p1 = 2 * x + 1;
                    int x2p2 = min(2 * x + 2, previousLevel.w - 1);

                    auto A = LM1.ptr[x2m1];
                    auto B = LM1.ptr[x2p0];
                    auto C = LM1.ptr[x2p1];
                    auto D = LM1.ptr[x2p2];

                    auto E = L0.ptr[x2m1];
                    auto F = L0.ptr[x2p0];
                    auto G = L0.ptr[x2p1];
                    auto H = L0.ptr[x2p2];

                    auto I = L1.ptr[x2m1];
                    auto J = L1.ptr[x2p0];
                    auto K = L1.ptr[x2p1];
                    auto L = L1.ptr[x2p2];

                    auto M = L2.ptr[x2m1];
                    auto N = L2.ptr[x2p0];
                    auto O = L2.ptr[x2p1];
                    auto P = L2.ptr[x2p2];


                    if (quality == Quality.cubic)
                    {
                        // Apply filter
                        // 1 3 3 1
                        // 3 9 9 3
                        // 3 9 9 3
                        // 1 3 3 1

                        RGBA line0 = RGBA.op!q{(a + d + 3 * (b + c) + 4) >> 3}(A, B, C, D);
                        RGBA line1 = RGBA.op!q{(a + d + 3 * (b + c) + 4) >> 3}(E, F, G, H);
                        RGBA line2 = RGBA.op!q{(a + d + 3 * (b + c) + 4) >> 3}(I, J, K, L);
                        RGBA line3 = RGBA.op!q{(a + d + 3 * (b + c) + 4) >> 3}(M, N, O, P);
                        dest.ptr[x] = RGBA.op!q{(a + d + 3 * (b + c) + 4) >> 3}(line0, line1, line2, line3);
                    }
                    else
                    {
                        // Apply filter + alpha weighting
                        // 1 3 3 1
                        // 3 9 9 3 multiplied by alpha are the filter
                        // 3 9 9 3
                        // 1 3 3 1

                        // Perform the [1 3 3 1] kernel + alpha weighing
                        static RGBA merge4(RGBA a, RGBA b, RGBA c, RGBA d) nothrow @nogc
                        {
                            int alphaA = a.a;
                            int alphaB = b.a * 3;
                            int alphaC = c.a * 3;
                            int alphaD = d.a;
                            int sum = alphaA + alphaB + alphaC + alphaD;
                            if (sum == 0)
                            {
                                return a; // return any since alpha is zero, it won't count
                            }
                            else
                            {
                                ubyte destAlpha = cast(ubyte)( (sum + 4) >> 3 );
                                int red =   (a.r * alphaA + b.r * alphaB + c.r * alphaC + d.r * alphaD);
                                int green = (a.g * alphaA + b.g * alphaB + c.g * alphaC + d.g * alphaD);
                                int blue =  (a.b * alphaA + b.b* alphaB + c.b * alphaC + d.b * alphaD);
                                int offset = sum >> 1;

                                return RGBA( cast(ubyte)( (red + offset) / sum),
                                             cast(ubyte)( (green + offset) / sum),
                                             cast(ubyte)( (blue + offset) / sum),
                                             destAlpha );
                            }
                        }

                        RGBA line0 = merge4(A, B, C, D);
                        RGBA line1 = merge4(E, F, G, H);
                        RGBA line2 = merge4(I, J, K, L);
                        RGBA line3 = merge4(M, N, O, P);
                        dest.ptr[x] = merge4(line0, line1, line2, line3);
                    }
                }
            }
        }
    }


private:
    /// Computes impact of updating the area box on next level
    static box2i impactOnNextLevel(Quality quality, box2i area, int currentLevelWidth, int currentLevelHeight) pure nothrow @nogc
    {
        box2i maxArea = box2i(0, 0, currentLevelWidth / 2, currentLevelHeight / 2);

        final switch(quality) with (Quality)
        {
        case box:
        case boxAlphaCov:
            int xmin = area.min.x / 2;
            int ymin = area.min.y / 2;
            int xmax = (area.max.x + 1) / 2;
            int ymax = (area.max.y + 1) / 2;
            return box2i(xmin, ymin, xmax, ymax).intersection(maxArea);

        case polyphase:
            int xmin = (area.min.x - 1) / 2;
            int ymin = (area.min.y - 1) / 2;
            int xmax = (area.max.x + 1) / 2;
            int ymax = (area.max.y + 1) / 2;
            return box2i(xmin, ymin, xmax, ymax).intersection(maxArea);

        case cubic:
        case cubicAlphaCov:
            int xmin = (area.min.x - 1) / 2;
            int ymin = (area.min.y - 1) / 2;
            int xmax = (area.max.x + 2) / 2;
            int ymax = (area.max.y + 2) / 2;
            return box2i(xmin, ymin, xmax, ymax).intersection(maxArea);
        }
    }
}

unittest
{
    Mipmap a;
    a.size(4, 256, 256);

    Mipmap b;
    b.size(16, 17, 333);
}

