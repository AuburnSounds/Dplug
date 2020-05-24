/**
* Not supported for now.
*
* Copyright: Copyright Chris Jones 2020.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.canvas.angularblit;

// disabled for now
/+

import dplug.canvas.rasterizer;
import dplug.canvas.gradient;
import dplug.canvas.misc;

/*
   angular gradient blit
*/

struct AngularBlit
{   
    void init(uint* pixels, int stride, int height,
              Gradient g, float x0, float y0, float x1, float y1, float r2)
    {
        assert(((cast(int)pixels) & 15) == 0); // must be 16 byte alligned
        assert((stride & 3) == 0);             // stride must be 16 byte alligned
        assert(height > 0);
        assert(g !is null);
        assert(isPow2(g.lutLength));

        this.pixels = pixels;
        this.stride = stride;
        this.height = height;
        this.gradient = g;
        int lutsize = g.lutLength;

        xctr = x0;
        yctr = y0;
        float w = x1-x0;
        float h = y1-y0;
        float hyp = w*w + h*h;
        if (hyp < 0.1) hyp = 0.1;
        xstep0 = lutsize * w / hyp; 
        ystep0 = lutsize * h / hyp;
        hyp = sqrt(hyp);
        xstep1 = lutsize * h / (r2*hyp);
        ystep1 = lutsize * -w / (r2*hyp); 
    }

    Blitter getBlitter(WindingRule wr)
    {
        if (wr == WindingRule.NonZero)
        {
            return &angular_blit!(WindingRule.NonZero);
        }
        else
        {
            return &angular_blit!(WindingRule.EvenOdd);
        }
    }

private:

    void angular_blit(WindingRule wr)(int* delta, DMWord* mask, int x0, int x1, int y)
    {
        assert(x0 >= 0);
        assert(x1 <= stride);
        assert(y >= 0);
        assert(y < height);
        assert((x0 & 3) == 0);
        assert((x1 & 3) == 0);

        // main blit variables

        int bpos = x0 / 4;
        int endbit = x1 / 4;
        uint* dest = &pixels[y*stride];
        __m128i xmWinding = 0;
        uint* lut = gradient.getLookup.ptr;
        uint lutmsk = gradient.lutLength - 1;
        bool isopaque = false;//gradient.isOpaque

        // XMM constants

        immutable __m128i XMZERO = 0;
        immutable __m128i XMFFFF = [0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF];
        immutable __m128i XMMSK16 = [0xFFFF,0xFFFF,0xFFFF,0xFFFF];

        // paint variables

        float t0 = (bpos*4-xctr)*xstep0 + (y-yctr)*ystep0;
        __m128 xmT0 = _mm_mul_ps(_mm_set1_ps(xstep0), _mm_setr_ps(0.0f,1.0f,2.0f,3.0f));
        xmT0 = _mm_add_ps(xmT0, _mm_set1_ps(t0));
        __m128 xmStep0 = _mm_set1_ps(xstep0*4);

        float t1 = (bpos*4-xctr)*xstep1 + (y-yctr)*ystep1;
        __m128 xmT1 = _mm_mul_ps(_mm_set1_ps(xstep1), _mm_setr_ps(0.0f,1.0f,2.0f,3.0f));
        xmT1 = _mm_add_ps(xmT1, _mm_set1_ps(t1));
        __m128 xmStep1 = _mm_set1_ps(xstep1*4);

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
                    cover = (tsc ^ (tsc >> 15)) * 2;
                }

                // We can skip the span

                if (cover == 0)
                {
                    __m128 tsl = _mm_set1_ps(nsb-bpos);
                    xmT0 = _mm_add_ps(xmT0, _mm_mul_ps(tsl,xmStep0));
                    xmT1 = _mm_add_ps(xmT1, _mm_mul_ps(tsl,xmStep1));
                    bpos = nsb;
                }

                // Or fill span with soid color

                else if (isopaque && (cover > 0xFF00))
                {
                    uint* ptr = &dest[bpos*4];
                    uint* end = ptr + ((nsb-bpos)*4);

                    while (ptr < end)
                    {
                        __m128 grad = gradOfSorts(xmT0,xmT1);
                        __m128 poly = polyAprox(grad);
                        __m128i ipos = _mm_cvtps_epi32(poly);
                        ipos = fixupQuadrant(ipos,xmT0,xmT1);

                        xmT0 = xmT0 + xmStep0;
                        xmT1 = xmT1 + xmStep1;

                        long tlip = _mm_cvtsi128_si64 (ipos);
                        ipos = _mm_shuffle_epi32!14(ipos);
                        ptr[0] = lut[tlip & lutmsk];
                        ptr[1] = lut[(tlip >> 32) & lutmsk];
                        tlip = _mm_cvtsi128_si64 (ipos);
                        ptr[2] = lut[tlip & lutmsk];
                        ptr[3] = lut[(tlip >> 32) & lutmsk];

                        ptr+=4;                        
                    }

                    bpos = nsb;
                }

