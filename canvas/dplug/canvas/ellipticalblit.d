/**
* Implement the elliptic gradient fill style. dplug:canvas internals.
*
* Copyright: Copyright Chris Jones 2020.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.canvas.ellipticalblit;

import dplug.canvas.rasterizer;
import dplug.canvas.gradient;
import dplug.canvas.misc;

struct EllipticalBlit
{   
nothrow:
@nogc:

    void init(Gradient g, float x0, float y0, float x1, float y1, float r2)
    {
        assert(g !is null);
        this.gradient = g;
        int lutsize = g.lutLength;

        xctr = x0;
        yctr = y0;
        float w = x1-x0;
        float h = y1-y0;
        float hyp = w*w + h*h;
        if (hyp < 1.0) hyp = 1.0;
        xstep0 = lutsize * w / hyp; 
        ystep0 = lutsize * h / hyp;
        hyp = sqrt(hyp);
        xstep1 = lutsize * h / (r2*hyp);
        ystep1 = lutsize * -w / (r2*hyp); 
    }

private:

    void color_blit(WindingRule wr)(uint* dest, int* delta, DMWord* mask, int x0, int x1, int y)
    {
        assert(x0 >= 0);
        assert(y >= 0);
        assert((x0 & 3) == 0);
        assert((x1 & 3) == 0);

        // main blit variables

        int bpos = x0 / 4;
        int endbit = x1 / 4;

        __m128i xmWinding = 0;
        uint* lut = gradient.getLookup.ptr;
        short lutMax = cast(short)(gradient.lutLength - 1);
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
                        __m128 rad = _mm_add_ps(_mm_mul_ps(xmT0, xmT0),_mm_mul_ps(xmT1, xmT1));
                        rad = _mm_sqrt_ps(rad);
                        xmT0 = xmT0 + xmStep0;
                        xmT1 = xmT1 + xmStep1;
                        __m128i ipos = _mm_cvttps_epi32 (rad);
                        ipos = _mm_clamp_0_to_N_epi32(ipos, lutMax);

                        ptr[0] = lut[ ipos.array[0] ];
                        ptr[1] = lut[ ipos.array[1] ];
                        ptr[2] = lut[ ipos.array[2] ];
                        ptr[3] = lut[ ipos.array[3] ];

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
                        __m128 rad = _mm_add_ps(_mm_mul_ps(xmT0, xmT0),_mm_mul_ps(xmT1, xmT1));
                        xmT0 = xmT0 + xmStep0;
                        xmT1 = xmT1 + xmStep1;
                        rad = _mm_sqrt_ps(rad);

                        __m128i d0 = _mm_loadu_si64 (ptr);
                        d0 = _mm_unpacklo_epi8 (d0, XMZERO);
                        __m128i d1 = _mm_loadu_si64 (ptr+2);
                        d1 = _mm_unpacklo_epi8 (d1, XMZERO);

                        __m128i ipos = _mm_cvttps_epi32 (rad);
                        ipos = _mm_clamp_0_to_N_epi32(ipos, lutMax);

                        __m128i c0 = _mm_loadu_si32 (&lut[ ipos.array[0] ]);
                        __m128i tnc = _mm_loadu_si32 (&lut[ ipos.array[1] ]);
                        c0 = _mm_unpacklo_epi32 (c0, tnc);
                        c0 = _mm_unpacklo_epi8 (c0, XMZERO);
                        __m128i a0 = _mm_broadcast_alpha(c0);
                        a0 = _mm_mulhi_epu16(a0, tqcvr);

                        __m128i c1 = _mm_loadu_si32 (&lut[ ipos.array[2] ]);
                        tnc = _mm_loadu_si32 (&lut[ ipos.array[3] ]);
                        c1 = _mm_unpacklo_epi32 (c1, tnc);
                        c1 = _mm_unpacklo_epi8 (c1, XMZERO);
                        __m128i a1 = _mm_broadcast_alpha(c1);
                        a1 = _mm_mulhi_epu16(a1, tqcvr);

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

                        _mm_storeu_si128 (cast(__m128i*)ptr,d0);
                        
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
                __m128 rad = _mm_add_ps(_mm_mul_ps(xmT0, xmT0),_mm_mul_ps(xmT1, xmT1));
                rad = _mm_sqrt_ps(rad);

                // Integrate delta values

                __m128i tqw = _mm_loadu_si128(cast(__m128i*)dlptr);
                tqw = _mm_add_epi32(tqw, _mm_slli_si128!4(tqw)); 
                tqw = _mm_add_epi32(tqw, _mm_slli_si128!8(tqw)); 
                tqw = _mm_add_epi32(tqw, xmWinding); 
                xmWinding = _mm_shuffle_epi32!255(tqw);  
                _mm_storeu_si128(cast(__m128i*)dlptr,XMZERO);

                // convert grad pos to integer

                __m128i ipos = _mm_cvttps_epi32(rad);
                ipos = _mm_clamp_0_to_N_epi32(ipos, lutMax);
                xmT0 = xmT0 + xmStep0;
                xmT1 = xmT1 + xmStep1;

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

                __m128i d0 = _mm_loadu_si64 (ptr);
                d0 = _mm_unpacklo_epi8 (d0, XMZERO);
                __m128i d1 = _mm_loadu_si64 (ptr+2);
                d1 = _mm_unpacklo_epi8 (d1, XMZERO);

                // load grad colors

                tcvr = _mm_unpacklo_epi16 (tcvr, tcvr);
                __m128i tcvr2 = _mm_unpackhi_epi32 (tcvr, tcvr);
                tcvr = _mm_unpacklo_epi32 (tcvr, tcvr);

                __m128i c0 = _mm_loadu_si32 (&lut[ ipos.array[0] ]);
                __m128i tnc = _mm_loadu_si32 (&lut[ ipos.array[1] ]);
                c0 = _mm_unpacklo_epi32 (c0, tnc);
                c0 = _mm_unpacklo_epi8 (c0, XMZERO);
                __m128i a0 = _mm_broadcast_alpha(c0);
                a0 = _mm_mulhi_epu16(a0, tcvr);

                __m128i c1 = _mm_loadu_si32 (&lut[ ipos.array[2] ]);
                tnc = _mm_loadu_si32 (&lut[ ipos.array[3] ]);
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

                _mm_storeu_si128 (cast(__m128i*)ptr,d0);
                
                bpos++;
                ptr+=4;
                dlptr+=4;

                if (((cast(ulong*)dlptr)[0] | (cast(ulong*)dlptr)[1]) == 0)  break;
            }
        }
    }

    // Member variables

    Gradient  gradient;
    float      xctr,yctr;
    float      xstep0,ystep0;
    float      xstep1,ystep1; 
}

void doBlit_EllipticalBlit_NonZero(void* userData, uint* dest, int* delta, DMWord* mask, int x0, int x1, int y) nothrow @nogc
{
    EllipticalBlit* cb = cast(EllipticalBlit*)userData;
    return cb.color_blit!(WindingRule.NonZero)(dest, delta, mask, x0, x1, y);
}

void doBlit_EllipticalBlit_EvenOdd(void* userData, uint* dest, int* delta, DMWord* mask, int x0, int x1, int y) nothrow @nogc
{
    EllipticalBlit* cb = cast(EllipticalBlit*)userData;
    return cb.color_blit!(WindingRule.EvenOdd)(dest, delta, mask, x0, x1, y);
}

