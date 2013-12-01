// See licenses/UNLICENSE.txt
module dplug.dsp.noise;

import std.random,
       std.math;

/// Generates white noise.
struct WhiteNoise
{
public:    
    void init()
    {
        _rng.seed(unpredictableSeed());
    }

    float next()
    {
        return uniform(-1.0f, 1.0f, _rng);
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

    void init(double samplerate)
    {
        _noise.init();
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
