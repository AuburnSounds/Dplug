/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.fft;

import core.stdc.string;

public import std.complex;
import std.math;

import gfm.math.funcs;

import dplug.dsp.funcs,
       dplug.dsp.window;


enum FFTDirection
{
    FORWARD = 0,
    REVERSE = 1
}
    
/// Perform in-place FFT.
void FFT(T)(Complex!T[] buffer, FFTDirection direction) nothrow @nogc
{
    int size = cast(int)(buffer.length);
    assert(isPowerOf2(size));
    int m = iFloorLog2(size);

    // do the bit reversal
    int i2 = cast(int)size / 2;
    int j = 0;
    for (int i = 0; i < size - 1; ++i)
    {
        if (i < j)
        {
            auto tmp = buffer[i];
            buffer[i] = buffer[j];
            buffer[j] = tmp;
        }

        int k = i2;
        while(k <= j)
        {
            j = j - k;
            k = k / 2;
        }
        j += k;
    }

    // compute the FFT
    Complex!T c = Complex!T(-1);
    int l2 = 1;
    for (int l = 0; l < m; ++l)
    {
        int l1 = l2;
        l2 = l2 * 2;
        Complex!T u = 1;
        for (int j2 = 0; j2 < l1; ++j2)
        {
            int i = j2;
            while (i < size)
            {
                int i1 = i + l1;
                Complex!T t1 = u * buffer[i1];
                buffer[i1] = buffer[i] - t1;
                buffer[i] += t1;
                i += l2;
            }
            u = u * c;
        }

        T newImag = sqrt((1 - c.re) / 2);
        if (direction == FFTDirection.FORWARD)
            newImag = -newImag;
        T newReal = sqrt((1 + c.re) / 2);
        c = Complex!T(newReal, newImag);
    }

    // scaling for forward transformation
    if (direction == FFTDirection.FORWARD)
    {
        for (int i = 0; i < size; ++i)
            buffer[i] = buffer[i] / Complex!T(cast(T)size, 0);
    }
}

/// From a signal, output chunks of determined size, with optional overlap.
/// Introduces approximately windowSize/2 samples delay.
struct Segmenter(T)
{
    int segmentSize() pure const nothrow @nogc
    {
        return _segmentSize;
    }

    int analysisPeriod() pure const nothrow @nogc
    {
        return _analysisPeriod;
    }

    /// To call at initialization and whenever samplerate changes.
    /// segmentSize = size of sound segments, expressed in samples.
    /// analysisPeriod = period of analysis results, allow to be more precise frequentially, expressed in samples.    
    void initialize(int segmentSize, int analysisPeriod) nothrow @nogc
    {
        assert(analysisPeriod <= segmentSize); // no support for zero overlap

        // 1-sized FFT support
        if (analysisPeriod == 0)
            analysisPeriod = 1;

        _segmentSize = segmentSize;
        _analysisPeriod = analysisPeriod;

        // clear input delay
        _buffer.reallocBuffer(_segmentSize);
        _buffer[] = 0;
        _index = 0;
    }

    ~this()
    {
        _buffer.reallocBuffer(0);
    }

    @disable this(this);

    // Push one sample, eventually call the delegate to process a segment.
    bool feed(T x, scope void delegate(T[] segment) nothrow @nogc processSegment = null) nothrow @nogc
    {
        _buffer[_index] = x;
        _index = _index + 1;
        if (_index >= _segmentSize)
        {
            // process segment (optional)
            if (processSegment !is null)
                processSegment(_buffer[0.._segmentSize]);

            // rotate buffer
            {
                int samplesToDrop = _analysisPeriod;
                assert(0 < samplesToDrop && samplesToDrop <= _segmentSize);
                int remainingSamples = _segmentSize - samplesToDrop;

                // TODO: use ring buffer instead of copy?
                memmove(_buffer.ptr, _buffer.ptr + samplesToDrop, T.sizeof * remainingSamples);
                _index = remainingSamples;

            }
            return true;
        }
        else 
            return false;
    }

    /// Returns: Internal buffer.
    T[] buffer() nothrow @nogc
    {
        return _buffer;
    }

private:
    T[] _buffer;
    int _segmentSize;     // in samples
    int _analysisPeriod; // in samples
    int _index;
}


/// From short term windowed data, output the summed signal.
/// Segments can be irregular and have different size.
struct ShortTermReconstruction
{
    /// maxSimultSegments is the maximum number of simulatneously summed samples.
    /// maxSegmentLength in samples
    void initialize(int maxSimultSegments, int maxSegmentLength) nothrow @nogc
    {
        _maxSegmentLength = maxSegmentLength;
        _maxSimultSegments = maxSimultSegments;
        _desc.reallocBuffer(maxSimultSegments);
        for (int i = 0; i < _maxSimultSegments; ++i)
        {
            _desc[i].playOffset = 0;
            _desc[i].length = 0;

            _desc[i].buffer.reallocBuffer(maxSegmentLength);
            //reallocBuffer(_desc[i].buffer, maxSegmentLength);
        } //) 
    }

