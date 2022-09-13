/**
Safe, flexible, audio buffer RAII structure.

Copyright: Copyright Guillaume Piolat 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.audio.audiobuffer;

import core.bitop: bsf;
import core.stdc.string;
import dplug.core.math;
import inteli.emmintrin;

// A word of warning:
// Do not try to use "inout" in this file.
// this is the path to misery.

nothrow:
@nogc:
@safe:

/// Allocate a new `AudioBuffer` with given `frames` and `channels`.
/// Its data is _not_ initialized.
AudioBuffer!T audioBufferAlloc(T)(int channels, int frames, int alignment = 1)
{
    AudioBuffer!T buf;
    buf.resize(channels, frames, alignment);
    return buf;
}

/// Allocate a new `AudioBuffer` with given `frames` and `channels`.
/// Its data is initialized to zeroes.
AudioBuffer!T audioBufferAllocZeroed(T)(int channels, int frames, int alignment = 1)
{
    AudioBuffer!T buf;
    buf.resize(channels, frames, alignment);
    buf.fillWithZeroes();
    return buf;
}

/// Create a `AudioBuffer` by reusing existing data. Hence no format conversion happens.
AudioBuffer!T audioBufferFromData(T)(int channels, int frames, T** inData) @system
{
    AudioBuffer!T buf;
    buf.initWithData(channels, frames, inData);
    return buf;
}
///ditto
const(AudioBuffer!T) audioBufferFromData(T)(int channels, int frames, const(T*)* inData) @system
{    
    int frameStart = 0;
    ubyte alignment = 1;
    ubyte flags = 0;
    return const(AudioBuffer!T)(channels, frames, inData, frameStart, alignment, flags);
}

/*
///ditto
const(AudioBuffer!T) audioBufferCreateSubBuffer(T)(ref const(AudioBuffer!T) parent, int frameStart, int frameEnd) @trusted
{
    assert(frameStart >= 0);
    assert(frameStart <= frameEnd);
    assert(frameEnd <= parent.frames());
    ubyte alignment = 1;
    int channels = parent.channels();
    int frames = frameEnd - frameStart;

    const(T*)* data = parent.getChannelsPointers();
    bool parentHasZeroFlag = parent.hasZeroFlag();

    return const(AudioBuffer!T)(channels, frames, data, frameStart,
                                alignment, parentHasZeroFlag ? AudioBuffer!T.Flags.isZero : 0);
}
*/

/// Duplicate an `AudioBuffer` with an own allocation, make it mutable.
AudioBuffer!T audioBufferDup(T)(ref const(AudioBuffer!T) buf, int alignment = 1)
{
    AudioBuffer!T b;
    b.resize(buf.channels(), buf.frames(), alignment);
    b.copyFrom(buf);
    return b;
}


/// An `AudioBuffer` is a multi-channel buffer, with defined length, to act as storage 
/// of audio samples of type `T`.
/// It is passed around by DSP algorithms.
/// Data is store deinterleaved.
struct AudioBuffer(T)
{
public:
nothrow:
@nogc:
@safe:

    /// Change the size (`channels` and `frames` of the underlying store.
    /// Data is left uninitialized.
    /// Typically you would reuse an `AudioBuffer` if you want to reuse the allocation.
    /// When the same size is requested, the same allocation is reused (unless alignment is changed).
    void resize(int channels, int frames, int alignment = 1)
    {
        resizeDiscard(channels, frames, alignment);

        // Debug: fill with NaNs, this will make non-initialization problem very explicit.
        debug
        {
            fillWithValue(T.nan);
        }
    }

    /// Dispose the previous content, if any.
    /// Allocate a new `AudioBuffer` with given `frames` and `channels`. This step can reuse an existing owned allocation.
    void initWithData(int channels, int frames, T** inData) @system
    {
        assert(channels <= maxPossibleChannels);

        // Release own memory if any.
        cleanUpData();

        _channels = channels;
        _frames = frames; 
        _alignment = 1;
        _flags = Flags.hasOtherMutableReference;

        for (int n = 0; n < channels; ++n)
        {
            _channelPointers[n] = inData[n];
        }
    }

    ~this()
    {
        cleanUp();
    }

    /// Return number of channels in this buffer.
    int channels() const
    {
        return _channels;
    }

    /// Return number of frames in this buffer.
    int frames() const
    {
        return _frames;
    }

