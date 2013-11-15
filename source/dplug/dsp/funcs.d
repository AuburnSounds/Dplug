module dplug.dsp.funcs;

import std.math;

immutable real TAU = PI * 2;
    
/// Map linearly x from the range [a, b] to the range [c, d]
T linmap(T)(T value, T a, T b, T c, T d)
{
    return c + (d - c) * (value - a) / (b - a);
}

/// map [0..1] to [min..max] logarithmically
T logmap(T)(T min, T max, T t) // min and max must be all > 0, t in [0..1]
{
    return min * exp(t * log(max / min));
}

/// Hermite interpolation.
T hermite(T)(T frac_pos, T xm1, T x0, T x1, T x2)
{
    T c = (x1 - xm1) * 0.5f;
    T v = x0 - x1;
    T w = c + v;
    T a = w + v + (x2 - x0) * 0.5f;
    T b_neg = w + a;
    return ((((a * frac_pos) - b_neg) * frac_pos + c) * frac_pos + x0);
}

   
/// Convert from dB to float.
T deciBelToFloat(T)(T dB)
{
    return exp(dB * (cast(T)LN10 / 20));
}

/// Convert from float to dB
T floatToDeciBel(T)(T x)
{
    return log(x) * (20 / cast(T)LN10);
}

/// Is this integer odd?
bool isOdd(T)(T i)
{
    return (i & 1) != 0;
}

/// Is this integer even?
bool isEven(T)(T i)
{
    return (i & 1) == 0;
}

double MIDIToFrequency(T)(int note)
{
    return 440 * pow(2.0, (note - 69.0) / 12.0);
}

double frequencyToMIDI(T)(double frequency)
{
    return 69.0 + 12 * log2(frequency / 440.0);
}

/// Fletcher and Munson equal-loudness curve
/// Reference: Xavier Serra thesis (1989).
T equalLoudnessCurve(T)(T frequency)
{
    T x = cast(T)0.05 + 4000 / frequency;
    return x * ( cast(T)10 ^^ x);
}

/// Cardinal sine
T sinc(T)(T x)
{
    if (cast(T)(1) + x * x == cast(T)(1))
        return 1;
    else
        return sin(cast(T)PI * x) / (cast(T)PI * x);
}

double expm1(double x)
{
    return tanh(x * 0.5) * (exp(x) + 1.0);
}

double expDecayFactor(double time, double samplerate)
{
    // 1 - exp(-time * sampleRate) would yield innacuracies
    return -expm1(-1.0 / (time * samplerate));
}

/// Give back a phase between -PI and PI
T normalizePhase(T)(T phase)
{
    T res = fmod(phase, cast(T)TAU);
    if (res > PI)
        res -= TAU;
    if (res < -PI)
        res += TAU;
    return res;
}


/// Quick and dirty sawtooth for testing purposes.
T rawSawtooth(T)(T x)
{
    return normalizePhase(x) / (cast(T)PI);
}

/// Quick and dirty triangle for testing purposes.
T rawTriangle(T)(T x)
{
    return 1 - normalizePhase(x) / cast(T)PI_2;
}

/// Quick and dirty square for testing purposes.
T rawSquare(T)(T x)
{
    return normalizePhase(x) > 0 ? 1 : -1;
}

// TODO: FPU/SSE save and restore?
   