/**
    DSP utility functions.
    They are a range of math function usual in DSP.

    Copyright: Guillaume Piolat 2015-2024.
    License:   http://www.boost.org/LICENSE_1_0.txt
*/
module dplug.core.math;

import std.math;
version(LDC) import ldc.intrinsics;

nothrow @nogc:


/**
    TAU is two times PI.
*/
immutable real TAU = PI * 2;


/**
    Map linearly x from the range [a, b] to the range [c, d].
*/
T linmap(T)(T value, T a, T b, T c, T d) pure
{
    return c + (d - c) * (value - a) / (b - a);
}
unittest
{
    double f = linmap(0.5f, 0.0, 2.0, 4.0, 5.0);
    assert( f == 4.25 );
}


/**
    Map the `[0..1]` range to `[min..max]` logarithmically.

    Params:
        t   = Interpolating value from [0 to 1]. UB if out of range.
        min = Value corresponding to t = 0. Must be > 0.
        max = Value corresponding to t = 1. Must be > 0.

    Note: You can totally have a max that is smaller than min.
          In this case, the range mapped with more accuracy will be
          small values (around `max` not `min`).
*/
T logmap(T)(T t, T min, T max) pure
{
    assert(min > 0 && max > 0);
    return min * exp(t * log(max / min));
}
unittest
{
    assert(isCloseRel(logmap!float(0.5f, 2.0f, 200.0f), 20.0f));
}


/**
    Gets a factor for making exponential decay curves, which are also
    the same thing as a 6dB/oct lowpass filter.

    Params:
        timeConstantSecs = Time after which the amplitude is only 37%
                           of the original.
        samplerate       = Sampling rate.

    Returns:
        Multiplier for this RC time constant and sampling rate.
        Use it like this: `smoothed += (v - smoothed) * result;`

    Note:
        Using `fast_exp` yield a decay-factor within -180 dB
        (at 384000hz) of the one obtained with `expm1`.
        The alleged inaccuracies of plain exp just did not show up so
        we don't prefer `expm1` anymore. This doesn't change the
        length of an iterated envelope like `ExpSmoother`.
        Actually, small variations of a decay factor often results in
        a misleadingly large RMS difference, that doesn't actually
        change the sound quality.
*/
double expDecayFactor(double timeConstantSecs,
                      double samplerate) pure
{
    return 1.0 - fast_exp(-1.0 / (timeConstantSecs * samplerate));
}


/**
    Map from MIDI notes to frequency (Hz).
*/
float convertMIDINoteToFrequency(float note) pure
{
    return 440.0f * pow(2.0, (note - 69.0f) / 12.0f);
}


/**
    Map from frequency (Hz) to MIDI notes.
*/
float convertFrequencyToMIDINote(float frequency) pure
{
    return 69.0f + 12.0f * log2(frequency / 440.0f);
}


/**
    Converts from decibels (dB) to linear gain (aka. voltage).

    Params:
        x Value in decibels. Can be -infinity.

    Returns:
        A voltage value, linear gain.

    Note:    0 dB is 1.0 in linear gain.
            -6 dB is 0.5 in linear gain.
          -inf dB is 0.0 in linear gain.

    Precision: This uses fast_exp which under normal conditions has a
               peak error under -135dB over the useful range.
               However, keep in mind that different exp function sound
               differently when modulated.
*/
float convertDecibelToLinearGain(float dB) pure @safe
{
    static immutable float ln10_20 = cast(float)LN10 / 20;
    return fast_exp(dB * ln10_20);
}
///ditto
double convertDecibelToLinearGain(double dB) pure @safe
{
    static immutable double ln10_20 = cast(double)LN10 / 20;
    return fast_exp(dB * ln10_20);
}
unittest
{
    assert(convertDecibelToLinearGain(-float.infinity) == 0);
    assert(convertDecibelToLinearGain(-double.infinity) == 0);
}