    /// Return alignment of the sample storage.
    int alignment() const
    {
        return _alignment;
    }


    @disable this(this);

    /// Recompute the status of the zero flag.
    /// Otherwise, asking for a mutable pointer into the zero data will clear this flag.
    /// This is useful if you've written in a buffer and want to optimize downstream.
    void recomputeZeroFlag()
    {
        if (computeIsBufferSilent())
            setZeroFlag();
        else
        {
            // Normally the zero flag is already unset.
            // is is a logical error if the zero flag is set when it can be non-zero
            assert(!hasZeroFlag);
        }
    }

    /// Returns: true if the buffer is all zeroes.
    bool isSilent() const
    {
        if (hasZeroFlag())
        {
            if (isIsolated())
                return true;
            else
                return computeIsBufferSilent();
        }
        else
            return computeIsBufferSilent();
    }

    /// Returns: `true` is the data is only pointed to by this `AudioBuffer`.
    bool isIsolated() const
    {
        return (_flags & Flags.hasOtherMutableReference)== 0;
    }

    // This break the isolated flag manually, in case you want to be able 
    // to use the zero flag regardless, at your own risk.
    void assumeIsolated()
    {
        clearHasOtherMutableReferenceFlag();
    }

    /// Returns: `true` is the buffer own its pointed audio data.
    bool hasOwnership() const
    {
        return (_flags & Flags.hasOwnership) != 0;
    }

    // <data-access>

    /// Get pointer of a given channel.
    T* getChannelPointer(int channel)
    {
        clearZeroFlag();
        return _channelPointers[channel];
    }

    /// Get const pointer of a given channel.
    const(T)* getChannelPointer(int channel) const
    {
        return _channelPointers[channel];
    }

    /// Get immutable pointer of a given channel.
    immutable(T)* getChannelPointer(int channel) immutable
    {
        return _channelPointers[channel];
    }

    /// Get channel pointers.
    T** getChannelsPointers() return @trusted
    {
        clearZeroFlag();
        return _channelPointers.ptr;
    }

    /// Get const channel pointers.
    const(T*)* getChannelsPointers() return @trusted const
    {
        return _channelPointers.ptr;
    }

    /// Get immutable channel pointers.
    immutable(T*)* getChannelsPointers() return @trusted immutable
    {
        return _channelPointers.ptr;
    }

    /// Get slice of a given channel.
    T[] getChannel(int channel) @trusted
    {
        clearZeroFlag();
        return _channelPointers[channel][0.._frames];
    }
    ///ditto
    const(T)[] getChannel(int channel) const @trusted
    {
        return _channelPointers[channel][0.._frames];
    }
    ///ditto
    immutable(T)[] getChannel(int channel) immutable @trusted
    {
        return _channelPointers[channel][0.._frames];
    }
    ///ditto
    inout(T)[] opIndex(int channel) inout @trusted
    {
        return _channelPointers[channel][0.._frames];
    }

    // </data-access>

    // <opIndex>

    /// Create an AudioBuffer that is a ref to the same data.
    AudioBuffer opIndex()
    {
        return sliceFrames(0, _frames);
    }
    ///ditto
    const(AudioBuffer) opIndex() const
    {
        return sliceFrames(0, _frames);
    }

    /// Index a single sample.
    ref inout(T) opIndex(int channel, int frame) inout @trusted
    { 
        return _channelPointers[channel][frame];
    }

    /// Slice with a sub-range of channels.
    AudioBuffer opIndex(int[2] chan)
    {
        return sliceChannels(chan[0], chan[1]);
    } 
    ///ditto
    const(AudioBuffer) opIndex(int[2] chan) const
    {
        return sliceChannels(chan[0], chan[1]);
    }

    /// Slice across channels and temporally.
    /// Take a sub-range of channels, and a sub-range of frames.
    AudioBuffer opIndex(int[2] chan, int[2] framesBounds)
    {
        return sliceChannels(chan[0], chan[1]).sliceFrames(framesBounds[0], framesBounds[1]);
    } 
    ///ditto
    const(AudioBuffer) opIndex(int[2] chan, int[2] framesBounds) const
    {
        return sliceChannels(chan[0], chan[1]).sliceFrames(framesBounds[0], framesBounds[1]);
    }

    // </op-index>

    // <slice>

    int opDollar(size_t dim : 0)() pure const 
    { 
        return _channels; 
    }

    int opDollar(size_t dim : 1)() pure const
    { 
        return _frames; 
    }

