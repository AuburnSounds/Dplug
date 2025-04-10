/**
* Miscellaneous functions for dplug:canvas internals. 
*
* Copyright: Copyright Chris Jones 2020.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.canvas.misc;

import core.stdc.stdlib : malloc, free, realloc;
public import inteli;
public import std.math : sqrt, abs;

nothrow:
@nogc:

version(LDC)
{
    import ldc.intrinsics;

    alias intr_bsf = llvm_ctlz;
    alias intr_bsr = llvm_cttz;
    alias fabs = llvm_fabs;        // DMD fabs sucks
}
else version(DigitalMars)
{
    import core.bitop;

    T intr_bsr(T)(T src, bool isZeroUndefined)
    {
        assert(isZeroUndefined);
        return bsf(src); // Note: llvm_cttz corresponds to bsf in DMD not bsr
    }
}

T min(T)(T a, T b)
{
    return (a < b) ? a : b;
}

T max(T)(T a, T b)
{
    return (a > b) ? a : b;
}

T clip(T)(T x, T min, T max)
{
    if (x < min) return min;
    if (x > max) return max;
    return x;
}

// round x up to next multiple of q

uint roundUpTo(uint x, uint q)
{
    uint tmp = x % q;
    return (tmp) ? x - tmp + q : x;
}

// round x up to next multiple of q

uint roundUpPow2(uint x)
{
    x--;
    x |= x >> 1;
    x |= x >> 2;
    x |= x >> 4;
    x |= x >> 8;
    x |= x >> 16;
    return x+1;
}

ulong roundUpPow2(ulong x)
{
    x--;
    x |= x >> 1;
    x |= x >> 2;
    x |= x >> 4;
    x |= x >> 8;
    x |= x >> 16;
    x |= x >> 32;
    return x+1;
}

// is power of 2

bool isPow2(int x)
{
    return ! ((x - 1) & x);
}

/*
  broadcast alpha

  x is [A2,R2,G2,B2,A1,R1,G1,B1], 16 bit components with lower 8 bits used
  returns [A2,A2,A2,A2,A1,A1,A1,A1], 16 bits used
  two versions, shuffleVector should lower to pshufb, but it is a bit slower on
  my CPU, maybe from increased register pressure?
*/

__m128i _mm_broadcast_alpha(__m128i x)
{
    x = _mm_shufflelo_epi16!255(x);
    x = _mm_shufflehi_epi16!255(x);
    return _mm_slli_epi16(x,8);
}

// Used for clamping 4 LUT indices to valid values.
__m128i _mm_clamp_0_to_N_epi32(__m128i v, short max)
{
    // turn into shorts to be able to use min and max functions
    // this preserve signedness
    // _mm_max_epi32 exists but in SSE4.1
    v = _mm_packs_epi32(v, _mm_setzero_si128());

    // Clip to zero if negative
    v = _mm_max_epi16(v, _mm_setzero_si128());

    // Clip to max if above
    v = _mm_min_epi16(v, _mm_set1_epi16(max));

    // Expand back to 32-bit
    return _mm_unpacklo_epi16(v, _mm_setzero_si128());
}

/*
  nextSetBit, searches the bit mask for the next set bit. 

  mask  - array that holds the bits
  start - start position
  end   - end position

  returns : index of next set bit, or "end" if none found

  note the mask should be long enough in the given word size to hold
  the bits, IE. If end = 65, then the uint mask should be 3 uints,
  the ulong mask should be 2 ulongs. If end = 64, then it only
  need be 2 uints or 1 ulong.
*/

int nextSetBit(ulong* mask, int start, int end)
{
    assert((start >= 0) && (start < end));

    int nsb = start;
    int idx = nsb>>6;
    ulong bits = mask[idx] >> (nsb & 63); 

    if (bits == 0)
    {
        idx++;
        int msklen = (end+63)>>6;
        while (idx < msklen)
        {
            if (mask[idx] != 0)
            {
                nsb = idx*64 + cast(int) intr_bsr(mask[idx],true);
                if (nsb > end) nsb = end;
                return nsb;
            }
            idx++;
        }
        return end;
    }
    nsb = nsb + cast(int) intr_bsr(bits,true);
    if (nsb > end) nsb = end;
    return nsb;
}

int nextSetBit(uint* mask, int start, int end)
{
    assert((start >= 0) && (start < end));

    int nsb = start;
    int idx = nsb>>5;
    uint bits = mask[idx] >> (nsb & 31); 

    if (bits == 0)
    {
        idx++;
        int msklen = (end+31)>>5;
        while (idx < msklen)
        {
            if (mask[idx] != 0)
            {
                nsb = idx*32 + cast(int) intr_bsr(mask[idx],true);
                if (nsb > end) nsb = end;
                return nsb;
            }
            idx++;
        }
        return end;
    }
    nsb = nsb + cast(int) intr_bsr(bits,true);
    if (nsb > end) nsb = end;
    return nsb;
}


/*
  Arena Allocator, very fast allocation, free all memory at once. Essentialy
  it is a linked list of memory blocks and allocation is sequential through
  each block and on to the next. If it runs out of blocks it allocates and
  adds a new one to the end of the linked list. Reset() resets the allocator
  to the begining of the first block. Nothing is freed back to the C allocator
  until the destructor is called. No init or clean up is done of the memory.
*/

struct ArenaAllocator(T, uint blockSize)
{  
nothrow:
@nogc:
    struct EABlock
    {
        EABlock* next;
        T[blockSize] items;
    }

    EABlock* m_root;
    EABlock* m_block;
    uint m_pos = uint.max;

    // note: m_pos is set to uint.max if no blocks are allocated yet. This avoids
    // having to do two conditional tests in the fast path of allocate() method.

public:

    ~this()
    {
        while (m_root)
        {
            EABlock* tmp = m_root;
            m_root = m_root.next;
            free(tmp);
        }
    }

    T* allocate()
    {
        if (m_pos < blockSize)
        {
            return &m_block.items[m_pos++];
        }
        else
        {
            if (m_block)
            {
                if (m_block.next)
                {
                    m_block = m_block.next;
                    m_pos = 0;
                    return &m_block.items[m_pos++];
                }
                else
                {
                    void* tmp = malloc(EABlock.sizeof);
                    if (!tmp) assert(0); // no mem abandon ship!
                    m_block.next = cast(EABlock*) tmp;
                    m_block = m_block.next;
                    m_block.next = null;
                    m_pos = 0;
                    return &m_block.items[m_pos++];
                }
            }
            else
            {
                void* tmp = malloc(EABlock.sizeof);
                if (!tmp) assert(0); // no mem abandon ship!
                m_root = cast(EABlock*) tmp;
                m_block = m_root;
                m_block.next = null;
                m_pos = 0;
                return &m_block.items[m_pos++];
            }
        }
    }

    void reset()
    {
        m_block = m_root;
        m_pos = (m_root) ? 0 : uint.max;
    }
}
