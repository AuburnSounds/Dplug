/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.smooth;

import std.algorithm;
import std.traits;
import std.math;

import gfm.core.memory;
import gfm.core.queue;

import dplug.core;

/// Smooth values exponentially with a 1-pole lowpass.
/// This is usually sufficient for most parameter smoothing.
struct ExpSmoother(T) if (isFloatingPoint!T)
{
public:
    /// time: the time constant of the smoother.
    /// threshold: absolute difference below which we consider current value and target equal
    void initialize(float samplerate, float timeAttackRelease, T initialValue) nothrow @nogc
    {
        assert(isFinite(initialValue));

        _current = cast(T)(initialValue);

        _expFactor = cast(T)(expDecayFactor(timeAttackRelease, samplerate));
        assert(isFinite(_expFactor));
    }

    /// Advance smoothing and return the next smoothed sample with respect
    /// to tau time and samplerate.
    T nextSample(T target) nothrow @nogc
    {
        T diff = target - _current;
        if (diff != 0)
        {
            if (abs(diff) < 1e-10f) // to avoid subnormal, and excess churn
            {
                _current = target;
            }
            else
            {
                double temp = _current + diff * _expFactor; // Is double-precision really needed here?
                T newCurrent = cast(T)(temp);
                _current = newCurrent;
            }
        }
        return _current;
    }

    void nextBuffer(const(T)* input, T* output, int frames)
    {
        for (int i = 0; i < frames; ++i)
        {
            output[i] = nextSample(input[i]);
        }
    }

     void nextBuffer(T input, T* output, int frames)
    {
        for (int i = 0; i < frames; ++i)
        {
            output[i] = nextSample(input);
        }
    }

private:
    T _current;
    T _expFactor;
}

unittest
{
    ExpSmoother!float a;
    ExpSmoother!double b;
}

/// Same as ExpSmoother but have different attack and release decay factors.
struct AttackReleaseSmoother(T) if (isFloatingPoint!T)
{
public:
    /// time: the time constant of the smoother.
    /// threshold: absolute difference below which we consider current value and target equal
    void initialize(float samplerate, float timeAttack, float timeRelease, T initialValue) nothrow @nogc
    {
        assert(isFinite(initialValue));

        _current = cast(T)(initialValue);

        _expFactorAttack = cast(T)(expDecayFactor(timeAttack, samplerate));
        _expFactorRelease = cast(T)(expDecayFactor(timeRelease, samplerate));
        assert(isFinite(_expFactorAttack));
        assert(isFinite(_expFactorRelease));
    }

    /// Advance smoothing and return the next smoothed sample with respect
    /// to tau time and samplerate.
    T nextSample(T target) nothrow @nogc
    {
        T diff = target - _current;
        if (diff != 0)
        {
            if (abs(diff) < 1e-10f) // to avoid subnormal, and excess churn
            {
                _current = target;
            }
            else
            {
                double expFactor = (diff > 0) ? _expFactorAttack : _expFactorRelease;
                double temp = _current + diff * expFactor; // Is double-precision really needed here?
                T newCurrent = cast(T)(temp);
                _current = newCurrent;
            }
        }
        return _current;
    }

    void nextBuffer(const(T)* input, T* output, int frames)
    {
        for (int i = 0; i < frames; ++i)
        {
            output[i] = nextSample(input[i]);
        }
    }

    void nextBuffer(T input, T* output, int frames)
    {
        for (int i = 0; i < frames; ++i)
        {
            output[i] = nextSample(input);
        }
    }

private:
    T _current;
    T _expFactorAttack;
    T _expFactorRelease;
}

unittest
{
    AttackReleaseSmoother!float a;
    AttackReleaseSmoother!double b;
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

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for(int i = 0; i < frames; ++i)
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
        _sampleRateInv = 1 / sampleRate;

        // clear state
        _current = initialValue;
        _phase = 0;
        _firstNextAfterInit = true;
    }

    /// Set the target value and return the next sample.
    T nextSample(T input) nothrow @nogc
    {
        _phase += _sampleRateInv;
        if (_firstNextAfterInit || _phase > _period)
        {
            _phase -= _period;
            _increment = (input - _current) * (_sampleRateInv * _periodInv);
            _firstNextAfterInit = false;
        }
        _current += _increment;
        return _current;
    }

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for(int i = 0; i < frames; ++i)
            output[i] = nextSample(input[i]);
    }

private:
    T _current;
    T _increment;
    float _period;
    float _periodInv;
    float _sampleRateInv;
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
        _first = true;
    }

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

        // sort in place
        nogc_qsort!T(arr[],  
            (a, b) nothrow @nogc 
            {
                if (a > b) return 1;
                else if (a < b) return -1;
                else return 0;
            }
        );

        T median = arr[N/2];

        for (int i = N - 3; i >= 0; --i)
            _delay[i + 1] = _delay[i];
        _delay[0] = input;
        return median;
    }

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for(int i = 0; i < frames; ++i)
            output[i] = nextSample(input[i]);
    }

private:
    T[N - 1] _delay;
    bool _first;
}

unittest
{
    void test() nothrow @nogc 
    {
        MedianFilter!(float, 3) a;
        MedianFilter!(double, 5) b;
        a.initialize();
        b.initialize();
    }
    test();
}


/// Simple FIR to smooth things cheaply.
/// Introduces (samples - 1) / 2 latency.
/// Converts everything to long for performance purpose.
struct MeanFilter(T) if (isFloatingPoint!T)
{
public:
    /// Initialize mean filter with given number of samples.
    void initialize(T initialValue, int samples, T maxExpectedValue) nothrow @nogc
    {
        _delay = RingBufferNoGC!long(samples);

        _factor = cast(T)(2147483648.0 / maxExpectedValue);
        _invNFactor = cast(T)1 / (_factor * samples);

        // clear state
        // round to integer
        long ivInt = toIntDomain(initialValue);

        while(!_delay.isFull())
            _delay.pushBack(ivInt);

        _sum = cast(int)(_delay.length) * ivInt;
    }

    /// Initialize with with cutoff frequency and samplerate.
    void initialize(T initialValue, double cutoffHz, double samplerate, T maxExpectedValue) nothrow @nogc
    {
        int nSamples = cast(int)(0.5 + samplerate / (2 * cutoffHz));

        if (nSamples < 1)
            nSamples = 1;

        initialize(initialValue, nSamples, maxExpectedValue);
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

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for(int i = 0; i < frames; ++i)
            output[i] = nextSample(input[i]);
    }

private:

    long toIntDomain(T x) pure const nothrow @nogc
    {
        return cast(long)(cast(T)0.5 + x * _factor);
    }

    RingBufferNoGC!long _delay;
    long _sum; // should always be the sum of samples in delay
    T _invNFactor;
    T _factor;
}

unittest
{
    void test() nothrow @nogc 
    {
        MeanFilter!float a;
        MeanFilter!double b;
        a.initialize(44100.0f, 0.001f, 0.001f, 0.0f);
        b.initialize(44100.0f, 0.001f, 0.001f, 0.0f);
    }
    test();
}

