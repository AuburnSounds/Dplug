/**
DSP utility functions. 

Copyright: Guillaume Piolat 2015-2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
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
/// Note: you can totally have a max that is smaller than min.
///       In this cases, the range mapped with more accuracy are still small values.
T logmap(T)(T t, T min, T max) pure nothrow @nogc
{
    assert(min > 0 && max > 0);
    T ratio = max / min;
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

/// Converts from dB to linear gain.
/// Precision: This uses fast_exp which under normal conditions has a peak 
/// error under -135dB over the useful range.
float convertDecibelToLinearGain(float dB) pure nothrow @nogc
{
    static immutable float ln10_20 = cast(float)LN10 / 20;
    return fast_exp(dB * ln10_20);
}
///ditto
double convertDecibelToLinearGain(double dB) pure nothrow @nogc
{
    static immutable double ln10_20 = cast(double)LN10 / 20;
    return fast_exp(dB * ln10_20);
}
unittest
{
    assert(convertDecibelToLinearGain(-float.infinity) == 0);
    assert(convertDecibelToLinearGain(-double.infinity) == 0);
}

/// Converts from linear gain to dB.
/// Precision: This uses fast_exp which under normal conditions has a peak 
/// error under -135dB over the useful range.
float convertLinearGainToDecibel(float x) pure nothrow @nogc
{
    static immutable float f20_ln10 = 20 / cast(float)LN10;
    return fast_log(x) * f20_ln10;
}
///ditto
double convertLinearGainToDecibel(double x) pure nothrow @nogc
{
    static immutable double f20_ln10 = 20 / cast(double)LN10;
    return fast_log(x) * f20_ln10;
}
unittest
{
    assert(convertLinearGainToDecibel(0.0f) == -float.infinity);
    assert(convertLinearGainToDecibel(0.0) == -double.infinity);
}

/// Converts from power to dB. 
/// Instantaneous power is the squared amplitude of a signal, and can be a 
/// nice domain to work in at times.
/// Precision: This uses fast_exp which under normal conditions has a peak error under -135dB over the useful range.
float convertPowerToDecibel(float x) pure nothrow @nogc
{
    // Explanation:
    //   20.log10(amplitude) 
    // = 20.log10(sqrt(power)) 
    // = 20.log10( 10^(0.5 * log10(power) )
    // = 10.log10(power)
    static immutable float f10_ln10 = 10 / cast(float)LN10;
    return fast_log(x) * f10_ln10;
}
///ditto
double convertPowerToDecibel(double x) pure nothrow @nogc
{
    static immutable double f10_ln10 = 10 / cast(double)LN10;
    return fast_log(x) * f10_ln10;
}

/// Is this integer odd?
bool isOdd(T)(T i) pure nothrow @nogc @safe
{
    return (i & 1) != 0;
}

/// Is this integer even?
bool isEven(T)(T i) pure nothrow @nogc @safe
{
    return (i & 1) == 0;
}

/// Returns: true of i is a power of 2.
bool isPowerOfTwo(int i) pure nothrow @nogc @safe
{
    assert(i >= 0);
    return (i != 0) && ((i & (i - 1)) == 0);
}

/// Returns: x, multiple of powerOfTwo, so that x >= n.
size_t nextMultipleOf(size_t n, size_t powerOfTwo) pure nothrow @nogc @safe
{
    // check power-of-two
    assert( (powerOfTwo != 0) && ((powerOfTwo & (powerOfTwo - 1)) == 0));

    size_t mask = ~(powerOfTwo - 1);
    return (n + powerOfTwo - 1) & mask;
}

unittest
{
    assert(nextMultipleOf(0, 4) == 0);
    assert(nextMultipleOf(1, 4) == 4);
    assert(nextMultipleOf(2, 4) == 4);
    assert(nextMultipleOf(3, 4) == 4);
    assert(nextMultipleOf(4, 4) == 4);
    assert(nextMultipleOf(5, 4) == 8);
}


/// Computes next power of 2.
/// Returns: N so that N is a power of 2 and N >= i.
/// Note: This function is not equivalent to the builtin `std.math.nextPow2` when the input is a power of 2.
int nextPow2HigherOrEqual(int i) pure nothrow @nogc
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

///ditto
long nextPow2HigherOrEqual(long i) pure nothrow @nogc
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

/// Mapping from MIDI notes to frequency.
float convertMIDINoteToFrequency(float note) pure nothrow @nogc
{
    return 440.0f * pow(2.0, (note - 69.0f) / 12.0f);
}

/// Mapping from frequency to MIDI notes.
float convertFrequencyToMIDINote(float frequency) pure nothrow @nogc
{
    return 69.0f + 12.0f * log2(frequency / 440.0f);
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

/// Gets a factor for making exponential decay curves, which are the same thing
/// as a 6dB/oct lowpass filter.
///
/// Returns: Multiplier for this RC time constant and sampling rate.
///
/// Params:
///    timeConstantInSeconds = Time after which the amplitude is only 37% of the original.
///    samplerate = Sampling rate.
///
/// Note: Using `fast_exp` yield a decay-factor within -180 dB (at 384000hz) of the one obtained with `expm1`.
///       The alleged "innacuracies" of plain exp just did not show up so we don't prefer `expm1` anymore.
///       It doesn't change the length of an iterated envelope like `ExpSmoother`.
///
double expDecayFactor(double timeConstantInSeconds, double samplerate) pure nothrow @nogc
{
    return 1.0 - fast_exp(-1.0 / (timeConstantInSeconds * samplerate));
}

/// Give back a phase between -PI and PI
T normalizePhase(T)(T phase) nothrow @nogc if (is(T == float) || is(T == double))
{
    static if (D_InlineAsm_Any)
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
    assert(isClose(normalizePhase!float(0.1f), 0.1f));
    assert(isClose(normalizePhase!float(TAU + 0.1f), 0.1f));

    assert(isClose(normalizePhase!double(-0.1f), -0.1f));
    assert(isClose(normalizePhase!double(-TAU - 0.1f), -0.1f));
}

/// Quick and dirty sawtooth for testing purposes.
T rawSawtooth(T)(T x) nothrow @nogc
{
    return normalizePhase(x) / (cast(T)PI);
}

/// Quick and dirty triangle for testing purposes.
T rawTriangle(T)(T x) nothrow @nogc
{
    return 1 - normalizePhase(x) / cast(T)PI_2;
}

/// Quick and dirty square for testing purposes.
T rawSquare(T)(T x) nothrow @nogc
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

// Expose LDC intrinsics, but usable with DMD too.

version(LDC)
{
    // Note: wrapper functions wouldn't work (depend on inlining), 
    //       it's much more reliable to use alias for speed gain.

    // Gives considerable speed improvement over `std.math.exp`.
    // Exhaustive testing for 32-bit `float` shows
    // Relative accuracy is within < 0.0002% of std.math.exp
    // for every possible input.
    // So a -120 dB inaccuracy, and -140dB the vast majority of the time.
    alias fast_exp = llvm_exp; 


    alias fast_log = llvm_log;

    // Note: fast_pow with a float argument (`powf`) can be a lot faster that with a double argument.
    alias fast_pow = llvm_pow;

    // Gives measurable speed improvement at audio-rate, without change for any input.
    alias fast_fabs = llvm_fabs;


    alias fast_log2 = llvm_log2;
    alias fast_exp2 = llvm_exp2;
    alias fast_log10 = llvm_log10;

    alias fast_floor = llvm_floor;
    alias fast_ceil = llvm_ceil;
    alias fast_trunc = llvm_trunc;
    alias fast_round = llvm_round;

    alias fast_sqrt = llvm_sqrt;
    alias fast_sin = llvm_sin;
    alias fast_cos = llvm_cos; // no speed change seen when using it
}
else
{
    alias fast_exp = exp;
    alias fast_log = log;
    alias fast_pow = pow;

    alias fast_fabs = fabs;
    alias fast_log2 = log2;
    alias fast_exp2 = exp2;
    alias fast_log10 = log10;

    alias fast_floor = floor;
    alias fast_ceil = ceil;
    alias fast_trunc = trunc;
    alias fast_round = round;

    alias fast_sqrt = sqrt; // Undefined behaviour for operands below -0
    alias fast_sin = sin;
    alias fast_cos = cos;
}

unittest
{
    assert(isClose(fast_exp2(0.1), std.math.exp2(0.1)));
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

/// Computes a normalized frequency form a frequency.
float convertFrequencyToNormalizedFrequency(float frequencyHz, float samplingRate) pure nothrow @nogc
{
    return frequencyHz / samplingRate;
}

/// Computes a frequency.
float convertNormalizedFrequencyToFrequency(float frequencyCyclesPerSample, float samplingRate) pure nothrow @nogc
{
    return frequencyCyclesPerSample * samplingRate;
}

