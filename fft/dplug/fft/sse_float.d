//          Copyright Jernej Krempuš 2012
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dplug.fft.sse_float;

import inteli.emmintrin;
import dplug.fft.fft_impl;

struct Vector 
{
nothrow:
@nogc:
    alias float4 vec;
    alias float T;
    
    enum vec_size = 4;
    enum log2_bitreverse_chunk_size = 2;
    
    version(all)
    {
        static vec scalar_to_vector()(float a)
        {
            return a;
        }

        static auto shufps(int m0, int m1, int m2, int m3)(float4 a, float4 b)
        {
            enum shufmask = _MM_SHUFFLE(m0, m1, m2, m3);
            return _mm_shuffle_ps!shufmask(a, b);
        }
        
        static vec unpcklps(vec a, vec b)
        { 
            return _mm_unpacklo_ps(a, b);
        }
        
        static vec unpckhps(vec a, vec b)
        { 
            return _mm_unpackhi_ps(a, b);
        }

       static vec unaligned_load(T* p)
        {
            return _mm_loadu_ps(p);
        }

        static void unaligned_store(T* p, vec v)
        {
            _mm_storeu_ps(p, v);
        }
        
        static vec reverse(vec v)
        {
            return _mm_shuffle_ps!(_MM_SHUFFLE(0, 1, 2, 3))(v, v);
        }
    }
    
    static if(is(typeof(shufps)))
    {
        static void complex_array_to_real_imag_vec(int len)(
            float * arr, ref vec rr, ref vec ri)
        {
            static if(len==2)
            {
                rr = ri = (cast(vec*)arr)[0];
                rr = shufps!(2,2,0,0)(rr, rr);    // I could use __builtin_ia32_movsldup here but it doesn't seem to increase performance
                ri = shufps!(3,3,1,1)(ri, ri);
            }
            else static if(len==4)
            {
                vec tmp = (cast(vec*)arr)[0];
                ri = (cast(vec*)arr)[1];
                rr = shufps!(2,0,2,0)(tmp, ri);
                ri = shufps!(3,1,3,1)(tmp, ri);
            }
        }

        static void transpose(int elements_per_vector)(
            vec a0,  vec a1, ref vec r0, ref vec r1)
        {
            if(elements_per_vector==4)
            {
                r0 = shufps!(2,0,2,0)(a0,a1);
                r1 = shufps!(3,1,3,1)(a0,a1);
                r0 = shufps!(3,1,2,0)(r0,r0);
                r1 = shufps!(3,1,2,0)(r1,r1);
            }
            else if(elements_per_vector==2)
            {
                r0 = shufps!(1,0,1,0)(a0,a1);
                r1 = shufps!(3,2,3,2)(a0,a1);
            }
        }
        
        static void interleave( 
            vec a0,  vec a1, ref vec r0, ref vec r1)
        {
            r0 = unpcklps(a0,a1);
            r1 = unpckhps(a0,a1);
        }
        
        static void deinterleave(
            vec a0,  vec a1, ref vec r0, ref vec r1)
        {
            r0 = shufps!(2,0,2,0)(a0,a1);
            r1 = shufps!(3,1,3,1)(a0,a1);
        }
        
        private static float4 * v()(float * a)
        {
            return cast(float4*)a;
        }
        
        private static void br16()(
            float4 a0, float4 a1, float4 a2, float4 a3, 
            ref float4 r0, ref float4 r1, ref float4 r2, ref float4 r3)
        {
            float4 b0 = shufps!(1,0,1,0)(a0, a2);
            float4 b1 = shufps!(1,0,1,0)(a1, a3);
            float4 b2 = shufps!(3,2,3,2)(a0, a2);
            float4 b3 = shufps!(3,2,3,2)(a1, a3);
            r0 = shufps!(2,0,2,0)(b0, b1);
            r1 = shufps!(2,0,2,0)(b2, b3);
            r2 = shufps!(3,1,3,1)(b0, b1);
            r3 = shufps!(3,1,3,1)(b2, b3);
        }
        
        static void bit_reverse_swap()(float * p0, float * p1, size_t m)
        {
            float4 b0 = *v(p1 + 0 * m); 
            float4 b1 = *v(p1 + 1 * m); 
            float4 b2 = *v(p1 + 2 * m); 
            float4 b3 = *v(p1 + 3 * m);
            
            br16(*v(p0 + 0 * m), *v(p0 + 1 * m), *v(p0 + 2 * m), *v(p0 + 3 * m), 
                 *v(p1 + 0 * m), *v(p1 + 1 * m), *v(p1 + 2 * m), *v(p1 + 3 * m));
            
            br16(b0, b1, b2, b3, 
                 *v(p0 + 0 * m), *v(p0 + 1 * m), *v(p0 + 2 * m), *v(p0 + 3 * m));
        }

        static void bit_reverse()(float * p, size_t m)
        {
            br16(*v(p + 0 * m), *v(p + 1 * m), *v(p + 2 * m), *v(p + 3 * m), 
                 *v(p + 0 * m), *v(p + 1 * m), *v(p + 2 * m), *v(p + 3 * m));
        }
    }
    else
        static assert(false);
}

struct Options
{
    enum log2_bitreverse_large_chunk_size = 5;
    enum large_limit = 14;
    enum log2_optimal_n = 10;
    enum passes_per_recursive_call = 4;
    enum log2_recursive_passes_chunk_size = 5;
    enum prefered_alignment = 4 * (1 << 10);
    //enum { fast_init };
}

unittest
{
    alias V = Vector;
    float[4] m;
    float[4] correct = [4.0f, 4.0f, 4.0f, 4.0f];
    V.vec A = V.scalar_to_vector(4.0f);
    V.unaligned_store(m.ptr, A);
    assert(m == correct);
}

unittest
{
    alias V = Vector;
    float[4] m = [2.0f, 3.0f, 4.0f, 5.0f];
    float[4] r;
    V.vec A = V.unaligned_load(m.ptr);
    A = V.reverse(A);
    float[4] correct = [5.0f, 4.0f, 3.0f, 2.0f];
    V.unaligned_store(r.ptr, A);
    assert(r == correct);

    // unpcklps
    V.vec B = V.unpcklps(A, A);
    correct = [5.0f, 5.0f, 4.0f, 4.0f];
    V.unaligned_store(r.ptr, B);
    assert(r == correct);

     // unpckhps
    B = V.unpckhps(A, A);
    correct = [3.0f, 3.0f, 2.0f, 2.0f];
    V.unaligned_store(r.ptr, B);
    assert(r == correct);
}

unittest
{
    alias V = Vector;
    float[4] A = [-1.0f, 2.0f, 3.0f, 4.0f];
    V.vec B = V.unaligned_load(A.ptr);
    V.vec C = V.shufps!(3,1,2,1)(B, B);
    float[4] correct = [2.0f, 3.0f, 2.0f, 4.0f];
    float[4] r;
    V.unaligned_store(r.ptr, C);
    assert(r == correct);
}