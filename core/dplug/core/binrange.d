/**
 * Utilities for parsing and emitting binary data from input ranges, or to output ranges.
 * It is unwise to depend on this outside of Dplug internals.
 *
 * Copyright: Copyright Auburn Sounds 2015-2023.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.core.binrange;

// FUTURE: Monomorphism. only allow reading from [] and writing on Vec!ubyte
import std.range.primitives;

import dplug.core.nogc;
import dplug.core.traits;

// Note: the exceptions thrown here are allocated with mallocEmplace,
// and should be released with destroyFree.

public @nogc
{
    /// Skip bytes in input range.
    /// Returns: On success, `*err` is set to `false` and return integer.
    ///          On failure, `*err` is set to `true` and return 0. The input range cannot be used anymore.
    void skipBytes(ref const(ubyte)[] input, int numBytes, bool* err) nothrow
    {
        for (int i = 0; i < numBytes; ++i)
        {
            popUbyte(input, err); 
            if (*err)
                return;
        }
        *err = false;
    }

    /// Reads a big endian integer from input.
    /// Returns: On success, `*err` is set to `false` and return integer.
    ///          On failure, `*err` is set to `true` and return 0. The input range cannot be used anymore.
    T popBE(T)(ref const(ubyte)[] input, bool* err) nothrow
    {
        return popFunction!(T, false)(input, err);
    }

    /// Reads a little endian integer from input.
    /// Returns: On success, `*err` is set to `false` and return integer.
    ///          On failure, `*err` is set to `true` and return 0. The input range cannot be used anymore.
    T popLE(T)(ref const(ubyte)[] input, bool* err) nothrow
    {
        return popFunction!(T, true)(input, err);
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
    /// Returns: On success, `*err` is set to `false` and return integer.
    ///          On failure, `*err` is set to `true` and undefined values for chunkId and chunkSize. The input range cannot be used anymore.
    void readRIFFChunkHeader(ref const(ubyte)[] input, out uint chunkId, out uint chunkSize, bool* err) nothrow
    {
        chunkId = popBE!uint(input, err);
        if (*err)
            return;
        chunkSize = popLE!uint(input, err);
        if (*err)
            return;
        *err = false;
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

    // Read one ubyte in stream.
    // On success, sets `*err` to `false` and return the byte value.
    // On error,   sets `err` to `true` and return 0.
    ubyte popUbyte(ref const(ubyte)[] input, bool* err) nothrow @nogc
    {
        if (input.length == 0)
        {
            *err = true;
            return 0;
        }
        ubyte b = input[0];
        input = input[1..$];
        return b;
    }

    // Generic integer parsing
    // On success, sets `*err` to `false` and return the byte value.
    // On error,   sets `err` to `true` and return 0.
    auto popInteger(int NumBytes, bool WantSigned, bool LittleEndian)(ref const(ubyte)[] input, bool* err) nothrow @nogc
    {
        alias T = IntegerLargerThan!NumBytes;

        T result = 0;

        static if (LittleEndian)
        {
            for (int i = 0; i < NumBytes; ++i)
            {
                ubyte b = popUbyte(input, err);
                if (*err)
                    return 0;
                result |= ( cast(T)(b) << (8 * i) );
            }
        }
        else
        {
            for (int i = 0; i < NumBytes; ++i)
            {
                ubyte b = popUbyte(input, err);
                if (*err)
                    return 0;
                result = cast(T)( (result << 8) | b );
            }
        }

        *err = false;

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

    void writeFunction(T, R, bool endian)(ref R output, T n) @nogc nothrow  if (isOutputRange!(R, ubyte))
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

    T popFunction(T, bool endian)(ref const(ubyte)[] input, bool* err) @nogc nothrow
    {
        static if(isBuiltinIntegral!T)
            return cast(T) popInteger!(T.sizeof, isSignedIntegral!T, endian)(input, err);
        else static if (is(T == float))
            return uint2float(popInteger!(4, false, endian)(input, err));
        else static if (is(T == double))
            return ulong2double(popInteger!(8, false, endian)(input, err));
        else
            static assert(false, "Unsupported type " ~ T.stringof);
    }
}

unittest
{
    // test 32-bit integer parsing
    {
        const(ubyte)[] arr = [ 0x00, 0x01, 0x02, 0x03 ,
                               0x00, 0x01, 0x02, 0x03 ];
        bool err;
        assert(popLE!uint(arr, &err) == 0x03020100);
        assert(!err);

        assert(popBE!int(arr, &err) == 0x00010203);
        assert(!err);
    }

    // test 64-bit integer parsing
    {
        bool err;
        const(ubyte)[] arr = [ 0x00, 0x01, 0x02, 0x03, 0x00, 0x01, 0x02, 0x03 ];
        assert(popLE!ulong(arr, &err) == 0x03020100_03020100);
        assert(!err);
    }
    {
        bool err;
        const(ubyte)[] arr = [ 0x00, 0x01, 0x02, 0x03, 0x00, 0x01, 0x02, 0x03 ];
        assert(popBE!long(arr, &err) == 0x00010203_00010203);
        assert(!err);
    }

    // read out of range
    //assert(popLE!uint(arr[1..$], &err) == 0);
   // assert(err);
    

    import dplug.core.vec;
    auto app = makeVec!ubyte();
    writeBE!float(app, 1.0f);
    writeLE!double(app, 2.0);
}


unittest
{
    bool err;
    const(ubyte)[] arr = [0, 0, 0, 0, 0, 0, 0xe0, 0x3f];
    double r = popLE!double(arr, &err);
    assert(!err);
    assert(r == 0.5);

    arr = [0, 0, 0, 0, 0, 0, 0xe0, 0xbf];
    r = popLE!double(arr, &err);
    assert(!err);
    assert(r == -0.5);
}