    /// Select only a slice of channels from `AudioBuffer`.
    /// Params:
    ///    frameStart offset in the buffer. Must be >= 0 and <= `frameEnd`.
    ///    frameEnd offset in the buffer. Cannot be larger than the parent size.
    AudioBuffer sliceChannels(int channelStart, int channelEnd) @trusted
    {
        assert(channelStart >= 0);
        assert(channelStart <= channelEnd);
        assert(channelEnd <= this.channels());
        int channelSub = channelEnd - channelStart;
        T** data = this.getChannelsPointers();

        ubyte flags = Flags.hasOtherMutableReference;
        if (this.hasZeroFlag())
            flags |= Flags.isZero;

        // Because this is a mutable reference, both the parent and the result
        // get the "has another mutable ref" flag.
        this.setHasOtherMutableReferenceFlag();

        return AudioBuffer!T(channelSub, 
                             this.frames(), 
                             data + channelStart,
                             0, 
                             _alignment,
                             flags);
    }
    //ditto
    const(AudioBuffer) sliceChannels(int channelStart, int channelEnd) const @trusted
    {
        assert(channelStart >= 0);
        assert(channelStart <= channelEnd);
        assert(channelEnd <= this.channels());
        int channelSub = channelEnd - channelStart;
        const(T*)* data = this.getChannelsPointers();

        ubyte flags = 0;
        if (this.hasZeroFlag())
            flags |= Flags.isZero;

        return AudioBuffer!T(channelSub, 
                             this.frames(), 
                             data + channelStart,
                             0, 
                             _alignment,
                             flags);
    }
    ///ditto
    int[2] opSlice(size_t dim)(int start, int end) const
    {
        return [start, end];
    }

    /// Create a `AudioBuffer` derivated from another buffer.
    /// Params:
    ///    frameStart offset in the buffer. Must be >= 0 and <= `frameEnd`.
    ///    frameEnd offset in the buffer. Cannot be larger than the parent size.
    AudioBuffer sliceFrames(int frameStart, int frameEnd) @trusted
    {
        assert(frameStart >= 0);
        assert(frameStart <= frameEnd);
        assert(frameEnd <= this.frames());
        ubyte alignment = childAlignment(_alignment, T.sizeof, frameStart);
        int channels = this.channels();
        int framesSub = frameEnd - frameStart;

        T** data = this.getChannelsPointers();

        ubyte flags = Flags.hasOtherMutableReference;
        if (this.hasZeroFlag())
            flags |= Flags.isZero;

        // Because this is a mutable reference, both the parent and the result
        // get the "has another mutable ref" flag.
        this.setHasOtherMutableReferenceFlag();

        return AudioBuffer!T(channels, 
                             framesSub, 
                             data,
                             frameStart, 
                             alignment,
                             flags);
    }
    ///ditto
    const(AudioBuffer) sliceFrames(int frameStart, int frameEnd) const @trusted
    {
        assert(frameStart >= 0);
        assert(frameStart <= frameEnd);
        assert(frameEnd <= this.frames());
        ubyte alignment = childAlignment(_alignment, T.sizeof, frameStart);
        int channels = this.channels();
        int framesSub = frameEnd - frameStart;

        const(T*)* data = this.getChannelsPointers();

        ubyte flags = 0;
        if (this.hasZeroFlag())
            flags |= Flags.isZero;

        return AudioBuffer!T(channels, 
                             framesSub, 
                             data,
                             frameStart, 
                             alignment,
                             flags);
    }

    // </slice>

    // <copy>

    /// Copy samples from `source` to `dest`.
    /// Number of `frames` and `channels` must match.
    void copyFrom(ref const(AudioBuffer) source) @trusted
    {
        assert(_frames == source.frames());
        assert(_channels == source.channels());

        size_t bytesForOneChannel = T.sizeof * _frames;
        for (int chan = 0; chan < _channels; ++chan)
        {
            memmove(_channelPointers[chan], source._channelPointers[chan], bytesForOneChannel);
        }
        if (source.hasZeroFlag)
            setZeroFlag();
    }

    // </copy>


    // <filling the buffer>

    /// Fill the buffer with zeroes.
    void fillWithZeroes() @trusted
    {
        size_t bytesForOneChannel = T.sizeof * _frames;
        for (int chan = 0; chan < _channels; ++chan)
        {
            memset(_channelPointers[chan], 0, bytesForOneChannel);
        }
        setZeroFlag();
    }