                // Or fill span with transparent color

                else
                {
                    __m128i tqcvr = _mm_set1_epi16 (cast(ushort) cover);

                    uint* ptr = &dest[bpos*4];
                    uint* end = &dest[nsb*4];

                    while (ptr < end)
                    {
                        __m128 grad = gradOfSorts(xmT0,xmT1);

                        __m128i d0 = _mm_loadu_si64 (ptr);
                        d0 = _mm_unpacklo_epi8 (d0, XMZERO);
                        __m128i d1 = _mm_loadu_si64 (ptr+2);
                        d1 = _mm_unpacklo_epi8 (d1, XMZERO);

                        __m128 poly = polyAprox(grad);
                        __m128i ipos = _mm_cvtps_epi32(poly);
                        ipos = fixupQuadrant(ipos,xmT0,xmT1);

                        long tlip = _mm_cvtsi128_si64 (ipos);
                        ipos = _mm_unpackhi_epi64 (ipos, ipos);

                        __m128i c0 = _mm_loadu_si32 (&lut[tlip & lutmsk]);
                        __m128i tnc = _mm_loadu_si32 (&lut[(tlip >> 32) & lutmsk]);
                        c0 = _mm_unpacklo_epi32 (c0, tnc);
                        c0 = _mm_unpacklo_epi8 (c0, XMZERO);
                        __m128i a0 = _mm_broadcast_alpha(c0);
                        a0 = _mm_mulhi_epu16(a0, tqcvr);

                        tlip = _mm_cvtsi128_si64 (ipos);
                        
                        __m128i c1 = _mm_loadu_si32 (&lut[tlip & lutmsk]);
                        tnc = _mm_loadu_si32 (&lut[(tlip >> 32) & lutmsk]);
                        c1 = _mm_unpacklo_epi32 (c1, tnc);
                        c1 = _mm_unpacklo_epi8 (c1, XMZERO);
                        __m128i a1 = _mm_broadcast_alpha(c1);
                        a1 = _mm_mulhi_epu16(a1, tqcvr);

                        xmT0 = xmT0 + xmStep0;
                        xmT1 = xmT1 + xmStep1;

                       // alpha*source + dest - alpha*dest

                        c0 = _mm_mulhi_epu16 (c0,a0);
                        c1 = _mm_mulhi_epu16 (c1,a1);
                        c0 = _mm_adds_epi16 (c0,d0);
                        c1 = _mm_adds_epi16 (c1,d1);
                        d0 = _mm_mulhi_epu16 (d0,a0);
                        d1 = _mm_mulhi_epu16 (d1,a1);
                        c0 =  _mm_subs_epi16 (c0, d0);
                        c1 =  _mm_subs_epi16 (c1, d1);

                        d0 = _mm_packus_epi16 (c0,c1);

                        _mm_store_si128 (cast(__m128i*)ptr,d0);
                        
                        ptr+=4;
                    }

                    bpos = nsb;
                }
            }

            // At this point we need to integrate scandelta

            uint* ptr = &dest[bpos*4];
            uint* end = &dest[endbit*4];
            int* dlptr = &delta[bpos*4];

            while (bpos < endbit)
            {
                __m128 grad = gradOfSorts(xmT0,xmT1);

                // Integrate delta values

                __m128i tqw = _mm_load_si128(cast(__m128i*)dlptr);
                tqw = _mm_add_epi32(tqw, _mm_slli_si128!4(tqw)); 
                tqw = _mm_add_epi32(tqw, _mm_slli_si128!8(tqw)); 
                tqw = _mm_add_epi32(tqw, xmWinding); 
                xmWinding = _mm_shuffle_epi32!255(tqw);  
                _mm_store_si128(cast(__m128i*)dlptr,XMZERO);

                __m128 poly = polyAprox(grad);

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

                // convert grad pos to integer

                __m128i ipos = _mm_cvtps_epi32(poly);

                // Load destination pixels

                __m128i d0 = _mm_loadu_si64 (ptr);
                d0 = _mm_unpacklo_epi8 (d0, XMZERO);
                __m128i d1 = _mm_loadu_si64 (ptr+2);
                d1 = _mm_unpacklo_epi8 (d1, XMZERO);

                ipos = fixupQuadrant(ipos,xmT0,xmT1);

                xmT0 = xmT0 + xmStep0;
                xmT1 = xmT1 + xmStep1;

                // load grad colors

                long tlip = _mm_cvtsi128_si64 (ipos);
                ipos = _mm_unpackhi_epi64 (ipos, ipos);

                tcvr = _mm_unpacklo_epi16 (tcvr, tcvr);
                __m128i tcvr2 = _mm_unpackhi_epi32 (tcvr, tcvr);
                tcvr = _mm_unpacklo_epi32 (tcvr, tcvr);

                __m128i c0 = _mm_loadu_si32 (&lut[tlip & lutmsk]);
                __m128i tnc = _mm_loadu_si32 (&lut[(tlip >> 32) & lutmsk]);
                c0 = _mm_unpacklo_epi32 (c0, tnc);
                c0 = _mm_unpacklo_epi8 (c0, XMZERO);
                __m128i a0 = _mm_broadcast_alpha(c0);
                a0 = _mm_mulhi_epu16(a0, tcvr);

                tlip = _mm_cvtsi128_si64 (ipos);

                __m128i c1 = _mm_loadu_si32 (&lut[tlip & lutmsk]);
                tnc = _mm_loadu_si32 (&lut[(tlip >> 32) & lutmsk]);
                c1 = _mm_unpacklo_epi32 (c1, tnc);
                c1 = _mm_unpacklo_epi8 (c1, XMZERO);
                __m128i a1 = _mm_broadcast_alpha(c1);
                a1 = _mm_mulhi_epu16(a1, tcvr2);

                // alpha*source + dest - alpha*dest

                c0 = _mm_mulhi_epu16 (c0,a0);
                c1 = _mm_mulhi_epu16 (c1,a1);
                c0 = _mm_adds_epi16 (c0,d0);
                c1 = _mm_adds_epi16 (c1,d1);
                d0 = _mm_mulhi_epu16 (d0,a0);
                d1 = _mm_mulhi_epu16 (d1,a1);
                c0 =  _mm_subs_epi16 (c0, d0);
                c1 =  _mm_subs_epi16 (c1, d1);

                d0 = _mm_packus_epi16 (c0,c1);

                _mm_store_si128 (cast(__m128i*)ptr,d0);
                
                bpos++;
                ptr+=4;
                dlptr+=4;

                if (((cast(ulong*)dlptr)[0] | (cast(ulong*)dlptr)[1]) == 0)  break;
            }
        }
    }

    // Member variables

    uint*      pixels;
    int        stride;
    int        height;
    Gradient   gradient;
    float      xctr,yctr;
    float      xstep0,ystep0;
    float      xstep1,ystep1; 
}

