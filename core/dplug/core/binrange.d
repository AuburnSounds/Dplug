/**

    Binary parsing and emitting from input ranges, or to
    output ranges.

    Copyright: Guillaume Piolat 2015-2024.
    License:   http://www.boost.org/LICENSE_1_0.txt

    It is used internally by Dplug, and also by the user for
    emitting and parsing plugin state chunks.

    See_also: `futureBinState`.

 */
module dplug.core.binrange;

// FUTURE: Monomorphism. only allow reading from [] and
// writing on Vec!ubyte
import std.range.primitives;

import dplug.core.nogc;
import dplug.core.traits;

@nogc nothrow:

public:

/* Public API in this file here:

  - popLE      Read  a little-endian integer (or FP number)
  - popBE      Read  a    big-endian integer (or FP number)
  - writeLE    Write a little-endian integer (or FP number)
  - writeBE    Write a    big-endian integer (or FP number)
  - skipBytes  Skip a number of bytes in input stream.
  - readRIFFChunkHeader
  - writeRIFFChunkHeader
  - RIFFChunkId FourCC constant helper.

  Those functions operate on slices of `ubyte` for input,
  and output ranges of `ubyte` for output only.

*/

/**
    Skip bytes while parsing an input slice.

    Params:
       input    = `ubyte` input range.
       numBytes = Number of bytes to skip.
       err      = `true` if read error.

    Returns: On success, `*err` is set to `false`.
             On failure, `*err` is set to `true`, and the
             input range cannot be used anymore.
*/
void skipBytes(ref const(ubyte)[] input,
               int numBytes,
               bool* err)
{
    for (int i = 0; i < numBytes; ++i)
    {
        popUbyte(input, err);
        if (*err)
            return;
    }
    *err = false;
}

/**
    Reads a base type from input slice.
    `popLE` parses bytes in little-endian order.
    `popBE` parses bytes in big-endian order.

    Params:
       input    = `ubyte` input range.
       err      = `true` if read error.

    Supported types:
        `byte`, `ubyte`, `short`, `ushort`,
         `int`,  `uint`,  `long`,  `ulong`,
         `float`, `double`

    Returns: On failure, `*err` is set to `true`, return 0.
          The input range cannot be used anymore.
*/
T popBE(T)(ref const(ubyte)[] input, bool* err)
{
    return popFunction!(T, false)(input, err);
}
///ditto
T popLE(T)(ref const(ubyte)[] input, bool* err)
{
    return popFunction!(T, true)(input, err);
}

/**
    Writes a big-endian/little-endian base type to output
    range.

    Params:
       output   = `ubyte` output range.
       n        = A base type to write.

    Supported types:
        `byte`, `ubyte`, `short`, `ushort`,
         `int`,  `uint`,  `long`,  `ulong`,
         `float`, `double`

    Warning: Doesn't report write errors.
*/
void writeBE(T, R)(ref R output, T n)
    if (isOutputRange!(R, ubyte))
{
    writeFunction!(T, R, false)(output, n);
}
///ditto
void writeLE(T, R)(ref R output, T n)
    if (isOutputRange!(R, ubyte))
{
    writeFunction!(T, R, true)(output, n);
}

/**
    Reads a [RIFF] chunk header from an input range.

    Params:
       input     = `ubyte` input range.
       chunkId   = RIFF chunk id.
       chunkSize = Chunk size.
       err       = `true` if input error.

    On failure, `*err` is set to `true`
    and `chunkId` and `chunkSize` are undefined.
    The input range cannot be used anymore.
    [RIFF]: http://www.daubnet.com/en/file-format-riff
*/
void readRIFFChunkHeader(ref const(ubyte)[] input,
                         out uint chunkId,
                         out uint chunkSize,
                         bool* err)
{
    chunkId = popBE!uint(input, err);
    if (*err)
        return;
    chunkSize = popLE!uint(input, err);
    if (*err)
        return;
    *err = false;
}

/**
    Reads a [RIFF] chunk header to an output range.

    Params:
       output    = `ubyte` output range.
       chunkId   = RIFF chunk id.
       chunkSize = Chunk size.    

    [RIFF]: http://www.daubnet.com/en/file-format-riff
*/
void writeRIFFChunkHeader(R)(ref R output,
                             uint chunkId,
                             uint chunkSize)
    if (isOutputRange!(R, ubyte))
{
    writeBE!uint(output, chunkId);
    writeLE!uint(output, chunkSize);
}

