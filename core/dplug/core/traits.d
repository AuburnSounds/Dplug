/**
 * Simple version of traits from std.traits, for the purpose of faster compile times.
 *
 * Copyright: Guillaume Piolat 2016.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 */
module dplug.core.traits;

// Like `Unqual` but does not remove "shared" or "inout"
template RemoveConst(T)
{    
    static if (is(T U == immutable U)) 
        alias Unqual = U;
    else static if (is(T U == const U)) 
        alias Unqual = U;
    else 
        alias Unqual = T;
}

// faster isIntegral, does not Unqual
template isBuiltinIntegral(T)
{
    static if (is(T == int) || is(T == uint) 
             ||is(T == byte) || is(T == ubyte)
             ||is(T == short) || is(T == ushort)
             ||is(T == long) || is(T == ulong))
        enum bool isBuiltinIntegral = true;
    else
        enum bool isBuiltinIntegral = false;
}

// faster isSigned, does not Unqual
template isSignedIntegral(T)
{
    enum isSignedIntegral = (is(T == int) || is(T == byte) || is(T == short) || is(T == long));
}

// faster isUnsigned, does not Unqual
template isUnsignedIntegral(T)
{
    enum isUnsignedIntegral = (is(T == uint) || is(T == ubyte) || is(T == ushort) || is(T == ulong));
}

template UnsignedToSigned(T)
{
    static if (is(T == uint))
        alias UnsignedToSigned = int;
    else static if (is(T == ushort))
        alias UnsignedToSigned = short;
    else static if (is(T == ubyte))
        alias UnsignedToSigned = byte;
    else static if (is(T == ulong))
        alias UnsignedToSigned = long;
    else
        static assert(false);
}