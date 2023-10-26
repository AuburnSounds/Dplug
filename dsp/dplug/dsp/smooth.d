/**
Various DSP smoothers.

Copyright: Guillaume Piolats 2015-2022.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.dsp.smooth;

import std.math;

import dplug.core.math;
import dplug.core.ringbuf;
import dplug.core.nogc;
import dplug.core.vec;

/// Smooth values exponentially with a 1-pole lowpass.
/// This is usually sufficient for most parameter smoothing.
deprecated("ExpSmoother will be removed as of Dplug v14") 
struct ExpSmoother(T) if (is(T == float) || is(T == double))
{
public:
    /// time: the time constant of the smoother.
    /// threshold: absolute difference below which we consider current value and target equal
    void initialize(float samplerate, float timeAttackRelease, T initialValue) nothrow @nogc
    {
        assert(isFinite(initialValue));

        _current = cast(T)(initialValue);
        _sampleRate = samplerate;

        setAttackReleaseTime(timeAttackRelease);

        assert(isFinite(_expFactor));
    }

    /// Changes attack and release time (given in seconds).
    void setAttackReleaseTime(float timeAttackRelease) nothrow @nogc
    {
        _expFactor = cast(T)(expDecayFactor(timeAttackRelease, _sampleRate));
    }

    /// Advance smoothing and return the next smoothed sample with respect
    /// to tau time and samplerate.
    T nextSample(T target) nothrow @nogc
    {
        T diff = target - _current;
        if (diff != 0)
        {
            if (fast_fabs(diff) < 1e-10f) // to avoid subnormal, and excess churn
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

    bool hasConverged(T target) nothrow @nogc
    {
        return target == _current;
    }

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for (int i = 0; i < frames; ++i)
        {
            output[i] = nextSample(input[i]);
        }
    }

    void nextBuffer(T input, T* output, int frames) nothrow @nogc
    {
        for (int i = 0; i < frames; ++i)
        {
            output[i] = nextSample(input);
        }
    }

private:
    T _current;
    T _expFactor;
    float _sampleRate;
}


/// Same as ExpSmoother but have different attack and release decay factors.
deprecated("AttackReleaseSmoother will be removed as of Dplug v14") 
struct AttackReleaseSmoother(T) if (is(T == float) || is(T == double))
{
public:
    /// time: the time constant of the smoother.
    /// threshold: absolute difference below which we consider current value and target equal
    void initialize(float sampleRate, float timeAttackSecs, float timeReleaseSecs, T initialValue) nothrow @nogc
    {
        assert(isFinite(initialValue));
        _sampleRate = sampleRate;
        _current = cast(T)(initialValue);
        setAttackTime(timeAttackSecs);
        setReleaseTime(timeReleaseSecs);
    }

    /// Changes attack time (given in seconds).
    void setAttackTime(float timeAttackSecs) nothrow @nogc
    {
        _expFactorAttack = cast(T)(expDecayFactor(timeAttackSecs, _sampleRate));
    }

    /// Changes release time (given in seconds).
    void setReleaseTime(float timeReleaseSecs) nothrow @nogc
    {
        _expFactorRelease = cast(T)(expDecayFactor(timeReleaseSecs, _sampleRate));
    }

    /// Advance smoothing and return the next smoothed sample with respect
    /// to tau time and samplerate.
    T nextSample(T target) nothrow @nogc
    {
        T diff = target - _current;
        if (diff != 0)
        {
            if (fast_fabs(diff) < 1e-10f) // to avoid subnormal, and excess churn
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
    float _sampleRate;
}


/// Non-linear smoother using absolute difference.
/// Designed to have a nice phase response.
/// Warning: samplerate-dependent.
deprecated("AbsSmoother will be removed as of Dplug v14") 
struct AbsSmoother(T) if (is(T == float) || is(T == double))
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

/// Smooth values over time with a linear slope.
/// This can be useful for some smoothing needs.
/// Intermediate between fast phase and actual smoothing.
deprecated("LinearSmoother will be removed as of Dplug v14")
struct LinearSmoother(T) if (is(T == float) || is(T == double))
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

/// Can be very useful when filtering values with outliers.
/// For what it's meant to do, excellent phase response.
deprecated("MedianFilter will be removed as of Dplug v14")
struct MedianFilter(T) if (is(T == float) || is(T == double))
{
public:

    void initialize(T initialValue, int samples) nothrow @nogc
    {
        assert(samples >= 2, "N must be >= 2");
        assert(samples % 2 == 1, "N must be odd");

        _delay.reallocBuffer(samples - 1);
        _delay[] = initialValue;

        _arr.reallocBuffer(samples);
        _N = samples;

        _tempbuf = makeVec!T();
    }

    ~this()
    {
        _delay.reallocBuffer(0);
        _arr.reallocBuffer(0);
    }

    T nextSample(T input) nothrow @nogc
    {
        // dramatically inefficient

        _arr[0] = input;
        for (int i = 0; i < _N - 1; ++i)
            _arr[i + 1] = _delay[i];

        // sort in place
        // this sort doesn't even need to be stable, but well.
        timSort!T(_arr[],
                  _tempbuf,
                  (a, b) nothrow @nogc
                  {
                      if (a > b) return 1;
                      else if (a < b) return -1;
                      else return 0;
                  }
        );

        T median = _arr[_N/2];

        for (int i = _N - 3; i >= 0; --i)
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
    T[] _delay;
    T[] _arr;
    int _N;
    Vec!T _tempbuf;
}

/// Simple FIR to smooth things cheaply.
/// Introduces (samples - 1) / 2 latency.
/// This one doesn't convert to integers internally so it may
/// loose precision over time. Meants for finite signals.
deprecated("UnstableMeanFilter will be removed as of Dplug v14")
struct UnstableMeanFilter(T) if (is(T == float) || is(T == double))
{
public:
    /// Initialize mean filter with given number of samples.
    void initialize(T initialValue, int samples) nothrow @nogc
    {
        _delay = RingBufferNoGC!T(samples);

        _invNFactor = cast(T)1 / samples;

        while(!_delay.isFull())
            _delay.pushBack(initialValue);

        _sum = _delay.length * initialValue;
    }

    /// Initialize with with cutoff frequency and samplerate.
    void initialize(T initialValue, double cutoffHz, double samplerate) nothrow @nogc
    {
        int nSamples = cast(int)(0.5 + samplerate / (2 * cutoffHz));

        if (nSamples < 1)
            nSamples = 1;

        initialize(initialValue, nSamples);
    }

    // process next sample
    T nextSample(T x) nothrow @nogc
    {
        _sum = _sum + x;
        _sum = _sum - _delay.popFront();
        _delay.pushBack(x);
        return _sum * _invNFactor;
    }

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for(int i = 0; i < frames; ++i)
            output[i] = nextSample(input[i]);
    }

private:
    RingBufferNoGC!T _delay;
    double _sum; // should be approximately the sum of samples in delay
    T _invNFactor;
    T _factor;
}

/// Simple FIR to smooth things cheaply.
/// Introduces (samples - 1) / 2 latency.
/// Converts everything to long for stability purpose.
/// So this may run forever as long as the input is below some threshold.
deprecated("MeanFilter will be removed as of Dplug v14")
struct MeanFilter(T) if (is(T == float) || is(T == double))
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

