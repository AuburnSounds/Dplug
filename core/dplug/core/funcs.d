module dplug.core.funcs;

import std.math;

immutable real TAU = PI * 2;

/** Four Character Constant (for AEffect->uniqueID) */
int CCONST(int a, int b, int c, int d) pure nothrow
{
    return (a << 24) | (b << 16) | (c << 8) | (d << 0);
}

/// Map linearly x from the range [a, b] to the range [c, d]
T linmap(T)(T value, T a, T b, T c, T d) pure nothrow @nogc
{
    return c + (d - c) * (value - a) / (b - a);
}

/// map [0..1] to [min..max] logarithmically
/// min and max must be all > 0, t in [0..1]
T logmap(T)(T t, T min, T max, ) pure nothrow @nogc
{
    return min * exp(t * log(max / min));
}

/// Hermite interpolation.
T hermite(T)(T frac_pos, T xm1, T x0, T x1, T x2) pure nothrow @nogc
{
    T c = (x1 - xm1) * 0.5f;
    T v = x0 - x1;
    T w = c + v;
    T a = w + v + (x2 - x0) * 0.5f;
    T b_neg = w + a;
    return ((((a * frac_pos) - b_neg) * frac_pos + c) * frac_pos + x0);
}

/// Convert from dB to float.
T deciBelToFloat(T)(T dB) pure nothrow @nogc
{
    static immutable T ln10_20 = cast(T)LN10 / 20;
    return exp(dB * ln10_20);
}

/// Convert from float to dB
T floatToDeciBel(T)(T x) pure nothrow @nogc
{
    static immutable T f20_ln10 = 20 / cast(T)LN10;
    return log(x) * f20_ln10;
}

/// Is this integer odd?
bool isOdd(T)(T i) pure nothrow @nogc
{
    return (i & 1) != 0;
}

/// Is this integer even?
bool isEven(T)(T i) pure nothrow @nogc
{
    return (i & 1) == 0;
}

/// Returns: x so that (1 << x) >= i
int iFloorLog2(int i) pure nothrow @nogc
{
    assert(i >= 1);
    int result = 0;
    while (i > 1)
    {
        i = i / 2;
        result = result + 1;
    }
    return result;
}

/// Mapping from MIDI notes to frequency
double MIDIToFrequency(T)(int note) pure nothrow @nogc
{
    return 440 * pow(2.0, (note - 69.0) / 12.0);
}

/// Mapping from frequency to MIDI notes
double frequencyToMIDI(T)(double frequency) pure nothrow @nogc
{
    return 69.0 + 12 * log2(frequency / 440.0);
}

/// Fletcher and Munson equal-loudness curve
/// Reference: Xavier Serra thesis (1989).
T equalLoudnessCurve(T)(T frequency) pure nothrow @nogc
{
    T x = cast(T)0.05 + 4000 / frequency;
    return x * ( cast(T)10 ^^ x);
}

/// Cardinal sine
T sinc(T)(T x) pure nothrow @nogc
{
    if (cast(T)(1) + x * x == cast(T)(1))
        return 1;
    else
        return sin(cast(T)PI * x) / (cast(T)PI * x);
}

double expDecayFactor(double time, double samplerate) pure nothrow @nogc
{
    // 1 - exp(-time * sampleRate) would yield innacuracies
    return -expm1(-1.0 / (time * samplerate));
}

/// Give back a phase between -PI and PI
T normalizePhase(T)(T phase) nothrow @nogc
{
    T res = fmod(phase, cast(T)TAU);
    if (res > PI)
        res -= TAU;
    if (res < -PI)
        res += TAU;
    return res;
}

unittest
{
    assert(approxEqual(normalizePhase!real(TAU), 0));

    assert(approxEqual(normalizePhase!float(0.1f), 0.1f));
    assert(approxEqual(normalizePhase!float(TAU + 0.1f), 0.1f));

    assert(approxEqual(normalizePhase!double(-0.1f), -0.1f));
    assert(approxEqual(normalizePhase!double(-TAU - 0.1f), -0.1f));

    bool approxEqual(T)(T a, T b) nothrow @nogc
    {
        return (a - b) < 1e-7;
    }
}

/// Quick and dirty sawtooth for testing purposes.
T rawSawtooth(T)(T x) pure nothrow @nogc
{
    return normalizePhase(x) / (cast(T)PI);
}

/// Quick and dirty triangle for testing purposes.
T rawTriangle(T)(T x) pure nothrow @nogc
{
    return 1 - normalizePhase(x) / cast(T)PI_2;
}

/// Quick and dirty square for testing purposes.
T rawSquare(T)(T x) pure nothrow @nogc
{
    return normalizePhase(x) > 0 ? 1 : -1;
}

T computeRMS(T)(T[] samples) pure nothrow @nogc
{
    double sum = 0;
    foreach(sample; samples)
        sum += sample * sample;
    return sqrt(sum / cast(int)samples.length);
}

unittest
{
    double[] d = [4, 5, 6];
    computeRMS(d);
}


/// Use throughout dplug:dsp to avoid reliance on GC.
/// This works like alignedRealloc except with slices as input.
///
/// Params:
///    buffer Existing allocated buffer. Can be null. Input slice length is not considered.
///    length desired slice length
///
void reallocBuffer(T)(ref T[] buffer, size_t length, int alignment = 16) nothrow @nogc
{
    import gfm.core.memory : alignedRealloc;

    T* pointer = cast(T*) alignedRealloc(buffer.ptr, T.sizeof * length, alignment);
    if (pointer is null)
        buffer = null;
    else
        buffer = pointer[0..length];
}

// A bit faster than a dynamic cast.
// This is to avoid TypeInfo look-up
T unsafeObjectCast(T)(Object obj)
{
    return cast(T)(cast(void*)(obj));
}