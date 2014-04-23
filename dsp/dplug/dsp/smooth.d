// See licenses/UNLICENSE.txt
module dplug.dsp.smooth;

import std.traits;

import gfm.core.queue;

import dplug.dsp.funcs;

/// Smooth values exponentially with a 1-pole lowpass.
/// This is usually sufficient for most parameter smoothing.
/// The type T must support arithmetic operations (+, -, +=, * with a float).
struct ExpSmoother(T)
{
public:
    /// time: the time constant of the smoother.
    /// threshold: absolute difference below which we consider current value and target equal
    void initialize(T initialValue, double time, double samplerate, T threshold)
    {
        assert(isFinite(initialValue));
        _target = _current = cast(T)(initialValue);
        setTimeParams(time, samplerate);
        _done = true;
        _threshold = threshold;
    }

    /// To call if samplerate changed, while preserving the current value.
    void setTimeParams(double time, double samplerate)
    {
        _expFactor = cast(T)(expDecayFactor(time, samplerate));
        assert(isFinite(_expFactor));
    }

    /// Advance smoothing and return the next smoothed sample with respect
    /// to tau time and samplerate.
    T next()
    {
        if (_done)
        {
            return _target;
        }
        else
        {
            T diff = _target - _current;
            if (fabs(diff) < _threshold)
            {
                _done = true;
                _current = _target;
            }
            else
            {
                double temp = _current + diff * _expFactor;
                T newCurrent = cast(T)(temp);

                // is this evolving?
                // is this assertion failed your threshold must be badly set
                assert(newCurrent != _current);
                assert(isFinite(newCurrent));
                _current = newCurrent;
            }
            return _current;
        }
    }

    /// Set the target value and return the next sample.
    T next(T x)
    {
        go(x);
        return next();
    }

    /// Set a new target for the smoothed value.
    void go(T newTarget)
    {
        assert(isFinite(newTarget));
        _target = newTarget;
        if (_target != _current)
            _done = false;
    }    

private:
    T _target;
    T _current;
    T _expFactor;
    T _threshold;
    bool _done;
}


/// Non-linear smoother using absolute difference.
/// Designed to have a nice phase response.
/// Warning: samplerate-dependent.
struct AbsSmoother(T)
{
public:

    /// Initialize the AbsSmoother.
    /// maxAbsDiff: maximum difference between filtered consecutive samples
    void initialize(T initialValue, T maxAbsDiff)
    {
        assert(isFinite(initialValue));
        _current = initialValue;
        _maxAbsDiff = maxAbsDiff;
    }

    T next(T input)
    {
       T absDiff = abs(input - _current);
       if (absDiff <= _maxAbsDiff)
           _current = input;
       else
           _current = _current + absDiff * (input > _current ? 1 : -1);
       return _current;
    }

private:
    T _current;
    T _maxAbsDiff;
}

/// Smooth values over time with a linear slope.
/// This can be useful for some smoothing needs.
/// Intermediate between fast phase and actual smoothing.
struct LinearSmoother(T)
{
public:

    /// Initialize the LinearSmoother.
    void initialize(T initialValue, double periodSecs, double sampleRate)
    {
        _target = initialValue;
        _current = initialValue;
        _period = periodSecs;
        _periodInv = 1 / periodSecs;
        setSamplerate(sampleRate);
        _phase = 0;
        _firstNextAfterInit = true;
        _done = true;
    }

    /// To call when samplerate changes, while preserving the current state.
    void setSamplerate(double samplerate)
    {
        _samplerateInv = 1 / samplerate;
        _current = _target;
    }

    /// Set a new target for the smoothed value.
    void go(T newTarget)
    {
        _target = newTarget;
        _done = false;
    }

    /// Advance smoothing and return the next smoothed sample.
    T next()
    {
        if (!_done)
        {
            _phase += _samplerateInv;
            if (_firstNextAfterInit || _phase > _period)
            {
                _phase -= _period;
                _increment = (_target - _current) * (_samplerateInv * _periodInv);
                if (_target == _current)
                    _done = true;
            }
            _current += _increment;
            _firstNextAfterInit = false;
        }
        return _current;
    }

    /// Set the target value and return the next sample.
    T next(T x)
    {
        go(x);
        return next();
    }

private:
    T _target;
    T _current;
    T _increment;
    double _period;
    double _periodInv;
    double _samplerateInv;
    double _phase;
    bool _firstNextAfterInit;
    bool _done;
}

/// Can be very useful when filtering values with outliers.
/// For what it's meant to do, excellent phase response.
struct MedianFilter(T, int N)
{
    static assert(N >= 2, "N must be >= 2");
    static assert(N % 2 == 1, "N must be odd");

public:

    void initialize()
    {
        _first = true;
    }

    T next(T input)
    {
        if (_first)
        {
            for (int i = 0; i < N - 1; ++i)
                _delay[i] = input;
            _first = false;
        }

        T arr[N];
        arr[0] = input;
        for (int i = 0; i < N - 1; ++i)
            arr[i + 1] = _delay[i];
        
        arr.sort; // sort in place

        T median = arr[N/2];

        for (int i = N - 3; i >= 0; --i)
            _delay[i + 1] = _delay[i];
        _delay[0] = input;
        return median;
    }

private:
    T _delay[N - 1];
    bool _first;
}


/// Simple FIR to smooth things cheaply.
/// I never succeeded in making it very useful, perhaps you need to cascade several.
/// Introduces (samples - 1) / 2 latency.
struct MeanFilter(T)
{
public:
    /// Initialize mean filter with given number of samples.
    void initialize(T initialValue, size_t samples, T maxExpectedValue)
    {
        _delay = new RingBuffer!long(samples);

        _factor = cast(T)(2147483648.0 / maxExpectedValue);
        _invNFactor = cast(T)1 / (_factor * samples);

        // round to integer
        long ivInt = toIntDomain(initialValue);

        while(!_delay.isFull())
            _delay.pushBack(ivInt);

        _sum = samples * ivInt;
    }

    /// Initialize with with cutoff frequency and samplerate.
    void initialize(T initialValue, double cutoffHz, double samplerate, T maxExpectedValue)
    {
        int nSamples = cast(int)(0.5 + samplerate / (2 * cutoffHz));

        if (nSamples < 1)
            nSamples = 1;

        initialize(initialValue, nSamples, maxExpectedValue);
    }

    size_t latency() const
    {
        return _delay.size();
    }

    // process next sample
    T next(T x)
    {
        // round to integer
        long input = cast(long)(cast(T)0.5 + x * _factor);
        _sum = _sum + input;
        _sum = _sum - _delay.popFront();
        _delay.pushBack(input);
        return cast(T)_sum * _invNFactor;
    }

private:

    long toIntDomain(T x)
    {
        return cast(long)(cast(T)0.5 + initialValue * _factor);
    }

    RingBuffer!long _delay;
    long _sum; // should always be the sum of samples in delay
    T _invNFactor;
    T _factor;
}