// helpers for fast atan2
// these should be inlined by ldc

private:

immutable __m128i ABSMASK = [0x7fffffff,0x7fffffff,0x7fffffff,0x7fffffff];
immutable __m128 MINSUM = [0.001,0.001,0.001,0.001];

__m128 gradOfSorts(__m128 x, __m128 y)
{
    __m128 absx = _mm_and_ps(x, cast(__m128) ABSMASK);
    __m128 absy = _mm_and_ps(y, cast(__m128) ABSMASK);
    __m128 sum = _mm_add_ps(absx,absy);
    __m128 diff = _mm_sub_ps(absx,absy);
    sum = _mm_max_ps(sum,MINSUM);
    return diff / sum;
}

immutable __m128 PCOEF0  = [0.785398163f,0.785398163f,0.785398163f,0.785398163f];
immutable __m128 PCOEF1  = [0.972394341f,0.972394341f,0.972394341f,0.972394341f];
immutable __m128 PCOEF3  = [0.19194811f,0.19194811f,0.19194811f,0.19194811f];
immutable __m128 PSCALE  = [128.0f / 3.142f,128.0f / 3.142f,128.0f / 3.142f,128.0f / 3.142f];

__m128 polyAprox(__m128 g)
{
    __m128 sqr = g*g;
    __m128 p3 = PCOEF3*g;
    __m128 p1 = PCOEF1*g;
    __m128 poly = PCOEF0 - p1 + p3*sqr;
    return poly * PSCALE;
}

__m128i fixupQuadrant(__m128i ipos, __m128 t0, __m128 t1)
{
    __m128i xmsk = _mm_srai_epi32(cast(__m128i)t1,31);
    __m128i ymsk = _mm_srai_epi32(cast(__m128i)t0,31);
    ipos = ipos ^ (xmsk ^ ymsk);
    return ipos ^ _mm_slli_epi32(ymsk,7);
}

// test mixing in rather than inlining???

/*
string gradOfSorts(string res, string x, string y)
{
    return 
        "{ __m128 absx = _mm_and_ps("~x~", ABSMASK);" ~
        "__m128 absy = _mm_and_ps(y, ABSMASK);"
        "__m128 sum = _mm_add_ps(absx,absy);"
        "__m128 diff = _mm_sub_ps(absx,absy);"
        "sum = _mm_max_ps(sum,MINSUM);"
        res ~ " = diff / sum;"
}*/


+/