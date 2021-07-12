//          Copyright Jernej Krempuš 2012
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dplug.fft.fft_impl;

import dplug.fft.shuffle;

nothrow:
@nogc:

struct Scalar(_T)
{
nothrow:
@nogc:
    alias _T vec;
    alias _T T;
    
    enum vec_size = 1;
    enum log2_bitreverse_chunk_size = 2;
    
    static vec scalar_to_vector(T a)
    {
        return a;
    }
   
    private static void load4br(T* p, size_t m, ref T a0, ref T a1, ref T a2, ref T a3)
    {
        a0 = p[0];
        a1 = p[m];
        a2 = p[1];
        a3 = p[m + 1];
    } 
 
    private static void store4(T* p, size_t m, T a0, T a1, T a2, T a3)
    {
        p[0] = a0;
        p[1] = a1;
        p[m] = a2;
        p[m + 1] = a3;
    }
 
    static void bit_reverse_swap(T * p0, T * p1, size_t m)
    {
        RepeatType!(T, 4) a, b;
       
        auto s = 2 * m;
        auto i0 = 0, i1 = 2, i2 = m, i3 = m + 2;
 
        load4br(p0, s, a); 
        load4br(p1, s, b); 
        store4(p1, s, a);     
        store4(p0, s, b);     
        
        load4br(p0 + i3, s, a); 
        load4br(p1 + i3, s, b); 
        store4(p1 + i3, s, a);     
        store4(p0 + i3, s, b);

        load4br(p0 + i1, s, a);
        load4br(p1 + i2, s, b);
        store4(p1 + i2, s, a);
        store4(p0 + i1, s, b);

        load4br(p1 + i1, s, a);
        load4br(p0 + i2, s, b);
        store4(p0 + i2, s, a);
        store4(p1 + i1, s, b);
    }

    static void bit_reverse(T * p,  size_t m)
    {
        //bit_reverse_static_size!4(p, m);
        T a0, a1, a2, b0, b1, b2;       

        a0 = p[1 + 0 * m];
        a1 = p[2 + 0 * m];
        a2 = p[3 + 0 * m];
        b0 = p[0 + 2 * m];
        b1 = p[0 + 1 * m];
        b2 = p[0 + 3 * m];

        p[0 + 2 * m] = a0;
        p[0 + 1 * m] = a1;
        p[0 + 3 * m] = a2;
        p[1 + 0 * m] = b0; 
        p[2 + 0 * m] = b1; 
        p[3 + 0 * m] = b2;

        a0 = p[1 + 1 * m];
        a1 = p[3 + 1 * m];
        a2 = p[3 + 2 * m];
        b0 = p[2 + 2 * m];
        b1 = p[2 + 3 * m];
        b2 = p[1 + 3 * m];

        p[2 + 2 * m] = a0;
        p[2 + 3 * m] = a1;
        p[1 + 3 * m] = a2;
        p[1 + 1 * m] = b0; 
        p[3 + 1 * m] = b1; 
        p[3 + 2 * m] = b2;
    }

    static T unaligned_load(T* p){ return *p; }
    static void unaligned_store(T* p, T a){ *p = a; }
    static T reverse(T a){ return a; }           
}

version(DisableLarge)
    enum disable_large = true;
else 
    enum disable_large = false;

// reinventing some Phobos stuff...

struct Tuple(A...)
{
    A a;
    alias a this;
}

template TypeTuple(A...)
{
    alias A TypeTuple;
}

template ParamTypeTuple(alias f)
{
    auto params_struct(Ret, Params...)(Ret function(Params) f) 
    {
        struct R
        {
            Params p;
        }
        return R.init;
    }

    static if(is(typeof(params_struct(&f))))
        alias f f_instance;
    else
        alias f!() f_instance;

    alias typeof(params_struct(&f_instance).tupleof) type;
}

void static_size_fft(int log2n, T)(T *pr, T *pi, T *table)
{ 
    enum n = 1 << log2n;
    RepeatType!(T, n) ar, ai;

    foreach(i; ints_up_to!n)
        ar[i] = pr[i];

    foreach(i; ints_up_to!n)
        ai[i] = pi[i];
    
    foreach(i; powers_up_to!n)
    {
        enum m = n / i;
        
        auto tp = table;
        foreach(j; ints_up_to!(n / m))
        {
            enum offset = m * j;
            
            T wr = tp[0];
            T wi = tp[1];
            tp += 2;
            foreach(k1; ints_up_to!(m / 2))
            {
                enum k2 = k1 + m / 2;
                static if(j == 0)
                {
                    T tr = ar[offset + k2], ti = ai[offset + k2];
                    T ur = ar[offset + k1], ui = ai[offset + k1];
                }
                else static if(j == 1)
                {
                    T tr = ai[offset + k2], ti = -ar[offset + k2];
                    T ur = ar[offset + k1], ui = ai[offset + k1];
                }
                else
                {
                    T tmpr = ar[offset + k2], ti = ai[offset + k2];
                    T ur = ar[offset + k1], ui = ai[offset + k1];
                    T tr = tmpr*wr - ti*wi;
                    ti = tmpr*wi + ti*wr;
                }
                ar[offset + k2] = ur - tr;
                ar[offset + k1] = ur + tr;                                                    
                ai[offset + k2] = ui - ti;                                                    
                ai[offset + k1] = ui + ti;
            }
        }
    }

    foreach(i; ints_up_to!n)
        pr[i] = ar[reverse_bits!(i, log2n)];

    foreach(i; ints_up_to!n)
        pi[i] = ai[reverse_bits!(i, log2n)];
}

