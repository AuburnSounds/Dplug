/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.delayline;

import std.traits;

import gfm.math.funcs;

import dplug.core;

/// Allow to sample signal back in time.
struct Delayline(T)
{
public:
    
    /// Initialize the delay line. Can delay up to count samples.
    void initialize(int numSamples) nothrow @nogc
    {
        resize(numSamples);        
    }

    void clearState() nothrow @nogc
    {
        _data[] = 0;
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

        int toAllocate = nextPowerOf2(numSamples + 1); 
        _data.reallocBuffer(toAllocate);
        _indexMask = toAllocate - 1;
        _numSamples = numSamples;
        clearState();
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
    void nextBuffer(T[] input, T[] output) nothrow @nogc
    {
        for(int i = 0; i < cast(int)(input.length); ++i)
            output[i] = nextSample(input[i]);
    }

    /// Adds a new sample at end of delay.
    void feedSample(T incoming) nothrow @nogc
    {
        _index = (_index + 1) & _indexMask;
        _data[_index] = incoming;
    }

    /// Adds several samples at end of delay.
    void feedBuffer(T[] incoming) nothrow @nogc
    {
        foreach(sample; incoming)
            feedSample(sample);
    }

    /// Random access sampling of the delay-line at integer points.
    /// Delay 0 = last entered sample with feed().
    T sampleFull(int delay) nothrow @nogc
    {
        assert(delay >= 0);
        return _data[(_index - delay) & _indexMask];
    }

    static if(isFloatingPoint!T)
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
    import std.stdio;
    writeln(line.nextSample(1));
    assert(line.nextSample(1) == 1);

    Delayline!double line2;

    Delayline!int line3;
    line3.initialize(2);
    assert(line3.nextSample(1) == 0);
    assert(line3.nextSample(2) == 0);
    assert(line3.nextSample(3) == 1);
}