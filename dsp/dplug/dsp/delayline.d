/**
* Delay-line implementation.
* Copyright: Guillaume Piolat 2015-2025.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.dsp.delayline;

import core.stdc.string;

import dplug.core.nogc;
import dplug.core.math;
import dplug.core.vec;

import inteli.emmintrin;

/// Allow to sample signal back in time.
/// This delay-line has a twin write index, so that the read pointer 
/// can read a contiguous memory area.
///
/// ┌────────────────────────────────────────────────────────────────────────────────────┐
/// │    │ _index │                  │ readPointer = _index + half size │                │
/// └────────────────────────────────────────────────────────────────────────────────────┘
///
/// A Delayline is initialized with an internal length of N = numSamples,
/// in order to do a simple delay of N samples.
/// Internally, the delayline actually has 2 x nextPow2(N + 1) samples of storage.
/// So typically a delay line is initialized with maxDelaySamples + maxFrames (if buffering is used)..
///
/// Example:
/// ---
/// import dplug.dsp.delayline;
///
/// void delaySampleBySample() // slower method, but easier to be correct
/// {
///     Delayline!float delayline;
///     delayline.initialize(maxPossibleDelay);
///     for (int n = 0; n < frames; ++n)
///     {
///         delayline.feedSample(input[n]);
///
///         // desiredDelay = 0 would be the sample we just fed
///         // the delayline with.
///         // desiredDelay = maxPossibleDelay for the oldest
///         delayed[n] = delayline.fullSample(desiredDelay); 
///     }
/// }
///
/// void delayUsingReadPointer() // fastest method, but more confusing
/// {
///     Delayline!float delayline;
///     delayline.initialize(maxFrames + maxPossibleDelay);
///     delayline.feedBuffer(input.ptr, frames);
///     const(float)* readPtr = d.readPointer() - desiredDelay - frames + 1;
///     delayed[0..frames] = readPtr[0..frames];
///     // Caveats: frames <= maxFrames and desiredDelay <= maxPossibleDelay.
/// }
/// ---
struct Delayline(T)
{
public:
nothrow:
@nogc:

    /// Initialize the delay line.
    /// Clear state. 
    /// Can delay up to `numSamples` samples.
    /// Equivalent: `resize`.
    void initialize(int numSamples)
    {
        resize(numSamples);
    }

    ~this()
    {
        _data.reallocBuffer(0);
    }

    @disable this(this);

    /// Resize the delay line. Can delay up to count samples.
    /// The state is cleared.
    void resize(int numSamples)
    {
        if (numSamples < 0)
            assert(false);

        // Over-allocate to support POW2 delaylines.
        // This wastes memory but allows delay-line of 
        // length 0 without tests.
        // The reason to add +1 here is that fundamentally 
        // in a delay line of "length = 1", in doubt
        // we want to keep track of the current sample
        // (at delay 0) and the former one (at delay 1). 
        // That's two samples.

        int toAllocate = nextPow2HigherOrEqual(numSamples + 1);
        _data.reallocBuffer(toAllocate * 2);
        _half = toAllocate;
        _indexMask = toAllocate - 1;
        _numSamples = numSamples;
        _index = _indexMask;
        _data[] = 0;
    }

    /// Resize the delay line, keeping existing history if any.
    /// Only newly added samples get cleared to 0.0.
    /// Can be used to resize up or down a delay without 
    /// loosing the history.
    void resizeKeep(int numSamples)
    {
        if (numSamples < 0)
            assert(false);

        // Existing data in pow2 buffer?
        int E = _half;
        {
            // content must be the same
            T[] src0 = _data[0..E];
            T[] src1 = _data[E..E*2];
            assert(src0[] == src1[]);
        }

        int toAllocate = nextPow2HigherOrEqual(numSamples + 1);

        if (toAllocate <= E)
        {
            // In case of reducing length of delay, since
            // it would be hard to keep proper history, 
            // simply lie and keep the larger buffer.
            _numSamples = numSamples;
            return;
        }
        
        _half = toAllocate;
        _data.reallocBuffer(toAllocate * 2);        
        _indexMask = toAllocate - 1;
        _numSamples = numSamples;

        // _index can be anywhere
        if (E == 0)
            _index = _indexMask;

        assert (E < _half);
        {
            // We want to preserve the two history buffers,
            // 0..E And E..E*2
            // index doesn't need to move, since the oldest
            // data (to be zeroed) is at its right.
            T[] src1  = _data[E..E*2];
            T[] zero0 = _data[E.._half];
            T[] dst1  = _data[_half.._half+E];
            T[] zero1 = _data[_half+E.._half*2];            
            memmove(dst1.ptr, src1.ptr, E * T.sizeof);
            zero0[] = 0;
            zero1[] = 0;
        }

    }
    /// Adds a new sample at end of delay.
    void feedSample(T incoming) pure
    {
        _index = (_index + 1) & _indexMask;
        _data.ptr[_index] = incoming;
        _data.ptr[_index + _half] = incoming;
    }


    /// Random access sampling of the delay-line at integer points.
    /// Delay 0 = last entered sample with feed().
    T sampleFull(int delay) pure
    {
        assert(delay >= 0);
        return readPointer()[-delay];
    }

    /// Random access sampling of the delay-line at integer points, extract a time slice.
    /// Delay 0 = last entered sample with feed().
    void sampleFullBuffer(int delayOfMostRecentSample, T* outBuffer, int frames) pure
    {
        assert(delayOfMostRecentSample >= 0);
        const(T*) p = readPointer();
        const(T*) source = &readPointer[-delayOfMostRecentSample - frames + 1];
        size_t numBytes = frames * T.sizeof;
        memcpy(outBuffer, source, numBytes);
    }

    static if (is(T == float) || is(T == double))
    {
        // PERF SOUND: tricky to test, but keeping delay in double
        // for Delayline!double in all sampling mode should bring 
        // a small sound and performance, like it had for 
        // `sampleLinear`.

        /// Random access sampling of the delay-line with linear interpolation.
        /// Note that will the HF rollout of linear interpolation, it can 
        /// often sound quite good in 44.1 kHz
        T sampleLinear(T delay) pure const
        {
            assert(delay > 0);
            int iPart;
            T fPart;
            decomposeFractionalDelay!T(delay, iPart, fPart);
            const(T)* pData = readPointer();
            T x0  = pData[iPart];
            T x1  = pData[iPart + 1];
            return fPart * x1 + (1 - fPart) * x0;
        }

        /// Random access sampling of the delay-line with a 3rd order polynomial.
        T sampleHermite(float delay) pure const
        {
            assert(delay > 1);
            int iPart;
            float fPart;
            decomposeFractionalDelay!float(delay, iPart, fPart);
            const(T)* pData = readPointer();
            T xm1 = pData[iPart-1];
            T x0  = pData[iPart  ];
            T x1  = pData[iPart+1];
            T x2  = pData[iPart+2];
            return hermiteInterp!T(fPart, xm1, x0, x1, x2);
        }

        /// Third-order spline interpolation
        /// http://musicdsp.org/showArchiveComment.php?ArchiveID=62
        T sampleSpline3(float delay) pure const
        {
            assert(delay > 1);
            int iPart;
            float fPart;
            decomposeFractionalDelay!float(delay, iPart, fPart);
            assert(fPart >= 0.0f);
            assert(fPart <= 1.0f);
            const(T)* pData = readPointer();
            T L1 = pData[iPart-1];
            T L0  = pData[iPart  ];
            T H0  = pData[iPart+1];
            T H1  = pData[iPart+2];

            return L0 + 0.5f *
                fPart*(H0-L1 +
                fPart*(H0 + L0*(-2) + L1 +
                fPart*( (H0 - L0)*9 + (L1 - H1)*3 +
                fPart*((L0 - H0)*15 + (H1 - L1)*5 +
                fPart*((H0 - L0)*6 + (L1 - H1)*2 )))));
        }

        /// 4th order spline interpolation
        /// http://musicdsp.org/showArchiveComment.php?ArchiveID=60
        T sampleSpline4(float delay) pure const
        {
            assert(delay > 2);
            int iPart;
            float fPart;
            decomposeFractionalDelay!float(delay, iPart, fPart);

            align(16) __gshared static immutable float[8][5] MAT = 
            [
                [  2.0f / 24, -16.0f / 24,   0.0f / 24,   16.0f / 24,  -2.0f / 24,   0.0f / 24, 0.0f, 0.0f ],
                [ -1.0f / 24,  16.0f / 24, -30.0f / 24,   16.0f / 24,  -1.0f / 24,   0.0f / 24, 0.0f, 0.0f ],
                [ -9.0f / 24,  39.0f / 24, -70.0f / 24,   66.0f / 24, -33.0f / 24,   7.0f / 24, 0.0f, 0.0f ],
                [ 13.0f / 24, -64.0f / 24, 126.0f / 24, -124.0f / 24,  61.0f / 24, -12.0f / 24, 0.0f, 0.0f ],
                [ -5.0f / 24,  25.0f / 24, -50.0f / 24,   50.0f / 24, -25.0f / 24,   5.0f / 24, 0.0f, 0.0f ]
            ];

            __m128 pFactor0_3 = _mm_setr_ps(0.0f, 0.0f, 1.0f, 0.0f);
            __m128 pFactor4_7 = _mm_setzero_ps();

            __m128 XMM_fPart = _mm_set1_ps(fPart);
            __m128 weight = XMM_fPart;
            pFactor0_3 = _mm_add_ps(pFactor0_3, _mm_load_ps(&MAT[0][0]) * weight);
            pFactor4_7 = _mm_add_ps(pFactor4_7, _mm_load_ps(&MAT[0][4]) * weight);
            weight = _mm_mul_ps(weight, XMM_fPart);
            pFactor0_3 = _mm_add_ps(pFactor0_3, _mm_load_ps(&MAT[1][0]) * weight);
            pFactor4_7 = _mm_add_ps(pFactor4_7, _mm_load_ps(&MAT[1][4]) * weight);
            weight = _mm_mul_ps(weight, XMM_fPart);
            pFactor0_3 = _mm_add_ps(pFactor0_3, _mm_load_ps(&MAT[2][0]) * weight);
            pFactor4_7 = _mm_add_ps(pFactor4_7, _mm_load_ps(&MAT[2][4]) * weight);
            weight = _mm_mul_ps(weight, XMM_fPart);
            pFactor0_3 = _mm_add_ps(pFactor0_3, _mm_load_ps(&MAT[3][0]) * weight);
            pFactor4_7 = _mm_add_ps(pFactor4_7, _mm_load_ps(&MAT[3][4]) * weight);
            weight = _mm_mul_ps(weight, XMM_fPart);
            pFactor0_3 = _mm_add_ps(pFactor0_3, _mm_load_ps(&MAT[4][0]) * weight);
            pFactor4_7 = _mm_add_ps(pFactor4_7, _mm_load_ps(&MAT[4][4]) * weight);

            float[8] pfactor = void;
            _mm_storeu_ps(&pfactor[0], pFactor0_3); 
            _mm_storeu_ps(&pfactor[4], pFactor4_7);

            T result = 0;
            const(T)* pData = readPointer();
            foreach(n; 0..6)
                result += pData[iPart-2 + n] * pfactor[n];
            return result;
        }
    }

    /// Adds several samples at end of delay.
    void feedBuffer(const(T)[] incoming) pure
    {
        int N = cast(int)(incoming.length);

        // Note: it is legal to overfeed the delayline, in case of large 
        // maxFrames for example. Though this is normally unexpected, but it's
        // useful when using silence detection.

        if (N > _numSamples + 1)
        {
            N = _numSamples + 1;
            incoming = incoming[$-N .. $];
        }

        // remaining samples before end of delayline
        int remain = _indexMask - _index;

        if (N == 0)
        {
            return;
        }
        else if (N <= remain)
        {
            memcpy( &_data[_index + 1], incoming.ptr, N * T.sizeof );
            memcpy( &_data[_index + 1 + _half], incoming.ptr, N * T.sizeof );
            _index += N;
        }
        else
        {
            if (remain != 0)
            {
                memcpy(_data.ptr + (_index+1), incoming.ptr, remain * T.sizeof );
                memcpy(_data.ptr + (_index+1) + _half, incoming.ptr, remain * T.sizeof);
            }
            size_t numBytes = (N - remain) * T.sizeof;
            memcpy( _data.ptr, incoming.ptr + remain, numBytes);
            memcpy( _data.ptr + _half, incoming.ptr + remain, numBytes);
            _index = (_index + N) & _indexMask;
        }
    }
    ///ditto
    void feedBuffer(const(T)* incoming, size_t count) pure
    {
        feedBuffer(incoming[0..count]);
    }

    /// Returns: A pointer which allow to get delayed values.
    ///    readPointer()[0] is the last samples fed, 
    ///    readPointer()[-1] is the penultimate.
    /// Warning: it goes backwards, increasing delay => decreasing addressed.
    const(T)* readPointer() pure const
    {
        return _data.ptr + _index + _half;
    }

    /// Combined feed + sampleFull.
    /// Uses the delay line as a fixed delay of count samples.
    ///
    /// This is normally very rare to need this vs separate `sampleXXX` and
    /// `feedSample`.
    T nextSample(T incoming) pure
    {
        feedSample(incoming);
        return sampleFull(_numSamples);
    }

    /// Combined feed + sampleFull.
    /// Uses the delay line as a fixed delay of count samples.
    ///
    /// Note: input and output may overlap. 
    ///       If this was ever optimized, this should preserve that property.
    ///
    /// This is normally very rare to need this vs separate `sampleXXX` and
    /// `feedBuffer`.
    void nextBuffer(const(T)* input, T* output, int frames) pure
    {
        for(int i = 0; i < frames; ++i)
            output[i] = nextSample(input[i]);
    }

private:
    T[] _data;
    int _index;
    int _half; // half the size of the data
    int _indexMask;
    int _numSamples;

    void decomposeFractionalDelay(T)(T delay, 
                                     out int outIntegerPart, 
                                     out T outFloatPart) pure const
    {
        // Float index can yield suprising low precision with 
        // interpolation. So precision is upped to double in order to
        // have a precise fractional part in all cases.

        int offset = cast(int)(_data.length);
        double doubleDelayMinus = cast(double)(-delay);
        int iPart = cast(int)(doubleDelayMinus + offset);
        iPart -= offset;
        T fPart = cast(T)(doubleDelayMinus - iPart);
        assert(fPart >= 0);
        assert(fPart <= 1);
        outIntegerPart = iPart;
        outFloatPart = fPart;
    }
}

unittest
{
    Delayline!float line;
    line.initialize(0); // should be possible
    assert(line.nextSample(1) == 1);
    Delayline!double line2;

    Delayline!float line3;
    line3.initialize(2);
    assert(line3.nextSample(1) == 0);
    assert(line3.nextSample(2) == 0);
    assert(line3.nextSample(3) == 1);
    assert(line3.nextSample(42) == 2);
    assert(line3.sampleFull(0) == 42);
    assert(line3.sampleFull(1) == 3);
    assert(line3.sampleLinear(0.5f) == (3.0f + 42.0f) * 0.5f);
}

// See Issue #607, usability of feedBuffer.
unittest
{
    float[256] zeroes;
    float[256] data;
    float[256] delayed;
    foreach (n; 0..256)
    {
        data[n] = cast(float)n;
        zeroes[n] = 0.0f;
    }

    // Delay of 256 samples, using `nextBuffer`.
    {
        Delayline!float d;
        d.initialize(256);
        d.nextBuffer(data.ptr, delayed.ptr, 256);
        assert(delayed == zeroes);
        d.nextBuffer(zeroes.ptr, delayed.ptr, 256);
        assert(delayed == data);
    }

    // It should be possible to use feedBuffer to delay of 256 amount too.
    {
        int desiredDelay = 256;
        Delayline!float d;
        d.initialize(256);
        int frames = 256;
        d.feedBuffer(data.ptr, frames);
        const(float)* readPtr = d.readPointer() - desiredDelay - frames + 1;
        delayed[0..frames] = readPtr[0..frames];
        assert(delayed == zeroes);

        d.feedBuffer(zeroes.ptr, frames);
        readPtr = d.readPointer() - desiredDelay - frames + 1;
        delayed[0..frames] = readPtr[0..frames];
        assert(delayed == data);
    }
}

// Issue 846, feeding a buffer larger than the delay line length.
// It's useful for testing effects in isolation, in a way that may
// have large maxFrames.
unittest
{
    int[256] data;
    for (int n = 0; n < 256; ++n)
        data[n] = n;
    Delayline!int d;
    d.initialize(128);
    d.feedBuffer(data[0..256]); // now work, only data[128..256] considered
    for (int n = 0; n < 128; ++n)
        assert(d.sampleFull(n) == 255 - n);
}

// Resize-keep
unittest
{
    int[] D = [8, 8, 8, 4, 5, 6];
    Delayline!int d;
    d.initialize(2);

    d.feedSample(1);
    d.feedSample(2);
    d.feedSample(3);
    assert(d.sampleFull(0) == 3);
    assert(d.sampleFull(1) == 2);
    assert(d.sampleFull(2) == 1);

    d.feedBuffer(D);
    assert(d.sampleFull(0) == 6);
    assert(d.sampleFull(1) == 5);
    assert(d.sampleFull(2) == 4);
    
    d.resizeKeep(10);
    d.feedSample(7);
    d.feedSample(8);
    d.feedSample(9);
    d.feedSample(10);
    assert(d.sampleFull(0) == 10);
    assert(d.sampleFull(1) == 9);
    assert(d.sampleFull(2) == 8);
    assert(d.sampleFull(3) == 7);
    assert(d.sampleFull(4) == 6);
    assert(d.sampleFull(5) == 5);
    for (int n = 6; n <= 10; ++n)
        assert(d.sampleFull(n) == 0);
    
    // resize down
    d.resizeKeep(3);
    assert(d.sampleFull(0) == 10);
    assert(d.sampleFull(1) == 9);
    assert(d.sampleFull(2) == 8);
    assert(d.sampleFull(3) == 7);
}

/// Simplified delay line, mostly there to compensate latency manually.
/// No interpolation and no delay change while playing.
struct SimpleDelay(T)
{
public:
nothrow:
@nogc:

    enum MAX_CHANNELS = 2; // current limitation

    void initialize(int numChans, int maxFrames, int delayInSamples)
    {
        assert(numChans <= MAX_CHANNELS);
        assert(_delayInSamples >= 0);
        _delayInSamples = delayInSamples;
        _numChans = numChans;
        if (_delayInSamples > 0)
        {
            for (int chan = 0; chan < _numChans; ++chan)
            {
                _delay[chan].initialize(maxFrames + delayInSamples + 1); // not sure if the +1 is still needed, or why. It is part of culture now.
            }
        }
    }

    /// Just a reminder, to compute this processor latency.
    static int latencySamples(int delayInSamples) pure
    {
        return delayInSamples;
    }   

    /// Process samples, single channel version.
    void nextBufferMono(const(T)* input, T* output, int frames)
    {
        assert(_numChans == 1);
        const(T)*[1] inputs;
        T*[1] outputs;

        inputs[0] = input;
        outputs[0] = output;
        nextBuffer(inputs.ptr, outputs.ptr, frames);
    }
    ///ditto
    void nextBufferMonoInPlace(T* inoutSamples, int frames)
    {
        assert(_numChans == 1);
        if  (_delayInSamples == 0)
            return;
        const(T)*[1] inputs;
        T*[1] outputs;
        inputs[0] = inoutSamples;
        outputs[0] = inoutSamples;
        nextBuffer(inputs.ptr, outputs.ptr, frames);
    }

    /// Process samples, multichannel version.
    /// Note: input and output buffers can overlap, or even be the same.
    void nextBuffer(const(T*)* inputs, T** output, int frames)
    {
        for (int chan = 0; chan < _numChans; ++chan)
        {
            if (_delayInSamples == 0)
            {
                // Since the two can overlap, use memmove.
                memmove(output[chan], inputs[chan], frames * T.sizeof);
            }
            else
            {
                 _delay[chan].feedBuffer(inputs[chan], frames);
                 const(T)* readPtr = _delay[chan].readPointer() - _delayInSamples - frames + 1;
                 output[chan][0..frames] = readPtr[0..frames];
            }
        }
    }
    ///ditto
    void nextBufferInPlace(T** inoutSamples, int frames)
    {
        if  (_delayInSamples == 0)
            return;
        nextBuffer(inoutSamples, inoutSamples, frames);
    }

private:
    int _numChans;
    int _delayInSamples;
    Delayline!T[MAX_CHANNELS] _delay;
}

/// A delay that resyncs latency of two signals when it's not clear which has 
/// more latency. This is a building block for internal latency compensation.
/// 
/// Input:                                              |         |
///       A with latency LA, B with latency LB          | A       | B
///                                                     V         V
///                                        ____________LatencyResync___________
///                                       |  Delayline of L1 = max(LB - LA, 0) |
///                                       |  Delayline of L2 = max(LA - LB, 0) |
///                                       |____________________________________|
///                                                     |         |
/// Output:                                             |         |
///        Two aligned signal, latency = max(LA, LB)    | A       | B
///                                                     V         V
struct LatencyResync(T)
{
public:
nothrow:
@nogc:
    void initialize(int numChans, int maxFrames, int latencySamplesA, int latencySamplesB)
    {
        int L1 = latencySamplesB - latencySamplesA;
        int L2 = latencySamplesA - latencySamplesB;
        if (L1 < 0) L1 = 0;        
        if (L2 < 0) L2 = 0;
        _delayA.initialize(numChans, maxFrames, L1);
        _delayB.initialize(numChans, maxFrames, L2);
    }

    /// Just a reminder, to compute this processor latency.
    static int latencySamples(int latencySamplesA, int latencySamplesB)
    {
        return latencySamplesA > latencySamplesB ? latencySamplesA : latencySamplesB;
    }

    /// Process mono inputs, help function.
    void nextBufferMono(const(T)* inputA, const(T)* inputB, T* outputA, T* outputB, int frames)
    {
        _delayA.nextBufferMono(inputA, outputA, frames);
        _delayB.nextBufferMono(inputB, outputB, frames);
    }
    ///ditto
    void nextBufferMonoInPlace(T* inoutASamples, T* inoutBSamples, int frames)
    {
        _delayA.nextBufferMonoInPlace(inoutASamples, frames);
        _delayB.nextBufferMonoInPlace(inoutBSamples, frames);
    }

    /// Process buffers. A and B signal gets aligned with regards to their relative latency.
    void nextBuffer(const(T)** inputsA, const(T)** inputsB, T** outputsA, T** outputsB, int frames)
    {
        _delayA.nextBuffer(inputsA, outputsA, frames);
        _delayB.nextBuffer(inputsB, outputsB, frames);
    }
    ///ditto
    void nextBufferInPlace(T** inoutASamples, T** inoutBSamples, int frames)
    {
        _delayA.nextBufferInPlace(inoutASamples, frames);
        _delayB.nextBufferInPlace(inoutBSamples, frames);
    }

private:
    SimpleDelay!T _delayA;
    SimpleDelay!T _delayB;
}

unittest
{
    {
        double[4] A = [0.0, 3, 0, 0];
        double[4] B = [0.0, 0, 2, 0];
        LatencyResync!double lr;
        int numChans = 1;
        int maxFrames = 4;
        int latencyA = 1;
        int latencyB = 2;
        lr.initialize(numChans, maxFrames, latencyA, latencyB);
        lr.nextBufferMono(A.ptr, B.ptr, A.ptr, B.ptr, 4);
        assert(A == [0.0, 0, 3, 0]);
        assert(B == [0.0, 0, 2, 0]);
    }

    {
        double[4] A = [0.0, 0, 3, 9];
        double[4] B = [2.0, 0, 0, 8];
        LatencyResync!double lr;
        int numChans = 1;
        int maxFrames = 4;
        int latencyA = 2;
        int latencyB = 0;
        lr.initialize(numChans, maxFrames, latencyA, latencyB);
        lr.nextBufferMonoInPlace(A.ptr, B.ptr, 3);
        assert(A == [0.0, 0, 3, 9]);
        assert(B == [0.0, 0, 2, 8]);
    }
}