struct FFT(V, Options)
{    
nothrow:
@nogc:
    import core.bitop, core.stdc.stdlib;
   
    alias BitReverse!(V, Options) BR;
    
    alias V.vec_size vec_size;
    alias V.T T;
    alias V.vec vec;
    alias FFT!(Scalar!T, Options) SFFT;
  
    import cmath = core.stdc.math;

    static if(is(T == float))
    {
        alias cmath.sinf _sin;
        alias cmath.cosf _cos;
        alias cmath.asinf _asin;
    }
    else static if(is(T == double))
    {
        alias cmath.sin _sin;
        alias cmath.cos _cos;
        alias cmath.asin _asin;
    }
    else static if(is(T == real))
    {
        alias cmath.sinl _sin;
        alias cmath.cosl _cos;
        alias cmath.asinl _asin;
    }
    else
        static assert(0);

    template st(alias a){ enum st = cast(size_t) a; }

    alias Tuple!(T,T) Pair;
    
    static void complex_array_to_vector()(Pair * pairs, size_t n)
    {
        for(size_t i=0; i<n; i += vec_size)
        {
          T[vec_size*2] buffer = void;
          for(size_t j = 0; j < vec_size; j++)
          {
            buffer[j] = pairs[i+j][0];
            buffer[j + vec_size] = pairs[i+j][1];
          }
          for(size_t j = 0; j < vec_size; j++)
          {
            pairs[i+j][0] = buffer[2*j];
            pairs[i+j][1] = buffer[2*j+1];
          }
        }
    }

    static int log2()(int a)
    {
        int r = 0;
        while(a)
        {
            a >>= 1;
            r++;
        }
        return r - 1;
    }

    static void sines_cosines_refine(bool computeEven)(
        Pair* src, Pair* dest, size_t n_from, T dphi)
    {
        T cdphi = _cos(dphi);
        T sdphi = _sin(dphi);
       
        enum compute = computeEven ? 0 : 1;
        enum copy = compute ^ 1;
 
        for(auto src_end = src + n_from; src < src_end; src++, dest += 2)
        {
            auto c = src[0][0];
            auto s = src[0][1];
            dest[copy][0] = c;
            dest[copy][1] = s;
            dest[compute][0] = c * cdphi - s * sdphi;   
            dest[compute][1] = c * sdphi + s * cdphi;
        }
    }

    static void sines_cosines(bool phi0_is_last)(
        Pair* r, size_t n, T phi0, T deltaphi, bool bit_reversed)
    {
        r[n - 1][0] = _cos(phi0);
        r[n - 1][1] = _sin(phi0);
        for(size_t len = 1; len < n; len *= 2)
        {
            auto denom = bit_reversed ? n / 2 / len : len;
            sines_cosines_refine!phi0_is_last(
                r + n - len, r + n - 2 * len, len, deltaphi / 2 / denom);
        }
    } 
    
    static void twiddle_table()(int log2n, Pair * r)
    {
        if(log2n >= Options.large_limit || log2n < 2 * log2(vec_size))
        {
            return sines_cosines!false(
                r, st!1 << (log2n - 1), 0.0, -2 * _asin(1), true);
        }

        r++;

        auto p = r;
        for (int s = 0; s < log2n; ++s)
        {
            size_t m2 = 1 << s;
            
            if(s < log2n - log2(vec_size))
                sines_cosines!false(p, m2, 0.0, -2 * _asin(1), true);
            else
            {
                sines_cosines!false(p, m2, 0.0, -2 * _asin(1), false);
                complex_array_to_vector(p, m2);
            }
            
            p += m2;
        }
       
        p = r;
        for (int s = 0; s + 1 < log2n - log2(vec_size);  s += 2)
        {
            size_t m2 = 1 << s;
            
            foreach(i; 0 .. m2)
                // p[i] is p[m2 + 2 * i] ^^ 2. We store it here so that we 
                // don't need to recompute it below, which improves precision 
                // slightly.
                p[m2 + 2 * i + 1] = p[i]; 

            foreach(i; 0 .. m2)
            {
                Pair a1 = p[m2 + 2 * i];
                Pair a2 = p[m2 + 2 * i + 1];
                Pair a3;
                
                a3[0] = a2[0] * a1[0] - a2[1] * a1[1];
                a3[1] = a2[0] * a1[1] + a2[1] * a1[0];
                
                p[3 * i] = a1;
                p[3 * i + 1] = a2;
                p[3 * i + 2] = a3;
            }
            
            p += 3 * m2;
        }
    }
    
