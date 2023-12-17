//          Copyright Jernej Krempuš 2012
//          Copyright Guillaume Piolat 2016-2023
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dplug.fft.impl_double;
import dplug.fft.fft_impl;

import dplug.fft.sse_double;
alias FFT!(Vector,Options) F;
alias TypeTuple!F FFTs;
enum implementation = 0;

mixin Instantiate!();

