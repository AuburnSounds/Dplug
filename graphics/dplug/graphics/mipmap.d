/**
* Mipmap pyramid implementation.
*
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.graphics.mipmap;

import std.algorithm.comparison;

import gfm.math.vector;
import gfm.math.box;
import dplug.graphics.color;

import dplug.core.nogc;
import dplug.core.alignedbuffer;
import dplug.graphics.drawex;

version( D_InlineAsm_X86 )
{
    version = AsmX86;
}
else version( D_InlineAsm_X86_64 )
{
    version = AsmX86;
}

// Because of unability to load globals in PIC code with DMD, only enable some assembly with LDC
version(LDC)
{
    version( D_InlineAsm_X86 )
    {
        version = inlineAsmCanLoadGlobalsInPIC;
    }
    else version( D_InlineAsm_X86_64 )
    {
        version = inlineAsmCanLoadGlobalsInPIC;
    }
}


/// Mipmapped images.
/// Supports non power-of-two textures.
/// Size of the i+1-th mipmap is { (width)/2, (height)/2 }
/// The mipmap owns each of its levels.
final class Mipmap(COLOR) if (is(COLOR == RGBA) || is(COLOR == L16))
{
public:
nothrow:
@nogc:

    enum Quality
    {
        box,                  // simple 2x2 filter, creates phase problems with NPOT. For higher levels, automatically uses cubic.
        cubic,                // Very smooth kernel [1 2 1] x [1 2 1]
        boxAlphaCov,          // ditto but alpha is used as weight, only implemented for RGBA
        boxAlphaCovIntoPremul, // same as boxAlphaConv but after such a step the next level is alpha-premultiplied
    }

    Vec!(OwnedImage!COLOR) levels;

    /// Creates empty
    this()
    {
        levels = makeVec!(OwnedImage!COLOR)();
    }

    /// Set number of levels and size
    /// maxLevel = 0 => only one image
    /// maxLevel = 1 => one image + one 2x downsampled mipmap
    /// etc...
    this(int maxLevel, int w, int h)
    {
        this();
        size(maxLevel, w, h);
    }


    /// Creates a Mipmap out of a flat OwnedImage.
    /// This takes ownership of the given image, which is now owned by the `Mipmap`.
    this(int maxLevel, OwnedImage!COLOR level0)
    {
        //PERF: could avoid to create the 0th level only to replace it later

        this(maxLevel, level0.w, level0.h);

        // replaces level 0
        levels[0].destroyFree();
        levels[0] = level0;
        generateMipmaps(Quality.box);
    }

    void size(int maxLevel, int w, int h)
    {
        // find number of needed levels
        int neededLevels = 0;
        {
            int wr = w;
            int hr = h;
            for (; neededLevels <= maxLevel; ++neededLevels)
            {
                if (wr == 0 || hr == 0)
                    break;
                wr  = (wr + 0) >> 1;
                hr  = (hr + 0) >> 1;
            }
        }

        void setLevels(int numLevels)
        {
            // FUTURE: cleanup excess levels
            // should not happen until we have resizing
            if (numLevels < levels.length)
            {
                assert(false);
            }

            int previousLength = cast(int)levels.length;

            levels.resize(numLevels);

            // create empty image for new levels
            for(int level = previousLength; level < numLevels; ++level)
            {
                levels[level] = mallocNew!(OwnedImage!COLOR)();
            }
        }

        setLevels(neededLevels);

        // resize levels
        for (int level = 0; level < neededLevels; ++level)
        {
            assert(w != 0 && h != 0);
            levels[level].size(w, h);
            w  = (w + 0) >> 1;
            h  = (h + 0) >> 1;
        }
    }

    ~this()
    {
        foreach(level; levels)
            level.destroyFree();
    }

    /// Interpolates a color between mipmap levels.  Floating-point level, spatial linear interpolation.
    /// x and y are in base level coordinates (top-left pixel is on (0.5, 0.5) coordinates).
    /// Clamped to borders.
    auto linearMipmapSample(float level, float x, float y) nothrow @nogc
    {
        int ilevel = cast(int)level;
        float flevel = level - ilevel;
        vec4f levelN = linearSample(ilevel, x, y);
        if (flevel == 0)
            return levelN;

        auto levelNp1 = linearSample(ilevel + 1, x, y);

        return levelN * (1 - flevel) + levelNp1 * flevel;
    }


    /// Interpolates a color.  Integer level, spatial linear interpolation.
    /// x and y are in base level coordinates (top-left pixel is on (0.5, 0.5) coordinates).
    /// Clamped to borders.
    auto linearSample(int level, float x, float y) nothrow @nogc
    {
        if (level < 0)
            level = 0;
        int numLevels = cast(int)levels.length;
        if (level >= numLevels)
            level = numLevels - 1;

        OwnedImage!COLOR image = levels[level];


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

        COLOR[] L0 = image.scanline(iy);
        COLOR[] L1 = image.scanline(iyp1);

        COLOR A = L0.ptr[ix];
        COLOR B = L0.ptr[ixp1];
        COLOR C = L1.ptr[ix];
        COLOR D = L1.ptr[ixp1];

        static if (is(COLOR == RGBA))
        {
            float inv255 = 1 / 255.0f;

            version( AsmX86 )
            {
                vec4f asmResult;

                asm nothrow @nogc
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

                    cvtdq2ps XMM0, XMM0;
                    cvtdq2ps XMM1, XMM1;

                    cvtdq2ps XMM2, XMM2;
                    cvtdq2ps XMM3, XMM3;

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

                    movups asmResult, XMM0;
                }

                // Uncomment to check
    /*
                vec4f vA = vec4f(A.r, A.g, A.b, A.a);
                vec4f vB = vec4f(B.r, B.g, B.b, B.a);
                vec4f vC = vec4f(C.r, C.g, C.b, C.a);
                vec4f vD = vec4f(D.r, D.g, D.b, D.a);

                vec4f up = vA * fxm1 + vB * fx;
                vec4f down = vC * fxm1 + vD * fx;
                vec4f dResult = up * fym1 + down * fy;

                import gfm.core;

                if (dResult.distanceTo(result) < 1.0f)
                    debugBreak();
    */

                vec4f result = asmResult;
                return result;
            }
            else
            {
                vec4f vA = vec4f(A.r, A.g, A.b, A.a);
                vec4f vB = vec4f(B.r, B.g, B.b, B.a);
                vec4f vC = vec4f(C.r, C.g, C.b, C.a);
                vec4f vD = vec4f(D.r, D.g, D.b, D.a);



                vec4f up = vA * fxm1 + vB * fx;
                vec4f down = vC * fxm1 + vD * fx;
                vec4f dResult = up * fym1 + down * fy;

              //  assert(dResult.distanceTo(asmResult) < 1.0f);

                return dResult;
            }
        }
        else
        {
            float up = A.l * fxm1 + B.l * fx;
            float down = C.l * fxm1 + D.l * fx;
            return up * fym1 + down * fy;
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
        OwnedImage!COLOR previousLevel = levels[level - 1];
        box2i updateRect = impactOnNextLevel(quality, updateRectPreviousLevel, previousLevel.w, previousLevel.h);
        generateLevel(level, quality, updateRect);
        return updateRect;
    }

    /// Regenerates one level
    /// updateRect expressed in level i-th coordinates
    void generateLevel(int level, Quality quality, box2i updateRect) nothrow @nogc
    {
        assert(level > 0);
        OwnedImage!COLOR thisLevel = levels[level];
        OwnedImage!COLOR previousLevel = levels[level - 1];

        final switch(quality) with (Quality)
        {
            case box:

                static if (is(COLOR == RGBA))
                    generateLevelBoxRGBA(thisLevel, previousLevel, updateRect);
                else static if (is(COLOR == L16))
                    generateLevelBoxL16(thisLevel, previousLevel, updateRect);
                else
                    static assert(false, "not implemented");

                enum checkBoxMipmaps = false;

                static if (checkBoxMipmaps)
                {
                    for (int y = updateRect.min.y; y < updateRect.max.y; ++y)
                    {
                        COLOR[] L0 = previousLevel.scanline(y * 2);
                        COLOR[] L1 = previousLevel.scanline(y * 2 + 1);
                        COLOR[] dest = thisLevel.scanline(y);

                        for (int x = updateRect.min.x; x < updateRect.max.x; ++x)
                        {
                            // A B
                            // C D
                            COLOR A = L0[2 * x];
                            COLOR B = L0[2 * x + 1];
                            COLOR C = L1[2 * x];
                            COLOR D = L1[2 * x + 1];
                            assert(dest[x] == COLOR.op!q{(a + b + c + d + 2) >> 2}(A, B, C, D));
                        }
                    }
                }
                break;

        case boxAlphaCov:

            static if (is(COLOR == RGBA))
            {
                generateLevelBoxAlphaCovRGBA(thisLevel, previousLevel, updateRect);

                static if (false)
                {
                    void checkLevelBoxAlphaConvRGBA(Image!RGBA* thisLevel, Image!RGBA* previousLevel, box2i updateRect)
                    {
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
                                    assert(dest.ptr[x] == A);
                                }
                                else
                                {
                                    int destAlpha = cast(ubyte)( (alphaA + alphaB + alphaC + alphaD + 2) >> 2 );
                                    int red =   (A.r * alphaA + B.r * alphaB + C.r * alphaC + D.r * alphaD);
                                    int green = (A.g * alphaA + B.g * alphaB + C.g * alphaC + D.g * alphaD);
                                    int blue =  (A.b * alphaA + B.b* alphaB + C.b * alphaC + D.b * alphaD);
                                    float invSum = 1 / cast(float)(sum);

                                    RGBA finalColor = RGBA( cast(ubyte)(0.5f + red * invSum),
                                                            cast(ubyte)(0.5f + green * invSum),
                                                            cast(ubyte)(0.5f + blue * invSum),
                                                            cast(ubyte)destAlpha );
                                    assert(dest.ptr[x] == finalColor);
                                }
                            }
                        }
                    }
                    checkLevelBoxAlphaConvRGBA(thisLevel, previousLevel, updateRect);
                }
                break;
            }
            else
                assert(false);

        case boxAlphaCovIntoPremul:

            static if (is(COLOR == RGBA))
            {
                generateLevelBoxAlphaCovIntoPremulRGBA(thisLevel, previousLevel, updateRect);
                break;
            }
            else
                assert(false);

        case cubic:
            static if (is(COLOR == RGBA))
            {
                generateLevelCubicRGBA(thisLevel, previousLevel, updateRect);
                break;
            }
            else static if (is(COLOR == L16))
            {
                generateLevelCubicL16(thisLevel, previousLevel, updateRect);
                break;
            }
            else
                static assert(false, "not implemented");


        }
    }


