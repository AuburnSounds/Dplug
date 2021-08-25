/**
Safe, flexible, audio buffer RAII structure.

Copyright: Copyright Guillaume Piolat 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.audio.audiobuffer;

import core.stdc.string;
import dplug.core.math;
import inteli.emmintrin;

nothrow:
@nogc:
@safe:

/// Allocate a new `AudioBuffer` with given `frames` and `channels`.
/// Initialized with zeroes.
AudioBuffer audioBufferCreateNew(int channels, int frames, AudioBuffer.Format format = AudioBuffer.Format.fp32, int alignment = 1)
{
    AudioBuffer buf;
    buf.createNew(channels, frames, format, alignment);
    return buf;
}

/// Allocate a new `AudioBuffer` with given `frames` and `channels`.
/// Not initialized.
AudioBuffer audioBufferCreateNewUninitialized(int channels, int frames, AudioBuffer.Format format = AudioBuffer.Format.fp32, int alignment = 1)
{
    AudioBuffer buf;
    buf.createNewUninitialized(channels, frames, format, alignment);
    return AudioBuffer.init;
}

/// Create a `AudioBuffer` by reusing existing data. Hence no format conversion happens.
AudioBuffer audioBufferCreateFromExistingData(int channels, int frames, void** inData, AudioBuffer.Format inFormat) @system
{
    assert(false);
}

/// Create a `AudioBuffer` derivated from another buffer.
/// Params:
///    frameStart offset in the buffer. Must be >= 0 and <= `frameEnd`.
///    frameEnd offset in the buffer. Cannot be larger than the parent size.
inout(AudioBuffer) audioBufferCreateSubBuffer(inout(AudioBuffer) buf, int frameStart, int frameEnd)
{
    assert(false);
}

/// Duplicate an `AudioBuffer` with an own allocation, make it mutable.
AudioBuffer audioBufferDup(AudioBuffer buf)
{
    assert(false);
}

/// Duplicate an `AudioBuffer` with an own allocation, make it `immutable`.
immutable(AudioBuffer) audioBufferIDup(AudioBuffer buf)
{
    assert(false);
}


/// An `AudioBuffer` is a multi-channel buffer, with defined length, to act as storage of audio samples.
/// It is passed around by DSP algorithms.
/// Data is store deinterleaved.
struct AudioBuffer
{
public:
nothrow:
@nogc:
@safe:

    enum Format : ubyte
    {
        fp32, /// 32-bit single precision
        fp64, /// 64-bit single precision
    }

    enum Flags : ubyte
    {
        /// Zero flag.
        isZero = 1,

        /// Owner flag.
        hasOwnership = 2, 

        /// Growable flag.
        //isGrowable = 4
    }

    // Constructors. Clean-up existing data if owner, then create.
    // Typically you would reused an `AudioBuffer` if you want to reuse the allocation.


    /// Dispose the previous content, if any.
    /// Allocate a new `AudioBuffer` with given `frames` and `channels`. This step can reuse an existing owned allocation.
    /// Data is then initialized with zeroes, and the zero flag is set.
    void createNew(int channels, int frames, Format format = Format.fp32, int alignment = 1)
    {
        resizeDiscard(channels, frames, format, alignment);
        fillWithZeroes();
    }

    /// Dispose the previous content, if any.
    /// Allocate a new `AudioBuffer` with given `frames` and `channels`. This step can reuse an existing owned allocation.
    void createNewUninitialized(int channels, int frames, Format format = Format.fp32, int alignment = 1)
    {
        resizeDiscard(channels, frames, format, alignment);

        // Debug: fill with NaNs, this will make non-initialization problem very explicit.
        debug
        {
            final switch(_format)
            {
                case Format.fp32:
                    fillWithValueFloat(float.nan);
                    break;
                case Format.fp64:
                    fillWithValueDouble(double.nan);
                    break;
            }
        }
    }

    ~this()
    {
        cleanUp();
    }

    /// Return number of channels in this buffer.
    int channels()
    {
        return _channels;
    }

    /// Return number of frames in this buffer.
    int frames()
    {
        return _frames;
    }    

    /// Return internal format.
    Format format()
    {
        return _format;
    }

    @disable this(this);

    /// Test if the 
    /// Returns: `true` is the buffer has the `zeroFlag` set.
    /// Warning: that when this flag isn't set, the buffer could still contains only zeroes.
    ///          If you want to test for zeroes, use `isSilent` instead.
    bool hasZeroFlag() const
    {
        return (_flags & Flags.isZero) != 0;
    }

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
            return true;
        else
            return computeIsBufferSilent();
    }

    /// Returns: `true` is the buffer own its pointed audio data.
    bool hasOwnership() const
    {
        return (_flags & Flags.hasOwnership) != 0;
    }

    // <data-access>

    // void*

    /// Get pointer of a given channel.
    void* getChannelPointer(int channel)
    {
        clearZeroFlag();
        return _channelPointers[channel];
    }

    /// Get const pointer of a given channel.
    const(void)* getChannelPointer(int channel) const
    {
        return _channelPointers[channel];
    }

    // float*

    /// Get slice of a given channel.
    float[] getChannelFloat(int channel) @trusted
    {
        clearZeroFlag();
        assert(_format == Format.fp32);
        return (cast(float*) _channelPointers[channel])[0.._frames];
    }

    /// Get const slice of a given channel.
    const(float)[] getChannelFloat(int channel) const @trusted
    {
        assert(_format == Format.fp32);
        return (cast(const(float)*) _channelPointers[channel])[0.._frames];
    }

    /// Get pointer of a given channel.
    float* getChannelPointerFloat(int channel) @trusted
    {
        clearZeroFlag();
        assert(_format == Format.fp32);
        return cast(float*) _channelPointers[channel];
    }

    /// Get const pointer of a given channel.
    const(float)* getChannelPointerFloat(int channel) const @trusted
    {
        assert(_format == Format.fp32);
        return cast(const(float)*) _channelPointers[channel];
    }  

    /// Get channel pointers.
    float** getChannelsPointersFloat() return @trusted
    {
        clearZeroFlag();
        assert(_format == Format.fp32);
        return cast(float**) _channelPointers.ptr;
    }

    /// Get const channel pointers.
    const(float*)* getChannelsPointersFloat() return @trusted const
    {
        assert(_format == Format.fp32);
        return cast(const(float*)*) _channelPointers.ptr;
    }

    // double*

    /// Get slice of a given channel.
    double[] getChannelDouble(int channel) @trusted
    {
        clearZeroFlag();
        assert(_format == Format.fp64);
        return (cast(double*) _channelPointers[channel])[0.._frames];
    }

    /// Get const slice of a given channel.
    const(double)[] getChannelDouble(int channel) const @trusted
    {
        assert(_format == Format.fp64);
        return (cast(const(double)*) _channelPointers[channel])[0.._frames];
    }

    /// Get pointer of a given channel.
    double* getChannelPointerDouble(int channel) @trusted
    {
        clearZeroFlag();
        assert(_format == Format.fp64);
        return cast(double*) _channelPointers[channel];
    }

    /// Get const pointer of a given channel.
    const(double)* getChannelPointerDouble(int channel) const @trusted
    {
        assert(_format == Format.fp64);
        return cast(const(double)*) _channelPointers[channel];
    }

    /// Get channel pointers.
    double** getChannelsPointersDouble() return @trusted
    {
        clearZeroFlag();
        assert(_format == Format.fp64);
        return cast(double**) _channelPointers.ptr;
    }

    /// Get const channel pointers.
    const(double*)* getChannelsPointersDouble() return const @trusted
    {
        assert(_format == Format.fp64);
        return cast(const(double*)*) _channelPointers.ptr;
    }

    // </data-access>



    // <filling the buffer>

    /// Fill the buffer with zeroes.
    void fillWithZeroes() @trusted
    {
        size_t bytesForOneChannel = bytesPerSample(_format) * _frames;
        for (int chan = 0; chan < _channels; ++chan)
        {
            memset(_channelPointers[chan], 0, bytesForOneChannel);
        }
        setZeroFlag();
    }

    /// Fill the buffer with a single value.
    /// Warning: the buffer must be in `fp32` format.
    void fillWithValueFloat(float value) @trusted
    {
        if (value == 0.0f)
            return fillWithZeroes();

        for (int chan = 0; chan < _channels; ++chan)
        {
            float* p = getChannelPointerFloat(chan);
            p[0.._frames] = value;
        }
        assert(!hasZeroFlag);
    }

    /// Fill the buffer with a single value.
    /// Warning: the buffer must be in `fp64` format.
    void fillWithValueDouble(float value) @trusted
    {
        if (value == 0.0)
            return fillWithZeroes();

        for (int chan = 0; chan < _channels; ++chan)
        {
            double* p = getChannelPointerDouble(chan);
            p[0.._frames] = value;
        }
        assert(!hasZeroFlag);
    }

    // </filling the buffer>

private:

    // TODO: lift that limitation
    enum maxPossibleChannels = 8;

    // Pointers to beginning of every channel.
    void*[maxPossibleChannels] _channelPointers;
    
    // Pointer to start of data.
    // If memory is _owned_, then it is allocated with `_mm_realloc_discard`/`_mm_free`
    void* _data     = null; // having no data pointer is the defining feature of AudioBuffer.init

    // Number of frames in the buffer.
    int _frames;

    // Number of channels in the buffer.
    int _channels;

    // Various flags.
    ubyte _flags;

    // Format tag.
    Format _format;

    // Current allocation alignment.
    ubyte _alignment = 0; // current alignment, 0 means "unassigned" 

    void clearZeroFlag()
    {
        _flags &= ~cast(int)Flags.isZero;
    }

    void setZeroFlag()
    {
        _flags |= Flags.isZero;
    }

    static size_t bytesPerSample(Format format)
    {
        final switch(format)
        {
            case Format.fp32: return 4;
            case Format.fp64: return 8;
        }
    }

    void resizeDiscard(int channels, int frames, Format format, int alignment) @trusted
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
        _format = format;

        size_t bytesForOneChannel = bytesPerSample(format) * frames;
        bytesForOneChannel = nextMultipleOf(bytesForOneChannel, alignment);
        
        size_t bytesTotal = bytesForOneChannel * channels;
        if (bytesTotal == 0) 
            bytesTotal = 1; // so that zero length or zero-channel buffers still kinda work.

        _data = _mm_realloc_discard(_data, bytesTotal, alignment);
        _flags = Flags.hasOwnership;

        for (int n = 0; n < _channels; ++n)
        {
            _channelPointers[n] = (cast(ubyte*)_data) + bytesForOneChannel * n;
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
        final switch(_format)
        {
            case Format.fp32:
            {
                for (int channel = 0; channel < _channels; ++channel)
                {
                    const(float)* samples = getChannelPointerFloat(channel);
                    for (int n = 0; n < _frames; ++n)
                    {
                        if (samples[n] != 0)
                            return false;
                    }
                }
                return true;
            }

            case Format.fp64:
            {
                for (int channel = 0; channel < _channels; ++channel)
                {
                    const(double)* samples = getChannelPointerDouble(channel);
                    for (int n = 0; n < _frames; ++n)
                    {
                        if (samples[n] != 0)
                            return false;
                    }
                }
                return true;
            }
        }
    }
}

// How zero flag works:
@trusted unittest 
{
    AudioBuffer a = audioBufferCreateNew(3, 1024, AudioBuffer.Format.fp64, 16);

    // Newly created AudioBuffer with own memory is zeroed out.
    assert(a.hasZeroFlag());

    // Getting a mutable pointer make the zero flag disappear.
    a.getChannelPointerDouble(2)[1023] = 0.0;
    assert(!a.hasZeroFlag()); 

    // To set the zero flag, either recompute it (slow)
    // or fill the buffer with zeroes.
    a.recomputeZeroFlag();
    assert(a.hasZeroFlag());
}

unittest 
{
    AudioBuffer b;
    b.createNewUninitialized(1, 1024, AudioBuffer.Format.fp64, 16);

    // Buffer can reuse an existing allocation and change the format.
    // if the alignment changes though, can't reuse allocation.
    b.createNewUninitialized(2, 1023, AudioBuffer.Format.fp32, 128);
    assert(b.format() == AudioBuffer.Format.fp32);
    assert(b.channels() == 2);
    assert(b.frames() == 1023);
    b.fillWithValueFloat(4.0f);
    float[] p = b.getChannelFloat(1);
    assert(p[1022] == 4.0f);
    assert(!b.hasZeroFlag());
}

@trusted unittest
{
    int numChans = 8;
    AudioBuffer c = audioBufferCreateNew(numChans, 123, AudioBuffer.Format.fp32);

    const(float*)* buffers = c.getChannelsPointersFloat();
    for (int chan = 0; chan < 8; ++chan)
    {
        assert(buffers[chan] == c.getChannelPointerFloat(chan));
    }
}