    alias void* Table;
   
    static size_t twiddle_table_size_bytes(int log2n)
    {
        auto compact = log2n >= Options.large_limit || 
            log2n < 2 * log2(vec_size);

        return Pair.sizeof << (compact ? log2n - 1 : log2n); 
    }
 
    static T* twiddle_table_ptr(void* p, int log2n)
    { 
        return cast(T*)p;
    }
    
    static uint* br_table_ptr(void* p, int log2n)
    {
        return cast(uint*)(p + twiddle_table_size_bytes(log2n));
    }
    
    static size_t table_size_bytes()(uint log2n)
    {
        uint log2nbr = log2n < Options.large_limit ? 
            log2n : 2 * Options.log2_bitreverse_large_chunk_size;
        
        return 
            twiddle_table_size_bytes(log2n) + 
            BR.br_table_size(log2nbr) * uint.sizeof;
    }
    
    static Table fft_table()(int log2n, void * p)
    {   
        if(log2n == 0)
            return p;
        //else if(log2n <= log2(vec_size))
         //   return SFFT.fft_table(log2n, p);
        
        Table tables = p;
        
        twiddle_table(log2n, cast(Pair *)(twiddle_table_ptr(tables, log2n)));
        
        if(log2n < V.log2_bitreverse_chunk_size * 2)
        {
        }
        else if(log2n < Options.large_limit)
        {
            BR.init_br_table(br_table_ptr(tables, log2n), log2n);
        }
        else
        {
            enum log2size = 2*Options.log2_bitreverse_large_chunk_size;
            BR.init_br_table(br_table_ptr(tables, log2n), log2size);
        }
        return tables;
    }
    
    static void fft_passes_bit_reversed()(vec* re, vec* im, size_t N , 
        vec* table, size_t start_stride = 1)
    {
        table += start_stride + start_stride;
        vec* pend = re + N;
        for (size_t m2 = start_stride; m2 < N ; m2 <<= 1)
        {      
            size_t m = m2 + m2;
            for(
                vec* pr = re, pi = im; 
                pr < pend ;
                pr += m, pi += m)
            {
                for (size_t k1 = 0, k2 = m2; k1<m2; k1++, k2 ++) 
                {  
                    vec wr = table[2*k1], wi = table[2*k1+1];                       

                    vec tmpr = pr[k2], ti = pi[k2];
                    vec ur = pr[k1], ui = pi[k1];
                    vec tr = tmpr*wr - ti*wi;
                    ti = tmpr*wi + ti*wr;
                    pr[k2] = ur - tr;
                    pr[k1] = ur + tr;                                                    
                    pi[k2] = ui - ti;                                                    
                    pi[k1] = ui + ti;
                }
            }
            table += m;
        }
    }
    
    static void first_fft_passes()(vec* pr, vec* pi, size_t n)
    {
        size_t i0 = 0, i1 = i0 + n/4, i2 = i1 + n/4, i3 = i2 + n/4, iend = i1;

        for(; i0 < iend; i0++, i1++, i2++, i3++)
        {
            vec tr = pr[i2], ti = pi[i2];
            vec ur = pr[i0], ui = pi[i0];
            vec ar0 = ur + tr;
            vec ar2 = ur - tr;
            vec ai0 = ui + ti;
            vec ai2 = ui - ti;

            tr = pr[i3], ti = pi[i3];
            ur = pr[i1], ui = pi[i1];
            vec ar1 = ur + tr;
            vec ar3 = ur - tr;
            vec ai1 = ui + ti;
            vec ai3 = ui - ti;

            pr[i0] = ar0 + ar1;
            pr[i1] = ar0 - ar1;
            pi[i0] = ai0 + ai1;
            pi[i1] = ai0 - ai1;

            pr[i2] = ar2 + ai3;
            pr[i3] = ar2 - ai3;
            pi[i2] = ai2 - ar3;
            pi[i3] = ai2 + ar3;      
        }
    }
        