private:
    /// Computes impact of updating the area box on next level
    static box2i impactOnNextLevel(Quality quality, box2i area, int currentLevelWidth, int currentLevelHeight) pure nothrow @nogc
    {
        box2i maxArea = box2i(0, 0, currentLevelWidth / 2, currentLevelHeight / 2);

        final  switch(quality) with (Quality)
        {
        case box:
        case boxAlphaCov:
        case boxAlphaCovIntoPremul:
            int xmin = area.min.x / 2;
            int ymin = area.min.y / 2;
            int xmax = (area.max.x + 1) / 2;
            int ymax = (area.max.y + 1) / 2;
            return box2i(xmin, ymin, xmax, ymax).intersection(maxArea);

        case cubic:
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
    Mipmap!RGBA a = new Mipmap!RGBA();
    a.size(4, 256, 256);
    a.destroy();

    Mipmap!L16 b = new Mipmap!L16();
    b.size(16, 17, 333);
    b.destroy();
}


private:

align(16) static immutable short[8] xmmTwoShort = [ 2, 2, 2, 2, 2, 2, 2, 2 ];
align(16) static immutable int[4] xmmTwoInt = [ 2, 2, 2, 2 ];
align(16) static immutable float[4] xmm0_5 = [ 0.5f, 0.5f, 0.5f, 0.5f ];
align(16) static immutable int[4] xmm512 = [ 512, 512, 512, 512 ];
align(16) static immutable short[8] xmm11113333 = [ 1, 1, 1, 1, 3, 3, 3, 3 ];
align(16) static immutable short[8] xmm33331111 = [ 3, 3, 3, 3, 1, 1, 1, 1 ];
align(16) static immutable short[8] xmm33339999 = [ 3, 3, 3, 3, 9, 9, 9, 9 ];
align(16) static immutable short[8] xmm99993333 = [ 9, 9, 9, 9, 3, 3, 3, 3 ];
align(16) static immutable short[8] xmm32       = [ 32, 32, 32, 32, 32, 32, 32, 32 ];


void generateLevelBoxRGBA(OwnedImage!RGBA thisLevel,
                          OwnedImage!RGBA previousLevel,
                          box2i updateRect) pure nothrow @nogc
{
    int width = updateRect.width();
    int height = updateRect.height();

    int previousPitch = previousLevel.w;
    int thisPitch = thisLevel.w;

    RGBA* L0 = previousLevel.scanline(updateRect.min.y * 2).ptr + updateRect.min.x * 2;
    RGBA* L1 = L0 + previousPitch;
    RGBA* dest = thisLevel.scanline(updateRect.min.y).ptr + updateRect.min.x;

    for (int y = 0; y < height; ++y)
    {
        version(inlineAsmCanLoadGlobalsInPIC)
        {
            version(D_InlineAsm_X86)
            {
                asm pure nothrow @nogc
                {
                    mov ECX, width;
                    shr ECX, 1;
                    jz no_need; // ECX = 0 => no pair of pixels to process

                    mov EAX, L0;
                    mov EDX, L1;
                    mov EDI, dest;
                    movaps XMM5, xmmTwoShort;

                loop_ecx:
                    movdqu XMM0, [EAX]; // A B E F
                    pxor XMM4, XMM4;
                    movdqu XMM1, [EDX]; // C D G H
                    movdqa XMM2, XMM0;
                    movdqa XMM3, XMM1;
                    punpcklbw XMM0, XMM4; // A B in short
                    punpcklbw XMM1, XMM4; // C D in short
                    punpckhbw XMM2, XMM4; // E F in short
                    punpckhbw XMM3, XMM4; // G H in short
                    paddusw XMM0, XMM1; // A + C | B + D
                    paddusw XMM2, XMM3; // E + F | G + H
                    movdqa XMM1, XMM0;
                    movdqa XMM3, XMM2;
                    psrldq XMM1, 8;
                    psrldq XMM3, 8;
                    add EDI, 8;
                    paddusw XMM0, XMM1; // A + B + C + D | garbage
                    paddusw XMM2, XMM3; // E + F + G + H | garbage
                    paddusw XMM0, XMM5; // A + B + C + D + 2 | garbage
                    paddusw XMM2, XMM5; // E + F + G + H + 2 | garbage
                    psrlw XMM0, 2; // (A + B + C + D + 2) >> 2 | garbage
                    psrlw XMM2, 2; // (E + F + G + H + 2) >> 2 | garbage
                    add EAX, 16;
                    punpcklqdq XMM0, XMM2;
                    add EDX, 16;
                    packuswb XMM0, XMM4; // (A + B + C + D + 2) >> 2 | (E + F + G + H + 2) >> 2 | 0 | 0
                    movq [EDI-8], XMM0;
                    sub ECX, 1;
                    jnz loop_ecx;
                no_need: ;
                }

                // Eventually filter the last pixel
                int remaining = width & ~1;
                for (int x = remaining; x < width; ++x)
                {
                    RGBA A = L0[2 * x];
                    RGBA B = L0[2 * x + 1];
                    RGBA C = L1[2 * x];
                    RGBA D = L1[2 * x + 1];
                    dest[x] = RGBA.op!q{(a + b + c + d + 2) >> 2}(A, B, C, D);
                }
            }
            else version(D_InlineAsm_X86_64)
            {
                asm pure nothrow @nogc
                {
                    mov ECX, width;
                    shr ECX, 1;
                    jz no_need; // ECX = 0 => no pair of pixels to process

                    mov RAX, L0;
                    mov RDX, L1;
                    mov RDI, dest;
                    movaps XMM5, xmmTwoShort;

                loop_ecx:
                    movdqu XMM0, [RAX]; // A B E F
                    pxor XMM4, XMM4;
                    movdqu XMM1, [RDX]; // C D G H
                    movdqa XMM2, XMM0;
                    movdqa XMM3, XMM1;
                    punpcklbw XMM0, XMM4; // A B in short
                    punpcklbw XMM1, XMM4; // C D in short
                    punpckhbw XMM2, XMM4; // E F in short
                    punpckhbw XMM3, XMM4; // G H in short
                    paddusw XMM0, XMM1; // A + C | B + D
                    paddusw XMM2, XMM3; // E + F | G + H
                    movdqa XMM1, XMM0;
                    movdqa XMM3, XMM2;
                    psrldq XMM1, 8;
                    psrldq XMM3, 8;
                    add RDI, 8;
                    paddusw XMM0, XMM1; // A + B + C + D | garbage
                    paddusw XMM2, XMM3; // E + F + G + H | garbage
                    paddusw XMM0, XMM5; // A + B + C + D + 2 | garbage
                    paddusw XMM2, XMM5; // E + F + G + H + 2 | garbage
                    psrlw XMM0, 2; // (A + B + C + D + 2) >> 2 | garbage
                    psrlw XMM2, 2; // (E + F + G + H + 2) >> 2 | garbage
                    add RAX, 16;
                    punpcklqdq XMM0, XMM2;
                    add RDX, 16;
                    packuswb XMM0, XMM4; // (A + B + C + D + 2) >> 2 | (E + F + G + H + 2) >> 2 | 0 | 0
                    movq [RDI-8], XMM0;
                    sub ECX, 1;
                    jnz loop_ecx;
                no_need: ;
                }

                // Eventually filter the last pixel
                int remaining = width & ~1;
                for (int x = remaining; x < width; ++x)
                {
                    RGBA A = L0[2 * x];
                    RGBA B = L0[2 * x + 1];
                    RGBA C = L1[2 * x];
                    RGBA D = L1[2 * x + 1];
                    dest[x] = RGBA.op!q{(a + b + c + d + 2) >> 2}(A, B, C, D);
                }
            }
            else
                static assert(false);
        }
        else
        {
            for (int x = 0; x < width; ++x)
            {
                // A B
                // C D
                RGBA A = L0[2 * x];
                RGBA B = L0[2 * x + 1];
                RGBA C = L1[2 * x];
                RGBA D = L1[2 * x + 1];

                dest[x] = RGBA.op!q{(a + b + c + d + 2) >> 2}(A, B, C, D);
            }
        }

        L0 += (2 * previousPitch);
        L1 += (2 * previousPitch);
        dest += thisPitch;
    }
}

void generateLevelBoxL16(OwnedImage!L16 thisLevel,
                         OwnedImage!L16 previousLevel,
                         box2i updateRect) pure nothrow @nogc
{
    int width = updateRect.width();
    int height = updateRect.height();

    int previousPitch = previousLevel.w;
    int thisPitch = thisLevel.w;

    L16* L0 = previousLevel.scanline(updateRect.min.y * 2).ptr + updateRect.min.x * 2;
    L16* L1 = L0 + previousPitch;

    L16* dest = thisLevel.scanline(updateRect.min.y).ptr + updateRect.min.x;

    for (int y = 0; y < height; ++y)
    {
        version(inlineAsmCanLoadGlobalsInPIC)
        {
            version(D_InlineAsm_X86)
            {
                asm pure nothrow @nogc
                {
                    mov ECX, width;
                    shr ECX, 2;
                    jz no_need; // ECX = 0 => less than 4 pixels to process

                    mov EAX, L0;
                    mov EDX, L1;
                    mov EDI, dest;
                    movdqa XMM5, xmmTwoInt;
                    pxor XMM4, XMM4;

                loop_ecx:
                    movdqu XMM0, [EAX]; // A B E F I J M N
                    movdqu XMM1, [EDX]; // C D G H K L O P

                    add EAX, 16;
                    add EDX, 16;

                    movdqa XMM2, XMM0;
                    movdqa XMM3, XMM1;

                    punpcklwd XMM0, XMM4; // A B E F in int32
                    punpckhwd XMM2, XMM4; // I J M N in int32
                    punpcklwd XMM1, XMM4; // C D G H in int32
                    punpckhwd XMM3, XMM4; // K L O P in int32

                    paddd XMM0, XMM1; // A+C B+D E+G F+H
                    paddd XMM2, XMM3; // I+K J+L M+O N+P

                    movdqa XMM1, XMM0;
                    movdqa XMM3, XMM2;

                    psrldq XMM1, 4; // B+D E+G F+H 0
                    psrldq XMM3, 4; // J+L M+O N+P 0

                    paddd XMM0, XMM1; // A+B+C+D garbage E+F+G+H garbage
                    paddd XMM2, XMM3; // I+J+K+L garbage M+N+O+P garbage

                    pshufd XMM0, XMM0, 0b00001000; // A+B+C+D E+F+G+H garbage garbage
                    pshufd XMM2, XMM2, 0b00001000; // I+J+K+L M+N+O+P garbage garbage

                    punpcklqdq XMM0, XMM2; // A+B+C+D E+F+G+H I+J+K+L M+N+O+P
                    paddd XMM0, XMM5; // add 2
                    psrld XMM0, 2; // >> 2

                    // because packusdw is not available before SSE4.1
                    // Extend sign bit to the right
                    pslld XMM0, 16;
                    psrad XMM0, 16;
                    add EDI, 8;
                    packssdw XMM0, XMM4;

                    movq [EDI-8], XMM0;
                    sub ECX, 1;
                    jnz loop_ecx;
                no_need: ;
                }

                // Eventually filter the 0 to 3 pixels
                int remaining = width & ~3;
                for (int x = remaining; x < width; ++x)
                {
                    L16 A = L0[2 * x];
                    L16 B = L0[2 * x + 1];
                    L16 C = L1[2 * x];
                    L16 D = L1[2 * x + 1];
                    dest[x] = L16.op!q{(a + b + c + d + 2) >> 2}(A, B, C, D);
                }
            }
            else version(D_InlineAsm_X86_64)
            {
                asm pure nothrow @nogc
                {
                    mov ECX, width;
                    shr ECX, 2;
                    jz no_need; // ECX = 0 => less than 4 pixels to process

                    mov RAX, L0;
                    mov RDX, L1;
                    mov RDI, dest;
                    movdqa XMM5, xmmTwoInt;
                    pxor XMM4, XMM4;

                loop_ecx:
                    movdqu XMM0, [RAX]; // A B E F I J M N
                    movdqu XMM1, [RDX]; // C D G H K L O P

                    add RAX, 16;
                    add RDX, 16;

                    movdqa XMM2, XMM0;
                    movdqa XMM3, XMM1;

                    punpcklwd XMM0, XMM4; // A B E F in int32
                    punpckhwd XMM2, XMM4; // I J M N in int32
                    punpcklwd XMM1, XMM4; // C D G H in int32
                    punpckhwd XMM3, XMM4; // K L O P in int32

                    paddd XMM0, XMM1; // A+C B+D E+G F+H
                    paddd XMM2, XMM3; // I+K J+L M+O N+P

                    movdqa XMM1, XMM0;
                    movdqa XMM3, XMM2;

                    psrldq XMM1, 4; // B+D E+G F+H 0
                    psrldq XMM3, 4; // J+L M+O N+P 0

                    paddd XMM0, XMM1; // A+B+C+D garbage E+F+G+H garbage
                    paddd XMM2, XMM3; // I+J+K+L garbage M+N+O+P garbage

                    pshufd XMM0, XMM0, 0b00001000; // A+B+C+D E+F+G+H garbage garbage
                    pshufd XMM2, XMM2, 0b00001000; // I+J+K+L M+N+O+P garbage garbage

                    punpcklqdq XMM0, XMM2; // A+B+C+D E+F+G+H I+J+K+L M+N+O+P
                    paddd XMM0, XMM5; // add 2
                    psrld XMM0, 2; // >> 2

                    // because packusdw is not available before SSE4.1
                    // Extend sign bit to the right
                    pslld XMM0, 16;
                    psrad XMM0, 16;
                    add RDI, 8;
                    packssdw XMM0, XMM4;

                    movq [RDI-8], XMM0;
                    sub ECX, 1;
                    jnz loop_ecx;
                no_need: ;
                }

                // Eventually filter the 0 to 3 pixels
                int remaining = width & ~3;
                for (int x = remaining; x < width; ++x)
                {
                    L16 A = L0[2 * x];
                    L16 B = L0[2 * x + 1];
                    L16 C = L1[2 * x];
                    L16 D = L1[2 * x + 1];
                    dest[x] = L16.op!q{(a + b + c + d + 2) >> 2}(A, B, C, D);
                }
            }
            else
                static assert(false);
        }
        else
        {
            for (int x = 0; x < width; ++x)
            {
                // A B
                // C D
                L16 A = L0[2 * x];
                L16 B = L0[2 * x + 1];
                L16 C = L1[2 * x];
                L16 D = L1[2 * x + 1];

                dest[x] = L16.op!q{(a + b + c + d + 2) >> 2}(A, B, C, D);
            }
        }

        L0 += (2 * previousPitch);
        L1 += (2 * previousPitch);
        dest += thisPitch;
    }
}


void generateLevelBoxAlphaCovRGBA(OwnedImage!RGBA thisLevel,
                                  OwnedImage!RGBA previousLevel,
                                  box2i updateRect) nothrow @nogc
{
    int width = updateRect.width();
    int height = updateRect.height();

    int previousPitch = previousLevel.w;
    int thisPitch = thisLevel.w;

    RGBA* L0 = previousLevel.scanline(updateRect.min.y * 2).ptr + updateRect.min.x * 2;
    RGBA* L1 = L0 + previousPitch;

    RGBA* dest = thisLevel.scanline(updateRect.min.y).ptr + updateRect.min.x;

    for (int y = 0; y < height; ++y)
    {
        version(inlineAsmCanLoadGlobalsInPIC)
        {
            version(D_InlineAsm_X86)
            {
                assert(width > 0);
                asm nothrow @nogc
                {
                    mov ECX, width;

                    mov EAX, L0;
                    mov EDX, L1;
                    mov EDI, dest;

                    loop_ecx:

                        movq XMM0, [EAX];                  // Ar Ag Ab Aa Br Bg Bb Ba + zeroes
                        movq XMM1, [EDX];                  // Cr Cg Cb Ca Dr Dg Db Da + zeroes
                        pxor XMM4, XMM4;
                        add EAX, 8;
                        add EDX, 8;

                        punpcklbw XMM0, XMM4;              // Ar Ag Ab Aa Br Bg Bb Ba
                        punpcklbw XMM1, XMM4;              // Cr Cg Cb Ca Dr Dg Db Da

                        movdqa XMM2, XMM0;
                        punpcklwd XMM0, XMM1;              // Ar Cr Ag Cg Ab Cb Aa Ca
                        punpckhwd XMM2, XMM1;              // Br Dr Bg Dg Bb Db Ba Da

                        // perhaps unnecessary
                        movdqa XMM3, XMM0;
                        punpcklwd XMM0, XMM2;              // Ar Br Cr Dr Ag Bg Cg Dg
                        punpckhwd XMM3, XMM2;              // Ab Bb Cb Db Aa Ba Ca Da

                        movdqa XMM1, XMM3;
                        punpckhqdq XMM1, XMM1;             // Aa Ba Ca Da Aa Ba Ca Da

                        // Are alpha all zeroes? if so, early continue.
                        movdqa XMM2, XMM1;
                        pcmpeqb XMM2, XMM4;
                        add EDI, 4;
                        pmovmskb ESI, XMM2;
                        cmp ESI, 0xffff;
                        jnz non_null;

                            pxor XMM0, XMM0;
                            sub ECX, 1;
                            movd [EDI-4], XMM0;            // dest[x] = A
                            jnz loop_ecx;
                            jmp end_of_loop;

                        non_null:

                            pmaddwd XMM0, XMM1;            // Ar*Aa+Br*Ba Cr*Ca+Dr*Da Ag*Aa+Bg*Ba Cg*Ca+Dg*Da
                            pmaddwd XMM3, XMM1;            // Ab*Aa+Bb*Ba Cb*Ca+Db*Da Aa*Aa+Ba*Ba Ca*Ca+Da*Da

                            // Starting computing sum of coefficients too
                            punpcklwd XMM1, XMM4;      // Aa Ba Ca Da

                            movdqa XMM2, XMM0;
                            movdqa XMM5, XMM3;
                            movdqa XMM4, XMM1;
                            psrldq XMM4, 8;

                            psrldq XMM2, 4;                // Cr*Ca+Dr*Da Ag*Aa+Bg*Ba Cg*Ca+Dg*Da 0
                            psrldq XMM5, 4;                // Cb*Ca+Db*Da Aa*Aa+Ba*Ba Ca*Ca+Da*Da 0
                            paddq XMM1, XMM4;              // Aa+Ca Ba+Da garbage garbage
                            movdqa XMM4, XMM1;

                            paddd XMM0, XMM2;              // Ar*Aa+Br*Ba+Cr*Ca+Dr*Da garbage Ag*Aa+Bg*Ba+Cg*Ca+Dg*Da garbage
                            paddd XMM3, XMM5;              // Ab*Aa+Bb*Ba+Cb*Ca+Db*Da garbage Aa*Aa+Ba*Ba+Ca*Ca+Da*Da garbage
                            psrldq XMM4, 4;

                            pshufd XMM0, XMM0, 0b00001000; // Ar*Aa+Br*Ba+Cr*Ca+Dr*Da Ag*Aa+Bg*Ba+Cg*Ca+Dg*Da garbage garbage
                            paddq XMM1, XMM4;          // Aa+Ba+Ca+Da garbage garbage garbage
                            pshufd XMM3, XMM3, 0b00001000; // Ab*Aa+Bb*Ba+Cb*Ca+Db*Da Aa*Aa+Ba*Ba+Ca*Ca+Da*Da garbage garbage

                            punpcklqdq XMM0, XMM3;     // fR fG fB fA
                            pshufd XMM1, XMM1, 0;

                            cvtdq2ps XMM0, XMM0;

                            cvtdq2ps XMM3, XMM1;       // sum sum sum sum

                            divps XMM0, XMM3;          // fR/sum fG/sum fB/sum fA/sum
                            addps XMM0, xmm0_5;
                            cvttps2dq XMM0, XMM0;      // return into integer domain using cast(int)(x + 0.5f)

                            paddd XMM1, xmmTwoInt;
                            psrld XMM1, 2;             // finalAlpha finalAlpha finalAlpha finalAlpha

                            pslldq XMM0, 4;            // 0 fR/sum fG/sum fB/sum
                            pslldq XMM1, 12;           // 0 0 0 finalAlpha
                            psrldq XMM0, 4;            // fR/sum fG/sum fB/sum 0

                            por XMM0, XMM1;            // fR/sum fG/sum fB/sum finalAlpha
                            pxor XMM3, XMM3;
                            packssdw XMM0, XMM3;       // same in words
                            packuswb XMM0, XMM3;       // same in bytes

                            sub ECX, 1;
                            movd [EDI-4], XMM0;            // dest[x] = A
                    jnz loop_ecx;
                    end_of_loop: ;
                }
            }
            else version(D_InlineAsm_X86_64)
            {
                assert(width > 0);
                asm nothrow @nogc
                {
                    mov ECX, width;

                    mov RAX, L0;
                    mov RDX, L1;
                    mov RDI, dest;

                loop_ecx:

                    movq XMM0, [RAX];                  // Ar Ag Ab Aa Br Bg Bb Ba + zeroes
                    movq XMM1, [RDX];                  // Cr Cg Cb Ca Dr Dg Db Da + zeroes
                    pxor XMM4, XMM4;
                    add RAX, 8;
                    add RDX, 8;

                    punpcklbw XMM0, XMM4;              // Ar Ag Ab Aa Br Bg Bb Ba
                    punpcklbw XMM1, XMM4;              // Cr Cg Cb Ca Dr Dg Db Da

                    movdqa XMM2, XMM0;
                    punpcklwd XMM0, XMM1;              // Ar Cr Ag Cg Ab Cb Aa Ca
                    punpckhwd XMM2, XMM1;              // Br Dr Bg Dg Bb Db Ba Da

                    // perhaps unnecessary
                    movdqa XMM3, XMM0;
                    punpcklwd XMM0, XMM2;              // Ar Br Cr Dr Ag Bg Cg Dg
                    punpckhwd XMM3, XMM2;              // Ab Bb Cb Db Aa Ba Ca Da

                    movdqa XMM1, XMM3;
                    punpckhqdq XMM1, XMM1;             // Aa Ba Ca Da Aa Ba Ca Da

                    // Are alpha all zeroes? if so, early continue.
                    movdqa XMM2, XMM1;
                    pcmpeqb XMM2, XMM4;
                    add RDI, 4;
                    pmovmskb ESI, XMM2;
                    cmp ESI, 0xffff;
                    jnz non_null;

                    pxor XMM0, XMM0;
                    sub ECX, 1;
                    movd [RDI-4], XMM0;            // dest[x] = A
                    jnz loop_ecx;
                    jmp end_of_loop;

                non_null:

                    pmaddwd XMM0, XMM1;            // Ar*Aa+Br*Ba Cr*Ca+Dr*Da Ag*Aa+Bg*Ba Cg*Ca+Dg*Da
                    pmaddwd XMM3, XMM1;            // Ab*Aa+Bb*Ba Cb*Ca+Db*Da Aa*Aa+Ba*Ba Ca*Ca+Da*Da

                    // Starting computing sum of coefficients too
                    punpcklwd XMM1, XMM4;      // Aa Ba Ca Da

                    movdqa XMM2, XMM0;
                    movdqa XMM5, XMM3;
                    movdqa XMM4, XMM1;
                    psrldq XMM4, 8;

                    psrldq XMM2, 4;                // Cr*Ca+Dr*Da Ag*Aa+Bg*Ba Cg*Ca+Dg*Da 0
                    psrldq XMM5, 4;                // Cb*Ca+Db*Da Aa*Aa+Ba*Ba Ca*Ca+Da*Da 0
                    paddq XMM1, XMM4;              // Aa+Ca Ba+Da garbage garbage
                    movdqa XMM4, XMM1;

                    paddd XMM0, XMM2;              // Ar*Aa+Br*Ba+Cr*Ca+Dr*Da garbage Ag*Aa+Bg*Ba+Cg*Ca+Dg*Da garbage
                    paddd XMM3, XMM5;              // Ab*Aa+Bb*Ba+Cb*Ca+Db*Da garbage Aa*Aa+Ba*Ba+Ca*Ca+Da*Da garbage
                    psrldq XMM4, 4;

                    pshufd XMM0, XMM0, 0b00001000; // Ar*Aa+Br*Ba+Cr*Ca+Dr*Da Ag*Aa+Bg*Ba+Cg*Ca+Dg*Da garbage garbage
                    paddq XMM1, XMM4;          // Aa+Ba+Ca+Da garbage garbage garbage
                    pshufd XMM3, XMM3, 0b00001000; // Ab*Aa+Bb*Ba+Cb*Ca+Db*Da Aa*Aa+Ba*Ba+Ca*Ca+Da*Da garbage garbage

                    punpcklqdq XMM0, XMM3;     // fR fG fB fA
                    pshufd XMM1, XMM1, 0;

                    cvtdq2ps XMM0, XMM0;

                    cvtdq2ps XMM3, XMM1;       // sum sum sum sum

                    divps XMM0, XMM3;          // fR/sum fG/sum fB/sum fA/sum
                    addps XMM0, xmm0_5;
                    cvttps2dq XMM0, XMM0;      // return into integer domain using cast(int)(x + 0.5f)

                    paddd XMM1, xmmTwoInt;
                    psrld XMM1, 2;             // finalAlpha finalAlpha finalAlpha finalAlpha

                    pslldq XMM0, 4;            // 0 fR/sum fG/sum fB/sum
                    pslldq XMM1, 12;           // 0 0 0 finalAlpha
                    psrldq XMM0, 4;            // fR/sum fG/sum fB/sum 0

                    por XMM0, XMM1;            // fR/sum fG/sum fB/sum finalAlpha
                    pxor XMM3, XMM3;
                    packssdw XMM0, XMM3;       // same in words
                    packuswb XMM0, XMM3;       // same in bytes

                    sub ECX, 1;
                    movd [RDI-4], XMM0;            // dest[x] = A
                    jnz loop_ecx;
                end_of_loop: ;
                }
            }
            else
                static assert(false);
        }
        else
        {
            for (int x = 0; x < width; ++x)
            {
                // A B
                // C D
                RGBA A = L0[2 * x];
                RGBA B = L0[2 * x + 1];
                RGBA C = L1[2 * x];
                RGBA D = L1[2 * x + 1];

                int alphaA = A.a;
                int alphaB = B.a;
                int alphaC = C.a;
                int alphaD = D.a;
                int sum = alphaA + alphaB + alphaC + alphaD;
                if (sum == 0)
                {
                    dest[x] = RGBA(0,0,0,0);
                }
                else
                {
                    int destAlpha = cast(ubyte)( (alphaA + alphaB + alphaC + alphaD + 2) >> 2 );
                    int red =   (A.r * alphaA + B.r * alphaB + C.r * alphaC + D.r * alphaD);
                    int green = (A.g * alphaA + B.g * alphaB + C.g * alphaC + D.g * alphaD);
                    int blue =  (A.b * alphaA + B.b* alphaB + C.b * alphaC + D.b * alphaD);
                    float invSum = 1 / cast(float)(sum);

                    RGBA finalColor = RGBA( cast(ubyte)(0.5f + red * invSum),
                                            cast(ubyte)(0.5f + green * invSum),
                                            cast(ubyte)(0.5f + blue * invSum),
                                            cast(ubyte)destAlpha );
                    dest[x] = finalColor;
                }
            }
        }

        enum verify = false;

        static if (verify)
        {
            for (int x = 0; x < width; ++x)
            {
                // A B
                // C D
                RGBA A = L0[2 * x];
                RGBA B = L0[2 * x + 1];
                RGBA C = L1[2 * x];
                RGBA D = L1[2 * x + 1];

                int alphaA = A.a;
                int alphaB = B.a;
                int alphaC = C.a;
                int alphaD = D.a;
                int sum = alphaA + alphaB + alphaC + alphaD;
                if (sum == 0)
                {
                    assert(dest[x] == RGBA(0,0,0,0));
                }
                else
                {
                    int destAlpha = cast(ubyte)( (alphaA + alphaB + alphaC + alphaD + 2) >> 2 );
                    int red =   (A.r * alphaA + B.r * alphaB + C.r * alphaC + D.r * alphaD);
                    int green = (A.g * alphaA + B.g * alphaB + C.g * alphaC + D.g * alphaD);
                    int blue =  (A.b * alphaA + B.b* alphaB + C.b * alphaC + D.b * alphaD);

                    float invSum = 1 / cast(float)(sum);

                    RGBA finalColor = RGBA( cast(ubyte)(0.5f + red * invSum),
                                            cast(ubyte)(0.5f + green * invSum),
                                           cast(ubyte)(0.5f + blue * invSum),
                                           cast(ubyte)destAlpha );
                    RGBA instead = dest[x];

                    int insteadR = instead.r;
                    int insteadG = instead.g;
                    int insteadB = instead.b;
                    int insteadA = instead.a;
                    int finalColorR = finalColor.r;
                    int finalColorG = finalColor.g;
                    int finalColorB = finalColor.b;
                    int finalColorA = finalColor.a;
                    import std.math;
                    assert(abs(insteadR - finalColorR) <= 1); // some remaining differences because of rounding
                    assert(abs(insteadG - finalColorG) <= 1);
                    assert(abs(insteadB - finalColorB) <= 1);
                    assert(insteadA == finalColorA);
                }
            }
        }

        L0 += (2 * previousPitch);
        L1 += (2 * previousPitch);
        dest += thisPitch;
    }
}

void generateLevelBoxAlphaCovIntoPremulRGBA(OwnedImage!RGBA thisLevel,
                                            OwnedImage!RGBA previousLevel,
                                            box2i updateRect) nothrow @nogc
{
    int width = updateRect.width();
    int height = updateRect.height();

    int previousPitch = previousLevel.w;
    int thisPitch = thisLevel.w;

    RGBA* L0 = previousLevel.scanline(updateRect.min.y * 2).ptr + updateRect.min.x * 2;
    RGBA* L1 = L0 + previousPitch;

    RGBA* dest = thisLevel.scanline(updateRect.min.y).ptr + updateRect.min.x;

    for (int y = 0; y < height; ++y)
    {
        version(inlineAsmCanLoadGlobalsInPIC)
        {
            version(D_InlineAsm_X86)
            {
                asm nothrow @nogc
                {
                    mov ECX, width;

                    mov EAX, L0;
                    mov EDX, L1;
                    mov EDI, dest;

                    movdqa XMM5, xmm512;               // 512 512 5121 512
                    pxor XMM4, XMM4;                   // all zeroes

                loop_ecx:

                    movq XMM0, [EAX];                  // Ar Ag Ab Aa Br Bg Bb Ba + zeroes
                    movq XMM1, [EDX];                  // Cr Cg Cb Ca Dr Dg Db Da + zeroes
                    pxor XMM4, XMM4;
                    add EAX, 8;
                    add EDX, 8;

                    punpcklbw XMM0, XMM4;              // Ar Ag Ab Aa Br Bg Bb Ba
                    punpcklbw XMM1, XMM4;              // Cr Cg Cb Ca Dr Dg Db Da

                    movdqa XMM2, XMM0;
                    punpcklwd XMM0, XMM1;              // Ar Cr Ag Cg Ab Cb Aa Ca
                    punpckhwd XMM2, XMM1;              // Br Dr Bg Dg Bb Db Ba Da

                    movdqa XMM3, XMM0;
                    punpcklwd XMM0, XMM2;              // Ar Br Cr Dr Ag Bg Cg Dg
                    punpckhwd XMM3, XMM2;              // Ab Bb Cb Db Aa Ba Ca Da

                    movdqa XMM1, XMM3;
                    punpckhqdq XMM1, XMM1;             // Aa Ba Ca Da Aa Ba Ca Da

                    add EDI, 4;

                    pmaddwd XMM0, XMM1;            // Ar*Aa+Br*Ba Cr*Ca+Dr*Da Ag*Aa+Bg*Ba Cg*Ca+Dg*Da
                    pmaddwd XMM3, XMM1;            // Ab*Aa+Bb*Ba Cb*Ca+Db*Da Aa*Aa+Ba*Ba Ca*Ca+Da*Da

                    movdqa XMM2, XMM0;
                    movdqa XMM1, XMM3;

                    psrldq XMM2, 4;                // Cr*Ca+Dr*Da Ag*Aa+Bg*Ba Cg*Ca+Dg*Da 0
                    psrldq XMM1, 4;                // Cb*Ca+Db*Da Aa*Aa+Ba*Ba Ca*Ca+Da*Da 0

                    paddd XMM0, XMM2;              // Ar*Aa+Br*Ba+Cr*Ca+Dr*Da garbage Ag*Aa+Bg*Ba+Cg*Ca+Dg*Da garbage
                    paddd XMM3, XMM1;              // Ab*Aa+Bb*Ba+Cb*Ca+Db*Da garbage Aa*Aa+Ba*Ba+Ca*Ca+Da*Da garbage

                    pshufd XMM0, XMM0, 0b00001000; // Ar*Aa+Br*Ba+Cr*Ca+Dr*Da Ag*Aa+Bg*Ba+Cg*Ca+Dg*Da garbage garbage
                    pshufd XMM3, XMM3, 0b00001000; // Ab*Aa+Bb*Ba+Cb*Ca+Db*Da Aa*Aa+Ba*Ba+Ca*Ca+Da*Da garbage garbage

                    punpcklqdq XMM0, XMM3;     // fR fG fB fA


                    paddd XMM0, XMM5;
                    psrld XMM0, 10;             // final color in dwords

                    packssdw XMM0, XMM4;       // same in words
                    packuswb XMM0, XMM4;       // same in bytes

                    sub ECX, 1;
                    movd [EDI-4], XMM0;            // dest[x] = A
                    jnz loop_ecx;
                }
            }
            else version(D_InlineAsm_X86_64)
            {
                asm nothrow @nogc
                {
                    mov ECX, width;

                    mov RAX, L0;
                    mov RDX, L1;
                    mov RDI, dest;

                    movdqa XMM5, xmm512;               // 512 512 5121 512
                    pxor XMM4, XMM4;                   // all zeroes

                loop_ecx:

                    movq XMM0, [RAX];                  // Ar Ag Ab Aa Br Bg Bb Ba + zeroes
                    movq XMM1, [RDX];                  // Cr Cg Cb Ca Dr Dg Db Da + zeroes
                    pxor XMM4, XMM4;
                    add RAX, 8;
                    add RDX, 8;

                    punpcklbw XMM0, XMM4;              // Ar Ag Ab Aa Br Bg Bb Ba
                    punpcklbw XMM1, XMM4;              // Cr Cg Cb Ca Dr Dg Db Da

                    movdqa XMM2, XMM0;
                    punpcklwd XMM0, XMM1;              // Ar Cr Ag Cg Ab Cb Aa Ca
                    punpckhwd XMM2, XMM1;              // Br Dr Bg Dg Bb Db Ba Da

                    movdqa XMM3, XMM0;
                    punpcklwd XMM0, XMM2;              // Ar Br Cr Dr Ag Bg Cg Dg
                    punpckhwd XMM3, XMM2;              // Ab Bb Cb Db Aa Ba Ca Da

                    movdqa XMM1, XMM3;
                    punpckhqdq XMM1, XMM1;             // Aa Ba Ca Da Aa Ba Ca Da

                    add RDI, 4;

                    pmaddwd XMM0, XMM1;            // Ar*Aa+Br*Ba Cr*Ca+Dr*Da Ag*Aa+Bg*Ba Cg*Ca+Dg*Da
                    pmaddwd XMM3, XMM1;            // Ab*Aa+Bb*Ba Cb*Ca+Db*Da Aa*Aa+Ba*Ba Ca*Ca+Da*Da

                    movdqa XMM2, XMM0;
                    movdqa XMM1, XMM3;

                    psrldq XMM2, 4;                // Cr*Ca+Dr*Da Ag*Aa+Bg*Ba Cg*Ca+Dg*Da 0
                    psrldq XMM1, 4;                // Cb*Ca+Db*Da Aa*Aa+Ba*Ba Ca*Ca+Da*Da 0

                    paddd XMM0, XMM2;              // Ar*Aa+Br*Ba+Cr*Ca+Dr*Da garbage Ag*Aa+Bg*Ba+Cg*Ca+Dg*Da garbage
                    paddd XMM3, XMM1;              // Ab*Aa+Bb*Ba+Cb*Ca+Db*Da garbage Aa*Aa+Ba*Ba+Ca*Ca+Da*Da garbage

                    pshufd XMM0, XMM0, 0b00001000; // Ar*Aa+Br*Ba+Cr*Ca+Dr*Da Ag*Aa+Bg*Ba+Cg*Ca+Dg*Da garbage garbage
                    pshufd XMM3, XMM3, 0b00001000; // Ab*Aa+Bb*Ba+Cb*Ca+Db*Da Aa*Aa+Ba*Ba+Ca*Ca+Da*Da garbage garbage

                    punpcklqdq XMM0, XMM3;     // fR fG fB fA


                    paddd XMM0, XMM5;
                    psrld XMM0, 10;             // final color in dwords

                    packssdw XMM0, XMM4;       // same in words
                    packuswb XMM0, XMM4;       // same in bytes

                    sub ECX, 1;
                    movd [RDI-4], XMM0;            // dest[x] = A
                    jnz loop_ecx;
                }
            }
            else 
                static assert(false);
        }
        else
        {
            for (int x = 0; x < width; ++x)
            {
                RGBA A = L0[2 * x];
                RGBA B = L0[2 * x + 1];
                RGBA C = L1[2 * x];
                RGBA D = L1[2 * x + 1];
                int red =   (A.r * A.a + B.r * B.a + C.r * C.a + D.r * D.a);
                int green = (A.g * A.a + B.g * B.a + C.g * C.a + D.g * D.a);
                int blue =  (A.b * A.a + B.b* B.a + C.b * C.a + D.b * D.a);
                int alpha =  (A.a * A.a + B.a* B.a + C.a * C.a + D.a * D.a);
                RGBA finalColor = RGBA( cast(ubyte)((red + 512) >> 10),
                                        cast(ubyte)((green + 512) >> 10),
                                        cast(ubyte)((blue + 512) >> 10),
                                        cast(ubyte)((alpha + 512) >> 10));
                dest[x] = finalColor;
            }
        }

        enum bool verify = false;

        static if (verify)
        {
            for (int x = 0; x < width; ++x)
            {
                RGBA A = L0[2 * x];
                RGBA B = L0[2 * x + 1];
                RGBA C = L1[2 * x];
                RGBA D = L1[2 * x + 1];
                int red =   (A.r * A.a + B.r * B.a + C.r * C.a + D.r * D.a);
                int green = (A.g * A.a + B.g * B.a + C.g * C.a + D.g * D.a);
                int blue =  (A.b * A.a + B.b* B.a + C.b * C.a + D.b * D.a);
                int alpha =  (A.a * A.a + B.a* B.a + C.a * C.a + D.a * D.a);
                RGBA finalColor = RGBA( cast(ubyte)((red + 512) >> 10),
                                        cast(ubyte)((green + 512) >> 10),
                                       cast(ubyte)((blue + 512) >> 10),
                                       cast(ubyte)((alpha + 512) >> 10));
                assert(dest[x] == finalColor);
            }
        }

        L0 += (2 * previousPitch);
        L1 += (2 * previousPitch);
        dest += thisPitch;
    }
}

void generateLevelCubicRGBA(OwnedImage!RGBA thisLevel,
                            OwnedImage!RGBA previousLevel,
                            box2i updateRect) nothrow @nogc
{
    for (int y = updateRect.min.y; y < updateRect.max.y; ++y)
    {
        int y2m1 = 2 * y - 1;
        if (y2m1 < 0)
            y2m1 = 0;

        int y2p2 = 2 * y + 2;
        if (y2p2 > previousLevel.h - 1)
            y2p2 = previousLevel.h - 1;

        RGBA* LM1 = previousLevel.scanline(y2m1).ptr;
        RGBA* L0 = previousLevel.scanline(y * 2).ptr;
        RGBA* L1 = previousLevel.scanline(y * 2 + 1).ptr;
        RGBA* L2 = previousLevel.scanline(y2p2).ptr;
        RGBA* dest = thisLevel.scanline(y).ptr;

        for (int x = updateRect.min.x; x < updateRect.max.x; ++x)
        {
            // A B C D
            // E F G H
            // I J K L
            // M N O P

            int x2m1 = 2 * x - 1;
            if (x2m1 < 0)
                x2m1 = 0;
            int x2p0 = 2 * x;
            int x2p2 = 2 * x + 2;
            if (x2p2 > previousLevel.w - 1)
                x2p2 = previousLevel.w - 1;

            version(inlineAsmCanLoadGlobalsInPIC)
            {
                version(D_InlineAsm_X86)
                {
                    RGBA[16] buf = void;
                    buf[0] = LM1[x2m1];
                    buf[1] = LM1[x2p0];
                    buf[2] = LM1[x2p0+1];
                    buf[3] = LM1[x2p2];
                    buf[4] = L0[x2m1];
                    buf[5] = L0[x2p0];
                    buf[6] = L0[x2p0+1];
                    buf[7] = L0[x2p2];
                    buf[8] = L1[x2m1];
                    buf[9] = L1[x2p0];
                    buf[10] = L1[x2p0+1];
                    buf[11] = L1[x2p2];
                    buf[12] = L2[x2m1];
                    buf[13] = L2[x2p0];
                    buf[14] = L2[x2p0+1];
                    buf[15] = L2[x2p2];
                    RGBA* pDest = dest + x;

                    asm nothrow @nogc
                    {
                        movdqu XMM0, buf;  // A B C D
                        movdqu XMM1, buf;
                        pxor XMM2, XMM2;      // zeroes
                        punpcklbw XMM0, XMM2; // A B
                        punpckhbw XMM1, XMM2; // C D
                        pmullw XMM0, xmm11113333; // A*1 B*3 in shorts
                        movdqa XMM3, XMM0;
                        pmullw XMM1, xmm33331111; // C*3 D*3 in shorts
                        movdqa XMM5, XMM1;

                        movdqu XMM0, buf+16;  // E F G H
                        movdqu XMM1, buf+16;
                        punpcklbw XMM0, XMM2; // E F
                        punpckhbw XMM1, XMM2; // G H
                        pmullw XMM0, xmm33339999; // E*3 F*9 in shorts
                        paddw XMM3, XMM0;
                        pmullw XMM1, xmm99993333; // G*9 H*3 in shorts
                        paddw XMM5, XMM1;

                        movdqu XMM0, buf+32;  // I J K L
                        movdqu XMM1, buf+32;
                        punpcklbw XMM0, XMM2; // I J
                        punpckhbw XMM1, XMM2; // K L
                        pmullw XMM0, xmm33339999; // I*3 J*9 in shorts
                        paddw XMM3, XMM0;
                        pmullw XMM1, xmm99993333; // K*9 L*3 in shorts
                        paddw XMM5, XMM1;

                        movdqu XMM0, buf+48;  // M N O P
                        movdqu XMM1, buf+48;
                        punpcklbw XMM0, XMM2; // M N
                        punpckhbw XMM1, XMM2; // O P
                        pmullw XMM0, xmm11113333; // M*1 N*3 in shorts
                        paddw XMM3, XMM0; // A+E*3+I*3+M B*3+F*9+J*9+3*N
                        pmullw XMM1, xmm33331111; // O*3 P*1 in shorts
                        paddw XMM5, XMM1; // C*3+G*9+K*9+O*3 D+H*3+L*3+P

                        movdqa XMM0, XMM3;
                        movdqa XMM1, XMM5;
                        psrldq XMM0, 8;
                        psrldq XMM1, 8;
                        paddw XMM3, XMM0; // A+E*3+I*3+M+B*3+F*9+J*9+3*N garbage(x4)
                        paddw XMM5, XMM1; // C*3+G*9+K*9+O*3+D+H*3+L*3+P garbage(x4)
                        paddw XMM3, XMM5; // total-sum garbage(x4)

                        paddw XMM3, xmm32;
                        psrlw XMM3, 6;
                        mov EAX, pDest;
                        packuswb XMM3, XMM2;

                        movd [EAX], XMM3;
                    }
                }
                else version(D_InlineAsm_X86_64)
                {
                    RGBA[16] buf = void;
                    buf[0] = LM1[x2m1];
                    buf[1] = LM1[x2p0];
                    buf[2] = LM1[x2p0+1];
                    buf[3] = LM1[x2p2];
                    buf[4] = L0[x2m1];
                    buf[5] = L0[x2p0];
                    buf[6] = L0[x2p0+1];
                    buf[7] = L0[x2p2];
                    buf[8] = L1[x2m1];
                    buf[9] = L1[x2p0];
                    buf[10] = L1[x2p0+1];
                    buf[11] = L1[x2p2];
                    buf[12] = L2[x2m1];
                    buf[13] = L2[x2p0];
                    buf[14] = L2[x2p0+1];
                    buf[15] = L2[x2p2];
                    RGBA* pDest = dest + x;

                    asm nothrow @nogc
                    {
                        movdqu XMM0, buf;  // A B C D
                        movdqu XMM1, buf;
                        pxor XMM2, XMM2;      // zeroes
                        punpcklbw XMM0, XMM2; // A B
                        punpckhbw XMM1, XMM2; // C D
                        pmullw XMM0, xmm11113333; // A*1 B*3 in shorts
                        movdqa XMM3, XMM0;
                        pmullw XMM1, xmm33331111; // C*3 D*3 in shorts
                        movdqa XMM5, XMM1;

                        movdqu XMM0, buf+16;  // E F G H
                        movdqu XMM1, buf+16;
                        punpcklbw XMM0, XMM2; // E F
                        punpckhbw XMM1, XMM2; // G H
                        pmullw XMM0, xmm33339999; // E*3 F*9 in shorts
                        paddw XMM3, XMM0;
                        pmullw XMM1, xmm99993333; // G*9 H*3 in shorts
                        paddw XMM5, XMM1;

                        movdqu XMM0, buf+32;  // I J K L
                        movdqu XMM1, buf+32;
                        punpcklbw XMM0, XMM2; // I J
                        punpckhbw XMM1, XMM2; // K L
                        pmullw XMM0, xmm33339999; // I*3 J*9 in shorts
                        paddw XMM3, XMM0;
                        pmullw XMM1, xmm99993333; // K*9 L*3 in shorts
                        paddw XMM5, XMM1;

                        movdqu XMM0, buf+48;  // M N O P
                        movdqu XMM1, buf+48;
                        punpcklbw XMM0, XMM2; // M N
                        punpckhbw XMM1, XMM2; // O P
                        pmullw XMM0, xmm11113333; // M*1 N*3 in shorts
                        paddw XMM3, XMM0; // A+E*3+I*3+M B*3+F*9+J*9+3*N
                        pmullw XMM1, xmm33331111; // O*3 P*1 in shorts
                        paddw XMM5, XMM1; // C*3+G*9+K*9+O*3 D+H*3+L*3+P

                        movdqa XMM0, XMM3;
                        movdqa XMM1, XMM5;
                        psrldq XMM0, 8;
                        psrldq XMM1, 8;
                        paddw XMM3, XMM0; // A+E*3+I*3+M+B*3+F*9+J*9+3*N garbage(x4)
                        paddw XMM5, XMM1; // C*3+G*9+K*9+O*3+D+H*3+L*3+P garbage(x4)
                        paddw XMM3, XMM5; // total-sum garbage(x4)

                        paddw XMM3, xmm32;
                        psrlw XMM3, 6;
                        mov RAX, pDest;
                        packuswb XMM3, XMM2;

                        movd [RAX], XMM3;
                    }
                }
                else
                    static assert(false);
            }
            else
            {
                auto A = LM1[x2m1];
                auto B = LM1[x2p0];
                auto C = LM1[x2p0+1];
                auto D = LM1[x2p2];

                auto E = L0[x2m1];
                auto F = L0[x2p0];
                auto G = L0[x2p0+1];
                auto H = L0[x2p2];

                auto I = L1[x2m1];
                auto J = L1[x2p0];
                auto K = L1[x2p0+1];
                auto L = L1[x2p2];

                auto M = L2[x2m1];
                auto N = L2[x2p0];
                auto O = L2[x2p0+1];
                auto P = L2[x2p2];

                // Apply filter
                // 1 3 3 1
                // 3 9 9 3
                // 3 9 9 3
                // 1 3 3 1

                int rSum = (A.r + D.r + M.r + P.r) + 3 * (B.r + C.r + E.r + H.r + I.r + L.r + N.r + O.r) + 9 * (F.r + G.r + J.r + K.r);
                int gSum = (A.g + D.g + M.g + P.g) + 3 * (B.g + C.g + E.g + H.g + I.g + L.g + N.g + O.g) + 9 * (F.g + G.g + J.g + K.g);
                int bSum = (A.b + D.b + M.b + P.b) + 3 * (B.b + C.b + E.b + H.b + I.b + L.b + N.b + O.b) + 9 * (F.b + G.b + J.b + K.b);
                int aSum = (A.a + D.a + M.a + P.a) + 3 * (B.a + C.a + E.a + H.a + I.a + L.a + N.a + O.a) + 9 * (F.a + G.a + J.a + K.a);
                dest[x].r = cast(ubyte)((rSum + 32) >> 6);
                dest[x].g = cast(ubyte)((gSum + 32) >> 6);
                dest[x].b = cast(ubyte)((bSum + 32) >> 6);
                dest[x].a = cast(ubyte)((aSum + 32) >> 6);
            }
        }
    }
}

void generateLevelCubicL16(OwnedImage!L16 thisLevel,
                           OwnedImage!L16 previousLevel,
                           box2i updateRect) nothrow @nogc
{
    for (int y = updateRect.min.y; y < updateRect.max.y; ++y)
    {
        int y2m1 = 2 * y - 1;
        if (y2m1 < 0)
            y2m1 = 0;

        int y2p2 = 2 * y + 2;
        if (y2p2 > previousLevel.h - 1)
            y2p2 = previousLevel.h - 1;

        L16* LM1 = previousLevel.scanline(y2m1).ptr;
        L16* L0 = previousLevel.scanline(y * 2).ptr;
        L16* L1 = previousLevel.scanline(y * 2 + 1).ptr;
        L16* L2 = previousLevel.scanline(y2p2).ptr;
        L16* dest = thisLevel.scanline(y).ptr;

        for (int x = updateRect.min.x; x < updateRect.max.x; ++x)
        {
            // A B C D
            // E F G H
            // I J K L
            // M N O P

            int x2m1 = 2 * x - 1;
            if (x2m1 < 0)
                x2m1 = 0;
            int x2p0 = 2 * x;
            int x2p2 = 2 * x + 2;
            if (x2p2 > previousLevel.w - 1)
                x2p2 = previousLevel.w - 1;

            ushort A = LM1[x2m1].l;
            ushort B = LM1[x2p0].l;
            ushort C = LM1[x2p0+1].l;
            ushort D = LM1[x2p2].l;

            ushort E = L0[x2m1].l;
            ushort F = L0[x2p0].l;
            ushort G = L0[x2p0+1].l;
            ushort H = L0[x2p2].l;

            ushort I = L1[x2m1].l;
            ushort J = L1[x2p0].l;
            ushort K = L1[x2p0+1].l;
            ushort L = L1[x2p2].l;

            ushort M = L2[x2m1].l;
            ushort N = L2[x2p0].l;
            ushort O = L2[x2p0+1].l;
            ushort P = L2[x2p2].l;

            // Apply filter
            // 1 3 3 1    A B C D
            // 3 9 9 3    E F G H
            // 3 9 9 3    I J K L
            // 1 3 3 1    M N O P

            int depthSum = (A + D + M + P)
                         + 3 * (B + C + E + H + I + L + N + O)
                         + 9 * (F + G + J + K);
            dest[x].l = cast(ushort)((depthSum + 32) >> 6  );
        }
    }
}

unittest
{
    Mipmap!RGBA rgbaMipmap;
    Mipmap!L16 l16Mipmap;
}