/**
    Converts from linear gain (voltage) to decibels (dB).

    Params:
        x Linear gain. Must be >= 0.

    Returns:
        A decibel value.

    Note: 1.0 linear gain is    0 dB in decibels.
          0.5 linear gain is   -6 dB in decibels.
          0.0 linear gain is -inf dB in decibels.

    Precision: This uses `fast_exp` which under normal conditions has
               a peak error under -135dB over the useful range.
*/
float convertLinearGainToDecibel(float x) pure @safe
{
    static immutable float f20_ln10 = 20 / cast(float)LN10;
    return fast_log(x) * f20_ln10;
}
///ditto
double convertLinearGainToDecibel(double x) pure @safe
{
    static immutable double f20_ln10 = 20 / cast(double)LN10;
    return fast_log(x) * f20_ln10;
}
unittest
{
    assert(convertLinearGainToDecibel(0.0f) == -float.infinity);
    assert(convertLinearGainToDecibel(0.0) == -double.infinity);
}

/**
    Converts a power value to decibels (dB).

    Instantaneous power is the squared amplitude of a signal, and can
    be a nice domain to work in at times.

    Precision: This uses `fast_exp` which under normal conditions has
               a peak error under -135 dB over the useful range.
*/
float convertPowerToDecibel(float x) pure @safe
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
double convertPowerToDecibel(double x) pure @safe
{
    static immutable double f10_ln10 = 10 / cast(double)LN10;
    return fast_log(x) * f10_ln10;
}


/// Linear interpolation, akin to GLSL's mix.
S lerp(S, T)(S a, S b, T t) pure
    if (is(typeof(t * b + (1 - t) * a) : S))
{
    return t * b + (1 - t) * a;
}

/// Same as GLSL smoothstep function.
/// See: http://en.wikipedia.org/wiki/Smoothstep
T smoothStep(T)(T a, T b, T t) pure
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


/**
    Normalized sinc function.
    Returns: `sin(PI*x)/(PI*x)`.
*/
T sinc(T)(T x) pure
{
    if (cast(T)(1) + x * x == cast(T)(1))
        return 1;
    else
        return sin(cast(T)PI * x) / (cast(T)PI * x);
}
unittest
{
    assert(sinc(0.0) == 1.0);
}


