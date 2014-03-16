// See licenses/UNLICENSE.txt
module dplug.dsp.wav;

import std.range,
       std.array,
       std.string;

/// Supports Microsoft WAV audio file format.


struct SoundFile
{
    int sampleRate;
    int numChannels;
    double[] data; // data layout: machine endianness, interleaved channels
}

SoundFile decodeWAVE(R)(R input) if (isInputRange!R)
{
    // check RIFF header
    {
        uint chunkId, chunkSize;
        getChunkHeader(input, chunkId, chunkSize);
        if (chunkId != RIFFChunkId!"RIFF")
            throw new WAVException("Expected RIFF chunk.");

        if (chunkSize < 4)
            throw new WAVException("RIFF chunk is too small to contains a format.");

        if (popUintBE(input) !=  RIFFChunkId!"WAVE")
            throw new WAVException("Expected WAVE format.");
    }    

    immutable int LinearPCM = 0x0001;
    immutable int FloatingPointIEEE = 0x0003;
    immutable int WAVE_FORMAT_EXTENSIBLE = 0xFFFE;

    bool foundFmt = false;
    bool foundData = false;

    
    int audioFormat;
    int numChannels;
    int sampleRate;
    int byteRate;
    int blockAlign;
    int bitsPerSample;

    SoundFile result;

    // while chunk is not
    while (!input.empty)
    {
        uint chunkId, chunkSize;
        getChunkHeader(input, chunkId, chunkSize); 
        if (chunkId == RIFFChunkId!"fmt ")
        {
            if (foundFmt)
                throw new WAVException("Found several 'fmt ' chunks in RIFF file.");

            foundFmt = true;

            if (chunkSize < 16)
                throw new WAVException("Expected at least 16 bytes in 'fmt ' chunk."); // found in real-world for the moment: 16 or 40 bytes

            audioFormat = popUshortLE(input);            
            if (audioFormat == WAVE_FORMAT_EXTENSIBLE)
                throw new WAVException("No support for format WAVE_FORMAT_EXTENSIBLE yet."); // Reference: http://msdn.microsoft.com/en-us/windows/hardware/gg463006.aspx
            
            if (audioFormat != LinearPCM && audioFormat != FloatingPointIEEE)
                throw new WAVException(format("Unsupported audio format %s, only PCM and IEEE float are supported.", audioFormat));

            numChannels = popUshortLE(input);

            sampleRate = popUintLE(input);
            if (sampleRate <= 0)
                throw new WAVException(format("Unsupported sample-rate %s.", cast(uint)sampleRate)); // we do not support sample-rate higher than 2^31hz

            uint bytesPerSec = popUintLE(input);
            int bytesPerFrame = popUshortLE(input);
            bitsPerSample = popUshortLE(input);

            if (bitsPerSample != 8 && bitsPerSample != 16 && bitsPerSample != 24 && bitsPerSample != 32) 
                throw new WAVException(format("Unsupported bitdepth %s.", cast(uint)bitsPerSample));

            if (bytesPerFrame != (bitsPerSample / 8) * numChannels)
                throw new WAVException("Invalid bytes-per-second, data might be corrupted.");

            skipBytes(input, chunkSize - 16);
        }
        else if (chunkId == RIFFChunkId!"data")
        {
            if (foundData)
                throw new WAVException("Found several 'data' chunks in RIFF file.");

            if (!foundFmt)
                throw new WAVException("'fmt ' chunk expected before the 'data' chunk.");

            int bytePerSample = bitsPerSample / 8;
            uint frameSize = numChannels * bytePerSample;
            if (chunkSize % frameSize != 0)
                throw new WAVException("Remaining bytes in 'data' chunk, inconsistent with audio data type.");

            uint numFrames = chunkSize / frameSize;
            uint numSamples = numFrames * numChannels;

            result.data.length = numSamples;

            if (audioFormat == FloatingPointIEEE)
            {
                if (bytePerSample == 4)
                {
                    for (uint i = 0; i < numSamples; ++i)
                        result.data[i] = popFloatLE(input);                  
                }
                else if (bytePerSample == 4)
                {
                    for (uint i = 0; i < numSamples; ++i)
                        result.data[i] = popDoubleLE(input);
                }
                else
                    throw new WAVException("Unsupported bit-depth for floating point data, should be 32 or 64.");
            }
            else if (audioFormat == LinearPCM)
            {
                if (bytePerSample == 1)
                {
                    for (uint i = 0; i < numSamples; ++i)
                    {
                        ubyte b = popByte(input);
                        result.data[i] = (b - 128) / 127.0;
                    }
                }
                else if (bytePerSample == 2)
                {
                    for (uint i = 0; i < numSamples; ++i)
                    {
                        int s = popShortLE(input);
                        result.data[i] = s / 32767.0;
                    }
                }
                else if (bytePerSample == 3)
                {
                    for (uint i = 0; i < numSamples; ++i)
                    {
                        int s = pop24bitsLE(input);
                        result.data[i] = s / 8388607.0;
                    }
                }
                else if (bytePerSample == 4)
                {
                    for (uint i = 0; i < numSamples; ++i)
                    {
                        int s = popIntLE(input);
                        result.data[i] = s / 2147483648.0;
                    }
                }
                else
                    throw new WAVException("Unsupported bit-depth for integer PCM data, should be 8, 16, 24 or 32 bits.");
            }
            else
                assert(false); // should have been handled earlier, crash

            foundData = true;

        }
        // ignore unrecognized chunks
    }

    if (!foundFmt)
        throw new WAVException("'fmt ' chunk not found.");

    if (!foundData)
        throw new WAVException("'data' chunk not found.");
 

    result.numChannels = numChannels;
    result.sampleRate = sampleRate;

    return result;
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
        if (input.empty)
            throw new WAVException("Expected a byte, but end-of-input found.");

        ubyte b = input.front;
        input.popFront();
        return b;
    }

    void skipBytes(R)(ref R input, int numBytes) if (isInputRange!R)
    {
        for (int i = 0; i < numBytes; ++i)
            popByte(input);
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

    int popIntLE(R)(ref R input) if (isInputRange!R)
    {
        return cast(int)(popUintLE(input));
    }

    uint pop24bitsLE(R)(ref R input) if (isInputRange!R)
    {
        ubyte b0 = popByte(input);
        ubyte b1 = popByte(input);
        ubyte b2 = popByte(input);
        return (b2 << 16) | (b1 << 8) | b0;
    }

    ushort popUshortLE(R)(ref R input) if (isInputRange!R)
    {
        ubyte b0 = popByte(input);
        ubyte b1 = popByte(input);
        return (b1 << 8) | b0;
    }

    short popShortLE(R)(ref R input) if (isInputRange!R)
    {
        return cast(short)popUshortLE(input);
    }

    ulong popUlongLE(R)(ref R input) if (isInputRange!R)
    {
        ulong b0 = popByte(input);
        ulong b1 = popByte(input);
        ulong b2 = popByte(input);
        ulong b3 = popByte(input);
        ulong b4 = popByte(input);
        ulong b5 = popByte(input);
        ulong b6 = popByte(input);
        ulong b7 = popByte(input);
        return (b7 << 56) | (b6 << 48) | (b5 << 40) | (b4 << 32) | (b3 << 24) | (b2 << 16) | (b1 << 8) | b0;
    }

    float popFloatLE(R)(ref R input) if (isInputRange!R)
    {
        union float_uint
        {
            float f;
            uint i;
        }
        float_uint fi;
        fi.i = popUintLE(input);
        return fi.f;
    }

    float popDoubleLE(R)(ref R input) if (isInputRange!R)
    {
        union double_ulong
        {
            double d;
            ulong i;
        }
        double_ulong du;
        du.i = popUlongLE(input);
        return du.d;
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