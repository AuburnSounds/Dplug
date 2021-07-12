//          Copyright Guillaume Piolat 2017
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dplug.fft.ldc_compat;

version(LDC)
{
    public import ldc.intrinsics;
    public import ldc.simd;
    public import ldc.attributes;
}
else
{
    /// Mock for ldc.attributes.target
    struct target
    {
        string specifier;
    }
}