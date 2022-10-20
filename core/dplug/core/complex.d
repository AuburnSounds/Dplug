/**
Dealing with complex numbers

Copyright: Copyright Guillaume Piolat 2015-2016
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.core.complex;

// Helpers to use builtin D language complex numbers vs library types.

import std.complex;

deprecated("Use Complex!T from std.complex instead") alias BuiltinComplex = Complex;