/// Give back a phase between -PI and PI
T normalizePhase(T)(T phase) if (is(T == float) || is(T == double))
{
    static if (D_InlineAsm_Any)
    {
        T k_TAU = PI * 2;
        T result = phase;
        asm nothrow @nogc
        {
            fld k_TAU;    // TAU
            fld result;   // phase | TAU
            fprem1;       // normalized(phase) | TAU
            fstp result;  // TAU
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
    assert(isCloseRel(normalizePhase!float(0.1f), 0.1f));
    assert(isCloseRel(normalizePhase!float(TAU + 0.1f), 0.1f));
    assert(isCloseRel(normalizePhase!double(-0.1f), -0.1f));
    assert(isCloseRel(normalizePhase!double(-TAU - 0.1f), -0.1f));
}


/**
    Hermite interpolation.

    Params:
        f_pos = Position of interpolation between (0 to 1).
                0 means at position x0, 1 at position x1.
        xm1   = Value of f(x-1)
        x0    = Value of f(x)
        x1    = Value of f(x+1)
        x2    = Value of f(x+2)

    Returns:
        An interpolated value corresponding to `f(x0 + f_pos)`.
*/
T hermiteInterp(T)(T f_pos, T xm1, T x0, T x1, T x2) pure
{
    T c = (x1 - xm1) * 0.5f;
    T v = x0 - x1;
    T w = c + v;
    T a = w + v + (x2 - x0) * 0.5f;
    T b_neg = w + a;
    return ((((a * f_pos) - b_neg) * f_pos + c) * f_pos + x0);
}
deprecated("Renamed to hermiteInterp") alias hermite = hermiteInterp;


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
    // So a -120 dB inaccuracy, and -140dB the vast majority of the
    // time.
    alias fast_exp = llvm_exp;


    alias fast_log = llvm_log;

    // Note: fast_pow with a float argument (`powf`) can be a lot
    // faster that with a double argument.
    alias fast_pow = llvm_pow;

    // Gives measurable speed improvement at audio-rate, without
    // change for any input.
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

    alias fast_sqrt = sqrt; // UB for operands below -0
    alias fast_sin = sin;
    alias fast_cos = cos;
}


/**
    Compute the next higher multiple of a pow^2 number.

    Returns:
        `x`, multiple of `powerOfTwo`, so that `x >= n`.
*/
size_t nextMultipleOf(size_t n, size_t powerOfTwo) pure @safe
{
    // FUTURE: why is it here in dplug:core?

    // check power-of-two
    assert((powerOfTwo != 0) && ((powerOfTwo & (powerOfTwo-1)) == 0));

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


/**
    Computes next power of 2.

    Returns:
        `N` so that `N` is a power of 2 and `N >= i`.

    Note: This function is NOT equivalent to the builtin
          `std.math.nextPow2` when the input is a power of 2.
*/
int nextPow2HigherOrEqual(int i) pure
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
long nextPow2HigherOrEqual(long i) pure
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
unittest
{
    assert(nextPow2HigherOrEqual(0) == 0);
    assert(nextPow2HigherOrEqual(64) == 64);
    assert(nextPow2HigherOrEqual(65L) == 128);
}


/// Returns: true of i is a power of 2.
bool isPowerOfTwo(int i) pure @safe
{
    assert(i >= 0);
    return (i != 0) && ((i & (i - 1)) == 0);
}



// -------- LINE OF DEPRECATION AREA -----------

/**
    Integer log, rounds towards -inf.

    Returns: x so that (1 << x) >= i

    FUTURE: Why is that in dplug:core?
*/
deprecated("Will be removed in Dplug v16") 
int iFloorLog2(int i) pure @safe
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

/// Fletcher and Munson equal-loudness curve
/// Reference: Xavier Serra thesis (1989).
deprecated("equalLoudnessCurve will be removed in Dplug v16")
T equalLoudnessCurve(T)(T frequency) pure
{
    T x = cast(T)0.05 + 4000 / frequency;
    return x * ( cast(T)10 ^^ x);
}

/// Is this integer odd?
deprecated bool isOdd(T)(T i) pure @safe
{
    return (i & 1) != 0;
}

/// Is this integer even?
deprecated bool isEven(T)(T i) pure @safe
{
    return (i & 1) == 0;
}

/// SSE approximation of reciprocal square root.
deprecated("WARNING: approximation. Use _mm_rsqrt_ss (approx) or 1/sqrt(x) (precise) instead")
T inverseSqrt(T)(T x) @nogc if (is(T : float) || is(T: double))
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

deprecated("use frequencyHz * samplingRate instead")
float convertFrequencyToNormalizedFrequency(float frequencyHz,
                                            float samplingRate) pure
{
    return frequencyHz / samplingRate;
}

deprecated("use freqCyclesPerSample * samplingRate instead")
float convertNormalizedFrequencyToFrequency(float freqCyclesPerSample,
                                            float samplingRate) pure
{
    return freqCyclesPerSample * samplingRate;
}

/// Quick and dirty sawtooth for testing purposes.
deprecated("rawSawtooth will be removed in Dplug v16")
T rawSawtooth(T)(T x)
{
    return normalizePhase(x) / (cast(T)PI);
}

/// Quick and dirty triangle for testing purposes.
deprecated("rawTriangle will be removed in Dplug v16")
T rawTriangle(T)(T x)
{
    return 1 - normalizePhase(x) / cast(T)PI_2;
}

/// Quick and dirty square for testing purposes.
deprecated("rawSquare will be removed in Dplug v16")
T rawSquare(T)(T x)
{
    return normalizePhase(x) > 0 ? 1 : -1;
}

deprecated("computeRMS will be removed in Dplug v16")
T computeRMS(T)(T[] samples) pure
{
    double sum = 0;
    foreach(sample; samples)
        sum += sample * sample;
    return sqrt(sum / cast(int)samples.length);
}

version(unittest)
private bool isCloseRel(double a, double b, double maxRelDiff = 1e-2f)
{
    if (a < 0)
    {
        a = -a;
        b = -b;
    }
    
    if (a == 0)
        return b == 0;

    return
       (a <= b *(1.0 + maxRelDiff))
       &&
       (b <= a *(1.0 + maxRelDiff));
}
