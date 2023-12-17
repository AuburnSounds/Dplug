//          Copyright Jernej Krempuš 2012
//          Copyright Guillaume Piolat 2016-2023
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)
module dplug.fft.sse_double;

import inteli.emmintrin;
import dplug.fft.fft_impl;

struct Vector
{
nothrow:
@nogc:
    alias double2 vec;
    alias double T;
    
    enum vec_size = 2;
    enum log2_bitreverse_chunk_size = 2;
    
    static vec scalar_to_vector(T a)
    {
        return a;
    }
        
    static void interleave(vec a0,  vec a1, ref vec r0, ref vec r1)
    {
        r0 = _mm_unpacklo_pd(a0, a1);
        r1 = _mm_unpackhi_pd(a0, a1);
    }
        
    static vec unaligned_load(T* p)
    {
        return _mm_loadu_pd(p);
    }

    static void unaligned_store(T* p, vec v)
    {
        _mm_storeu_pd(p, v);
    }

    static vec reverse(vec v)
    {
        return _mm_shuffle_pd!1(v, v);
    }

    private static vec * v(T * a)
    {
        return cast(vec*)a;
    }

    static void complex_array_to_real_imag_vec(int len)(
        T * arr, ref vec rr, ref vec ri)
    {
            interleave(v(arr)[0], v(arr)[1], rr, ri);
    }

    alias interleave deinterleave;

    static void  transpose(int elements_per_vector)(
            vec a0,  vec a1, ref vec r0, ref vec r1)
    {
        static if(elements_per_vector == 2)
            interleave(a0, a1, r0, r1);
        else
            static assert(0);
    }

    static void bit_reverse_swap(T * p0, T * p1, size_t m)
    {
        vec a0, a1, a2, a3, b0, b1, b2, b3;

        a0 = v(p0 + m * 0)[0];
        a1 = v(p0 + m * 2)[0];
        b0 = v(p1 + m * 0)[0];
        b1 = v(p1 + m * 2)[0];
        interleave(a0, a1, a0, a1);
        interleave(b0, b1, b0, b1);
        v(p1 + m * 0)[0] = a0;
        v(p1 + m * 2)[0] = a1;
        v(p0 + m * 0)[0] = b0;
        v(p0 + m * 2)[0] = b1;
        
        a2 = v(p0 + m * 1)[1];
        a3 = v(p0 + m * 3)[1];
        b2 = v(p1 + m * 1)[1];
        b3 = v(p1 + m * 3)[1];
        interleave(a2, a3, a2, a3);
        interleave(b2, b3, b2, b3);
        v(p1 + m * 1)[1] = a2;
        v(p1 + m * 3)[1] = a3;
        v(p0 + m * 1)[1] = b2;
        v(p0 + m * 3)[1] = b3;
        
        a0 = v(p0 + m * 0)[1];
        a1 = v(p0 + m * 2)[1];
        a2 = v(p0 + m * 1)[0];
        a3 = v(p0 + m * 3)[0];
        interleave(a0, a1, a0, a1);
        interleave(a2, a3, a2, a3);
        b0 = v(p1 + m * 0)[1];
        b1 = v(p1 + m * 2)[1];
        b2 = v(p1 + m * 1)[0];
        b3 = v(p1 + m * 3)[0];
        v(p1 + m * 0)[1] = a2;
        v(p1 + m * 2)[1] = a3;
        v(p1 + m * 1)[0] = a0;
        v(p1 + m * 3)[0] = a1;
        interleave(b0, b1, b0, b1);
        interleave(b2, b3, b2, b3);
        v(p0 + m * 0)[1] = b2;
        v(p0 + m * 2)[1] = b3;
        v(p0 + m * 1)[0] = b0;
        v(p0 + m * 3)[0] = b1;
    }

    static void bit_reverse(T * p, size_t m)
    {
        vec a0, a1, a2, a3;
        a0 = v(p + m * 0)[0];
        a1 = v(p + m * 2)[0];
        a2 = v(p + m * 1)[1];
        a3 = v(p + m * 3)[1];
        interleave(a0, a1, a0, a1);
        interleave(a2, a3, a2, a3);
        v(p + m * 0)[0] = a0;
        v(p + m * 2)[0] = a1;
        v(p + m * 1)[1] = a2;
        v(p + m * 3)[1] = a3;
        
        a0 = v(p + m * 0)[1];
        a1 = v(p + m * 2)[1];
        a2 = v(p + m * 1)[0];
        a3 = v(p + m * 3)[0];
        interleave(a0, a1, a0, a1);
        interleave(a2, a3, a2, a3);
        v(p + m * 0)[1] = a2;
        v(p + m * 2)[1] = a3;
        v(p + m * 1)[0] = a0;
        v(p + m * 3)[0] = a1;
    }
}

struct Options
{
    enum log2_bitreverse_large_chunk_size = 5;
    enum large_limit = 13;
    enum log2_optimal_n = 10;
    enum passes_per_recursive_call = 4;
    enum log2_recursive_passes_chunk_size = 5;
    enum prefered_alignment = 4 * (1 << 10);
    enum { fast_init };
}