    static void fft_pass()(vec *pr, vec *pi, vec *pend, T *table, size_t m2)
    {
        size_t m = m2 + m2;
        for(; pr < pend ; pr += m, pi += m)
        {
            vec wr = V.scalar_to_vector(table[0]);
            vec wi = V.scalar_to_vector(table[1]);
            table += 2;
            for (size_t k1 = 0, k2 = m2; k1<m2; k1++, k2 ++) 
            { 
                vec tmpr = pr[k2], ti = pi[k2];
                vec ur = pr[k1], ui = pi[k1];
                vec tr = tmpr*wr - ti*wi;
                ti = tmpr*wi + ti*wr;
                pr[k2] = ur - tr;
                pr[k1] = ur + tr;                                                    
                pi[k2] = ui - ti;                                                    
                pi[k1] = ui + ti;
            }
        }
    }
    
    static void fft_two_passes(Tab...)(
        vec *pr, vec *pi, vec *pend, size_t m2, Tab tab)
    {
        // When this function is called with tab.length == 2 on DMD, it 
        // sometimes gives an incorrect result (for example when building with 
        // SSE on 64 bit Linux and runnitg test_float  pfft "14".), so lets's 
        // use fft_pass instead.
    
        // Disabled work-around

        version(DigitalMars)
        {
            static if (tab.length == 2)
                enum workaroundTabLength = true;
            else
                enum workaroundTabLength = false;
        }
        else
            enum workaroundTabLength = false;
        
        static if (workaroundTabLength)
        {
            fft_pass(pr, pi, pend, tab[0], m2);
            fft_pass(pr, pi, pend, tab[1], m2 / 2);
        }
        else
        {
            size_t m = m2 + m2;
            size_t m4 = m2 / 2;
            for(; pr < pend ; pr += m, pi += m)
            {
                static if(tab.length == 2)
                {
                    vec w1r = V.scalar_to_vector(tab[1][0]);
                    vec w1i = V.scalar_to_vector(tab[1][1]);

                    vec w2r = V.scalar_to_vector(tab[0][0]);
                    vec w2i = V.scalar_to_vector(tab[0][1]);

                    vec w3r = w1r * w2r - w1i * w2i;
                    vec w3i = w1r * w2i + w1i * w2r;

                    tab[0] += 2;
                    tab[1] += 4;
                }
                else
                {
                    vec w1r = V.scalar_to_vector(tab[0][0]);
                    vec w1i = V.scalar_to_vector(tab[0][1]);

                    vec w2r = V.scalar_to_vector(tab[0][2]);
                    vec w2i = V.scalar_to_vector(tab[0][3]);

                    vec w3r = V.scalar_to_vector(tab[0][4]);
                    vec w3i = V.scalar_to_vector(tab[0][5]);
            
                    tab[0] += 6;
                }
            
                for (
                    size_t k0 = 0, k1 = m4, k2 = m2, k3 = m2 + m4; 
                    k0<m4; k0++, 
                    k1++, k2++, k3++) 
                {                 
                    vec tr, ur, ti, ui;
                
                    vec r0 = pr[k0];
                    vec r1 = pr[k1];
                    vec r2 = pr[k2];
                    vec r3 = pr[k3];
                
                    vec i0 = pi[k0];
                    vec i1 = pi[k1];
                    vec i2 = pi[k2];
                    vec i3 = pi[k3];
                
                    tr = r2 * w2r - i2 * w2i;
                    ti = r2 * w2i + i2 * w2r;
                    r2 = r0 - tr;
                    i2 = i0 - ti;
                    r0 = r0 + tr;
                    i0 = i0 + ti;
                
                    tr = r3 * w3r - i3 * w3i;
                    ti = r3 * w3i + i3 * w3r;
                    ur = r1 * w1r - i1 * w1i;
                    ui = r1 * w1i + i1 * w1r;
                    r3 = ur - tr;
                    i3 = ui - ti;
                    r1 = ur + tr;
                    i1 = ui + ti;
                
                    tr = r1;
                    ti = i1;
                    r1 = r0 - tr;
                    i1 = i0 - ti;
                    r0 = r0 + tr;
                    i0 = i0 + ti;
                
                    tr = i3;
                    ti = r3;                // take minus into account later
                    r3 = r2 - tr;
                    i3 = i2 + ti;
                    r2 = r2 + tr;
                    i2 = i2 - ti;
                
                    pr[k0] = r0;
                    pr[k1] = r1;
                    pr[k2] = r2;
                    pr[k3] = r3;
                
                    pi[k0] = i0;
                    pi[k1] = i1;
                    pi[k2] = i2;
                    pi[k3] = i3;
                }
            }
        }
    }
    
    static void fft_passes(bool compact_table)(
        vec* re, vec* im, size_t N , T* table)
    {
        vec * pend = re + N;

        size_t tableRowLen = 2;
        size_t m2 = N/2;

        static nextRow(ref T* table, ref size_t len)
        {
            static if(!compact_table)
            {
                table += len;
                len += len;
            }
        }

        if(m2 > 1)
        {
            first_fft_passes(re, im, N);
            
            m2 >>= 2;

            nextRow(table, tableRowLen);
            nextRow(table, tableRowLen);
        }
       	
        for (; m2 > 1 ; m2 >>= 2)
        {
            static if(compact_table)
                fft_two_passes(re, im, pend, m2, table, table);
            else
                fft_two_passes(re, im, pend, m2, table);

            nextRow(table, tableRowLen);
            nextRow(table, tableRowLen);
        }
        
        if(m2 != 0)
            fft_pass(re, im, pend, table, m2);
    }
    
