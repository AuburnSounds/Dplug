/**
* Implement the plain color fill style. dplug:canvas internals.
*
* Copyright: Copyright Chris Jones 2020.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.canvas.colorblit;

import dplug.canvas.rasterizer;
import dplug.canvas.misc;

/*
  ColorBlit
*/

nothrow:
@nogc:

struct ColorBlit
{   
nothrow:
@nogc:

    void init(ubyte* pixels, size_t strideBytes, int height, uint color)
    {
        assert(height > 0);
        
        this.pixels = pixels;
        this.strideBytes = strideBytes;
        this.height = height;
        this.color = color;
    }

private:

    void color_blit(WindingRule wr)(int* delta, DMWord* mask, int x0, int x1, int y)
    {
        assert(x0 >= 0);
        assert(x1 * 4 <= strideBytes);
        assert(y >= 0);
        assert(y < height);
        assert((x0 & 3) == 0);
        assert((x1 & 3) == 0);

        // main blit variables

        int bpos = x0 / 4;
        int endbit = x1 / 4;
        uint* dest = cast(uint*)(&pixels[y*strideBytes]);
        __m128i xmWinding = 0;
        bool isopaque = (color >> 24) == 0xFF;

        // XMM constants

        immutable __m128i XMZERO = 0;
        immutable __m128i XMFFFF = [0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF];
        immutable __m128i XMMSK16 = [0xFFFF,0xFFFF,0xFFFF,0xFFFF];

        // paint variables

        __m128i xmColor = _mm_loadu_si32 (&color);
        xmColor = _mm_unpacklo_epi8 (xmColor, _mm_setzero_si128());
        xmColor = _mm_unpacklo_epi64 (xmColor, xmColor);
        __m128i xmAlpha = _mm_set1_epi16 (cast(ushort) ((color >> 24) << 8));

        // main loop

        while (bpos < endbit)
        {
            int nsb = nextSetBit(mask, bpos, endbit);

            // do we have a span of unchanging coverage?

            if (bpos < nsb)
            {
                // Calc coverage of first pixel

                static if (wr == WindingRule.NonZero)
                {
                    int cover = xmWinding[3]+delta[bpos*4];
                    cover = abs(cover)*2;
                    if (cover > 0xFFFF) cover = 0xFFFF;
                }
                else
                {
                    int cover = xmWinding[3]+delta[bpos*4];
                    short tsc = cast(short) cover;
                    cover = (tsc ^ (tsc >> 15)) << 1;
                }

                // We can skip the span

                if (cover < 0x100)
                {
                    bpos = nsb;
                }

                // Or fill span with soid color

                else if (isopaque && (cover > 0xFF00))
                {
                    __m128i tqc = _mm_set1_epi32(color);

                    uint* ptr = &dest[bpos*4];
                    uint* end = &dest[nsb*4];

                    while (ptr < end)
                    {
                        _mm_storeu_si128(cast(__m128i*)ptr, tqc);
                        ptr+=4;                        
                    }

                    bpos = nsb;
                }

                // Or fill the span with transparent color

                else
                {
                    __m128i tpma = _mm_set1_epi16(cast(ushort) cover); 
                    tpma = _mm_mulhi_epu16(xmAlpha,tpma);
                    __m128i tpmc = _mm_mulhi_epu16(xmColor,tpma);
                    tpmc = _mm_packus_epi16(tpmc,tpmc);
                    tpma  = tpma ^ XMFFFF;               // 1-alpha

                    uint* ptr = &dest[bpos*4];
                    uint* end = &dest[nsb*4];

                    while (ptr < end)
                    {
                        __m128i d0 = _mm_loadu_si128(cast(__m128i*)ptr);
                        __m128i d1 = _mm_unpackhi_epi8(d0,XMZERO);
                        d0 = _mm_unpacklo_epi8(d0,XMZERO);
                        d0 = _mm_mulhi_epu16(d0,tpma);
                        d1 = _mm_mulhi_epu16(d1,tpma);
                        d0 = _mm_packus_epi16(d0,d1);
                        d0 =  _mm_adds_epu8(d0,tpmc);
                        _mm_storeu_si128(cast(__m128i*)ptr,d0);
                        ptr+=4;
                    }

                    bpos = nsb;
                }
            }

            // At this point we need to integrate scandelta

            uint* ptr = &dest[bpos*4];
            uint* end = &dest[endbit*4];
            int* dlptr = &delta[bpos*4];

            while (ptr < end)
            {
                // Integrate delta values

                __m128i tqw = _mm_loadu_si128(cast(__m128i*)dlptr);
                tqw = _mm_add_epi32(tqw, _mm_slli_si128!4(tqw)); 
                tqw = _mm_add_epi32(tqw, _mm_slli_si128!8(tqw)); 
                tqw = _mm_add_epi32(tqw, xmWinding); 
                xmWinding = _mm_shuffle_epi32!255(tqw);  
                _mm_storeu_si128(cast(__m128i*)dlptr,XMZERO);

                // Process coverage values taking account of winding rule
                
                static if (wr == WindingRule.NonZero)
                {
                    __m128i tcvr = _mm_srai_epi32(tqw,31); 
                    tqw = _mm_add_epi32(tcvr,tqw);
                    tqw = _mm_xor_si128(tqw,tcvr);        // abs
                    tcvr = _mm_packs_epi32(tqw,XMZERO);   // saturate/pack to int16
                    tcvr = _mm_slli_epi16(tcvr, 1);       // << to uint16
                }
                else
                {
                    __m128i tcvr = _mm_and_si128(tqw,XMMSK16); 
                    tqw = _mm_srai_epi16(tcvr,15);       // mask
                    tcvr = _mm_xor_si128(tcvr,tqw);      // fold in halff
                    tcvr = _mm_packs_epi32(tcvr,XMZERO); // pack to int16
                    tcvr = _mm_slli_epi16(tcvr, 1);      // << to uint16
                } 

                // Load destination pixels
                __m128i d01 = _mm_loadu_si128(cast(__m128i*) ptr);
                __m128i d0 = _mm_unpacklo_epi8 (d01, XMZERO);
                __m128i d1 = _mm_unpackhi_epi8 (d01, XMZERO);

                // muliply source alpha & coverage

                __m128i a0 = _mm_mulhi_epu16(tcvr,xmAlpha);
                a0 = _mm_unpacklo_epi16(a0,a0); 
                __m128i a1 = _mm_unpackhi_epi32(a0,a0);
                a0 = _mm_unpacklo_epi32(a0,a0);

                // r = alpha*color + dest - alpha*dest

                __m128i r0 = _mm_mulhi_epu16(xmColor,a0);
                __m128i tmp = _mm_mulhi_epu16(d0,a0);
                r0 = _mm_add_epi16(r0, d0);
                r0 = _mm_sub_epi16(r0, tmp);

                __m128i r1 = _mm_mulhi_epu16(xmColor,a1);
                tmp   = _mm_mulhi_epu16(d1,a1);
                r1 = _mm_add_epi16(r1, d1);
                r1 = _mm_sub_epi16(r1, tmp);

                __m128i r01 = _mm_packus_epi16(r0,r1);

                _mm_storeu_si128(cast(__m128i*)ptr,r01);
                
                bpos++;
                ptr+=4;
                dlptr+=4;

                if (((cast(ulong*)dlptr)[0] | (cast(ulong*)dlptr)[1]) == 0) break;
            }
        }
    }

    ubyte* pixels;
    size_t strideBytes;
    int height;
    uint color;
}

 void doBlit_ColorBlit(void* userData, int* delta, DMWord* mask, int x0, int x1, int y)
 {
     ColorBlit* cb = cast(ColorBlit*)userData;
     return cb.color_blit!(WindingRule.NonZero)(delta, mask, x0, x1, y);
 }
