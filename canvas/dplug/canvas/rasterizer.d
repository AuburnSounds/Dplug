/**
 * Analytic antialiasing rasterizer.
 * Copyright: Copyright Chris Jones 2020.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module dplug.canvas.rasterizer;

import std.traits;
import dplug.core.math;
import dplug.core.vec;
import dplug.canvas.misc;

// Those asserts are disabled by default, since they are very slow in debug mode.
//debug = checkRasterizer;

/*
  Analytic antialiasing rasterizer.
  =================================

  Internally works with 24:8 fixed point integer coordinates.

  You need 8 bits fractional to get 256 levels of gray for almost
  horizontal or almost vertical lines. Hence 24:8 fixed point.

  It's a scanline based rasterizer. You add path data in the form
  of lines and curves etc... Those are converted to edges. The edges
  are converted to scanline coverage, then coverage is combined with
  paint and blended to the destination pixels.

  The coverage is stored in differentiated form, each cell in
  the scanline stores the difference between cells rather than
  the actual coverage. This means we dont have to track coverage
  for long spans where nothing happens.

  It also uses a bitmask to track changes in coverage. It's an idea
  taken from Blend2D although i think my implementation is different.
  Basically anywhere an edge crosses the current scanline the bit
  for the leftmost pixel it touches is set in the mask. So we can
  use a bitscan instruction to find long spans of unchanging
  coverage and where we need to start processing the coverage again.

  The mask uses 1 bit for every 4 pixels, because the blitters are
  processing 4 pixels at once with SIMD.

  Cliping is handled by having left and right clip buffers, any edges
  crossing the left or righ boundry are spit at the boundry. Parts inside
  are handled normaly, parts outside are added to the clip buffers so
  that we keep track of what coverage they contribute. This is then
  added to the scandelta at the start of processing each line. These
  buffers use differentiated coverage.
*/

/*
   Winding rule
   Gradient repeat mode
   Angular gradient mode

   (repeat modes not implemented yet)
*/

nothrow:
@nogc:

enum WindingRule
{
    NonZero,
    EvenOdd
}

enum RepeatMode
{
    Pad,
    Repeat,
    Mirror
}

enum AngularMode
{
    Single,
    Double,
    Quad
}

enum CompositeOp
{
    SourceOver,
    Add,
    Subtract,
    LightenOnly,
    DarkenOnly
}

/*
  Delta mask stuff
  what word type to use for mask
  how many pixels per bit
  how many pixels per word
  bit mask for width of DMWord
*/

static if ((void*).sizeof == 4)
    alias DMWord = uint;
else static if ((void*).sizeof == 8)
    alias DMWord = ulong;
else
    static assert(0);

private:

enum dmPixPerBit = 4; 
enum dmPixPerWord = dmPixPerBit * 8 * DMWord.sizeof;
enum dmWordMask = 8 * DMWord.sizeof - 1;

/*
  set a bit in the delta mask, 'x' is pixel cordinate, not bit index
*/

void DMSetBit(DMWord* mask, uint x)
{
    mask[x/dmPixPerWord] |= (cast(DMWord)1) << ((x / dmPixPerBit) & dmWordMask);  
}

void DMSetBitRange(DMWord* mask, uint x0, int x1)
{
    while (x0 <= x1)
    {
        mask[x0/dmPixPerWord] |= (cast(DMWord)1) << ((x0 / dmPixPerBit) & dmWordMask);
        x0+=4;
    }
}

/*
  Few constants for fixed point coordinates / gradients
*/

enum fpFracBits = 8;    // 8 bits fractional
enum fpScale = 256.0f;  // for converting from float
enum fpDXScale = 4294967296.0; // convert to dx gradient in 32:32
enum fpDYScale = 1073741824.0; // as above but div 4

/*
  Blitter delegate. A callback that does the actual blitting once coverage
  for the given scanline has been calculated.
    dest  - destination pixels
    delta - pointer to the delta buffer
    mask  - pointer to delta mask
    x0    - start x
    x1    - end x
    y     - current y (needed for gradients)
*/

alias BlitFunction = void function(void* userData, uint* dest, int* delta, DMWord* mask, int x0, int x1, int y);



/*
  a*b/c, with the intermediate result of a*b in 64 bit
  the asm version might be faster in 32 bit mode, havent tested yet, but the
  plain D version is same speed with 64bit / LDC
*/

public:

struct Blitter
{
    void* userData; // used for retrieving context
    BlitFunction doBlit;
}

