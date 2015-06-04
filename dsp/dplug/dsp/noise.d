// See licenses/UNLICENSE.txt
module dplug.dsp.noise;

import std.random,
       std.math;

import gfm.core.memory;

/// Generates white gaussian noise.
struct WhiteNoise
{
public:
    void initialize() nothrow @nogc
    {
        _rng.seed(nogc_unpredictableSeed());
    }

    float next() nothrow @nogc
    {
        return randNormal!Xorshift32(_rng, 0.0f, 1.0f);
    }

private:
    Xorshift32 _rng;
}


/// Makes a periodic noise for plugins demos.
/// Simply multiply you signal to footprint by the next() sample.
struct DemoNoise
{
public:
    enum int PERIOD = 30;
    enum int NOISE_DURATION = 2;

    void initialize(double samplerate) nothrow @nogc
    {
        _noise.initialize();
        _increment = 1.0 / samplerate;
        _counter = 0;
    }

    /// Return the next
    double next() nothrow @nogc
    {
        _counter += _increment;
        while (_counter >= PERIOD)
            _counter = _counter - PERIOD;

        if (_counter > PERIOD - NOISE_DURATION)
            return 1 + _noise.next() * 0.3 * sin(PI * (_counter - PERIOD + NOISE_DURATION) / NOISE_DURATION);
        else
            return 1;
    }

private:
    double _counter;
    double _increment;
    WhiteNoise _noise;
}

/// 1D perlin noise octave.
/// Is useful to slightly move parameters over time.
struct Perlin1D
{
public:
    void init(double frequency, double samplerate) nothrow @nogc
    {
        _rng.seed(nogc_unpredictableSeed());
        _current = 0.0f;
        newGoal();
        _phase = 0.0f;
        _phaseInc = cast(float)(frequency / samplerate);
    }

    float next() nothrow @nogc
    {
        _phase += _phaseInc;
        if (_phase > 1)
        {
            _current = _goal;
            newGoal();
            _phase -= 1;
        }
        float f = smootherstep(_phase);
        return f * _goal + (1 - f) * _current;
    }

private:
    static float smootherstep(float x) nothrow @nogc
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
struct PinkNoise
{
    void init(double frequency, double samplerate) nothrow @nogc
    {
        _rng.seed(nogc_unpredictableSeed());
        contrib[] = 0;
        accum = 0;

    }

    int[5] contrib; // stage contributions
    short  accum;      // combined generators
    Xorshift32 _rng;

    float next() nothrow @nogc
    {
        int randu = nogc_uniform_int(0, 32768, _rng);
        int  randv = nogc_uniform_int(-32768, 32768, _rng); // [-32768,32767]

        // Structured block, at most one update is performed
        for (int n = 0; n < 5; ++n)
        {
            if (randu < pPSUM[n])
            {
                accum -= contrib[n];
                contrib[n] = randv * pA[n];
                accum += contrib[n];
                break;
            }
        }
        return (accum >> 16) / 32767.0f;
    }

private:

    static immutable int[5] pA = [ 14055, 12759, 10733, 12273, 15716 ];
    static immutable int[5] pPSUM = [ 22347, 27917, 29523, 29942, 30007 ];
}

private
{
    // Work-around std.random not being @nogc
    auto nogc_unpredictableSeed() @nogc nothrow
    {
        return assumeNothrowNoGC( (){ return unpredictableSeed(); } )();
    }

    auto nogc_uniform_int(int min, int max, ref Xorshift32 rng) @nogc nothrow
    {
        return assumeNothrowNoGC( (int min, int max, ref Xorshift32 rng)
                                  { 
                                      return uniform(min, max, rng); 
                                  } )(min, max, rng);
    }

    auto nogc_uniform_float(float min, float max, ref Xorshift32 rng) @nogc nothrow
    {
        return assumeNothrowNoGC( (float min, float max, ref Xorshift32 rng)
                                  { 
                                      return uniform(min, max, rng); 
                                  } )(min, max, rng);
    }


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