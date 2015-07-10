/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.smooth;

import std.algorithm;
import std.traits;
import std.math;

import gfm.core.queue;

import dplug.core;

/// Smooth values exponentially with a 1-pole lowpass.
/// This is usually sufficient for most parameter smoothing.
/// The type T must support arithmetic operations (+, -, +=, * with a float).
struct ExpSmoother(T) if (isFloatingPoint!T)
{
public:
    /// time: the time constant of the smoother.
    /// threshold: absolute difference below which we consider current value and target equal
    void initialize(double samplerate, double timeAttack, double timeRelease, T initialValue = 0) nothrow @nogc
    {
        assert(isFinite(initialValue));

        clearState(initialValue);

        _expFactorAttack = cast(T)(expDecayFactor(timeAttack, samplerate));
        _expFactorRelease = cast(T)(expDecayFactor(timeRelease, samplerate));
        assert(isFinite(_expFactorAttack));
        assert(isFinite(_expFactorRelease));
    }

    void clearState(T initialValue) pure nothrow
    {
        _current = cast(T)(initialValue);
    }

    /// Advance smoothing and return the next smoothed sample with respect
    /// to tau time and samplerate.
    T nextSample(T target) nothrow @nogc
    {
        T diff = target - _current;
        double expFactor = (diff > 0) ? _expFactorAttack : _expFactorRelease;
        double temp = _current + diff * expFactor;
        T newCurrent = cast(T)(temp);
        _current = newCurrent;
        return _current;
    }

private:
    T _current;
    T _expFactorAttack;
    T _expFactorRelease;
}

unittest
{
    ExpSmoother!float a;
    ExpSmoother!double b;
}

/// Non-linear smoother using absolute difference.
/// Designed to have a nice phase response.
/// Warning: samplerate-dependent.
struct AbsSmoother(T) if (isFloatingPoint!T)
{
public:

    /// Initialize the AbsSmoother.
    /// maxAbsDiff: maximum difference between filtered consecutive samples
    void initialize(T initialValue, T maxAbsDiff) nothrow @nogc
    {
        assert(isFinite(initialValue));
        _maxAbsDiff = maxAbsDiff;
        clearState(initialValue);
    }

    void clearState(T initialValue) nothrow @nogc
    {
        _current = initialValue;
    }

    T nextSample(T input) nothrow @nogc
    {
       T absDiff = abs(input - _current);
       if (absDiff <= _maxAbsDiff)
           _current = input;
       else
           _current = _current + absDiff * (input > _current ? 1 : -1);
       return _current;
    }

    void nextBuffer(T[] input, T[] output) nothrow @nogc
    {
        for(int i = 0; i < cast(int)(input.length); ++i)
            output[i] = nextSample(input[i]);
    }

private:
    T _current;
    T _maxAbsDiff;
}

unittest
{
    AbsSmoother!float a;
    AbsSmoother!double b;
}

/// Smooth values over time with a linear slope.
/// This can be useful for some smoothing needs.
/// Intermediate between fast phase and actual smoothing.
struct LinearSmoother(T) if (isFloatingPoint!T)
{
public:

    /// Initialize the LinearSmoother.
    void initialize(T initialValue, float periodSecs, float sampleRate) nothrow @nogc
    {
        _period = periodSecs;
        _periodInv = 1 / periodSecs;
        _samplerateInv = 1 / samplerate;
        clearState(initialValue);
    }

    /// Advance smoothing and return the next smoothed sample.
    T clearState(T initialValue) nothrow @nogc
    {
        _current = initialValue;
        _phase = 0;
        _firstNextAfterInit = true;
    }

    /// Set the target value and return the next sample.
    T nextSample(T input) nothrow @nogc
    {
        _phase += _samplerateInv;
        if (_firstNextAfterInit || _phase > _period)
        {
            _phase -= _period;
            _increment = (_target - _current) * (_samplerateInv * _periodInv);
            _firstNextAfterInit = false;
        }
        _current += _increment;
    }