    static void fft_passes_fractional()(
        vec * pr, vec * pi, vec * pend, 
        T * table, size_t tableI)
    {
        static if(is(typeof(V.transpose!2)))
        {
            for(; pr < pend; pr += 2, pi += 2, tableI += 4)
            {
                auto ar = pr[0];
                auto ai = pi[0];
                auto br = pr[1];
                auto bi = pi[1];
                
                foreach(i; ints_up_to!(log2(vec_size)))
                {
                    vec wr, wi, ur, ui;

                    V.complex_array_to_real_imag_vec!(2 << i)(
                        table + (tableI << i), wr, wi);
                    
                    V.transpose!(2 << i)(ar, br, ur, br);
                    V.transpose!(2 << i)(ai, bi, ui, bi);

                    auto tr = br * wr - bi * wi;
                    auto ti = bi * wr + br * wi;

                    ar = ur + tr;
                    br = ur - tr;
                    ai = ui + ti;
                    bi = ui - ti;
                }  
                
                V.interleave(ar, br, pr[0], pr[1]); 
                V.interleave(ai, bi, pi[0], pi[1]); 
            }
        }
        else
            for (size_t m2 = vec_size >> 1; m2 > 0 ; m2 >>= 1)
            {
                SFFT.fft_pass(
                    cast(T*) pr, cast(T*) pi, cast(T*)pend, table + tableI, m2);
                
                tableI *= 2;
            }
    }
  
    // bug_killer below is a dummy parameter which apparently causes the DMD 
    // stack alignment bug to go away. 
    static void fft_passes_strided(int l, int chunk_size)(
        vec * pr, vec * pi, size_t N , 
        ref T * table, ref size_t tableI, void* bug_killer, 
        size_t stride, int nPasses)
    {
        ubyte[aligned_size!vec(l * chunk_size, 64)] rmem = void;
        ubyte[aligned_size!vec(l * chunk_size, 64)] imem = void;
        
        auto rbuf = aligned_ptr!vec(rmem.ptr, 64);
        auto ibuf = aligned_ptr!vec(imem.ptr, 64);
      
        BR.strided_copy!(chunk_size)(rbuf, pr, chunk_size, stride, l);
        BR.strided_copy!(chunk_size)(ibuf, pi, chunk_size, stride, l);
        
        size_t m2 = l*chunk_size/2;
        size_t m2_limit = m2>>nPasses;

        if(tableI  == 0 && nPasses >= 2)
        {
            first_fft_passes(rbuf, ibuf, l*chunk_size);
            m2 >>= 1;
            tableI *= 2;
            m2 >>= 1;
            tableI *= 2;
        }
       
        for(; m2 > 2 * m2_limit; m2 >>= 2)
        {
            fft_two_passes(rbuf, ibuf, rbuf + l*chunk_size, m2, 
                table + tableI, table + 2 * tableI);

            tableI *= 4;
        }
        
        if(m2 != m2_limit)
        {
            fft_pass(rbuf, ibuf, rbuf + l*chunk_size, table + tableI, m2);
            tableI *= 2;
        }
      
        BR.strided_copy!(chunk_size)(pr, rbuf, stride, chunk_size, l);
        BR.strided_copy!(chunk_size)(pi, ibuf, stride, chunk_size, l);
    }
    
    static void fft_passes_recursive()(
        vec * pr, vec *  pi, size_t N , 
        T * table, size_t tableI)
    {
        if(N <= (1<<Options.log2_optimal_n))
        {
            size_t m2 = N >> 1;
            
            for (; m2 > 1 ; m2 >>= 2)
            {
                fft_two_passes(pr, pi, pr + N, m2, table + tableI, 
                    table + 2 * tableI);
                
                tableI *= 4;
            }

            if(m2 != 0)
            {
                fft_pass(pr, pi, pr + N, table + tableI, m2);
                tableI *= 2;
            }
            
            fft_passes_fractional(pr, pi, pr + N, table, tableI);

            return;
        }
   
        enum log2l =  Options.passes_per_recursive_call, l = 1 << log2l;
        enum chunk_size = 1UL << Options.log2_recursive_passes_chunk_size;

        int log2n = bsf(N);

        int nPasses = log2n > log2l + Options.log2_optimal_n ?
            log2l : log2n - Options.log2_optimal_n;

        nPasses = (nPasses & 1) && !(log2l & 1)  ? nPasses + 1 : nPasses;

        int log2m = log2n - log2l;
        size_t m = st!1 << log2m;
        
        size_t tableIOld = tableI;

        for(size_t i=0; i < m; i += chunk_size)
        {
            tableI = tableIOld;

            fft_passes_strided!(l, chunk_size)(
                pr + i, pi + i, N, table, tableI, null, m, nPasses);
        }

        {
            size_t nextN = (N>>nPasses);

            for(int i = 0; i<(1<<nPasses); i++)
                fft_passes_recursive(
                    pr + nextN*i, pi  + nextN*i, nextN, 
                    table, tableI + 2*i);
        }
    }
   
