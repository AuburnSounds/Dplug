/**
Mipmap pyramid implementation.

Copyright: Guillaume Piolat 2015-2023.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.graphics.mipmap;

import dplug.math.vector;
import dplug.math.box;
import dplug.graphics.image;
import dplug.core.nogc;
import dplug.core.vec;

import inteli.smmintrin;

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
/// The mipmap owns each of its levels.
final class Mipmap(COLOR) if (is(COLOR == RGBA) || is(COLOR == L16) || is(COLOR == RGBA16) )
{
public:
nothrow:
@nogc:

    enum Quality
    {
        box,                   // simple 2x2 filter, creates phase problems with NPOT. For higher levels, automatically uses cubic.
        cubic,                 // Very smooth kernel [1 2 1] x [1 2 1]

        /// Box-filter, and after such a step the next level is alpha-premultiplied.
        /// This is intended for the first level 0 to level 1 transition, in case of bloom.
        /// This also transitions to linear space to have 
        /// more natural highlights (with PBREmissive option)
        boxAlphaCovIntoPremul, 
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

    /// Cubic filtering mode, using a Catmull-Rom bicubic filter.
    /// Integer level, spatial linear interpolation.
    /// x and y are in base level coordinates (top-left pixel is on (0.5, 0.5) coordinates).
    /// Clamped to borders.
    /// Reference: https://registry.khronos.org/OpenGL/extensions/IMG/IMG_texture_filter_cubic.txt
    auto cubicSample(int level, float x, float y) nothrow @nogc 
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

        __m128 mm0123 = _mm_setr_ps(-1, 0, 1, 2);
        __m128i x_indices = _mm_cvttps_epi32( _mm_set1_ps(x) + mm0123);
        __m128i y_indices = _mm_cvttps_epi32( _mm_set1_ps(y) + mm0123);
        __m128i zero = _mm_setzero_si128();
        x_indices = _mm_max_epi32(x_indices, zero);
        y_indices = _mm_max_epi32(y_indices, zero);
        x_indices = _mm_min_epi32(x_indices, _mm_set1_epi32(image.w-1));
        y_indices = _mm_min_epi32(y_indices, _mm_set1_epi32(image.h-1));

        int i0 = x_indices.array[0];
        int i1 = x_indices.array[1];
        int i2 = x_indices.array[2];
        int i3 = x_indices.array[3];

        // fractional part
        float a = x + 1.0f;
        float b = y + 1.0f;
        a = a - cast(int)(a);
        b = b - cast(int)(b);
        assert(a >= -0.01 && a <= 1.01);
        assert(b >= -0.01 && b <= 1.01);

        COLOR*[4] L = void;
        L[0] = image.scanlinePtr(y_indices.array[0]);
        L[1] = image.scanlinePtr(y_indices.array[1]);
        L[2] = image.scanlinePtr(y_indices.array[2]);
        L[3] = image.scanlinePtr(y_indices.array[3]);

        static if (is(COLOR == L16))
        {
            static float clamp_0_to_65535(float a)
            {
                if (a < 0) a = 0;
                if (a > 65535) a = 65535;
                return a;
            }
            static cubicInterp(float t, float x0, float x1, float x2, float x3) pure nothrow @nogc
            {
                // PERF: doesn't sound that great???
                return x1 
                    + t * ((-0.5f * x0) + (0.5f * x2))
                    + t * t * (x0 - (2.5f * x1) + (2.0f * x2) - (0.5f * x3))
                    + t * t * t * ((-0.5f * x0) + (1.5f * x1) - (1.5f * x2) + 0.5f * x3);
            }

            float[4] R;
            for (int row = 0; row < 4; ++row)
            {
                COLOR* pRow = L[row];
                COLOR ri0jn = pRow[i0];
                COLOR ri1jn = pRow[i1];
                COLOR ri2jn = pRow[i2];
                COLOR ri3jn = pRow[i3];
                float A = ri0jn.l;
                float B = ri1jn.l;
                float C = ri2jn.l;
                float D = ri3jn.l;
                R[row] = cubicInterp(a, A, B, C, D);
            }
            return clamp_0_to_65535(cubicInterp(b, R[0], R[1], R[2], R[3]));
        }
        else
        {
            // actually optimized ok by LDC
            static vec4f clamp_0_to_65535(vec4f a)
            {
                if (a[0] < 0) a[0] = 0;
                if (a[1] < 0) a[1] = 0;
                if (a[2] < 0) a[2] = 0;
                if (a[3] < 0) a[3] = 0;
                if (a[0] > 65535) a[0] = 65535;
                if (a[1] > 65535) a[1] = 65535;
                if (a[2] > 65535) a[2] = 65535;
                if (a[3] > 65535) a[3] = 65535;
                return a;
            }

            static cubicInterp(float t, vec4f x0, vec4f x1, vec4f x2, vec4f x3) pure nothrow @nogc
            {
                // PERF: doesn't sound that great???
                return x1 
                     + t * ((-0.5f * x0) + (0.5f * x2))
                     + t * t * (x0 - (2.5f * x1) + (2.0f * x2) - (0.5f * x3))
                     + t * t * t * ((-0.5f * x0) + (1.5f * x1) - (1.5f * x2) + 0.5f * x3);
            }
            vec4f[4] R = void;
            for (int row = 0; row < 4; ++row)
            {
                COLOR* pRow = L[row];
                COLOR ri0jn = pRow[i0];
                COLOR ri1jn = pRow[i1];
                COLOR ri2jn = pRow[i2];
                COLOR ri3jn = pRow[i3];
                vec4f A = vec4f(ri0jn.r, ri0jn.g, ri0jn.b, ri0jn.a);
                vec4f B = vec4f(ri1jn.r, ri1jn.g, ri1jn.b, ri1jn.a);
                vec4f C = vec4f(ri2jn.r, ri2jn.g, ri2jn.b, ri2jn.a);
                vec4f D = vec4f(ri3jn.r, ri3jn.g, ri3jn.b, ri3jn.a);
                R[row] = cubicInterp(a, A, B, C, D);
            }
            return clamp_0_to_65535(cubicInterp(b, R[0], R[1], R[2], R[3]));
        }
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

        if (x < 0)
            x = 0;
        if (y < 0)
            y = 0;

        __m128 floatCoords = _mm_setr_ps(x, y, 0, 0);
        __m128i truncatedCoord = _mm_cvttps_epi32(floatCoords);
        int ix = truncatedCoord.array[0];
        int iy = truncatedCoord.array[1];

        // Get fractional part
        float fx = x - ix;
        float fy = y - iy;

        const int maxX = image.w-1;
        const int maxY = image.h-1;
        if (ix > maxX)
            ix = maxX;
        if (iy > maxY)
            iy = maxY;

        int ixp1 = ix + 1;
        int iyp1 = iy + 1;
        if (ixp1 > maxX)
            ixp1 = maxX;
        if (iyp1 > maxY)
            iyp1 = maxY;  

        float fxm1 = 1 - fx;
        float fym1 = 1 - fy;

        COLOR* L0 = image.scanlinePtr(iy);
        COLOR* L1 = image.scanlinePtr(iyp1);

        COLOR A = L0[ix];
        COLOR B = L0[ixp1];
        COLOR C = L1[ix];
        COLOR D = L1[ixp1];

        static if (is(COLOR == RGBA))
        {
            float inv255 = 1 / 255.0f;
            version(LDC)
            {
                int Ai = *cast(int*)(&A);
                int Bi = *cast(int*)(&B);
                int Ci = *cast(int*)(&C);
                int Di = *cast(int*)(&D);

                __m128i mmZero = _mm_setzero_si128();
                __m128i mmABCD = _mm_setr_epi32(Ai, Bi, Ci, Di);

                // Convert to float of the form (R, G, B, A)
                __m128i mmAB = _mm_unpacklo_epi8(mmABCD, mmZero);
                __m128i mmCD = _mm_unpackhi_epi8(mmABCD, mmZero);
                __m128 vA = _mm_cvtepi32_ps( _mm_unpacklo_epi16(mmAB, mmZero));
                __m128 vB = _mm_cvtepi32_ps( _mm_unpackhi_epi16(mmAB, mmZero));
                __m128 vC = _mm_cvtepi32_ps( _mm_unpacklo_epi16(mmCD, mmZero));
                __m128 vD = _mm_cvtepi32_ps( _mm_unpackhi_epi16(mmCD, mmZero));

                __m128 vfx = _mm_set1_ps(fx);
                __m128 vfxm1 = _mm_set1_ps(fxm1);
                __m128 up = vA * vfxm1 + vB * vfx;
                __m128 down = vC * vfxm1 + vD * vfx;

                __m128 vfy = _mm_set1_ps(fy);
                __m128 vfym1 = _mm_set1_ps(fym1);
                __m128 dResult = up * fym1 + down * fy;
                vec4f result = void;
                _mm_storeu_ps(result.ptr, dResult);
                return result;

            }
            else version( AsmX86 )
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
        else static if (is(COLOR == L16))
        {
            float up = A.l * fxm1 + B.l * fx;
            float down = C.l * fxm1 + D.l * fx;
            return up * fym1 + down * fy;
        }
        else // RGBA16
        {
            vec4f vA = vec4f(A.r, A.g, A.b, A.a);
            vec4f vB = vec4f(B.r, B.g, B.b, B.a);
            vec4f vC = vec4f(C.r, C.g, C.b, C.a);
            vec4f vD = vec4f(D.r, D.g, D.b, D.a);

            vec4f up = vA * fxm1 + vB * fx;
            vec4f down = vC * fxm1 + vD * fx;
            vec4f result = up * fym1 + down * fy;
            return result;
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
                else static if (is(COLOR == RGBA16))
                    generateLevelBoxRGBA16(thisLevel, previousLevel, updateRect);
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
            else static if (is(COLOR == RGBA16))
            {
                generateLevelCubicRGBA16(thisLevel, previousLevel, updateRect);
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

    for (int y = 0; y < height; ++y)
    {
        RGBA* L0   = previousLevel.scanlinePtr( (updateRect.min.y + y) * 2    ) + updateRect.min.x * 2;
        RGBA* L1   = previousLevel.scanlinePtr( (updateRect.min.y + y) * 2 + 1) + updateRect.min.x * 2;
        RGBA* dest =     thisLevel.scanlinePtr(           updateRect.min.y + y) + updateRect.min.x;

        

     // PERF: enable later, this is faster on a full mipmap even without AVX2
     /// Requires a somewhat recent intel-intrinsics though
     /+
            int x = 0;
            __m256i zero = _mm256_setzero_si256();
            __m256i two = _mm256_set1_epi16(2);
            for ( ; x + 3 < width; x += 4)
            {
                // pixel patches:
                // A B E F   Goal = (A + B + C + D + 2) / 4   => res
                // C D G H          (E + F + G + H + 2) / 4   => res+1
                //
                __m256i ABEF = _mm256_loadu_si256(cast(const(__m256i)*) &L0[2*x]);
                __m256i CDGH = _mm256_loadu_si256(cast(const(__m256i)*) &L1[2*x]);
                __m256i AB = _mm256_unpacklo_epi8(ABEF, zero);
                __m256i EF = _mm256_unpackhi_epi8(ABEF, zero);
                __m256i CD = _mm256_unpacklo_epi8(CDGH, zero);
                __m256i GH = _mm256_unpackhi_epi8(CDGH, zero);
                AB = _mm256_add_epi16(AB, CD);                 // A + C   B + D
                EF = _mm256_add_epi16(EF, GH);                 // E + G   F + H
                __m256i AC_EG = _mm256_unpacklo_epi64(AB, EF); // A+C  E+G
                __m256i BD_FH = _mm256_unpackhi_epi64(AB, EF); // B+D  F+H
                __m256i sum = _mm256_add_epi16(AC_EG, BD_FH); // A+B+C+D   E+F+G+H
                sum = _mm256_add_epi16(sum, two);             // A+B+C+D+2 E+F+G+H+2
                sum = _mm256_srai_epi16(sum, 2);              // (A+B+C+D+2)/4 (E+F+G+H+2)/4
                __m256i finalPixels = _mm256_packus_epi16(sum, zero);

                __m128i f_lo = _mm256_extractf128_si256!0(finalPixels);
                __m128i f_hi = _mm256_extractf128_si256!1(finalPixels);
                _mm_storeu_si64(&dest[x], f_lo);  // PERF Would need a vpermute here. In each lane, only the low 8 bytes are interesting.
                _mm_storeu_si64(&dest[x+2], f_hi);
            }
        }

        +/

        __m128i zero = _mm_setzero_si128();
        __m128i two = _mm_set1_epi16(2);
        int x = 0;
        for ( ; x + 1 < width; x += 2)
        {
            // pixel patches:
            // A B E F   Goal = (A + B + C + D + 2) / 4   => res
            // C D G H          (E + F + G + H + 2) / 4   => res+1
            //
            __m128i ABEF = _mm_loadu_si128(cast(const(__m128i)*) &L0[2*x]);
            __m128i CDGH = _mm_loadu_si128(cast(const(__m128i)*) &L1[2*x]);
            __m128i AB = _mm_unpacklo_epi8(ABEF, zero);
            __m128i EF = _mm_unpackhi_epi8(ABEF, zero);
            __m128i CD = _mm_unpacklo_epi8(CDGH, zero);
            __m128i GH = _mm_unpackhi_epi8(CDGH, zero);
            AB = _mm_add_epi16(AB, CD);                 // A + C   B + D
            EF = _mm_add_epi16(EF, GH);                 // E + G   F + H
            __m128i AC_EG = _mm_unpacklo_epi64(AB, EF); // A+C  E+G
            __m128i BD_FH = _mm_unpackhi_epi64(AB, EF); // B+D  F+H
            __m128i sum = _mm_add_epi16(AC_EG, BD_FH); // A+B+C+D   E+F+G+H
            sum = _mm_add_epi16(sum, two);             // A+B+C+D+2 E+F+G+H+2
            sum = _mm_srai_epi16(sum, 2);              // (A+B+C+D+2)/4 (E+F+G+H+2)/4
            __m128i finalPixels = _mm_packus_epi16(sum, zero);
            _mm_storeu_si64(&dest[x], finalPixels);
        }

        for (; x < width; ++x)
        {
            RGBA A = L0[2 * x];
            RGBA B = L0[2 * x + 1];
            RGBA C = L1[2 * x];
            RGBA D = L1[2 * x + 1];
            dest[x] = RGBA.op!q{(a + b + c + d + 2) >> 2}(A, B, C, D);
        }
    }
}

void generateLevelBoxL16(OwnedImage!L16 thisLevel,
                         OwnedImage!L16 previousLevel,
                         box2i updateRect) pure nothrow @nogc
{
    int width = updateRect.width();
    int height = updateRect.height();

    for (int y = 0; y < height; ++y)
    {
        L16* L0   = previousLevel.scanlinePtr( (updateRect.min.y + y) * 2    ) + updateRect.min.x * 2;
        L16* L1   = previousLevel.scanlinePtr( (updateRect.min.y + y) * 2 + 1) + updateRect.min.x * 2;
        L16* dest =     thisLevel.scanlinePtr(           updateRect.min.y + y) + updateRect.min.x;


        // Fun performance fact: for this loop (LDC 1.33, arch x86_64), assembly is slower than intrinsics, 
        // themselves slower than normal D code.

        int x = 0;
        for (; x < width; ++x)
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
}

void generateLevelBoxRGBA16(OwnedImage!RGBA16 thisLevel,
                            OwnedImage!RGBA16 previousLevel,
                            box2i updateRect) pure nothrow @nogc
{
    // untested and unused for now
    int width = updateRect.width();
    int height = updateRect.height();

    for (int y = 0; y < height; ++y)
    {
        RGBA16* L0   = previousLevel.scanlinePtr( (updateRect.min.y + y) * 2    ) + updateRect.min.x * 2;
        RGBA16* L1   = previousLevel.scanlinePtr( (updateRect.min.y + y) * 2 + 1) + updateRect.min.x * 2;
        RGBA16* dest =     thisLevel.scanlinePtr(           updateRect.min.y + y) + updateRect.min.x;
        for (int x = 0; x < width; ++x)
        {
            // A B
            // C D
            RGBA16 A = L0[2 * x];
            RGBA16 B = L0[2 * x + 1];
            RGBA16 C = L1[2 * x];
            RGBA16 D = L1[2 * x + 1];

            dest[x] = RGBA16.op!q{(a + b + c + d + 2) >> 2}(A, B, C, D);
        }
    }
}

void generateLevelBoxAlphaCovIntoPremulRGBA(OwnedImage!RGBA thisLevel,
                                            OwnedImage!RGBA previousLevel,
                                            box2i updateRect) nothrow @nogc
{
    int width = updateRect.width();
    int height = updateRect.height();

    for (int y = 0; y < height; ++y)
    {
        RGBA* L0   = previousLevel.scanlinePtr( (updateRect.min.y + y) * 2    ) + updateRect.min.x * 2;
        RGBA* L1   = previousLevel.scanlinePtr( (updateRect.min.y + y) * 2 + 1) + updateRect.min.x * 2;
        RGBA* dest =     thisLevel.scanlinePtr(           updateRect.min.y + y) + updateRect.min.x;

        version(legacyPBREmissive)
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
        else
        {
            // Note: basically very hard to beat with intrinsics.
            // Hours lost trying to do that: 4.
            // Neither float or integer intrinsics shenanigans do better than this plain code.

            for (int x = 0; x < width; ++x)
            {
                RGBA A = L0[2 * x];
                RGBA B = L0[2 * x + 1];
                RGBA C = L1[2 * x];
                RGBA D = L1[2 * x + 1];

                // This is only approximate, does a pow2
                static RGBAf convert_gammaspace_to_linear_premul (RGBA col)
                {
                    RGBAf res;
                    enum float inv_255 = 1.0f / 255;
                    res.a = col.a * inv_255; // alpha is linear
                    res.r = col.r * inv_255 *col.r * inv_255* res.a;
                    res.g = col.g * inv_255 *col.g * inv_255* res.a;
                    res.b = col.b * inv_255 *col.b * inv_255* res.a;
                    return res;
                }

                // Convert those into 
                RGBAf A_linear = convert_gammaspace_to_linear_premul(A);
                RGBAf B_linear = convert_gammaspace_to_linear_premul(B);
                RGBAf C_linear = convert_gammaspace_to_linear_premul(C);
                RGBAf D_linear = convert_gammaspace_to_linear_premul(D);

                float meanR = A_linear.r + B_linear.r + C_linear.r + D_linear.r;
                float meanG = A_linear.g + B_linear.g + C_linear.g + D_linear.g;
                float meanB = A_linear.b + B_linear.b + C_linear.b + D_linear.b;
                float meanA = A_linear.a + B_linear.a + C_linear.a + D_linear.a;

                RGBA finalColor = RGBA( cast(ubyte)(meanR * 0.25f * 255.0f + 0.5f),
                                        cast(ubyte)(meanG * 0.25f * 255.0f + 0.5f),
                                        cast(ubyte)(meanB * 0.25f * 255.0f + 0.5f),
                                        cast(ubyte)(meanA * 0.25f * 255.0f + 0.5f) );
                dest[x] = finalColor;
            }
        }
       
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

        RGBA* LM1 = previousLevel.scanlinePtr(y2m1);
        RGBA* L0 = previousLevel.scanlinePtr(y * 2);
        RGBA* L1 = previousLevel.scanlinePtr(y * 2 + 1);
        RGBA* L2 = previousLevel.scanlinePtr(y2p2);
        RGBA* dest = thisLevel.scanlinePtr(y);

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

            static if (true)
            {
                align(16) RGBA[16] buf = void;
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

                const __m128i mmZero = _mm_setzero_si128();

                // Note: no coefficients improvements really convince.
                // This was Issue #827, read for more context.

                const __m128i xmm11113333 = _mm_setr_epi16(1, 1, 1, 1, 3, 3, 3, 3);
                const __m128i xmm33339999 = _mm_setr_epi16(3, 3, 3, 3, 9, 9, 9, 9);

                __m128i ABCD = _mm_load_si128(cast(const(__m128i*)) &buf[0]);
                __m128i EFGH = _mm_load_si128(cast(const(__m128i*)) &buf[4]);
                __m128i IJKL = _mm_load_si128(cast(const(__m128i*)) &buf[8]);
                __m128i MNOP = _mm_load_si128(cast(const(__m128i*)) &buf[12]);

                __m128i AB = _mm_unpacklo_epi8(ABCD, mmZero);
                __m128i CD = _mm_unpackhi_epi8(ABCD, mmZero);
                __m128i EF = _mm_unpacklo_epi8(EFGH, mmZero);
                __m128i GH = _mm_unpackhi_epi8(EFGH, mmZero);
                __m128i IJ = _mm_unpacklo_epi8(IJKL, mmZero);
                __m128i KL = _mm_unpackhi_epi8(IJKL, mmZero);
                __m128i MN = _mm_unpacklo_epi8(MNOP, mmZero);
                __m128i OP = _mm_unpackhi_epi8(MNOP, mmZero);

                // This avoid a few multiplications
                AB = _mm_add_epi16(AB, MN);
                CD = _mm_add_epi16(CD, OP);
                EF = _mm_add_epi16(EF, IJ);
                GH = _mm_add_epi16(GH, KL);

                // Wrap a bit more, avoids two muls
                AB = _mm_add_epi16(AB, _mm_shuffle_epi32!0x4e(CD)); // invert quadwords
                EF = _mm_add_epi16(EF, _mm_shuffle_epi32!0x4e(GH)); // invert quadwords

                // PERF: we can win a few mul here
                __m128i sum01 = _mm_mullo_epi16(AB, xmm11113333);
                sum01 = _mm_add_epi16(sum01, _mm_mullo_epi16(EF, xmm33339999));
                sum01 = _mm_add_epi16(sum01, _mm_srli_si128!8(sum01));

                __m128i sum = sum01;
                sum = _mm_add_epi16(sum, _mm_set1_epi16(32));
                sum = _mm_srli_epi16(sum, 6);
                __m128i finalPixels = _mm_packus_epi16(sum, mmZero);
                _mm_storeu_si32(pDest, finalPixels);
            }
            else
            {
                RGBA A = LM1[x2m1];
                RGBA B = LM1[x2p0];
                RGBA C = LM1[x2p0+1];
                RGBA D = LM1[x2p2];

                RGBA E = L0[x2m1];
                RGBA F = L0[x2p0];
                RGBA G = L0[x2p0+1];
                RGBA H = L0[x2p2];

                RGBA I = L1[x2m1];
                RGBA J = L1[x2p0];
                RGBA K = L1[x2p0+1];
                RGBA L = L1[x2p2];

                RGBA M = L2[x2m1];
                RGBA N = L2[x2p0];
                RGBA O = L2[x2p0+1];
                RGBA P = L2[x2p2];

                // Apply filter
                // 1 3 3 1
                // 3 9 9 3      / 64
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

        L16* LM1 = previousLevel.scanlinePtr(y2m1);
        L16* L0 = previousLevel.scanlinePtr(y * 2);
        L16* L1 = previousLevel.scanlinePtr(y * 2 + 1);
        L16* L2 = previousLevel.scanlinePtr(y2p2);
        L16* dest = thisLevel.scanlinePtr(y);

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

void generateLevelCubicRGBA16(OwnedImage!RGBA16 thisLevel,
                              OwnedImage!RGBA16 previousLevel,
                              box2i updateRect) nothrow @nogc
{
    // untested and unused for now
    for (int y = updateRect.min.y; y < updateRect.max.y; ++y)
    {
        int y2m1 = 2 * y - 1;
        if (y2m1 < 0)
            y2m1 = 0;

        int y2p2 = 2 * y + 2;
        if (y2p2 > previousLevel.h - 1)
            y2p2 = previousLevel.h - 1;

        RGBA16* LM1 = previousLevel.scanlinePtr(y2m1);
        RGBA16* L0 = previousLevel.scanlinePtr(y * 2);
        RGBA16* L1 = previousLevel.scanlinePtr(y * 2 + 1);
        RGBA16* L2 = previousLevel.scanlinePtr(y2p2);
        RGBA16* dest = thisLevel.scanlinePtr(y);

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
            dest[x].r = cast(ushort)((rSum + 32) >> 6);
            dest[x].g = cast(ushort)((gSum + 32) >> 6);
            dest[x].b = cast(ushort)((bSum + 32) >> 6);
            dest[x].a = cast(ushort)((aSum + 32) >> 6);
        }
    }
}

unittest
{
    Mipmap!RGBA rgbaMipmap;
    Mipmap!L16 l16Mipmap;
}