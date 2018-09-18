/**
High-level interfaces for providing FFT analysis, real FFT, and resynthesis from grains.

Copyright: Guillaume Piolat 2015.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.dsp.fft;

import core.stdc.string;

import std.math;

import dplug.dsp.window;
import dplug.core.math;
import dplug.core.complex;
import dplug.core.vec;
import pfft.pfft;


enum FFTDirection
{
    FORWARD = 0,
    REVERSE = 1
}

/// Perform in-place FFT.
/// Equivalent to `std.numeric.fft`, but this one is nothrow @nogc.
void forwardFFT(T)(BuiltinComplex!T[] buffer) nothrow @nogc
{
    FFT_internal!(T, FFTDirection.FORWARD)(buffer);
}

/// Perform in-place inverse FFT.
/// Equivalent to `std.numeric.inverseFft`, but this one is nothrow @nogc.
void inverseFFT(T)(BuiltinComplex!T[] buffer) nothrow @nogc
{
    FFT_internal!(T, FFTDirection.REVERSE)(buffer);
}

// PERF: use pfft instead would be much faster
private void FFT_internal(T, FFTDirection direction)(BuiltinComplex!T[] buffer) pure nothrow @nogc
{
    int size = cast(int)(buffer.length);
    assert(isPowerOfTwo(size));
    int m = iFloorLog2(size);

    BuiltinComplex!T* pbuffer = buffer.ptr;

    // do the bit reversal
    int i2 = cast(int)size / 2;
    int j = 0;
    for (int i = 0; i < size - 1; ++i)
    {
        if (i < j)
        {
            auto tmp = pbuffer[i];
            pbuffer[i] = pbuffer[j];
            pbuffer[j] = tmp;
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
    BuiltinComplex!T c = -1+0i;
    int l2 = 1;
    for (int l = 0; l < m; ++l)
    {
        int l1 = l2;
        l2 = l2 * 2;
        BuiltinComplex!T u = 1+0i;
        for (int j2 = 0; j2 < l1; ++j2)
        {
            int i = j2;
            while (i < size)
            {
                int i1 = i + l1;
                BuiltinComplex!T t1 = u * pbuffer[i1];
                pbuffer[i1] = pbuffer[i] - t1;
                pbuffer[i] += t1;
                i += l2;
            }
            u = u * c;
        }

        T newImag = sqrt((1 - c.re) / 2);
        static if (direction == FFTDirection.FORWARD)
            newImag = -newImag;
        T newReal = sqrt((1 + c.re) / 2);
        c = newReal + 1.0fi * newImag;
    }

    // scaling when doing the reverse transformation, to avoid being multiplied by size
    static if (direction == FFTDirection.REVERSE)
    {
        T divider = 1 / cast(T)size;
        for (int i = 0; i < size; ++i)
        {
            pbuffer[i] = pbuffer[i] * divider;
        }
    }
}


// should operate the same as Phobos FFT
unittest
{
    import std.complex;
    import std.numeric: fft;

    bool approxEqualArrBuiltin(BuiltinComplex!double[] a, BuiltinComplex!double[] b) pure
    {
        foreach(i; 0..a.length)
        {
            if (!approxEqual(a[i].re, b[i].re))
                return false;
            if (!approxEqual(a[i].im, b[i].im))
                return false;
        }
        return true;
    }

    bool approxEqualArr(BuiltinComplex!double[] a, Complex!double[] b) pure
    {
        foreach(i; 0..a.length)
        {
            if (!approxEqual(a[i].re, b[i].re))
                return false;
            if (!approxEqual(a[i].im, b[i].im))
                return false;
        }
        return true;
    }

    BuiltinComplex!double[] A = [1+0i, 13-4i, 5-5i, 0+2i];
    Complex!double[] Abis = [Complex!double(1, 0), Complex!double(13, -4), Complex!double(5,-5), Complex!double(0,2)];
    Complex!double[] fftARef = fft(Abis);

    auto B = A.dup;
    forwardFFT!double(B);
    assert(approxEqualArr(B, fftARef));
    inverseFFT!double(B);
    assert(approxEqualArrBuiltin(B, A));
}

/// From a signal, output chunks of determined size, with optional overlap.
/// Introduces approximately windowSize/2 samples delay.
struct Segmenter(T)
{
nothrow:
@nogc:

    int segmentSize() pure const
    {
        return _segmentSize;
    }

    int analysisPeriod() pure const
    {
        return _analysisPeriod;
    }

    /// To call at initialization and whenever samplerate changes.
    /// segmentSize = size of sound segments, expressed in samples.
    /// analysisPeriod = period of analysis results, allow to be more precise frequentially, expressed in samples.
    void initialize(int segmentSize, int analysisPeriod)
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
    bool feed(T x, scope void delegate(T[] segment) nothrow @nogc processSegment = null)
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

                // FUTURE: use ring buffer instead of copy?
                memmove(_buffer.ptr, _buffer.ptr + samplesToDrop, T.sizeof * remainingSamples);
                _index = remainingSamples;

            }
            return true;
        }
        else
            return false;
    }

    /// Returns: Internal buffer.
    T[] buffer()
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
nothrow:
@nogc:
    /// maxSimultSegments is the maximum number of simulatneously summed samples.
    /// maxSegmentLength in samples
    void initialize(int maxSimultSegments, int maxSegmentLength)
    {
        _maxSegmentLength = maxSegmentLength;
        _maxSimultSegments = maxSimultSegments;
        _desc.reallocBuffer(maxSimultSegments);
        for (int i = 0; i < _maxSimultSegments; ++i)
        {
            _desc[i].playOffset = 0; // initially inactive
            _desc[i].length = 0;
            _desc[i].buffer = null;
            _desc[i].buffer.reallocBuffer(maxSegmentLength);
            //reallocBuffer(_desc[i].buffer, maxSegmentLength);
        } //)
    }

    ~this()
    {
        if (_desc !is null)
            for (int i = 0; i < _maxSimultSegments; ++i)
                _desc[i].buffer.reallocBuffer(0);
        _desc.reallocBuffer(0);
    }

    @disable this(this);

    // Copy segment to a free slot, and start its summing.
    // The first sample of this segment will be played at next() call if delay is 0.
    void startSegment(float[] newSegment, int delay = 0)
    {
        assert(newSegment.length <= _maxSegmentLength);
        int i = allocSegmentSlot();
        int len = cast(int)(newSegment.length);
        _desc[i].playOffset = -delay;
        _desc[i].length = len;
        _desc[i].buffer[0..len] = newSegment[]; // copy segment
    }

    // Same, but with the input being split into two slices A ~ B. This is a common case
    // when summing zero-phase windows in STFT analysis.
    void startSegmentSplitted(float[] segmentA, float[] segmentB, int delay = 0)
    {
        int i = allocSegmentSlot();
        int lenA = cast(int)(segmentA.length);
        int lenB = cast(int)(segmentB.length);
        assert(lenA + lenB <= _maxSegmentLength);

        _desc[i].playOffset = -delay;
        _desc[i].length = lenA + lenB;
        _desc[i].buffer[0..lenA] = segmentA[];         // copy segment part A
        _desc[i].buffer[lenA..lenA+lenB] = segmentB[]; // copy segment part B
    }

    float nextSample()
    {
        float sum = 0;
        foreach(ref desc; _desc)
        {
            if (desc.playOffset < desc.length)
            {
                if (desc.playOffset >= 0)
                    sum += desc.buffer[desc.playOffset];
                desc.playOffset += 1;
            }
        }
        return sum;
    }

    void nextBuffer(float* outAudio, int frames)
    {
        outAudio[0..frames] = 0;

        // Add each pending segment
        foreach(ref desc; _desc)
        {
            const int offset = desc.playOffset;
            const int len = desc.length;
            if (offset < len)
            {
                // Compute relative time event for the segment
                int startOfSegment = -offset;
                int endOfSegment = startOfSegment + len;

                // Compute the area in 0..frames we can playback the segment
                int startOfSumming = startOfSegment;
                if (startOfSumming < 0)
                    startOfSumming = 0;
                if (startOfSumming >= frames)
                    startOfSumming = frames;
                int endOfSumming = endOfSegment;
                if (endOfSumming >= frames)
                    endOfSumming = frames;

                int count = endOfSumming - startOfSumming;
                assert(count >= 0);

                const(float)* segmentData = desc.buffer.ptr + offset;

                // PERF: this can be optimized further
                for (int i = startOfSumming; i < endOfSumming; ++i)
                {
                    outAudio[i] += segmentData[i];
                }
                desc.playOffset = offset + frames;
            }
            // else disabled segment
        }
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

    int allocSegmentSlot()
    {
        for (int i = 0; i < _maxSimultSegments; ++i)
            if (!_desc[i].active())
                return i;
        assert(false); // maxSimultSegments too small, or usage error
    }
}

version = useRealFFT;

/// From a signal, output short term FFT data.
/// Variable overlap.
/// Introduces approximately windowSize/2 samples delay.
/// Uses a real FFT to gain some speed.
struct FFTAnalyzer(T)
{
public:

    /// To call at initialization and whenever samplerate changes.
    /// windowSize = size of window, expressed in samples
    /// fftSize = size of FFT. Must be power-of-two and >= windowSize. Missing samples are zero-padded in time domain.
    /// analysisPeriod = period of analysis results, allow to be more precise frequentially, expressed in samples.
    /// Basic overlap is achieved with windowSize = 2 * analysisPeriod
    /// if zeroPhaseWindowing = true, "zero phase" windowing is used
    /// (center of window is at first sample, zero-padding happen at center)
    void initialize(int windowSize,
                    int fftSize,
                    int analysisPeriod,
                    WindowDesc windowDesc,
                    bool zeroPhaseWindowing) nothrow @nogc
    {
        assert(isPowerOfTwo(fftSize));
        assert(fftSize >= windowSize);

        _zeroPhaseWindowing = zeroPhaseWindowing;

        _fftSize = fftSize;

        _window.initialize(windowDesc, windowSize);
        _windowSize = windowSize;

        // account for window shape
        _scaleFactor = fftSize / _window.sumOfWindowSamples();

        // account for overlap
        _scaleFactor *= cast(float)(analysisPeriod) / windowSize;

        _segmenter.initialize(windowSize, analysisPeriod);

        version(useRealFFT)
        {
            _timeData.reallocBuffer(fftSize);
            _rfft.initialize(fftSize);
        }
    }

    ~this()
    {
        version(useRealFFT)
        {
            _timeData.reallocBuffer(0);
        }
    }

    version(useRealFFT)
    {
        /// Gets the RFFT object which allows to perform efficient incverse FFT with the same pre-computed tables.
        ref RFFT!T realFFT()
        {
            return _rfft;
        }
    }

    bool feed(float x, BuiltinComplex!T[] fftData) nothrow @nogc
    {
        void processSegment(T[] segment) nothrow @nogc
        {
            int windowSize = _windowSize;
            assert(segment.length == _windowSize);

            T scaleFactor = _scaleFactor;

            version(useRealFFT)
            {
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
                        _timeData[i] = (segment[center + i] * _window[center + i] * scaleFactor);

                    int nPadding = _fftSize - _windowSize;
                    for (int i = 0; i < nPadding; ++i)
                        _timeData[nLeft + i] = 0;

                    for (int i = 0; i < center; ++i)
                        _timeData[nLeft + nPadding + i] = (segment[i] * _window[i] * scaleFactor);
                }
                else
                {
                    // "Normal" windowing
                    // Phase of output coefficient will relate to the start of the buffer
                    //      _
                    //    _/ \_
                    //   /     \
                    //  /       \
                    //_/         \____________

                    // fill FFT buffer and multiply by window
                    for (int i = 0; i < _windowSize; ++i)
                        _timeData[i] = (segment[i] * _window[i] * scaleFactor);

                    // zero-padding
                    for (int i = _windowSize; i < _fftSize; ++i)
                        _timeData[i] = 0;
                }
            }
            else
            {

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
                        fftData[i] = (segment[center + i] * _window[center + i] * scaleFactor)+0i;

                    int nPadding = _fftSize - _windowSize;
                    for (int i = 0; i < nPadding; ++i)
                        fftData[nLeft + i] = 0+0i;

                    for (int i = 0; i < center; ++i)
                        fftData[nLeft + nPadding + i] = (segment[i] * _window[i] * scaleFactor)+0i;
                }
                else
                {
                    // "Normal" windowing
                    // Phase of output coefficient will relate to the start of the buffer
                    //      _
                    //    _/ \_
                    //   /     \
                    //  /       \
                    //_/         \____________

                    // fill FFT buffer and multiply by window
                    for (int i = 0; i < _windowSize; ++i)
                        fftData[i] = (segment[i] * _window[i] * scaleFactor)+0i;

                    // zero-padding
                    for (int i = _windowSize; i < _fftSize; ++i)
                        fftData[i] = 0+0i;
                }
            }

            // perform forward FFT on this slice
            version(useRealFFT)
            {
                // If you fail here, you are giving a larger slice than strictly necessary to FFTAnalyzer.
                // This can cause hard to find memory corruption if you read the slice one bin too far.
                // Give a slice with length of exactly _fftSize/2+1.
                assert(fftData.length == _fftSize/2+1, "FFTAnalyzer is given too large a slice");

                _rfft.forwardTransform(_timeData[], fftData[0.._fftSize/2+1]);
            }
            else
                forwardFFT!T(fftData[0.._fftSize]);
        }

        return _segmenter.feed(x, &processSegment);
    }

private:
    Segmenter!T _segmenter;
    bool _zeroPhaseWindowing;
    int _fftSize;        // in samples

    Window!T _window;
    int _windowSize;     // in samples

    T _scaleFactor; // account to the shape of the windowing function

    version(useRealFFT)
    {
        RFFT!T _rfft;
        T[] _timeData;
    }
}

unittest
{
    FFTAnalyzer!float a;
    a.initialize(1024, 2048, 512, WindowDesc(WindowType.hann, WindowAlignment.left), true);

    FFTAnalyzer!double b;
    b.initialize(1024, 2048, 512, WindowDesc(WindowType.hann, WindowAlignment.right), false);
}


/// Converts a normalized frequency to a FFT bin.
/// Params:
///     normalizedFrequency = Frequency in cycles per sample.
///     fftSize = Size of FFT.
/// Returns: Corresponding fractional bin.
float convertNormalizedFrequencyToFFTBin(float normalizedFrequency, int fftSize) nothrow @nogc
{
    return (normalizedFrequency * fftSize);
}

/// Converts a frequency to a FFT bin.
/// Returns: Corresponding fractional bin.
float convertFrequencyToFFTBin(float frequencyHz, float samplingRate, int fftSize) nothrow @nogc
{
    return (frequencyHz * fftSize) / samplingRate;
}

/// Converts a frequency to a FFT bin.
/// Returns: Corresponding fractional bin.
float convertFrequencyToFFTBinInv(float frequencyHz, float invSamplingRate, int fftSize) nothrow @nogc
{
    return (frequencyHz * fftSize) * invSamplingRate;
}

/// Converts a FFT bin to a frequency.
/// Returns: Corresponding center frequency.
float convertFFTBinToFrequency(float fftBin, int fftSize, float samplingRate) nothrow @nogc
{
    return (samplingRate * fftBin) / fftSize;
}

/// Converts a FFT bin to a frequency.
/// Returns: Corresponding center frequency.
float convertFFTBinToFrequencyInv(float fftBin, float invFFTSize, float samplingRate) nothrow @nogc
{
    return (samplingRate * fftBin) * invFFTSize;
}

/// Converts a FFT bin to a normalized frequency.
/// Params:
///     fftBin = Bin index in the FFT.
///     fftSize = Size of FFT.
/// Returns: Corresponding normalized frequency
float convertFFTBinToNormalizedFrequency(float fftBin, int fftSize) nothrow @nogc
{
    return fftBin / fftSize;
}


/// Converts a FFT bin to a normalized frequency.
/// Params:
///     fftBin = Bin index of the FFT.
///     invFFTSize = Inverse size of FFT.
/// Returns: Corresponding normalized frequency.
float convertFFTBinToNormalizedFrequencyInv(float fftBin, float invFFTSize) nothrow @nogc
{
    return fftBin * invFFTSize;
}

/// Perform a FFT from a real signal, saves up CPU.
struct RFFT(T)
{
public:
nothrow:
@nogc:

    void initialize(int length)
    {
        _length = length;
        _internal.initialize(length);

        int newAlignment = cast(int)_internal.alignment(length);

        // if the alignement changes, we can't reuse that buffer
        if (_alignment != -1 && _alignment != newAlignment)
        {
            _buffer.reallocBuffer(0, _alignment);
        }

        _buffer.reallocBuffer(length, newAlignment);
        _alignment = newAlignment;
    }

    ~this()
    {
        if (_buffer != null)
            _buffer.reallocBuffer(0, _alignment);
    }

    @disable this(this);

    void forwardTransform(const(T)[] timeData, BuiltinComplex!T[] outputBins)
    {
        _buffer[] = timeData[];

        // Perform real FFT
        _internal.rfft(_buffer);

        //_buffer[]  =0;
        // At this point, f contains:
        //    f destination array (frequency bins)
        //    f[0...length(x)/2] = real values,
        //    f[length(x)/2+1...length(x)-1] = imaginary values of coefficents 1...length(x)/2-1.
        // So we have to reshuffle them to have nice complex bins.
        int mid = _length/2;
        outputBins[0] = _buffer[0] + 0i;
        for(int i = 1; i < mid; ++i)
            outputBins[i] = _buffer[i] + 1i * _buffer[mid+i];
        outputBins[mid] = _buffer[mid] + 0i; // for length 1, this still works
    }

    /**
    * Compute the inverse FFT of the array. Perform post-scaling.
    *
    * Params:
    *    inputBins = Source arrays (N/2 + 1 frequency bins).
    *    timeData = Destination array (N time samples).
    *
    * Note:
    *    This transform has the benefit you don't have to conjugate the "mirrored" part of the FFT.
    *    Excess data in imaginary part of DC and Nyquist bins are ignored.
    */
    void reverseTransform(BuiltinComplex!T[] inputBins, T[] timeData)
    {
        // On inverse transform, scale down result
        T invMultiplier = cast(T)1 / _length;

        // Shuffle input frequency bins, and scale down.
        int mid = _length/2;
        for(int i = 0; i <= mid; ++i)
            _buffer[i] = inputBins[i].re * invMultiplier;
        for(int i = mid+1; i < _length; ++i)
            _buffer[i] = inputBins[i-mid].im * invMultiplier;

        // At this point, the format in f is:
        //          f [0...length(x)/2] = real values
        //          f [length(x)/2+1...length(x)-1] = negative imaginary values of coefficents 1...length(x)/2-1.
        // Which is suitable for the RealFFT algorithm.
        _internal.irfft(_buffer);

        // Perf: use scaling from pfft
        timeData[] = _buffer[];
    }

private:
    // Required alignment for RFFT buffers.
    int _alignment = -1;

    // pfft object
    Rfft!T _internal;

    // length of FFT
    int _length;

    // temporary buffer since pfft is in-place
    T[] _buffer;
}


unittest
{
    for (int i = 0; i < 16; ++i)
    {
        RFFT!float rfft;
        rfft.initialize(128);
        rfft.initialize(2048);
    }
}