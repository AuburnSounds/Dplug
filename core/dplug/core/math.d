/**
* Copyright: Copyright Auburn Sounds 2015-2016
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.core.math;

import std.math;

version(LDC)
{
    import ldc.intrinsics;
}

immutable real TAU = PI * 2;

/// Map linearly x from the range [a, b] to the range [c, d]
T linmap(T)(T value, T a, T b, T c, T d) pure nothrow @nogc
{
    return c + (d - c) * (value - a) / (b - a);
}

/// map [0..1] to [min..max] logarithmically
/// min and max must be all > 0, t in [0..1]
T logmap(T)(T t, T min, T max) pure nothrow @nogc
{
    assert(min < max);
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

/// Returns: true of i is a power of 2.
bool isPowerOfTwo(int i) pure nothrow @nogc
{
    assert(i >= 0);
    return (i != 0) && ((i & (i - 1)) == 0);
}

/// Computes next power of 2.
int nextPowerOf2(int i) pure nothrow @nogc
{
    int v = i - 1;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    v++;
    return v;
}

/// Computes next power of 2.
long nextPowerOf2(long i) pure nothrow @nogc
{
    long v = i - 1;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    v |= v >> 32;
    v++;
    return v;
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
    enum bool Assembly = D_InlineAsm_Any && !(is(Unqual!T == real));

    static if (Assembly)
    {
        T k_TAU = PI * 2;
        T result = phase;
        asm nothrow @nogc
        {
            fld k_TAU;    // TAU
            fld result;    // phase | TAU
            fprem1;       // normalized(phase) | TAU
            fstp result;   // TAU
            fstp ST(0);   //
        }
        return result;
    }
    else
    {
        T res = fmod(phase, cast(T)TAU);
        if (res > PI)
            res -= TAU;
        if (res < -PI)
            res += TAU;
        return res;
    }
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


version(D_InlineAsm_X86)
    private enum D_InlineAsm_Any = true;
else version(D_InlineAsm_X86_64)
    private enum D_InlineAsm_Any = true;
else
    private enum D_InlineAsm_Any = false;

// These functions trade correctness for speed
// The contract is that they don't check for infinity or NaN
// and assume small finite numbers instead.
// Don't rely on them being correct for your situation: test them.

///
T fast_pow(T)(T val, T power)
{
    version(LDC)
        return llvm_pow(val, power);
    else
        return pow(val, power);
}

///
T fast_exp(T)(T val, T)
{
    version(LDC)
        return llvm_exp(val);
    else
        return exp(val);
}

///
T fast_log(T)(T val)
{
    version(LDC)
        return llvm_log(val);
    else
        return log(val);
}

///
T fast_floor(T)(T val)
{
    version(LDC)
        return llvm_floor(val);
    else
        return log(val);
}

///
T fast_ceil(T)(T val)
{
    version(LDC)
        return llvm_ceil(val);
    else
        return ceil(val);
}

///
T fast_trunc(T)(T val)
{
    version(LDC)
        return llvm_trunc(val);
    else
        return trunc(val);
}

///
T fast_round(T)(T val)
{
    version(LDC)
        return llvm_round(val);
    else
        return round(val);
}

///
T fast_exp2(T)(T val)
{
    version(LDC)
        return llvm_exp2(val);
    else
        return exp2(val);
}

///
T fast_log10(T)(T val)
{
    version(LDC)
        return llvm_log10(val);
    else
        return log10(val);
}

///
T fast_log2(T)(T val)
{
    version(LDC)
        return llvm_log2(val);
    else
        return log2(val);
}

/// Linear interpolation, akin to GLSL's mix.
S lerp(S, T)(S a, S b, T t) pure nothrow @nogc 
    if (is(typeof(t * b + (1 - t) * a) : S))
{
    return t * b + (1 - t) * a;
}

/// Same as GLSL smoothstep function.
/// See: http://en.wikipedia.org/wiki/Smoothstep
T smoothStep(T)(T a, T b, T t) pure nothrow @nogc 
{
    if (t <= a)
        return 0;
    else if (t >= b)
        return 1;
    else
    {
        T x = (t - a) / (b - a);
        return x * x * (3 - 2 * x);
    }
}

/// SSE approximation of reciprocal square root.
T inverseSqrt(T)(T x) pure nothrow @nogc if (is(T : float) || is(T: double))
{
    version(AsmX86)
    {
        static if (is(T == float))
        {
            float result;

            asm pure nothrow @nogc 
            {
                movss XMM0, x; 
                rsqrtss XMM0, XMM0; 
                movss result, XMM0; 
            }
            return result;
        }
        else
            return 1 / sqrt(x);
    }
    else
        return 1 / sqrt(x);
}

unittest
{
    assert(abs( inverseSqrt!float(1) - 1) < 1e-3 );
    assert(abs( inverseSqrt!double(1) - 1) < 1e-3 );
}