    void nextBuffer(T[] input, T[] output) nothrow @nogc
    {
        for(int i = 0; i < cast(int)(input.length); ++i)
            input[i] = nextSample(output[i]);
    }

private:
    T _current;
    T _increment;
    float _period;
    float _periodInv;
    float _samplerateInv;
    float _phase;
    bool _firstNextAfterInit;
}

unittest
{
    LinearSmoother!float a;
    LinearSmoother!double b;
}

/// Can be very useful when filtering values with outliers.
/// For what it's meant to do, excellent phase response.
struct MedianFilter(T, int N) if (isFloatingPoint!T)
{
    static assert(N >= 2, "N must be >= 2");
    static assert(N % 2 == 1, "N must be odd");

public:

    void initialize() nothrow @nogc
    {
        clearState();
    }

    void clearState() nothrow @nogc
    {
        _first = true;
    }

    // TODO: make it nothrow @nogc
    T nextSample(T input) nothrow @nogc
    {
        if (_first)
        {
            for (int i = 0; i < N - 1; ++i)
                _delay[i] = input;
            _first = false;
        }

        T[N] arr;
        arr[0] = input;
        for (int i = 0; i < N - 1; ++i)
            arr[i + 1] = _delay[i];

        sort(arr[]); // sort in place

        T median = arr[N/2];

        for (int i = N - 3; i >= 0; --i)
            _delay[i + 1] = _delay[i];
        _delay[0] = input;
        return median;
    }

    void nextBuffer(T[] input, T[] output) nothrow @nogc
    {
        for (int i = 0; i < cast(int)(input.length); ++i)
            output[i] = nextSample(input[i]);
    }

private:
    T[N - 1] _delay;
    bool _first;
}

unittest
{
    MedianFilter!(float, 3) medianfilter;
    MedianFilter!(double, 5) medianfilter;
}


/// Simple FIR to smooth things cheaply.
/// I never succeeded in making it very useful, perhaps you need to cascade several.
/// Introduces (samples - 1) / 2 latency.
/// Converts everything to integers for performance purpose.
struct MeanFilter(T) if (isFloatingPoint!T)
{
public:
    /// Initialize mean filter with given number of samples.
    void initialize(T initialValue, int samples, T maxExpectedValue) nothrow @nogc
    {
        _delay = new RingBuffer!long(samples);

        _factor = cast(T)(2147483648.0 / maxExpectedValue);
        _invNFactor = cast(T)1 / (_factor * samples);

        clearState();
    }

    /// Initialize with with cutoff frequency and samplerate.
    void initialize(T initialValue, double cutoffHz, double samplerate, T maxExpectedValue) nothrow @nogc
    {
        int nSamples = cast(int)(0.5 + samplerate / (2 * cutoffHz));

        if (nSamples < 1)
            nSamples = 1;

        initialize(initialValue, nSamples, maxExpectedValue);
    }

    void clearState(T initialValue) nothrow @nogc
    {
        // round to integer
        long ivInt = toIntDomain(initialValue);

        while(!_delay.isFull())
            _delay.pushBack(ivInt);

        _sum = samples * ivInt;
    }

    int latency() const nothrow @nogc
    {
        return cast(int)(_delay.length());
    }

    // process next sample
    T nextSample(T x) nothrow @nogc
    {
        // round to integer
        long input = cast(long)(cast(T)0.5 + x * _factor);
        _sum = _sum + input;
        _sum = _sum - _delay.popFront();
        _delay.pushBack(input);
        return cast(T)_sum * _invNFactor;
    }

    void nextBuffer(T[] input, T[] output) nothrow @nogc
    {
        for (int i = 0; i < cast(int)(input.length); ++i)
            output[i] = nextSample(input[i]);
    }

private:

    long toIntDomain(T x) pure const nothrow @nogc
    {
        return cast(long)(cast(T)0.5 + x * _factor);
    }

    RingBuffer!long _delay;
    long _sum; // should always be the sum of samples in delay
    T _invNFactor;
    T _factor;
}

unittest
{
    MeanFilter!float a;
    MeanFilter!double b;
}