    static void bit_reverse_small_two(int minLog2n)(
        T* re, T* im, int log2n, uint* brTable)
    {
        enum l = V.log2_bitreverse_chunk_size;
        
        static if(minLog2n < 2 * l)
        {
            if(log2n < 2 * l)
            {
                // only works for log2n < 2 * l
                bit_reverse_tiny!(2 * l)(re, log2n);
                bit_reverse_tiny!(2 * l)(im, log2n);
            }
            else
            {
                BR.bit_reverse_small(re, log2n, brTable); 
                BR.bit_reverse_small(im, log2n, brTable);
            }
        }
        else                                                            
        {
            //we already know that log2n >= 2 * l here.
            BR.bit_reverse_small(re, log2n, brTable); 
            BR.bit_reverse_small(im, log2n, brTable);
        }   
    }

    static auto v(T* p){ return cast(vec*) p; }

    static void fft_tiny()(T * re, T * im, int log2n, Table tables)
    {
        // assert(log2n > log2(vec_size));
        
        auto N = st!1 << log2n;
        fft_passes!(true)(v(re), v(im), N / vec_size, 
            twiddle_table_ptr(tables, log2n));
        
        fft_passes_fractional(
            v(re), v(im), v(re) + N / vec_size,
            twiddle_table_ptr(tables, log2n), 0);

        bit_reverse_small_two!(log2(vec_size) + 1)(
            re, im, log2n, br_table_ptr(tables, log2n));
    }

    static void fft_small()(T * re, T * im, int log2n, Table tables)
    {
        // assert(log2n >= 2*log2(vec_size));
        
        size_t N = (1<<log2n);
        
        fft_passes!false(
            v(re), v(im), N / vec_size, 
            twiddle_table_ptr(tables, log2n) + 2);
        
        bit_reverse_small_two!(2 * log2(vec_size))(
            re, im, log2n, br_table_ptr(tables, log2n));

        static if(vec_size > 1) 
            fft_passes_bit_reversed(
                v(re), v(im) , N / vec_size, 
                cast(vec*) twiddle_table_ptr(tables, log2n), 
                N / vec_size/vec_size);
    }
    
    static void fft_large()(T * re, T * im, int log2n, Table tables)
    {
        size_t N = (1<<log2n);
        
        fft_passes_recursive(
            v(re), v(im), N / vec_size, 
            twiddle_table_ptr(tables, log2n), 0);
        
        BR.bit_reverse_large(re, log2n, br_table_ptr(tables, log2n)); 
        BR.bit_reverse_large(im, log2n, br_table_ptr(tables, log2n));
    }
    
    static void fft()(T * re, T * im, int log2n, Table tables)
    {
        foreach(i; ints_up_to!(log2(vec_size) + 1))
            if(i == log2n)
                return static_size_fft!i(re, im, twiddle_table_ptr(tables, i));

        if(log2n < 2 * log2(vec_size))
            return fft_tiny(re, im, log2n, tables);
        else if( log2n < Options.large_limit || disable_large)
            return fft_small(re, im, log2n, tables);
        else 
            static if(!disable_large)
                fft_large(re, im, log2n, tables);
    }
  
    alias T* RTable;
 
    static auto rtable_size_bytes()(int log2n)
    {
        return T.sizeof << (log2n - 1);
    }

    enum supports_real = is(typeof(
    {
        T a;
        vec v = V.unaligned_load(&a);
        v = V.reverse(v);
        V.unaligned_store(&a, v);
    }));

    static RTable rfft_table()(int log2n, void *p) if(supports_real)
    {
        if(log2n < 2)
            return cast(RTable) p;
        else if(st!1 << log2n < 4 * vec_size)
            return SFFT.rfft_table(log2n, p);

        auto r = (cast(Pair*) p)[0 .. (st!1 << (log2n - 2))];

        auto phi = _asin(1);
        sines_cosines!true(r.ptr, r.length, -phi, phi, false);

        /*foreach(size_t i, ref e; r)
        {
            T phi = - (_asin(1.0) * (i + 1)) / r.length;
 
            e[0] = _cos(phi);
            e[1] = _sin(phi);
        }*/
        
        complex_array_to_vector(r.ptr, r.length);

        return cast(RTable) r.ptr;
    }

