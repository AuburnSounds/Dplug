// See licenses/UNLICENSE.txt
module dplug.dsp.noise;

import std.random,
       std.math;

import gfm.math.simplerng;

/// Generates white gaussian noise.
struct WhiteNoise
{
public:
    void initialize()
    {
        _rng.seed(unpredictableSeed());
    }

    float next()
    {
        return randNormal!Xorshift32(_rng, 0.0, 1.0);
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

    void initialize(double samplerate)
    {
        _noise.initialize();
        _increment = 1.0 / samplerate;
        _counter = 0;
    }

    /// Return the next
    double next()
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
    void init(double frequency, double samplerate)
    {
        _rng.seed(unpredictableSeed());
        _current = 0.0f;
        newGoal();
        _phase = 0.0f;
        _phaseInc = cast(float)(frequency / samplerate);
    }

    float next()
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
    static float smootherstep(float x)
    {
        return x * x * x * (x * (x * 6 - 15) + 10);
    }

    void newGoal()
    {
        _goal = 2 * (uniform(0.0f, 1.0f, _rng) - 0.5f);
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
        _rng.seed(unpredictableSeed());
        contrib[] = 0;
        accum = 0;

    }

    int[5] contrib; // stage contributions
    short  accum;      // combined generators
    Xorshift32 _rng;

    float next() nothrow @nogc
    {
        short int  randu = _rng.uniform(0, 32768);
        short int  randv = _rng.uniform(-32768, 32768); // [-32768,32767]

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

    static immutable int pA[5] = [ 14055, 12759, 10733, 12273, 15716 ];
    static immutable int pPSUM[5] = [ 22347, 27917, 29523, 29942, 30007 ];
}

