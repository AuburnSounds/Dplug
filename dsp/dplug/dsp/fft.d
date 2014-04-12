// See licenses/UNLICENSE.txt
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
void FFT(T)(Complex!T[] buffer, FFTDirection direction)
{
    size_t size = buffer.length;
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

/// From a signal, output short term windowed data.
/// Variable overlap.
/// Introduces approximately windowSize/2 samples delay.
struct ShortTermAnalyzer
{
    size_t segmentSize() const
    {
        return _segmentSize;
    }

    size_t analysisPeriod() const
    {
        return _analysisPeriod;
    }

    /// To call at initialization and whenever samplerate changes.
    /// segmentSize = size of sound segments, expressed in samples.
    /// analysisPeriod = period of analysis results, allow to be more precise frequentially, expressed in samples.    
    void initialize(size_t segmentSize, size_t analysisPeriod)
    {
        assert(analysisPeriod <= segmentSize); // no support for zero overlap

        // 1-sized FFT support
        if (analysisPeriod == 0)
            analysisPeriod = 1;

        _segmentSize = segmentSize;
        _analysisPeriod = analysisPeriod;

        // clear input delay
        _audioBuffer.length = _segmentSize;
        _index = 0;
    }

    // Push one sample, eventually call the delegate to process a segment.
    bool feed(float x, scope void delegate(float[] segment) processSegment)
    {
        _audioBuffer[_index] = x;
        _index = _index + 1;
        if (_index >= _segmentSize)
        {
            // process segment
            processSegment(_audioBuffer[0.._segmentSize]);

            // rotate buffer
            {
                size_t samplesToDrop = _analysisPeriod;
                assert(0 < samplesToDrop && samplesToDrop <= _segmentSize);
                size_t remainingSamples = _segmentSize - samplesToDrop;

                // TODO: use ring buffer instead of copy?
                memmove(_audioBuffer.ptr, _audioBuffer.ptr + samplesToDrop, float.sizeof * remainingSamples);
                _index = remainingSamples;

            }
            return true;
        }
        else 
            return false;
    }


private:
    float[] _audioBuffer;    
    size_t _segmentSize;     // in samples
    size_t _analysisPeriod; // in samples
    size_t _index;
}


/// From short term windowed data, output the summed signal.
/// Segments can be irregular and have different size.
struct ShortTermReconstruction
{
    /// maxSimultSegments is the maximum number of simulatneously summed samples.
    /// maxSegmentLength in samples
    void initialize(size_t maxSimultSegments, size_t maxSegmentLength)
    {
        _maxSimultSegments = maxSimultSegments;
        _desc.length = maxSimultSegments;
        for (int i = 0; i < _maxSimultSegments; ++i)
        {
            _desc[i].playOffset = 0;
            _desc[i].length = 0;
            _desc[i].buffer.length = maxSegmentLength;
        }
    }

    // Copy segment to a free slot, and start its summing.
    // The first sample of this segment will be played at next() call.
    void startSegment(float[] newSegment)
    {
        assert(newSegment.length <= _maxSegmentLength);
        
        for (int i = 0; i < _maxSimultSegments; ++i)
        {
            if (!_desc[i].active())
            {
                size_t len = newSegment.length;
                _desc[i].playOffset = 0;
                _desc[i].length = len;
                _desc[i].buffer[0..len] = newSegment[]; // copy segment
                return;
            }
        }

        assert(false);
    }

    // Get next sample, update segment statuses.
    float next()
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
        size_t playOffset; // offset in this segment
        size_t length; // length in this segment
        float[] buffer; // 0..length => data for this segment

        bool active() pure const nothrow
        {
            return playOffset >= length;
        }
    }
    size_t _maxSimultSegments;
    size_t _maxSegmentLength;
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
    void initialize(size_t windowSize, size_t fftSize, size_t analysisPeriod, WindowType windowType, bool zeroPhaseWindowing, bool correctWindowLoss)
    {
        assert(isPowerOf2(fftSize));
        assert(fftSize >= windowSize);

        _zeroPhaseWindowing = zeroPhaseWindowing;
        
        _fftSize = fftSize;

        _window.initialize(windowType, windowSize);
        _windowSize = windowSize;

        _analyzer.initialize(windowSize, analysisPeriod);
    }

    
private:
    ShortTermAnalyzer _analyzer;
    bool _zeroPhaseWindowing;
    size_t _fftSize;        // in samples

    Window!float _window;
    size_t _windowSize;     // in samples
    

    bool feed(float x, Complex!float[] fftData)
    {    
        void processSegment(float[] segment)
        {
            int windowSize = _windowSize;
            assert(segment.length == _windowSize);

            fftData.length = _fftSize;

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
                size_t center = (_windowSize - 1) / 2; // position of center bin
                size_t nLeft = _windowSize - center;
                for (size_t i = 0; i < nLeft; ++i)
                    fftData[i] = segment[center + i] * _window[center + i];

                size_t nPadding = _fftSize - _windowSize;
                for (size_t i = 0; i < nPadding; ++i)
                    fftData[nLeft + i] = 0.0f;

                for (size_t i = 0; i < center; ++i)
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
                for (size_t i = 0; i < _windowSize; ++i)
                    fftData[i] = segment[i] * _window[i];

                // zero-padding
                for (size_t i = _windowSize; i < _fftSize; ++i)
                    fftData[i] = 0.0f;
            }

            // perform forward FFT on this slice
            FFT!float(fftData[0.._fftSize], FFTDirection.FORWARD);
        }

        return _analyzer.feed(x, &processSegment); // TODO: not sure this doesn't allocate
    }
}