    static auto rfft_table()(int log2n, void *p) if(!supports_real)
    {
        return SFFT.rfft_table(log2n, p);
    }

    static void rfft()(
        T* rr, T* ri, int log2n, Table table, RTable rtable) 
    {
        if(log2n == 0)
            return;
        else if(log2n == 1)
        {
            auto rr0 = rr[0], ri0 = ri[0];
            rr[0] = rr0 + ri0;
            ri[0] = rr0 - ri0;
            return;
        }

        fft(rr, ri, log2n - 1, table);
        rfft_last_pass!false(rr, ri, log2n, rtable);
    }

    static void irfft()(
        T* rr, T* ri, int log2n, Table table, RTable rtable) 
    {
        if(log2n == 0)
            return;
        else if(log2n == 1)
        {
            // we don't multiply with 0.5 here because we want the inverse to
            // be scaled by 2.

            auto rr0 = rr[0], ri0 = ri[0];
            rr[0] = (rr0 + ri0);
            ri[0] = (rr0 - ri0);
            return;
        }

        rfft_last_pass!true(rr, ri, log2n, rtable);
        fft(ri, rr, log2n - 1, table);
    }

    static void rfft_last_pass(bool inverse)(T* rr, T* ri, int log2n, RTable rtable) 
    if(supports_real)
    {
        if(st!1 << log2n < 4 * vec_size)
            return SFFT.rfft_last_pass!inverse(rr, ri, log2n, rtable);       
 
        static vec* v(T* a){ return cast(vec*) a; }

        auto n = st!1 << log2n;

        vec half = V.scalar_to_vector(cast(T) 0.5);

        T middle_r = rr[n / 4];        
        T middle_i = ri[n / 4];        

        for(
            size_t i0 = 1, i1 = n / 2 - vec_size, iw = 0; 
            i0 <= i1; 
            i0 += vec_size, i1 -= vec_size, iw += 2*vec_size)
        {
            vec wr = *v(rtable + iw);
            vec wi = *v(rtable + iw + vec_size);

            vec r0r = V.unaligned_load(&rr[i0]);
            vec r0i = V.unaligned_load(&ri[i0]);
            vec r1r = V.reverse(*v(rr + i1));
            vec r1i = V.reverse(*v(ri + i1));

            vec ar = r0r + r1r;
            vec ai = r1i - r0i;
            vec br = r0r - r1r;
            vec bi = r0i + r1i;

            static if(inverse) 
            {
                // we use -w* instead of w in this case and we do not divide by 2.
                // The reason for that is that we want the inverse to be scaled
                // by n as it is in the complex case and not just by n / 2.

                vec tmp = br * wi - bi * wr;
                br = bi * wi + br * wr;
                bi = tmp;
            }
            else
            {
                ar *= half;
                ai *= half;
                br *= half;
                bi *= half;
                vec tmp = br * wi + bi * wr;
                br = bi * wi - br * wr;
                bi = tmp;
            }

            V.unaligned_store(rr + i0, ar + bi);
            V.unaligned_store(ri + i0, br - ai);

            *v(rr + i1) = V.reverse(ar - bi);
            *v(ri + i1) = V.reverse(ai + br);
        }
        
        // fixes the aliasing bug:
        rr[n / 4] = inverse ? middle_r + middle_r : middle_r; 
        ri[n / 4] = -(inverse ? middle_i + middle_i : middle_i);
        

        {
            // When calculating inverse we would need to multiply with 0.5 here 
            // to get an exact inverse. We don't do that because we actually
            // want the inverse to be scaled by 2.         
    
            auto r0r = rr[0];
            auto r0i = ri[0];
            
            rr[0] = r0r + r0i;
            ri[0] = r0r - r0i;
        }
    }
    
    static void rfft_last_pass(bool inverse)(T* rr, T* ri, int log2n, RTable rtable) 
    if(!supports_real)
    {
        SFFT.rfft_last_pass!inverse(rr, ri, log2n, rtable); 
    }

    static void interleave_array()(T* even, T* odd, T* interleaved, size_t n)
    {
        static if(is(typeof(V.interleave)))
        {
            if(n < vec_size)
                SFFT.interleave_array(even, odd, interleaved, n);
            else
                foreach(i; 0 .. n / vec_size)
                    V.interleave(
                        (cast(vec*)even)[i], 
                        (cast(vec*)odd)[i], 
                        (cast(vec*)interleaved)[i * 2], 
                        (cast(vec*)interleaved)[i * 2 + 1]);
        }
        else
            foreach(i; 0 .. n)
            {
                interleaved[i * 2] = even[i];
                interleaved[i * 2 + 1] = odd[i];
            }
    }
    