    /// Fill the buffer with a single value.
    /// Warning: the buffer must be in `fp32` format.
    void fillWithValue(T value) @trusted
    {
        if (value == 0)
            return fillWithZeroes(); // Note: this turns -0.0 into +0.0

        for (int chan = 0; chan < _channels; ++chan)
        {
            T* p = getChannelPointer(chan);
            p[0.._frames] = value;
        }
        assert(!hasZeroFlag);
    }

    // </filling the buffer>

    // <buffer splitting>

    /// Return an input range that returns several subbuffers that covers the 
    /// parent buffer, each with length not larger than `maxFrames`.
    auto chunkBy(int maxFrames)
    {
        static struct AudioBufferRange
        {
            AudioBuffer buf;
            int offset = 0;
            int maxFrames;
            int totalFrames;

            AudioBuffer front()
            {
                int end = offset + maxFrames;
                if (end > totalFrames)
                    end = totalFrames;
                AudioBuffer res = buf.sliceFrames(offset, end);
                return res;
            }

            void popFront()
            {
                offset += maxFrames;
            }

            bool empty()
            {
                return offset >= totalFrames;
            }
        }
        return AudioBufferRange( sliceFrames(0, frames()), 0, maxFrames, frames() );
    }
    ///ditto
    auto chunkBy(int maxFrames) const
    {
        static struct AudioBufferRange
        {
            const(AudioBuffer) buf;
            int offset;
            int maxFrames;
            int totalFrames;

            const(AudioBuffer) front()
            {
                int end = offset + maxFrames;
                if (end > totalFrames)
                    end = totalFrames;
                const(AudioBuffer) res = buf.sliceFrames(offset, end);
                return res;
            }

            void popFront()
            {
                offset += maxFrames;
            }

            bool empty()
            {
                return offset >= totalFrames;
            }
        }
        return AudioBufferRange( sliceFrames(0, frames()), 0, maxFrames, frames() );
    }

    // </buffer splitting>

private:

    /// Internal flags
    enum Flags : ubyte
    {
        /// Zero flag.
        isZero = 1,

        /// Owner flag.
        hasOwnership = 2, 

        /// Growable flag.
        //isGrowable = 4

        /// Data is pointed to, mutably, by other things than this `AudioBuffer`.
        hasOtherMutableReference = 8,
    }

    // TODO: lift that limitation
    enum maxPossibleChannels = 8;

    // Pointers to beginning of every channel.
    T*[maxPossibleChannels] _channelPointers;
    
    // Pointer to start of data.
    // If memory is _owned_, then it is allocated with `_mm_realloc_discard`/`_mm_free`
    void* _data     = null;

    // Number of frames in the buffer.
    int _frames;

    // Number of channels in the buffer.
    int _channels;

    // Various flags.
    ubyte _flags;

    // Current allocation alignment.
    ubyte _alignment = 0; // current alignment, 0 means "unassigned" 

    // Test if the zero flag is set.
    // Returns: `true` is the buffer has the `zeroFlag` set.
    // Warning: that when this flag isn't set, the buffer could still contains only zeroes.
    //          If you want to test for zeroes, use `isSilent` instead.
    bool hasZeroFlag() const
    {
        return (_flags & Flags.isZero) != 0;
    }    

    void clearZeroFlag()
    {
        _flags &= ~cast(int)Flags.isZero;
    }

    void setZeroFlag()
    {
        _flags |= Flags.isZero;
    }

    void setHasOtherMutableReferenceFlag()
    {
        _flags |= Flags.hasOtherMutableReference;
    }

    void clearHasOtherMutableReferenceFlag()
    {
        _flags &= ~cast(int)Flags.hasOtherMutableReference;
    }

    // Private constructor, the only way to create const/immutable object.
    this(int channels, 
         int frames, 
         const(T*)* inData, 
         int offsetFrames, // point further in the input
         ubyte alignment, 
         ubyte flags) @system 
    {
        assert(offsetFrames >= 0);
        assert(channels <= maxPossibleChannels);
        _channels = channels;
        _frames = frames; 
        _alignment = alignment;
        _flags = flags;

        for (int n = 0; n < channels; ++n)
        {
            _channelPointers[n] = cast(T*)(inData[n]) + offsetFrames; // const_cast here
        }
    }

