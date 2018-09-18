/**
Various noise sources. 

Copyright: Guillaume Piolat 2015.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
deprecated("Scheduled for removal in Dplug v8") module dplug.dsp.noise;

import std.random,
       std.math;

import dplug.core.nogc;
import dplug.core.random;

/// Generates white gaussian noise.
deprecated("Scheduled for removal in Dplug v8") struct WhiteNoise(T) if (is(T == float) || is(T == double))
{
public:
    void initialize() nothrow @nogc
    {
        _rng.seed(nogc_unpredictableSeed());
    }

    T nextSample() nothrow @nogc
    {
        return randNormal!Xorshift32(_rng, cast(T)0, cast(T)1);
    }

    void nextBuffer(T* output, int frames) nothrow @nogc
    {
        for (int i = 0; i < frames; ++i)
            output[i] = nextSample();
    }

private:
    Xorshift32 _rng;
}

/// Makes a periodic noise for plugins demos.
/// Simply multiply you signal to footprint by the next() sample.
deprecated("Scheduled for removal in Dplug v8") struct DemoNoise(T) if (is(T == float) || is(T == double))
{
public:
    enum int PERIOD = 30;
    enum int NOISE_DURATION = 2;

    void initialize(float sampleRate) nothrow @nogc
    {
        _noise.initialize();
        _increment = 1.0 / sampleRate;
        _counter = 0;
    }

    T nextSample() nothrow @nogc
    {
        _counter += _increment;
        while (_counter >= PERIOD)
            _counter = _counter - PERIOD;

        if (_counter > PERIOD - NOISE_DURATION)
            return 1 + _noise.nextSample() * 0.3 * sin(PI * (_counter - PERIOD + NOISE_DURATION) / NOISE_DURATION);
        else
            return 1;
    }

    void nextBuffer(T* output, int frames) nothrow @nogc
    {
        for (int i = 0; i < frames; ++i)
            output[i] = nextSample();
    }

private:
    float _counter;
    float _increment;
    WhiteNoise!T _noise;
}

/// 1D perlin noise octave.
/// Is useful to slightly move parameters over time.
deprecated("Scheduled for removal in Dplug v8") struct Perlin1D(T) if (is(T == float) || is(T == double))
{
public:
    void initialize(double frequency, double samplerate) nothrow @nogc
    {
        _rng.seed(nogc_unpredictableSeed());
        _current = 0.0f;
        newGoal();
        _phase = 0.0f;    
        _phaseInc = cast(float)(frequency / samplerate);
    }

    T nextSample() nothrow @nogc
    {
        _phase += _phaseInc;
        if (_phase > 1)
        {
            _current = _goal;
            newGoal();
            _phase -= 1;
        }
        float f = smootherstep!float(_phase);
        return f * _goal + (1 - f) * _current;
    }

    void nextBuffer(T* output, int frames) nothrow @nogc
    {
        for (int i = 0; i < frames; ++i)
            output[i] = nextSample();
    }

private:
    static T smootherstep(T)(T x) nothrow @nogc
    {
        return x * x * x * (x * (x * 6 - 15) + 10);
    }

    void newGoal() nothrow @nogc
    {
        _goal = 2 * (nogc_uniform_float(0.0f, 1.0f, _rng) - 0.5f);
    }

    float _current;
    float _phase;
    float _phaseInc;
    float _goal;
    void _newGoal();

    Xorshift32 _rng;
}

/// Pink noise class using the autocorrelated generator method.
/// Method proposed and described by Larry Trammell "the RidgeRat" --
/// see http://home.earthlink.net/~ltrammell/tech/newpink.htm
/// There are no restrictions.
/// See_also: http://musicdsp.org/showArchiveComment.php?ArchiveID=244
deprecated("Scheduled for removal in Dplug v8") struct PinkNoise(T) if (is(T == float) || is(T == double))
{
public:
    void initialize() nothrow @nogc
    {
        _rng.seed(nogc_unpredictableSeed());
        _contrib[] = 0;
        _accum = 0;
    }

    float nextSample() nothrow @nogc
    {
        int randu = nogc_uniform_int(0, 32768, _rng);
        int  randv = nogc_uniform_int(-32768, 32768, _rng); // [-32768,32767]

        // Structured block, at most one update is performed
        for (int n = 0; n < 5; ++n)
        {
            if (randu < pPSUM[n])
            {
                _accum -= _contrib[n];
                _contrib[n] = randv * pA[n];
                _accum += _contrib[n];
                break;
            }
        }
        return _accum / 32768.0f;
    }

    void nextBuffer(T* output, int frames) nothrow @nogc
    {
        for (int i = 0; i < frames; ++i)
            output[i] = nextSample();
    }

private:

    int[5] _contrib; // stage contributions
    int _accum;      // combined generators
    Xorshift32 _rng;

    static immutable int[5] pA = [ 14055, 12759, 10733, 12273, 15716 ];
    static immutable int[5] pPSUM = [ 22347, 27917, 29523, 29942, 30007 ];
}

private
{
    /// Returns: Normal (Gaussian) random sample.
    /// See_also: Box-Muller algorithm.
    float randNormal(RNG)(ref RNG rng, float mean = 0.0, float standardDeviation = 1.0) nothrow @nogc
    {
        assert(standardDeviation > 0);
        double u1;

        do
        {
            u1 = nogc_uniform_float(0.0f, 1.0f, rng);
        } while (u1 == 0); // u1 must not be zero
        float u2 = nogc_uniform_float(0.0f, 1.0f, rng);
        float r = sqrt(-2.0 * log(u1));
        float theta = 2.0 * PI * u2;
        return mean + standardDeviation * r * sin(theta);
    }
}