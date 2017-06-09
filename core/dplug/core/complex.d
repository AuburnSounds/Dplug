/**
* Copyright: Copyright Auburn Sounds 2015-2016
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.core.complex;

// Helpers to use builtin D language complex numbers.


template BuiltinComplex(T)
{
    static if (is(T == float))
        alias BuiltinComplex = cfloat;
    else static if (is(T == double))
        alias BuiltinComplex = cdouble;
    else static if (is(T == real))
        alias BuiltinComplex = creal;
    else
        static assert("This type doesn't match any builtin complex type");
}

template BuiltinImaginary(T)
{
    static if (is(T == float))
        alias BuiltinComplex = ifloat;
    else static if (is(T == double))
        alias BuiltinComplex = idouble;
    else static if (is(T == real))
        alias BuiltinComplex = ireal;
    else
        static assert("This type doesn't match any builtin imaginary complex type");
}


/// Returns: The argument (or phase) of `z`.
T arg(T)(BuiltinComplex!T z) @safe pure nothrow @nogc
{
    import std.math : atan2;
    return atan2(z.im, z.re);
}


BuiltinComplex!T makeComplex(T)(T re, T im)
{
    return re + im * 1i;
}