    void resizeDiscard(int channels, int frames, int alignment) @trusted
    {
        assert(channels >= 0 && frames >= 0);
        assert(alignment >= 1 && alignment <= 128);
        assert(isPowerOfTwo(alignment));
        assert(channels <= maxPossibleChannels); // TODO allocate to support arbitrary channel count.

        if (_alignment != 0 && _alignment != alignment)
        {
            // Can't keep the allocation if the alignment changes.
            cleanUpData();
        }

        _channels = channels;
        _frames = frames; 
        _alignment = cast(ubyte)alignment;

        size_t bytesForOneChannel = T.sizeof * frames;
        bytesForOneChannel = nextMultipleOf(bytesForOneChannel, alignment);
        
        size_t bytesTotal = bytesForOneChannel * channels;
        if (bytesTotal == 0) 
            bytesTotal = 1; // so that zero length or zero-channel buffers still kinda work.

        _data = _mm_realloc_discard(_data, bytesTotal, alignment);
        _flags = Flags.hasOwnership;

        for (int n = 0; n < _channels; ++n)
        {
            ubyte* p = (cast(ubyte*)_data) + bytesForOneChannel * n;
            _channelPointers[n] = cast(T*)p;
        }
    }

    void cleanUp()
    {
        cleanUpData();
    }

    void cleanUpData()
    {
        if (hasOwnership())
        {
            if (_data !is null)
            {
                _mm_free(_data);
                _data = null;
            }
        }

        // Note: doesn't loose the ownership flag, because morally this AudioBuffer is still 
        // the kind of AudioBuffer that owns its data, it just has no data right now.
    }

    // Returns: true if the whole buffer is filled with 0 (or -0 for floating-point) 
    // Do not expose this API as it isn't clear how fast it is.
    bool computeIsBufferSilent() const nothrow @nogc @trusted
    {
        for (int channel = 0; channel < _channels; ++channel)
        {
            const(T)* samples = getChannelPointer(channel);
            for (int n = 0; n < _frames; ++n)
            {
                if (samples[n] != 0)
                    return false;
            }
        }
        return true;
    }
}

private:

// Compute largest possible byte alignment for a sub-buffer.
ubyte childAlignment(ubyte parentAlignment, size_t itemSize, int frameStart) pure
{
    assert(parentAlignment >= 1 && parentAlignment <= 128);

    // For reference, this is the alignment for T == float:
    //
    // float(4 bytes)|  0   |  1  |  2   |  3  |   4 |
    // ----------------------------------------------|
    // parent 1      |  1   |  1  |  1   |  1  |   1 |
    // parent 2      |  2   |  2  |  2   |  2  |   2 |
    // parent 4      |  4   |  4  |  4   |  4  |   4 |
    // parent 8      |  8   |  4  |  8   |  4  |   8 |
    // parent 16     |  16  |  4  |  8   |  4  |  16 |
    // parent 32     |  32  |  4  |  8   |  4  |  16 |

    size_t offset = frameStart * itemSize;
    // how many zero bits there are in LSB?
    if (offset == 0)
        return parentAlignment;
    int zeroBits = bsf(offset);
    if (zeroBits > 7) 
        zeroBits = 7; // do not exceed 128
    int a = (1 << zeroBits);
    if (a > parentAlignment)
        a = parentAlignment;
    return cast(ubyte)a;
}
unittest
{
    assert( childAlignment(1, 8, 8) == 1 );        // do not exceed aprent align
    assert( childAlignment(16, 4, 2) == 8 );
    assert( childAlignment(16, 8, 0) == 16 );
    assert( childAlignment(16, 8, 1024) == 16 );
    assert( childAlignment(16, 4, 1) == 4 );
    assert( childAlignment(128, 4, 1024) == 128 ); // do not exceed 128
}

// How zero flag works:
@trusted unittest 
{
    AudioBuffer!double a = audioBufferAlloc!double(3, 1024, 16);
    assert(!a.hasZeroFlag());
    assert(!a.isSilent);
    a.fillWithValue(0.0);

    // Newly created AudioBuffer with own memory is zeroed out.
    assert(a.hasZeroFlag());
    assert(a.isSilent);

    // Getting a mutable pointer make the zero flag disappear.
    a.getChannelPointer(2)[1023] = 0.0;
    assert(!a.hasZeroFlag());
    assert(a.isSilent());

    // To set the zero flag, either recompute it (slow)
    // or fill the buffer with zeroes.
    a.recomputeZeroFlag();
    assert(a.hasZeroFlag());
    assert(a.isSilent());
}

