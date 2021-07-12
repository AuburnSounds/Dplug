//          Copyright Jernej Krempuš 2012
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dplug.fft.impl_double;
import dplug.fft.fft_impl;

//version = SSE_AVX; // only backend supported in this fork

version(SSE_AVX)
{
    import sse = pfft.sse_double, avx = pfft.avx_double, pfft.detect_avx;  
    
    alias get implementation;
    alias TypeTuple!(FFT!(sse.Vector, sse.Options), avx) FFTs;
}
else
{
    version(Scalar)
    {
        import dplug.fft.scalar_double;
    }
    else version(Neon)
    {
        import dplug.fft.neon_double;
    }
    else version(StdSimd)
    {
        import dplug.fft.stdsimd;
    }
    else version(AVX)
    {
        import dplug.fft.avx_double;
    }
    else
    {
        import dplug.fft.sse_double;
    }
    
    alias FFT!(Vector,Options) F;
    alias TypeTuple!F FFTs;
    enum implementation = 0;
}

mixin Instantiate!();