/**
    A RIFF chunk id. Also called "FourCC".

    [RIFF]: http://www.daubnet.com/en/file-format-riff
*/
template RIFFChunkId(string id)
{
    static assert(id.length == 4);
    enum uint RIFFChunkId = (cast(ubyte)(id[0]) << 24)
                          | (cast(ubyte)(id[1]) << 16)
                          | (cast(ubyte)(id[2]) <<  8)
                          | (cast(ubyte)(id[3])      );
}

private:

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

uint float2uint(float x) pure
{
    float_uint fi;
    fi.f = x;
    return fi.i;
}

float uint2float(int x) pure
{
    float_uint fi;
    fi.i = x;
    return fi.f;
}

ulong double2ulong(double x) pure
{
    double_ulong fi;
    fi.f = x;
    return fi.i;
}

double ulong2double(ulong x) pure
{
    double_ulong fi;
    fi.i = x;
    return fi.f;
}

private template IntegerLargerThan(int numBytes)
    if (numBytes >= 1 && numBytes <= 8)
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

ubyte popUbyte(ref const(ubyte)[] input, bool* err)
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

auto popInteger(int NumBytes,
                bool WantSigned,
                bool LittleEndian)
               (ref const(ubyte)[] input, bool* err)
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

void writeInteger(R, int NumBytes, bool LittleEndian)
     (ref R output, IntegerLargerThan!NumBytes n)
     if (isOutputRange!(R, ubyte))
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
            ubyte b = (u >> ((NumBytes-1-i)*8)) & 255;
            output.put(b);
        }
    }
}

void writeFunction(T, R, bool endian)(ref R o, T n)
    if (isOutputRange!(R, ubyte))
{
    static if (isBuiltinIntegral!T)
        writeInteger!(R, T.sizeof, endian)(o, n);
    else static if (is(T : float))
        writeInteger!(R, 4, endian)(o, float2uint(n));
    else static if (is(T : double))
        writeInteger!(R, 8, endian)(o, double2ulong(n));
    else
        static assert(false);
}

T popFunction(T, bool endian)
    (ref const(ubyte)[] i, bool* err)
{
    static if(isBuiltinIntegral!T)
    {
        enum Signed = isSignedIntegral!T;
        alias F = popInteger!(T.sizeof, Signed, endian);
        return cast(T) F(i, err);
    }
    else static if (is(T == float))
    {
        alias F = popInteger!(float.sizeof, false, endian);
        return uint2float(F(i, err));
    }
    else static if (is(T == double))
    {
        alias F = popInteger!(double.sizeof, false, endian);
        return ulong2double(F(i, err));
    }
    else
        static assert(false);
}

unittest
{
    static immutable ubyte[8] ARR =
            [ 0x00, 0x01, 0x02, 0x03 ,
              0x00, 0x01, 0x02, 0x03 ];

    // test 32-bit integer parsing
    {
        const(ubyte)[] arr = ARR[];
        bool err;
        assert(popLE!uint(arr, &err) == 0x03020100);
        assert(!err);

        assert(popBE!int(arr, &err) == 0x00010203);
        assert(!err);
    }

    // test 64-bit integer parsing
    {
        bool err;
        const(ubyte)[] arr = ARR[];
        assert(popLE!ulong(arr, &err)==0x03020100_03020100);
        assert(!err);
    }
    {
        bool err;
        const(ubyte)[] arr = ARR[];
        assert(popBE!long(arr, &err)==0x00010203_00010203);
        assert(!err);
    }

    import dplug.core.vec;
    auto app = makeVec!ubyte();
    writeBE!float(app, 1.0f);
    writeLE!double(app, 2.0);
}


unittest
{
    static immutable ubyte[8] ARR1 =
            [ 0, 0, 0, 0, 0, 0, 0xe0, 0x3f ];

    static immutable ubyte[8] ARR2 =
            [ 0, 0, 0, 0, 0, 0, 0xe0, 0xbf ];

    bool err;
    const(ubyte)[] arr = ARR1[];
    double r = popLE!double(arr, &err);
    assert(!err);
    assert(r == 0.5);

    arr = ARR2[];
    r = popLE!double(arr, &err);
    assert(!err);
    assert(r == -0.5);
}
