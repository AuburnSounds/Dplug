// See licenses/UNLICENSE.txt
module dplug.dsp.wav;

import std.range;

/// WAVEform audio file format (ie. WAV files)

double[][] decodeWAVE(R)(R input) if (isInputRange!R)
{
    uint chunkId, chunkSize;
    getChunkHeader(input, chunkId, chunkSize);
    if (chunkId != RIFFChunkId!"RIFF")
        throw new WAVException("Expected RIFF chunk.");

    return null;
}



final class WAVException : Exception
{
    this(string msg)
    {
        super(msg);
    }
}




private
{
    ubyte popByte(R)(ref R input) if (isInputRange!R)
    {
        ubyte b = input.front;
        input.popFront();
        return b;
    }

    uint popUintBE(R)(ref R input) if (isInputRange!R)
    {
        ubyte b0 = popByte(input);
        ubyte b1 = popByte(input);
        ubyte b2 = popByte(input);
        ubyte b3 = popByte(input);
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
    }

    uint popUintLE(R)(ref R input) if (isInputRange!R)
    {
        ubyte b0 = popByte(input);
        ubyte b1 = popByte(input);
        ubyte b2 = popByte(input);
        ubyte b3 = popByte(input);
        return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0;
    }

    // read RIFF chunk header
    void getChunkHeader(R)(ref R input, out uint chunkId, out uint chunkSize) if (isInputRange!R)
    {
        chunkId = popUintBE(input);
        chunkSize = popUintLE(input);
    }

    template RIFFChunkId(string id)
    {
        static assert(id.length == 4);
        uint RIFFChunkId = (cast(ubyte)(id[0]) << 24) 
            | (cast(ubyte)(id[1]) << 16)
            | (cast(ubyte)(id[2]) << 8)
            | (cast(ubyte)(id[3]));
    }
}

void test1()
{

    immutable ubyte[] testWAV = 
    [
        0x52, 0x49, 0x46, 0x46, 0x24, 0x08, 0x00, 0x00, 
        0x57, 0x41, 0x56, 0x45, 0x66, 0x6d, 0x74, 0x20, 
        0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00, 
        0x22, 0x56, 0x00, 0x00, 0x88, 0x58, 0x01, 0x00, 
        0x04, 0x00, 0x10, 0x00, 0x64, 0x61, 0x74, 0x61, 
        0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 
        0x24, 0x17, 0x1e, 0xf3, 0x3c, 0x13, 0x3c, 0x14, 
        0x16, 0xf9, 0x18, 0xf9, 0x34, 0xe7, 0x23, 0xa6, 
        0x3c, 0xf2, 0x24, 0xf2, 0x11, 0xce, 0x1a, 0x0d 
    ];

    decodeWAVE(testWAV[]);

}