unittest 
{
    // Buffer must reuse an existing allocation if the size/alignment is the same.
    // Even in this case, the content is NOT preserved.
    AudioBuffer!double b;
    b.resize(1, 1024, 16);
    double* chan0 = b.getChannelPointer(0);

    b.resize(1, 1024, 16);
    assert(chan0 == b.getChannelPointer(0));

    // If the alignment changes though, can't reuse allocation.
    b.resize(1, 1024, 128);
    assert(b.channels() == 1);
    assert(b.frames() == 1024);
    b.resize(2, 1023, 128);

    b.fillWithValue(4.0);
    double[] p = b.getChannel(1);
    assert(p[1022] == 4.0);
    assert(!b.hasZeroFlag());
}

@trusted unittest
{
    // const borrow preserve zero flag
    int numChans = 8;
    const(AudioBuffer!float) c = audioBufferAllocZeroed!float(numChans, 123);
    assert(c.hasZeroFlag());
    const(float*)* buffers = c.getChannelsPointers();
    for (int chan = 0; chan < 8; ++chan)
    {
        assert(buffers[chan] == c.getChannelPointer(chan));
    }
    const(AudioBuffer!float) d = c.sliceFrames(10, c.frames());
    assert(d.frames() == 123 - 10);
    assert(d.hasZeroFlag());

    const(AudioBuffer!float) e = d[0..$, 0..24];
    assert(e.channels() == d.channels());
    assert(e.frames() == 24);
}

@trusted unittest
{
    // Mutable borrow doesn't preserve zero flag, and set hasOtherMutableReference flag
    int numChans = 2;
    AudioBuffer!double c = audioBufferAlloc!double(numChans, 14);
    c.fillWithZeroes();
    assert(c.hasZeroFlag());
    assert(c.isIsolated());
    
    AudioBuffer!double d = c[0..$, 10 .. 14];
    assert(!c.hasZeroFlag());
    assert(!d.hasZeroFlag());
    assert(!c.isIsolated);
    assert(!d.isIsolated);

    // Fill right channel with 2.5f 
    d.getChannel(1)[] = 2.5;
    assert(c[1, 9] == 0.0);
    c[1, 8] = -1.0;
    assert(c[1, 8] == -1.0);    
    
    assert(c[1][10] == 2.5);

    // Mutable dup
    AudioBuffer!double e = audioBufferDup(d);
    assert(e.isIsolated);
}

@trusted unittest
{   
    // Create mutable buffer from mutable data.
    {
        float[128][2] data;
        float*[2] pdata;
        pdata[0] = data[0].ptr;
        pdata[1] = data[1].ptr;
        AudioBuffer!float b;
        b.initWithData(2, 128, pdata.ptr);
        assert(!b.isIsolated);

        // This break the isolated flag manually, in case you want to be able 
        // to use the zero flag regardless, at your own risk.
        b.assumeIsolated(); 
        assert(b.isIsolated);
    }

    // Create const buffer from const data.
    {
        float[128][2] data;
        const(float*)[2] pdata = [ data[0].ptr, data[1].ptr];
        const(AudioBuffer!float) b = audioBufferFromData(2, 128, pdata.ptr);
        assert(b.isIsolated);
    }
}

unittest
{
    // Chunked foreach
    {
        AudioBuffer!double whole = audioBufferAlloc!double(2, 323 + 1024, 16);
        foreach(b; whole.chunkBy(1024))
        {
            assert(b.frames() <= 1024);
            b.fillWithZeroes();

            AudioBuffer!double c = b[0..$];
            assert(c.channels == whole.channels);
            assert(c.alignment == whole.alignment); // inherited alignment correctly
            assert(c.frames == b.frames);
        }
        assert(whole.computeIsBufferSilent());
    }

    // Chunked const foreach
    {
        const(AudioBuffer!double) whole = audioBufferAllocZeroed!double(3, 2000);
        foreach(b; whole.chunkBy(1024)) // split by frames
        {
            assert(b.isSilent);

            // Split by channels
            const(AudioBuffer!double) left = b[0..1];
            const(AudioBuffer!double) right = b.sliceChannels(1, 2);
            assert(left.isSilent);
            assert(b.frames == left.frames);
            assert(left.channels == 1);
            assert(right.isSilent);
        }
    }
}