/// Rasterizer
package struct Rasterizer
{
public:
nothrow:
@nogc:

    @disable this(this);


    /*
      initialise -- This sets the clip rectange, flushes any existing state
      and preps for drawing.

      The clip window left,top is inside, right,bottom is outside. So if the
      window is 100,100 --> 200,200, then pixel 100,100 can be modified but
      pixel 200,200 will not.

      The rasterizer however needs to allow coordinates that fall directly on
      the right side and bottom side of the clip even though those pixels are
      techically outside. It's easier and faster to give the temporary buffers
      a bit extra room for overspill than it is to check and special case
      when it happens.

      Also the delta buffer and two clip buffers use differentiated coverage
      which also causes one extra pixel overspill. If you differentiate a
      sequence of length N you get a sequence of length N+1. Again it's easier
      and faster to just allow for the overspill than it is to check for and
      special case it.
    */

    void initialise(int left, int top, int right, int bottom)
    {
        assert((left >= 0) && (left < right));
        assert((top >= 0) && (top < bottom));

        m_clipleft = left << fpFracBits;
        m_cliptop = top << fpFracBits;
        m_clipright = right << fpFracBits;
        m_clipbottom = bottom << fpFracBits;

        // reset edge buffer and Y extent tracking

        m_edgepool.reset();
        m_yrmin = bottom;
        m_yrmax = top;

        // init buffers
        m_scandelta.resize(roundUpPow2((right+3)|63));

        m_deltamaskSize = cast(size_t) roundUpPow2(1+right/dmPixPerWord);
        if (m_deltamaskSize > m_deltamaskAlloc)
        {
            m_deltamask = cast(DMWord*) alignedReallocDiscard(m_deltamask, m_deltamaskSize * (DMWord*).sizeof, 1);
            m_deltamaskAlloc = m_deltamaskSize;
        }

        m_buckets.resize(roundUpPow2(bottom+1));
        m_clipbfr_l.resize(roundUpPow2((bottom+2)|63));
        m_clipbfr_r.resize(roundUpPow2((bottom+2)|63));

        m_destBuf.resize( (right+3)*4 ); // 3 additional pixels, size of a scanline

        m_scandelta.fill(0);
        // m_deltamask is init on each rasterized line
        m_buckets.fill(null);
        m_clipbfr_l.fill(0);
        m_clipbfr_r.fill(0);

        // init prev x,y and sub path start x,y

        m_prevx = 0;
        m_prevy = 0;
        m_subpx = 0;
        m_subpy = 0;
        m_fprevx = 0;
        m_fprevy = 0;
    }

    ~this()
    {
        if (m_deltamask)
        {
            alignedFree(m_deltamask, 1);
            m_deltamask = null;
        }
    }

    // rasterize

    void rasterize(ubyte* imagePixels,
                   const size_t imagePitchInBytes,
                   const int imageHeight,
                   Blitter blitter,
                   CompositeOp compositeOp)
    {
        Edge dummy;
        Edge* prev = &dummy;
        Edge* edge = null;

        int startx = (m_clipleft >> fpFracBits) & 0xFFFFFFFC;
        int endx = ((m_clipright >> fpFracBits) + 3) & 0xFFFFFFFC;
        int starty = m_yrmin >> fpFracBits;
        int endy = (m_yrmax+255) >> fpFracBits;

        int cl_acc,cr_acc;
        int cl_pos = m_clipleft >> fpFracBits;
        int cr_pos = m_clipright >> fpFracBits;

        ubyte* pDest = imagePixels + imagePitchInBytes * starty;

        for (int y = starty; y < endy; y++)
        {
            m_deltamask[0..m_deltamaskSize] = 0;
            int ly = (y << fpFracBits) + 256;

            // clip accumulator

            cl_acc += m_clipbfr_l[y];
            m_clipbfr_l[y] = 0;
            cr_acc += m_clipbfr_r[y];
            m_clipbfr_r[y] = 0;

            if (cl_acc) DMSetBit(m_deltamask, cl_pos);
            if (cr_acc) DMSetBit(m_deltamask, cr_pos);

            m_scandelta[cl_pos] += cl_acc;
            m_scandelta[cr_pos] += cr_acc;

            // At this point 'prev' either points at 'dummy' or at the last node in
            //   active edges linked list, so we just add the new edges to it.

            prev.next = m_buckets[y];
            m_buckets[y] = null;

            // loop through the active edges

            prev = &dummy;
            edge = dummy.next;

            while (edge)
            {
                int ny = void;

                if (edge.y2 <= ly)
                {
                    ny = edge.y2;
                    prev.next = edge.next;
                }
                else
                {
                    ny = ly;
                    prev = edge;
                }

                int span = ny - edge.y;
                long nx = edge.x + edge.dx * span;

                int bpspan = span * ((cast(int)(edge.dy>>63))|1);

                int x0 = cast(int)(edge.x >> 40);
                int x1 = cast(int)(nx >> 40);
                int steps = x1 - x0;

                if (steps == 0)
                {
                    DMSetBit(m_deltamask, x0);

                    int w = (edge.x >> 32) & 0xFF;
                    int v = (nx >> 32) & 0xFF;
                    int area = (bpspan * (512 - w - v)) >> 2;
                    m_scandelta[x0] += area;
                    x0++;
                    m_scandelta[x0] += bpspan * 128 - area;
                }
                else if (steps > 0)
                {
                    DMSetBitRange(m_deltamask, x0, x1);

                    int w = 256 - ((edge.x >> 32) & 0xFF);
                    long acc = w * edge.dy;
                    int area = cast(int)((w * acc) >> 32);
                    m_scandelta[x0] += area;
                    x0++;
                    acc += edge.dy << 7;

                    while (x0 < x1)
                    {
                        int lc = area;
                        area = cast(int)(acc >> 23);
                        m_scandelta[x0] += area - lc;
                        x0++;
                        acc += edge.dy << 8;
                    }

                    int q = (nx >> 32) & 0xFF;
                    int rect = bpspan * 128;
                    int lc = area;
                    area = rect - cast(int)((q * q * edge.dy) >> 32);
                    m_scandelta[x0] += area - lc;
                    x0++;
                    m_scandelta[x0] += rect - area;
                }
                else if (steps < 0)
                {
                    DMSetBitRange(m_deltamask, x1, x0);

                    int w = 256 - ((nx >> 32) & 0xFF);
                    long acc = w * edge.dy;
                    int area = cast(int)((w * acc) >> 32);
                    m_scandelta[x1] += area;
                    x1++;
                    acc += edge.dy << 7;

                    while (x1 < x0)
                    {
                        int lc = area;
                        area = cast(int)(acc >> 23);
                        m_scandelta[x1] += area - lc;
                        x1++;
                        acc += edge.dy << 8;
                    }

                    int q = (edge.x >> 32) & 0xFF;
                    int rect = bpspan * 128;
                    int lc = area;
                    area = rect - cast(int)((q * q * edge.dy) >> 32);
                    m_scandelta[x1] += area - lc;
                    x1++;
                    m_scandelta[x1] += rect - area;
                }

                edge.x = nx;
                edge.y = ny;
                edge = edge.next;
            }

            // Blit scanline
            if (compositeOp == CompositeOp.SourceOver)
            {
                // special case for fastest blit, source-over is the default.
                blitter.doBlit(blitter.userData, cast(uint*)pDest, m_scandelta.ptr, m_deltamask, startx, endx, y);                
            }
            else
            {
                uint* tmpBuf = cast(uint*)m_destBuf.ptr;
                uint* dest = cast(uint*)pDest;

                assert((startx & 3) == 0);
                assert((endx & 3) == 0);

                // Fill with zeroes
                tmpBuf[startx..endx] = 0; // black in rgba8

                // Write into destbuf.
                // There is an additional difficulty, because the pixels that were touched have an excess in -3 to +3 potentially.
                // This is done with coverage being zero. So our Porter-Duff would overwrite if we don't multiply with source-alpha!
                blitter.doBlit(blitter.userData, tmpBuf, m_scandelta.ptr, m_deltamask, startx, endx, y);

                // Custom composite operations go here.

                // Note: in HTML standard, destination alpha is considered, and the resulting color
                // is a weighted average of the dest and blended source. I suppose alpha also gets to be
                // a weighted average, but this implies a divide, and we assume background alpha to be 255.
                //
                // alpha-res = (255 * 255 + src-alpha * src-alpha) / (src-alpha + 255)
                // Under these circumstances, alpha-res is always close to 255.

                __m128i alphaMask = _mm_set1_epi32(0xff000000);

                final switch (compositeOp)
                {
                    case CompositeOp.SourceOver:
                        assert(false);

                    case CompositeOp.Add:
                        for (int x = startx; x < endx; x += 4)
                        {
                            __m128i D = _mm_loadu_si128(cast(__m128i*) &dest[x]);
                            __m128i S = _mm_loadu_si128(cast(__m128i*) &tmpBuf[x]);
                            __m128i Z = _mm_setzero_si128();
                            __m128i D0_3 = _mm_unpacklo_epi8(D, Z); 
                            __m128i D4_7 = _mm_unpackhi_epi8(D, Z);
                            __m128i S0_3 = _mm_unpacklo_epi8(S, Z); 
                            __m128i S4_7 = _mm_unpackhi_epi8(S, Z);
                            D0_3 = _mm_add_epi16(D0_3, S0_3);
                            D4_7 = _mm_add_epi16(D4_7, S4_7);
                            __m128i R = _mm_packus_epi16(D0_3, D4_7);
                            R = _mm_or_si128(R, alphaMask);
                            _mm_storeu_si128(cast(__m128i*) &dest[x], R);
                        }
                        break;

                    case CompositeOp.Subtract:
                        for (int x = startx; x < endx; x += 4)
                        {
                            __m128i D = _mm_loadu_si128(cast(__m128i*) &dest[x]);
                            __m128i S = _mm_loadu_si128(cast(__m128i*) &tmpBuf[x]);
                            __m128i Z = _mm_setzero_si128();
                            __m128i D0_3 = _mm_unpacklo_epi8(D, Z); 
                            __m128i D4_7 = _mm_unpackhi_epi8(D, Z);
                            __m128i S0_3 = _mm_unpacklo_epi8(S, Z); 
                            __m128i S4_7 = _mm_unpackhi_epi8(S, Z);
                            D0_3 = _mm_sub_epi16(D0_3, S0_3);
                            D4_7 = _mm_sub_epi16(D4_7, S4_7);
                            __m128i R = _mm_packus_epi16(D0_3, D4_7);
                            R = _mm_or_si128(R, alphaMask);
                            _mm_storeu_si128(cast(__m128i*) &dest[x], R);
                        }
                        break;

                    case CompositeOp.LightenOnly:
                        //    (1 - alpha) * bg + max(bg, fg) * alpha
                        // == (1 - alpha) * bg + max(bg * alpha, fg * alpha) and we get fg.alpha
                        for (int x = startx; x < endx; x += 4)
                        {
                            __m128i D = _mm_loadu_si128(cast(__m128i*) &dest[x]);   // BG
                            __m128i S = _mm_loadu_si128(cast(__m128i*) &tmpBuf[x]); // FG * A, A
                            __m128i Z = _mm_setzero_si128();
                            
                            __m128i D0_1 = _mm_unpacklo_epi8(D, Z); // two background pixels
                            __m128i D2_3 = _mm_unpackhi_epi8(D, Z); // ditto
                            __m128i S0_1 = _mm_unpacklo_epi8(S, Z); // two foreground pixels
                            __m128i S2_3 = _mm_unpackhi_epi8(S, Z); // ditto

                            __m128i A0_1 = _mm_shufflelo_epi16!0xff(_mm_shufflehi_epi16!0xff(S0_1)); // A0 A0 A0 A0 A1 A1 A1 A1
                            __m128i A2_3 = _mm_shufflelo_epi16!0xff(_mm_shufflehi_epi16!0xff(S2_3)); // A2 A2 A2 A2 A3 A3 A3 A3
                            __m128i m255 = _mm_set1_epi16(255);
                            __m128i mA0_1 = _mm_sub_epi16(m255, A0_1); // (255-A0)x4 (255-A1)x4
                            __m128i mA2_3 = _mm_sub_epi16(m255, A2_3);
                            A0_1 = _mm_slli_epi16(A0_1, 8);
                            A2_3 = _mm_slli_epi16(A2_3, 8);
                            mA0_1 = _mm_slli_epi16(mA0_1, 8);
                            mA2_3 = _mm_slli_epi16(mA2_3, 8);

                            // multiply bg * alpha
                            __m128i BGA0_1 = _mm_mulhi_epu16(A0_1, D0_1);
                            __m128i BGA2_3 = _mm_mulhi_epu16(A2_3, D2_3);

                            // multiply bg * (1 - alpha)
                            __m128i mBGA0_1 = _mm_mulhi_epu16(mA0_1, D0_1);
                            __m128i mBGA2_3 = _mm_mulhi_epu16(mA2_3, D2_3);

                            __m128i R0_1 = _mm_add_epi16( _mm_max_epi16(S0_1, BGA0_1), mBGA0_1);
                            __m128i R2_3 = _mm_add_epi16( _mm_max_epi16(S2_3, BGA2_3), mBGA2_3);

                            __m128i R = _mm_packus_epi16(R0_1, R2_3);
                            R = _mm_or_si128(R, alphaMask);
                            _mm_storeu_si128(cast(__m128i*) &dest[x], R);
                        }
                        break;

                    case CompositeOp.DarkenOnly:
                        //    (1 - alpha) * bg + min(bg, fg) * alpha
                        // == (1 - alpha) * bg + min(bg * alpha, fg * alpha) and we get fg.alpha
                        for (int x = startx; x < endx; x += 4)
                        {
                            __m128i D = _mm_loadu_si128(cast(__m128i*) &dest[x]);   // BG
                            __m128i S = _mm_loadu_si128(cast(__m128i*) &tmpBuf[x]); // FG * A, A
                            __m128i Z = _mm_setzero_si128();

                            __m128i D0_1 = _mm_unpacklo_epi8(D, Z); // two background pixels
                            __m128i D2_3 = _mm_unpackhi_epi8(D, Z); // ditto
                            __m128i S0_1 = _mm_unpacklo_epi8(S, Z); // two foreground pixels
                            __m128i S2_3 = _mm_unpackhi_epi8(S, Z); // ditto

                            __m128i A0_1 = _mm_shufflelo_epi16!0xff(_mm_shufflehi_epi16!0xff(S0_1)); // A0 A0 A0 A0 A1 A1 A1 A1
                            __m128i A2_3 = _mm_shufflelo_epi16!0xff(_mm_shufflehi_epi16!0xff(S2_3)); // A2 A2 A2 A2 A3 A3 A3 A3
                            __m128i m255 = _mm_set1_epi16(255);
                            __m128i mA0_1 = _mm_sub_epi16(m255, A0_1); // (255-A0)x4 (255-A1)x4
                            __m128i mA2_3 = _mm_sub_epi16(m255, A2_3);
                            A0_1 = _mm_slli_epi16(A0_1, 8);
                            A2_3 = _mm_slli_epi16(A2_3, 8);
                            mA0_1 = _mm_slli_epi16(mA0_1, 8);
                            mA2_3 = _mm_slli_epi16(mA2_3, 8);

                            // multiply bg * alpha
                            __m128i BGA0_1 = _mm_mulhi_epu16(A0_1, D0_1);
                            __m128i BGA2_3 = _mm_mulhi_epu16(A2_3, D2_3);

                            // multiply bg * (1 - alpha)
                            __m128i mBGA0_1 = _mm_mulhi_epu16(mA0_1, D0_1);
                            __m128i mBGA2_3 = _mm_mulhi_epu16(mA2_3, D2_3);

                            __m128i R0_1 = _mm_add_epi16( _mm_min_epi16(S0_1, BGA0_1), mBGA0_1);
                            __m128i R2_3 = _mm_add_epi16( _mm_min_epi16(S2_3, BGA2_3), mBGA2_3);

                            __m128i R = _mm_packus_epi16(R0_1, R2_3);
                            R = _mm_or_si128(R, alphaMask);
                            _mm_storeu_si128(cast(__m128i*) &dest[x], R);
                        }
                        break;
                }
            }

            pDest += imagePitchInBytes;

            // clear scandelta overspill

            m_scandelta[endx] = 0;

            debug(checkRasterizer)
            {

                size_t size = m_scandelta.length;
                foreach(e; m_scandelta) assert(e == 0);
            }
        }

        // clear clip buffers overspill

        m_clipbfr_l[endy] = 0;
        m_clipbfr_r[endy] = 0;

        debug(checkRasterizer)
        {
           foreach(e; m_clipbfr_l) assert(e == 0);
           foreach(e; m_clipbfr_r) assert(e == 0);
        }

        // clear m_buckets overspill, this is only needed because in very
        // rare cases we could end up with an edge could end up on the
        // bottom clip boundry after spliting an edge, these should really
        // be removed in the clipping code

        m_buckets[endy] = null;
        
        debug(checkRasterizer)
        {
           foreach(e; m_buckets) assert(e == null);
        } 

        m_edgepool.reset();
    }

    /*
      drawing methods
    */

    void moveTo(double x, double y)
    {
        intMoveTo(cast(int)(x * fpScale), cast(int)(y * fpScale));
        m_fprevx = x;
        m_fprevy = y;
    }

    void moveTo(float x, float y)
    {
        intMoveTo(cast(int)(x * fpScale), cast(int)(y * fpScale));
        m_fprevx = x;
        m_fprevy = y;
    }

    void lineTo(double x, double y)
    {
        intLineTo(cast(int)(x * fpScale), cast(int)(y * fpScale));
        m_fprevx = x;
        m_fprevy = y;
    }

    void lineTo(float x, float y)
    {
        intLineTo(cast(int)(x * fpScale), cast(int)(y * fpScale));
        m_fprevx = x;
        m_fprevy = y;
    }

    void quadTo(float x1, float y1, float x2, float y2)
    {
        float x01 = (m_fprevx+x1)*0.5;
        float y01 = (m_fprevy+y1)*0.5;
        float x12 = (x1+x2)*0.5;
        float y12 = (y1+y2)*0.5;
        float xctr = (x01+x12)*0.5;
        float yctr = (y01+y12)*0.5;
        float err = (x1-xctr)*(x1-xctr)+(y1-yctr)*(y1-yctr);

        if (err > 0.1)
        {
            quadTo(x01,y01,xctr,yctr);
            quadTo(x12,y12,x2,y2);
        }
        else
        {
            intLineTo(cast(int)(x2 * fpScale), cast(int)(y2 * fpScale));
        }

        m_fprevx = x2;
        m_fprevy = y2;
    }

    void cubicTo(float x1, float y1, float x2, float y2, float x3, float y3)
    {
        bool error = (x1 == x2 && x2 == x3 && y1 == y2 && y2 == y3);

        // Avoid stack overflow with infinite recursion.
        // It is poorly understood why that happens.
        if (error)
            return;

        float x01 = (m_fprevx+x1)*0.5;
        float y01 = (m_fprevy+y1)*0.5;
        float x12 = (x1+x2)*0.5;
        float y12 = (y1+y2)*0.5;
        float x23 = (x2+x3)*0.5;
        float y23 = (y2+y3)*0.5;
        
        float xc0 = (x01+x12)*0.5;
        float yc0 = (y01+y12)*0.5;
        float xc1 = (x12+x23)*0.5;
        float yc1 = (y12+y23)*0.5;
        float xctr = (xc0+xc1)*0.5;
        float yctr = (yc0+yc1)*0.5;
        
        // this flattenening test code was from a page on the antigrain geometry
        // website.

        float dx = x3-m_fprevx;
        float dy = y3-m_fprevy;

        double d2 = fast_fabs(((x1 - x3) * dy - (y1 - y3) * dx));
        double d3 = fast_fabs(((x2 - x3) * dy - (y2 - y3) * dx));

        if((d2 + d3)*(d2 + d3) < 0.5 * (dx*dx + dy*dy))
        {
            intLineTo(cast(int)(x3 * fpScale), cast(int)(y3 * fpScale));
        }
        else
        {
            cubicTo(x01,y01,xc0,yc0,xctr,yctr);
            cubicTo(xc1,yc1,x23,y23,x3,y3);
        }

        m_fprevx = x3;
        m_fprevy = y3;
    }

    void closePath()
    {
        if ((m_prevx != m_subpx) || (m_prevy != m_subpy))
        {
            intLineTo(m_subpx, m_subpy);
        }
    }

private:

    // internal moveTo. Note this will close any existing subpath because
    // unclosed paths cause bad things to happen. (visually at least)

    void intMoveTo(int x, int y)
    {
        closePath();
        m_prevx = x;
        m_prevy = y;
        m_subpx = x;
        m_subpy = y;
    }

    // internal lineTo, clips and adds the line to edge buckets and clip
    // buffers as appropriate

    void intLineTo(int x, int y)
    {
        // mixin for adding edges. For some reason LDC wouldnt inline this when
        // it was a separate function, and it was 15% slower that way

        string addEdgeM(string x0, string y0, string x1, string y1, string dir)
        {
            string tmp = (dir == "+") ? (y1~"-"~y0) : (y0~"-"~y1);
            return
                "Edge* edge = m_edgepool.allocate();" ~
                "edge.dx = cast(long) (fpDXScale * ("~x1~"-"~x0~") / ("~y1~"-"~y0~"));" ~
                "edge.x = (cast(long) "~x0~") << 32;" ~
                "edge.y = "~y0~";" ~
                "edge.y2 = "~y1~";" ~
                "int by = "~y0~" >> fpFracBits;" ~
                "int xxx = max(abs("~x1~"-"~x0~"),1);" ~
                "edge.dy = cast(long) (fpDYScale * ("~tmp~") /  xxx);" ~
                "edge.next = m_buckets[by];" ~
                "m_buckets[by] = edge;";
        }

        // mixin for clip accumulator

        string addToClip(string y0, string y1, string side, string dir)
        {
            return
                "{ int i0 = "~y0~" >> fpFracBits;" ~
                "int f0 = ("~y0~" & 0xFF) << 7;" ~
                "int i1 = "~y1~" >> fpFracBits;" ~
                "int f1 = ("~y1~" & 0xFF) << 7;" ~
                "m_clipbfr_"~side~"[i0] "~dir~"= 32768-f0;" ~
                "m_clipbfr_"~side~"[i0+1] "~dir~"= f0;" ~
                "m_clipbfr_"~side~"[i1] "~dir~"= f1-32768;" ~
                "m_clipbfr_"~side~"[i1+1] "~dir~"= -f1; }";
        }

        // handle upward and downward lines seperately

        if (m_prevy < y)
        {
            int x0 = m_prevx, y0 = m_prevy, x1 = x, y1 = y;

            // edge is outside clip box or horizontal

            if ((y0 == y1) || (y0 >= m_clipbottom) || (y1 <= m_cliptop))
            {
                goto finished;
            }

            // clip to top and bottom

            if (y0 < m_cliptop)
            {
                x0 = x0 + MulDiv64(m_cliptop - y0, x1 - x0,  y1 - y0);
                y0 = m_cliptop;
            }

            if (y1 > m_clipbottom)
            {
                x1 = x0 + MulDiv64(m_clipbottom - y0, x1 - x0, y1 - y0);
                y1 = m_clipbottom;
            }

            // track y extent

            if (y0 < m_yrmin) m_yrmin = y0;
            if (y1 > m_yrmax) m_yrmax = y1;

            // generate horizontal zoning flags, these are set depending on where
            // x0 and x1 are in respect of the clip box.

            uint a = cast(uint)(x0<m_clipleft);
            uint b = cast(uint)(x0>m_clipright);
            uint c = cast(uint)(x1<m_clipleft);
            uint d = cast(uint)(x1>m_clipright);
            uint flags = a | (b*2) | (c*4) | (d*8);

            if (flags == 0) // bit faster to pull no clip out front
            {             
                mixin(addEdgeM("x0","y0","x1","y1","+"));
                goto finished;
            }

            // note cliping here can occasionaly result in horizontals, and can
            // ocaisionaly put a horizontal on bucket for clipbotttom, which is
            // outside the drawable area, currently it allows it and zeros that
            // bucket after rasterization. 

            switch (flags)
            {
            case (1): // 0001 --> x0 left, x1 center
                int sy = y0 + MulDiv64(y1 - y0, m_clipleft - x0, x1 - x0);
                mixin(addToClip("y0","sy","l","+"));
                mixin(addEdgeM("m_clipleft","sy","x1","y1","+"));
                break;
            case (2): // 0010 --> x0 right, x1 center
                int sy = y0 + MulDiv64(y1 - y0, m_clipright - x0, x1 - x0);
                mixin(addToClip("y0","sy","r","+"));
                mixin(addEdgeM("m_clipright","sy","x1","y1","+"));
                break;
            case (4): // 0100 --> x0 center, x1 left
                int sy = y0 + MulDiv64(y1 - y0, m_clipleft - x0, x1 - x0);
                mixin(addEdgeM("x0","y0","m_clipleft","sy","+"));
                mixin(addToClip("sy","y1","l","+"));
                break;
            case (5): // 0101 --> x0 left, x1 left
                mixin(addToClip("y0","y1","l","+"));
                break;
            case (6): // 0110 --> x0 right, x1 left
                int sl = y0 + MulDiv64(y1 - y0, m_clipleft - x0, x1 - x0);
                int sr = y0 + MulDiv64(y1 - y0, m_clipright - x0, x1 - x0);
                mixin(addToClip("y0","sr","r","+"));
                mixin(addEdgeM("m_clipright","sr","m_clipleft","sl","+"));
                mixin(addToClip("sl","y1","l","+"));
                break;
            case (8): // 1000 --> x0 center, x1 right
                int sy = y0 + MulDiv64(y1 - y0, m_clipright - x0, x1 - x0);
                mixin(addEdgeM("x0","y0","m_clipright","sy","+"));
                mixin(addToClip("sy","y1","r","+"));
                break;
            case (9): // 1001 --> x0 left, x1 right
                int sl = y0 + MulDiv64(y1 - y0, m_clipleft - x0, x1 - x0);
                int sr = y0 + MulDiv64(y1 - y0, m_clipright - x0, x1 - x0);
                mixin(addToClip("y0","sl","l","+"));
                mixin(addEdgeM("m_clipleft","sl","m_clipright","sr","+"));
                mixin(addToClip("sr","y1","r","+"));
                break;
            case (10): // 1001 --> x0 right, x1 right
                mixin(addToClip("y0","y1","r","+"));
                break;
            default: // everything else is NOP
                break; 
            }
        }
        else
        {
            int x1 = m_prevx, y1 = m_prevy, x0 = x, y0 = y;

            // edge is outside clip box or horizontal

            if ((y0 == y1) || (y0 >= m_clipbottom) || (y1 <= m_cliptop))
            {
                goto finished;
            }

            // clip to top and bottom

            if (y0 < m_cliptop)
            {
                x0 = x0 + MulDiv64(m_cliptop - y0, x1 - x0,  y1 - y0);
                y0 = m_cliptop;
            }

            if (y1 > m_clipbottom)
            {
                x1 = x0 + MulDiv64(m_clipbottom - y0, x1 - x0, y1 - y0);
                y1 = m_clipbottom;
            }

            // track y extent

            if (y0 < m_yrmin) m_yrmin = y0;
            if (y1 > m_yrmax) m_yrmax = y1;

            // generate horizontal zoning flags, these are set depending on where
            // x0 and x1 are in respect of the clip box.

            uint a = cast(uint)(x0<m_clipleft);
            uint b = cast(uint)(x0>m_clipright);
            uint c = cast(uint)(x1<m_clipleft);
            uint d = cast(uint)(x1>m_clipright);
            uint flags = a | (b*2) | (c*4) | (d*8);

            if (flags == 0) // bit faster to pull no clip out front
            {             
                mixin(addEdgeM("x0","y0","x1","y1","-"));
                goto finished;
            }
         
            // note cliping here can occasionaly result in horizontals, and can
            // occasionally put a horizontal on bucket for clipbotttom, which is
            // outside the drawable area, currently it allows it and zeros that
            // bucket after rasterization. 

            switch (flags)
            {
            case (1): // 0001 --> x0 left, x1 center
                int sy = y0 + MulDiv64(y1 - y0, m_clipleft - x0, x1 - x0);
                mixin(addToClip("y0","sy","l","-"));
                mixin(addEdgeM("m_clipleft","sy","x1","y1","-"));
                break;
            case (2): // 0010 --> x0 right, x1 center
                int sy = y0 + MulDiv64(y1 - y0, m_clipright - x0, x1 - x0);
                mixin(addToClip("y0","sy","r","-"));
                mixin(addEdgeM("m_clipright","sy","x1","y1","-"));
                break;
            case (4): // 0100 --> x0 center, x1 left
                int sy = y0 + MulDiv64(y1 - y0, m_clipleft - x0, x1 - x0);
                mixin(addEdgeM("x0","y0","m_clipleft","sy","-"));
                mixin(addToClip("sy","y1","l","-"));
                break;
            case (5): // 0101 --> x0 left, x1 left
                mixin(addToClip("y0","y1","l","-"));
                break;
            case (6): // 0110 --> x0 right, x1 left
                int sl = y0 + MulDiv64(y1 - y0, m_clipleft - x0, x1 - x0);
                int sr = y0 + MulDiv64(y1 - y0, m_clipright - x0, x1 - x0);
                mixin(addToClip("y0","sr","r","-"));
                mixin(addEdgeM("m_clipright","sr","m_clipleft","sl","-"));
                mixin(addToClip("sl","y1","l","-"));
                break;
            case (8): // 1000 --> x0 center, x1 right
                int sy = y0 + MulDiv64(y1 - y0, m_clipright - x0, x1 - x0);
                mixin(addEdgeM("x0","y0","m_clipright","sy","-"));
                mixin(addToClip("sy","y1","r","-"));
                break;
            case (9): // 1001 --> x0 left, x1 right
                int sl = y0 + MulDiv64(y1 - y0, m_clipleft - x0, x1 - x0);
                int sr = y0 + MulDiv64(y1 - y0, m_clipright - x0, x1 - x0);
                mixin(addToClip("y0","sl","l","-"));
                mixin(addEdgeM("m_clipleft","sl","m_clipright","sr","-"));
                mixin(addToClip("sr","y1","r","-"));
                break;
            case (10): // 1001 --> x0 right, x1 right
                mixin(addToClip("y0","y1","r","-"));
                break;
            default: // everything else is NOP
                break; 
            }
        }
    
    finished:

        m_prevx = x;
        m_prevy = y;
    }

    // edge struct

    struct Edge
    {
        long x, dx, dy;
        int y, y2;
        Edge* next;
    }

    ArenaAllocator!(Edge,100) m_edgepool;

    // Note: the reason why it's Vec is to avoid an initialization that would reallocate down.

    Vec!(Edge*) m_buckets;
    Vec!int m_scandelta;

    size_t m_deltamaskSize = 0;
    size_t m_deltamaskAlloc = 0;
    DMWord* m_deltamask;

    Vec!int m_clipbfr_l;
    Vec!int m_clipbfr_r;

    // clip rectangle, in 24:8 fixed point

    int m_clipleft;
    int m_cliptop;
    int m_clipright;
    int m_clipbottom;

    // keeps track of y extent

    int m_yrmin,m_yrmax;

    // start of current subpath, 

    int m_subpx,m_subpy;

    // previous x,y (internal coords)

    int m_prevx,m_prevy;

    // previous x,y float coords

    float m_fprevx,m_fprevy;

    // Temporary dest buffer for Porter Duff operations.
    Vec!ubyte m_destBuf;
}

// the rasterizer itself should be a reusable, small object suitable for the stack
static assert(Rasterizer.sizeof < 280);

private:

int MulDiv64(int a, int b, int c)
{
    return cast(int) ((cast(long) a * b) / c);
}