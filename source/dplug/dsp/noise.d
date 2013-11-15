module dplug.dsp.noise;

import std.random,
       std.math;

import gfm.math.simplerng;

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
        union float_uint
        {
            float f;
            uint ui;
        }
        float_uint fu;
        fu.ui = _rng.front;
        _rng.popFront();
        return fu.f - 3.0f; // 32-bits int to float conversion trick
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
    enum int SOUND_DURATION = 2;

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

        if (_counter > PERIOD - SOUND_DURATION)
            return 1 + _noise.next() * 0.3 * sin(PI * (_counter - PERIOD + SOUND_DURATION) / SOUND_DURATION);
        else
            return 1;
    }

private:
    double _counter;
    double _increment;
    WhiteNoise _noise;
};