/**
 * Utilities for parsing and emitting binary data from input ranges, or to output ranges.
 *
 * Copyright: Copyright Auburn Sounds 2015-2016.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.client.binrange;

import std.range.primitives;

import dplug.core.nogc;
import dplug.core.traits;

// Note: the exceptions thrown here are allocated with mallocEmplace,
// and should be released with destroyFree.

public @nogc
{
    void skipBytes(R)(ref R input, int numBytes) if (isInputRange!R)
    {
        for (int i = 0; i < numBytes; ++i)
            popUbyte(input);
    }

    // Reads a big endian integer from input.
    T popBE(T, R)(ref R input) if (isInputRange!R)
    {
        return popFunction!(T, R, false)(input);
    }

    // Reads a little endian integer from input.
    T popLE(T, R)(ref R input) if (isInputRange!R)
    {
        return popFunction!(T, R, true)(input);
    }

    /// Writes a big endian integer/float to output.
    void writeBE(T, R)(ref R output, T n) if (isOutputRange!(R, ubyte))
    {
        writeFunction!(T, R, false)(output, n);
    }

    /// Writes a little endian integer/float to output.
    void writeLE(T, R)(ref R output, T n) if (isOutputRange!(R, ubyte))
    {
        writeFunction!(T, R, true)(output, n);
    }

    /// Returns: A RIFF chunk header parsed from an input range.
    void readRIFFChunkHeader(R)(ref R input, out uint chunkId, out uint chunkSize) if (isInputRange!R)
    {
        chunkId = popBE!uint(input);
        chunkSize = popLE!uint(input);
    }

    /// Writes a RIFF chunk header to an output range.
    void writeRIFFChunkHeader(R)(ref R output, uint chunkId, uint chunkSize) if (isOutputRange!(R, ubyte))
    {
        writeBE!uint(output, chunkId);
        writeLE!uint(output, chunkSize);
    }

    /// Returns: A RIFF chunk id.
    template RIFFChunkId(string id)
    {
        static assert(id.length == 4);
        uint RIFFChunkId = (cast(ubyte)(id[0]) << 24)
                         | (cast(ubyte)(id[1]) << 16)
                         | (cast(ubyte)(id[2]) << 8)
                         | (cast(ubyte)(id[3]));
    }

}

private
{
    // read/write 64-bits float
    union float_uint
    {
        float f;
        uint i;
    }

    // read/write 64-bits float
    union double_ulong
    {
        double f;
        ulong i;
    }

    uint float2uint(float x) pure nothrow @nogc
    {
        float_uint fi;
        fi.f = x;
        return fi.i;
    }

    float uint2float(int x) pure nothrow @nogc
    {
        float_uint fi;
        fi.i = x;
        return fi.f;
    }

    ulong double2ulong(double x) pure nothrow @nogc
    {
        double_ulong fi;
        fi.f = x;
        return fi.i;
    }

    double ulong2double(ulong x) pure nothrow @nogc
    {
        double_ulong fi;
        fi.i = x;
        return fi.f;
    }

    private template IntegerLargerThan(int numBytes) if (numBytes >= 1 && numBytes <= 8)
    {
        static if (numBytes == 1)
            alias IntegerLargerThan = ubyte;
        else static if (numBytes == 2)
            alias IntegerLargerThan = ushort;
        else static if (numBytes <= 4)
            alias IntegerLargerThan = uint;
        else
            alias IntegerLargerThan = ulong;
    }

    ubyte popUbyte(R)(ref R input) @nogc if (isInputRange!R)
    {
        if (input.empty)
            throw mallocNew!Exception("Expected a byte, but found end of input");

        ubyte b = input.front;
        input.popFront();
        return b;
    }

    // Generic integer parsing
    auto popInteger(R, int NumBytes, bool WantSigned, bool LittleEndian)(ref R input) @nogc if (isInputRange!R)
    {
        alias T = IntegerLargerThan!NumBytes;

        T result = 0;

        static if (LittleEndian)
        {
            for (int i = 0; i < NumBytes; ++i)
                result |= ( cast(T)(popUbyte(input)) << (8 * i) );
        }
        else
        {
            for (int i = 0; i < NumBytes; ++i)
                result = (result << 8) | popUbyte(input);
        }

        static if (WantSigned)
            return cast(UnsignedToSigned!T)result;
        else
            return result;
    }

    // Generic integer writing
    void writeInteger(R, int NumBytes, bool LittleEndian)(ref R output, IntegerLargerThan!NumBytes n) if (isOutputRange!(R, ubyte))
    {
        alias T = IntegerLargerThan!NumBytes;

        static assert(isUnsignedIntegral!T);
        auto u = cast(T)n;

        static if (LittleEndian)
        {
            for (int i = 0; i < NumBytes; ++i)
            {
                ubyte b = (u >> (i * 8)) & 255;
                output.put(b);
            }
        }
        else
        {
            for (int i = 0; i < NumBytes; ++i)
            {
                ubyte b = (u >> ( (NumBytes - 1 - i) * 8) ) & 255;
                output.put(b);
            }
        }
    }

    void writeFunction(T, R, bool endian)(ref R output, T n) @nogc if (isOutputRange!(R, ubyte))
    {
        static if (isBuiltinIntegral!T)
            writeInteger!(R, T.sizeof, endian)(output, n);
        else static if (is(T : float))
            writeInteger!(R, 4, endian)(output, float2uint(n));
        else static if (is(T : double))
            writeInteger!(R, 8, endian)(output, double2ulong(n));
        else
            static assert(false, "Unsupported type " ~ T.stringof);
    }

    T popFunction(T, R, bool endian)(ref R input) @nogc if (isInputRange!R)
    {
        static if(isBuiltinIntegral!T)
            return popInteger!(R, T.sizeof, isSignedIntegral!T, endian)(input);
        else static if (is(T == float))
            return uint2float(popInteger!(R, 4, false, endian)(input));
        else static if (is(T == double))
            return ulong2double(popInteger!(R, 8, false, endian)(input));
        else
            static assert(false, "Unsupported type " ~ T.stringof);
    }
}

unittest
{
    ubyte[] arr = [ 0x00, 0x01, 0x02, 0x03 ,
                    0x00, 0x01, 0x02, 0x03 ];

    assert(popLE!uint(arr) == 0x03020100);
    assert(popBE!int(arr) == 0x00010203);

    import dplug.core.vec;
    auto app = makeVec!ubyte();
    writeBE!float(app, 1.0f);
    writeLE!double(app, 2.0);
}


unittest
{
    ubyte[] arr = [0, 0, 0, 0, 0, 0, 0xe0, 0x3f];
    assert(popLE!double(arr) == 0.5);
    arr = [0, 0, 0, 0, 0, 0, 0xe0, 0xbf];
    assert(popLE!double(arr) == -0.5);
}
