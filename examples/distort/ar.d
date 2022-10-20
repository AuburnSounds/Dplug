/**
Attack and release basic smoother.

Copyright: Guillaume Piolat 2015-2022.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module ar;

//import std.algorithm.comparison;
//import std.math;

import std.math: isFinite;
import dplug.core.math;
import dplug.core.ringbuf;
import dplug.core.nogc;
import dplug.core.vec;

struct AttackRelease(T) if (is(T == float) || is(T == double))
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