    ~this() nothrow @nogc
    {
        if (_desc !is null)
            for (int i = 0; i < _maxSimultSegments; ++i)
                _desc[i].buffer.reallocBuffer(0);
        _desc.reallocBuffer(0);
    }

    @disable this(this);

    // Copy segment to a free slot, and start its summing.
    // The first sample of this segment will be played at next() call.
    void startSegment(float[] newSegment) nothrow @nogc
    {
        assert(newSegment.length <= _maxSegmentLength);
        
        for (int i = 0; i < _maxSimultSegments; ++i)
        {
            if (!_desc[i].active())
            {
                int len = cast(int)(newSegment.length);
                _desc[i].playOffset = 0;
                _desc[i].length = len;
                _desc[i].buffer[0..len] = newSegment[]; // copy segment
                return;
            }
        }

        assert(false); // maxSimultSegments too small, or usage error
    }

    // Get next sample, update segment statuses.
    float next() nothrow @nogc
    {
        float sum = 0;
        foreach(ref desc; _desc)
        {
            if (desc.playOffset < desc.length)
            {
                sum += desc.buffer[desc.playOffset];
                desc.playOffset += 1;
            }
        }
        return sum;
    }

private:

    struct SegmentDesc
    {
        int playOffset; // offset in this segment
        int length; // length in this segment
        float[] buffer; // 0..length => data for this segment

        bool active() pure const nothrow @nogc
        {
            return playOffset < length;
        }
    }
    int _maxSimultSegments;
    int _maxSegmentLength;
    SegmentDesc[] _desc;
}

/// From a signal, output short term FFT data.
/// Variable overlap.
/// Introduces approximately windowSize/2 samples delay.
struct FFTAnalyzer
{
public:

    /// To call at initialization and whenever samplerate changes.
    /// windowSize = size of window, expressed in samples
    /// fftSize = size of FFT. Must be power-of-two and >= windowSize. Missing samples are zero-padded in time domain.
    /// analysisPeriod = period of analysis results, allow to be more precise frequentially, expressed in samples.
    /// Basic overlap is achieved with windowSize = 2 * analysisPeriod
    /// if zeroPhaseWindowing = true, "zero phase" windowing is used
    /// (center of window is at first sample, zero-padding happen at center)
    void initialize(int windowSize, int fftSize, int analysisPeriod, WindowType windowType, bool zeroPhaseWindowing, bool correctWindowLoss) nothrow @nogc
    {
        assert(isPowerOf2(fftSize));
        assert(fftSize >= windowSize);

        _zeroPhaseWindowing = zeroPhaseWindowing;
        
        _fftSize = fftSize;

        _window.initialize(windowType, windowSize);
        _windowSize = windowSize;

        _segmenter.initialize(windowSize, analysisPeriod);
    }

    bool feed(float x, Complex!float[] fftData) nothrow @nogc
    {    
        void processSegment(float[] segment) nothrow @nogc
        {
            int windowSize = _windowSize;
            assert(segment.length == _windowSize);

            // TODO: this assume fftData was allocated with alignedAlloc, looks like a problem
            fftData.reallocBuffer(_fftSize); 

            if (_zeroPhaseWindowing)
            {
                // "Zero Phase" windowing
                // Through clever reordering, phase of ouput coefficients will relate to the
                // center of the window
                //_
                // \_                   _/
                //   \                 /
                //    \               /
                //     \_____________/____
                int center = (_windowSize - 1) / 2; // position of center bin
                int nLeft = _windowSize - center;
                for (int i = 0; i < nLeft; ++i)
                    fftData[i] = segment[center + i] * _window[center + i];

                int nPadding = _fftSize - _windowSize;
                for (int i = 0; i < nPadding; ++i)
                    fftData[nLeft + i] = 0.0f;

                for (int i = 0; i < center; ++i)
                    fftData[nLeft + nPadding + i] = segment[i] * _window[i];
            }
            else
            {
                // "Normal" windowing
                // Phase of ouput coefficient will relate to the start of the buffer
                //      _
                //    _/ \_
                //   /     \
                //  /       \
                //_/         \____________

                // fill FFT buffer and multiply by window
                for (int i = 0; i < _windowSize; ++i)
                    fftData[i] = segment[i] * _window[i];

                // zero-padding
                for (int i = _windowSize; i < _fftSize; ++i)
                    fftData[i] = 0.0f;
            }

            // perform forward FFT on this slice
            FFT!float(fftData[0.._fftSize], FFTDirection.FORWARD);
        }

        return _segmenter.feed(x, &processSegment); // TODO: not sure this doesn't allocate
    }

private:
    Segmenter!float _segmenter;
    bool _zeroPhaseWindowing;
    int _fftSize;        // in samples

    Window!float _window;
    int _windowSize;     // in samples
}