    static void deinterleave_array()(T* even, T* odd, T* interleaved, size_t n)
    {
        static if(is(typeof(V.deinterleave)))
        {
            if(n < vec_size)
                SFFT.deinterleave_array(even, odd, interleaved, n);
            else
                foreach(i; 0 .. n / vec_size)
                    V.deinterleave(
                        (cast(vec*)interleaved)[i * 2], 
                        (cast(vec*)interleaved)[i * 2 + 1], 
                        (cast(vec*)even)[i], 
                        (cast(vec*)odd)[i]);
        }
        else
            foreach(i; 0 .. n)
            {
                even[i] = interleaved[i * 2];
                odd[i] = interleaved[i * 2 + 1];
            }
    }

    alias bool* ITable;
    
    alias Interleave!(V, 8, false).itable_size_bytes itable_size_bytes;
    alias Interleave!(V, 8, false).interleave_table interleave_table;
    alias Interleave!(V, 8, false).interleave interleave;
    alias Interleave!(V, 8, true).interleave deinterleave;

    static void scale(T* data, size_t n, T factor)
    {
        auto k  = V.scalar_to_vector(factor);
        
        foreach(ref e; (cast(vec*) data)[0 .. n / vec_size])
            e = e * k;

        foreach(ref e;  data[ n & ~(vec_size - 1) .. n])
            e = e * factor;
    }

    static size_t alignment(size_t n)
    {
        static if(is(typeof(Options.prefered_alignment)) && 
            Options.prefered_alignment > vec.sizeof)
        {
            enum a = Options.prefered_alignment;
        } 
        else
            enum a = vec.sizeof; 
        
        auto bytes = T.sizeof << bsr(n);
        
        bytes = bytes < a ? bytes : a;
        return bytes > (void*).sizeof && (bytes & (bytes - 1)) == 0 ? 
            bytes : (void*).sizeof;
    }
}

mixin template Instantiate()
{
nothrow:
@nogc:
    struct TableValue{};
    alias TableValue* Table;

    struct RTableValue{};
    alias RTableValue* RTable;
    
    struct ITableValue{};
    alias ITableValue* ITable;

    template selected(string func_name, Ret...)
    {
        auto selected(A...)(A args)
        {
            auto impl = implementation;
            foreach(i, F; FFTs)
                if(i == impl)
                {
                    mixin("alias F." ~ func_name ~ " func;");

                    ParamTypeTuple!(func).type fargs;

                    foreach(j, _; fargs)
                        fargs[j] = cast(typeof(fargs[j])) args[j];

                    static if(Ret.length == 0)
                        return func(fargs);
                    else
                        return cast(Ret[0]) func(fargs);
                }
          
            assert(false);
        }
    }

    alias FFTs[0] FFT0;
    alias FFT0.T T;

    void fft(T* re, T* im, uint log2n, Table t)
    {
        selected!"fft"(re, im, log2n, cast(FFT0.Table) t);
    }

    Table fft_table(uint log2n, void* p = null)
    {
        return selected!("fft_table", Table)(log2n, p);
    }

    size_t table_size_bytes(uint log2n)
    {
        return selected!"table_size_bytes"(log2n);
    }

    void scale(T* data, size_t n, T factor)
    {
        selected!"scale"(data, n, factor); 
    }

    size_t alignment(size_t n)
    {
        return selected!"alignment"(n);
    }

    void rfft(T* re, T* im, uint log2n, Table t, RTable rt)
    {
        selected!"rfft"(re, im, log2n, cast(FFT0.Table) t, cast(FFT0.RTable) rt);
    }

    void irfft(T* re, T* im, uint log2n, Table t, RTable rt)
    {
        selected!"irfft"(re, im, log2n, cast(FFT0.Table) t, cast(FFT0.RTable) rt);
    }

    RTable rfft_table(uint log2n, void* p = null)
    {
        return selected!("rfft_table", RTable)(log2n, p);
    }

    size_t rtable_size_bytes(int log2n)
    {
        return selected!"rtable_size_bytes"(log2n);
    }

    void deinterleave_array(T* even, T* odd, T* interleaved, size_t n)
    {
        selected!"deinterleave_array"(even, odd, interleaved, n);
    }

    void interleave_array(T* even, T* odd, T* interleaved, size_t n)
    {
        selected!"interleave_array"(even, odd, interleaved, n);
    }

    size_t itable_size_bytes(uint log2n)
    {
        return selected!"itable_size_bytes"(log2n);
    }

    ITable interleave_table(uint log2n, void* p)
    {
        return selected!("interleave_table", ITable)(log2n, p);
    }

    void interleave(T* p, uint log2n, ITable table)
    {
        selected!"interleave"(p, log2n, cast(FFT0.ITable) table);  
    }

    void deinterleave(T* p, uint log2n, ITable table)
    {
        selected!"deinterleave"(p, log2n, cast(FFT0.ITable) table);  
    }
}    
