/**
* Delay-line implementation.
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.delayline;

import core.stdc.string;

import dplug.core.nogc;
import dplug.core.math;
import dplug.core.vec;

/// Allow to sample signal back in time.
struct Delayline(T)
{
public:

    /// Initialize the delay line. Can delay up to count samples.
    void initialize(int numSamples) nothrow @nogc
    {
        resize(numSamples);
    }

    ~this() nothrow @nogc
    {
        _data.reallocBuffer(0);
    }

    @disable this(this);

    /// Resize the delay line. Can delay up to count samples.
    /// The state is cleared.
    void resize(int numSamples) nothrow @nogc
    {
        if (numSamples < 0)
            assert(false);

        // Over-allocate to support POW2 delaylines.
        // This wastes memory but allows delay-line of length 0 without tests.

        int toAllocate = nextPow2HigherOrEqual(numSamples + 1);
        _data.reallocBuffer(toAllocate);
        _indexMask = toAllocate - 1;
        _numSamples = numSamples;
        _index = _indexMask;
        _data[] = 0;
    }

    /// Combined feed + sampleFull.
    /// Uses the delay line as a fixed delay of count samples.
    T nextSample(T incoming) nothrow @nogc
    {
        feedSample(incoming);
        return sampleFull(_numSamples);
    }

    /// Combined feed + sampleFull.
    /// Uses the delay line as a fixed delay of count samples.
    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for(int i = 0; i < frames; ++i)
            output[i] = nextSample(input[i]);
    }

    /// Adds a new sample at end of delay.
    void feedSample(T incoming) nothrow @nogc
    {
        _index = (_index + 1) & _indexMask;
        _data[_index] = incoming;
    }

    /// Adds several samples at end of delay.
    void feedBuffer(const(T)[] incoming) nothrow @nogc
    {
        int N = cast(int)(incoming.length);

        // this buffer must be smaller than the delay line, 
        // else we may risk dropping samples immediately
        assert(N < _numSamples);

        // remaining samples before end of delayline
        int remain = _indexMask - _index;

        if (N <= remain)
        {
            memcpy( &_data[_index + 1], incoming.ptr, N * T.sizeof );
            _index += N;
        }
        else
        {
            memcpy( _data.ptr + (_index + 1), incoming.ptr, remain * T.sizeof );
            size_t numBytes = (N - remain) * T.sizeof;
            memcpy( _data.ptr, incoming.ptr + remain, numBytes);
            _index = (_index + N) & _indexMask;
        }
    }

    /// Random access sampling of the delay-line at integer points.
    /// Delay 0 = last entered sample with feed().
    T sampleFull(int delay) nothrow @nogc
    {
        assert(delay >= 0);
        return _data[(_index - delay) & _indexMask];
    }

    static if (is(T == float) || is(T == double))
    {
        /// Random access sampling of the delay-line with linear interpolation.
        T sampleLinear(float delay) nothrow @nogc
        {
            assert(delay > 0);
            float sampleLoc = (_index - delay) + 2 * _data.length;
            assert(sampleLoc >= 1);
            int iPart = cast(int)(sampleLoc);
            float fPart = cast(float)(sampleLoc - iPart);
            T x0  = _data[iPart       & _indexMask];
            T x1  = _data[(iPart + 1) & _indexMask];
            return lerp(x0, x1, fPart);
        }

        /// Random access sampling of the delay-line with a 3rd order polynomial.
        T sampleHermite(float delay) nothrow @nogc
        {
            assert(delay > 1);
            float sampleLoc = (_index - delay) + 2 * _data.length;
            assert(sampleLoc >= 1);
            int iPart = cast(int)(sampleLoc);
            float fPart = cast(float)(sampleLoc - iPart);
            assert(fPart >= 0.0f);
            assert(fPart <= 1.0f);
            T xm1 = _data[(iPart - 1) & _indexMask];
            T x0  = _data[ iPart      & _indexMask];
            T x1  = _data[(iPart + 1) & _indexMask];
            T x2  = _data[(iPart + 2) & _indexMask];
            return hermite!T(fPart, xm1, x0, x1, x2);
        }

        /// Third-order splice interpolation
        /// http://musicdsp.org/showArchiveComment.php?ArchiveID=62
        T sampleSpline3(float delay)
        {
            assert(delay > 1);
            float sampleLoc = (_index - delay) + 2 * _data.length;
            assert(sampleLoc >= 1);

            int iPart = cast(int)(sampleLoc);
            float fPart = cast(float)(sampleLoc - iPart);
            assert(fPart >= 0.0f);
            assert(fPart <= 1.0f);
            T L1 = _data[(iPart - 1) & _indexMask];
            T L0  = _data[ iPart      & _indexMask];
            T H0  = _data[(iPart + 1) & _indexMask];
            T H1  = _data[(iPart + 2) & _indexMask];

            return L0 + 0.5f *
                fPart*(H0-L1 +
                fPart*(H0 + L0*(-2) + L1 +
                fPart*( (H0 - L0)*9 + (L1 - H1)*3 +
                fPart*((L0 - H0)*15 + (H1 - L1)*5 +
                fPart*((H0 - L0)*6 + (L1 - H1)*2 )))));
        }

        /// 4th order spline interpolation
        /// http://musicdsp.org/showArchiveComment.php?ArchiveID=60
        T sampleSpline4(float delay)
        {
            assert(delay > 2);
            T sampleLoc = (_index - delay) + 2 * _data.length;
            assert(sampleLoc >= 2);

            int iPart = cast(int)(sampleLoc);
            T fPart = cast(T)(sampleLoc - iPart);


            assert(fPart >= 0.0f);
            assert(fPart <= 1.0f);

            T p0 = _data[(iPart-2) & _indexMask];
            T p1 = _data[(iPart-1) & _indexMask];
            T p2 = _data[iPart     & _indexMask];
            T p3 = _data[(iPart+1) & _indexMask];
            T p4 = _data[(iPart+2) & _indexMask];
            T p5 = _data[(iPart+3) & _indexMask];

            return p2 + 0.04166666666f * fPart * ((p3 - p1) * 16 + (p0 - p4) * 2
            + fPart * ((p3 + p1) * 16 - p0 - p2 * 30 - p4
            + fPart * (p3 * 66 - p2 * 70 - p4 * 33 + p1 * 39 + p5 * 7- p0 * 9
            + fPart * ( p2 * 126 - p3 * 124 + p4 * 61 - p1 * 64 - p5 * 12 + p0 * 13
            + fPart * ((p3-p2) * 50 + (p1-p4) * 25 + (p5-p0)*5)))));
        };
    }

private:
    T[] _data;
    int _index;
    int _indexMask;
    int _numSamples;
}

unittest
{
    Delayline!float line;
    line.initialize(0); // should be possible
    assert(line.nextSample(1) == 1);

    Delayline!double line2;

    Delayline!int line3;
    line3.initialize(2);
    assert(line3.nextSample(1) == 0);
    assert(line3.nextSample(2) == 0);
    assert(line3.nextSample(3) == 1);
}