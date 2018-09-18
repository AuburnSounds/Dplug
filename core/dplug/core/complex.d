/**
Dealing with complex numbers

Copyright: Copyright Guillaume Piolat 2015-2016
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
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

@safe pure nothrow @nogc:

/// Returns: The argument (or phase) of `z`.
float arg(cfloat z)
{
    import std.math : atan2;
    return atan2(z.im, z.re);
}

/// Returns: The argument (or phase) of `z`.
double arg(cdouble z)
{
    import std.math : atan2;
    return atan2(z.im, z.re);
}

/// Returns: The squared modulus of `z`.
float sqAbs(cfloat z)
{
    return z.re*z.re + z.im*z.im;
}

/// Returns: The squared modulus of `z`.
float sqAbs(cdouble z)
{
    return z.re*z.re + z.im*z.im;
}

/// Returns: Complex number from polar coordinates.
cfloat fromPolar(float modulus, float argument)
{
    import std.math : sin, cos;
    return (modulus*cos(argument)) + 1i * (modulus*sin(argument));
}

/// Returns: Complex number from polar coordinates.
cdouble fromPolar(double modulus, double argument)
{
    import std.math : sin, cos;
    return (modulus*cos(argument)) + 1i * (modulus*sin(argument));
}