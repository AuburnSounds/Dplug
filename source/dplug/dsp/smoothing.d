module dplug.dsp.smoothing;

import std.traits;

import dplug.dsp.funcs;

/**
 * Smooth values exponentially with a 1-pole lowpass.
 * This is usually sufficient for most parameter smoothing.
 * The type T must support arithmetic operations (+, -, +=, * with a float).
 */
struct ExpSmoother(T)
{
public:

    /**
     * Initialize the Smoother.
     *
     * @param initialValue first value of the value to be smoothed
     * @param time the time constant of the smoother
     * @param sampleRate the target sample rate
     * @param threshold difference where we consider value and target are equal
     */
    void init(T initialValue, double time, double samplerate, T threshold)
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
    void init(T initialValue, T maxAbsDiff)
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

/// Class to smooth values over time with a linear slope.
/// This can be useful for some smoothing needs.
/// Intermediate between fast phase and actual smoothing.
struct LinearSmoother(T)
{
public:

    /**
     * Initialize the LinearSmoother.
     *
     * @param initialValue first value of the value to be smoothed
     * @param period time period between updates, in seconds
     */
    void init(T initialValue, double periodSecs, double sampleRate)
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
};
