module dplug.dsp.smoothing;

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

    // to call if samplerate changed
    void setTimeParams(double time, double samplerate)
    {
        _expFactor = cast(T)(expDecayFactor(time, samplerate));
        assert(isFinite(_expFactor));
    }

    /**
     * Set a new target for the smoothed value.
     */
    void go(T newTarget)
    {
        assert(isFinite(newTarget));
        _target = newTarget;
        if (_target != _current)
        {
            _done = false;
        }
    }

    /**
     * Advance smoothing and return the next smoothed sample with respect
     * to tau time and samplerate.
     */
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

    T goal() const
    {
        return _target;
    }

    /**
     * Current smoothed value.
     */
    T current() const
    {
        return _current;
    }

    /**
     * Use the smoother as an envelope follower.
     * Combined call to go and next.
     */
    T follow(T x)
    {
        go(x);
        return next();
    }

    /**
     * Get target value.
     */
    T target() const
    {
        return _target;
    }

    bool done() const
    {
        return _done;
    }

private:
    T _target;
    T _current;
    T _expFactor;
    T _threshold;
    bool _done;
}
