//          Copyright Jernej Krempuš 2012
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dplug.fft.sse_float;

import core.simd;

import dplug.fft.fft_impl;

template shuf_mask(int a3, int a2, int a1, int a0)
{ 
    enum shuf_mask = a0 | (a1<<2) | (a2<<4) | (a3<<6); 
}

version(X86_64)
    version(linux)
        version = linux_x86_64;


import dplug.fft.ldc_compat;
import dplug.fft.dmd32_compat;
        
struct Vector 
{
nothrow:
@nogc:
    alias float4 vec;
    alias float T;
    
    enum vec_size = 4;
    enum log2_bitreverse_chunk_size = 2;
    
    version(GNU)
    {
        import gcc.builtins;
                
        static vec scalar_to_vector()(T a)
        {
            return a;
        }  

        private static shufps(int m0, int m1, int m2, int m3)(float4 a, float4 b)
        {
            return __builtin_ia32_shufps(a, b, shuf_mask!(m0, m1, m2, m3));
        }

        alias __builtin_ia32_unpcklps unpcklps;
        alias __builtin_ia32_unpckhps unpckhps;
              
        static vec unaligned_load(T* p)
        {
            return __builtin_ia32_loadups(p);
        }

        static void unaligned_store(T* p, vec v)
        {
            return __builtin_ia32_storeups(p, v);
        }

        static vec reverse(vec v)
        {
            return shufps!(0, 1, 2, 3)(v, v);
        }
    }
    
    version(DigitalMars)
    {
        static vec scalar_to_vector()(float a)
        {
            version(linux_x86_64)
                asm nothrow @nogc
                {
                    naked;
                    shufps XMM0, XMM0, 0;
                    ret;
                }
            else
            {
                static struct quad
                {
                    align(16) float a;
                    float b;
                    float c;
                    float d;
                }
                auto q = quad(a,a,a,a);
                return *cast(vec*)& q;
            }
        }
    }
    
    version(LDC)
    {    
        static vec scalar_to_vector()(float a)
        {
            return a;
        }

        static auto shufps(int m0, int m1, int m2, int m3)(float4 a, float4 b)
        {
            return shufflevector!(float4, m3, m2, m1+4, m0+4)(a, b);
        }
        
        static vec unpcklps(vec a, vec b)
        { 
            return shufflevector!(float4, 0, 4, 1, 5)(a, b);
        }
        
        static vec unpckhps(vec a, vec b)
        { 
            return shufflevector!(float4, 2, 6, 3, 7)(a, b);
        }

       static vec unaligned_load(T* p)
        {
            return loadUnaligned!vec(cast(float*)p);
        }

        static void unaligned_store(T* p, vec v)
        {
            storeUnaligned!vec(v, cast(float*)p);
        }
        
        static vec reverse(vec v)
        {
            return shufflevector!(float4, 3, 2, 1, 0)(v, v);
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
    {        
        static void bit_reverse()(T * p0, size_t m)
        {
            version(linux_x86_64)
                asm nothrow @nogc
                {
                    naked;
                    lea     RAX,[RDI+RDI*1];
                    lea     RCX,[RSI+RDI*4];
                    lea     RDI,[RDI+RDI*2];
                    movaps  XMM1,[RSI];
                    lea     RDX,[RSI+RAX*4];
                    lea     R8,[RSI+RDI*4];
                    movaps  XMM0,[RCX];
                    movaps  XMM3,XMM1;
                    movaps  XMM5,[RDX];
                    movaps  XMM2,XMM0;
                    movaps  XMM4,[R8];
                    shufps  XMM1,XMM5,0xEE;
                    movlhps XMM3,XMM5;
                    shufps  XMM0,XMM4,0xEE;
                    movlhps XMM2,XMM4;
                    movaps  XMM6,XMM3;
                    movaps  XMM7,XMM1;
                    shufps  XMM3,XMM2,0xDD;
                    shufps  XMM6,XMM2,0x88;
                    shufps  XMM7,XMM0,0x88;
                    shufps  XMM1,XMM0,0xDD;
                    movaps  [RSI],XMM6;
                    movaps  [RCX],XMM7;
                    movaps  [RDX],XMM3;
                    movaps  [R8],XMM1;
                    ret;
                }
            else
                Scalar!T.bit_reverse(p0, m);
        }

        static void bit_reverse_swap()(T * p0, T * p1, size_t m)
        {
            version(linux_x86_64)
                asm nothrow @nogc
                {
                    naked;
                    lea     RAX,[RDI+RDI*1];
                    lea     RCX,[RDI*4+0x0];
                    lea     RDI,[RDI+RDI*2];
                    movaps  XMM1,[RSI];
                    shl     RAX,0x2;
                    lea     R10,[RSI+RCX*1];
                    shl     RDI,0x2;
                    lea     R9,[RSI+RAX*1];
                    movaps  XMM3,[RDX];
                    add     RAX,RDX;
                    lea     R8,[RSI+RDI*1];
                    add     RCX,RDX;
                    movaps  XMM5,[R9];
                    add     RDI,RDX;
                    movaps  XMM7,XMM3;
                    movaps  XMM9,[RAX];
                    movaps  XMM12,XMM1;
                    shufps  XMM1,XMM5,0xEE;
                    movaps  XMM0,[R10];
                    shufps  XMM3,XMM9,0xEE;
                    movlhps XMM7,XMM9;
                    movaps  XMM2,[RCX];
                    movlhps XMM12,XMM5;
                    movaps  XMM13,XMM0;
                    movaps  XMM4,[R8];
                    movaps  XMM6,XMM2;
                    movaps  XMM10,XMM7;
                    movaps  XMM8,[RDI];
                    shufps  XMM0,XMM4,0xEE;
                    movaps  XMM11,XMM3;
                    shufps  XMM2,XMM8,0xEE;
                    movlhps XMM6,XMM8;
                    movlhps XMM13,XMM4;
                    movaps  XMM14,XMM12;
                    movaps  XMM15,XMM1;
                    shufps  XMM10,XMM6,0x88;
                    shufps  XMM11,XMM2,0x88;
                    shufps  XMM7,XMM6,0xDD;
                    shufps  XMM3,XMM2,0xDD;
                    shufps  XMM14,XMM13,0x88;
                    shufps  XMM15,XMM0,0x88;
                    shufps  XMM12,XMM13,0xDD;
                    shufps  XMM1,XMM0,0xDD;
                    movaps  [RSI],XMM10;
                    movaps  [R10],XMM11;
                    movaps  [R9],XMM7;
                    movaps  [R8],XMM3;
                    movaps  [RDX],XMM14;
                    movaps  [RCX],XMM15;
                    movaps  [RAX],XMM12;
                    movaps  [RDI],XMM1;
                    ret;
                }
            else
                Scalar!T.bit_reverse_swap(p0, p1, m);
        }                         
    }
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

