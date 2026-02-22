/**
    Basic IIR 1-pole and 2-pole filters through biquads or
    similar structures.

    Copyright: Guillaume Piolat (c) 2015-2026.
    Copyright: Yuriy Ivantsov (c) 2025-2026.
    License:   http://www.boost.org/LICENSE_1_0.txt, BSL-1.0

    This introduces 4 concepts:

       - `BiquadCoeff` holds filter coefficients for a
          "biquad", up to two poles and two zeroes,

       - `BiquadDelay` is a processor where the filtering
          happens, designed for **unchanging** coefficients,

       - `InterpolatedBiquad` is an alternative processor
         who smooth coefficient and allow to modulate
         filtering over time without clicks.

       - `IvantsovIIR`, an easy to use struct with fast and
         decramped 1st-order and 2nd-order filters.

    Reference:
        https://en.wikipedia.org/wiki/Digital_biquad_filter
        https://github.com/yIvantsov/ivantsov-filters
*/
module dplug.dsp.iir;

import std.math: SQRT2, SQRT1_2, PI, pow, sin, cos, sqrt;
import std.complex: Complex,
                    complexAbs = abs,
                    complexExp = exp,
                    complexsqAbs = sqAbs,
                    complexFromPolar = fromPolar;
import dplug.core.math;
import inteli.emmintrin;

nothrow @nogc:



/*

 ▄▄▄▄▄▄       ██                                         ▄▄
 ██▀▀▀▀██     ▀▀                                         ██
 ██    ██   ████      ▄███▄██  ██    ██   ▄█████▄   ▄███▄██
 ███████      ██     ██▀  ▀██  ██    ██   ▀ ▄▄▄██  ██▀  ▀██
 ██    ██     ██     ██    ██  ██    ██  ▄██▀▀▀██  ██    ██
 ██▄▄▄▄██  ▄▄▄██▄▄▄  ▀██▄▄███  ██▄▄▄███  ██▄▄▄███  ▀██▄▄███
 ▀▀▀▀▀▀▀   ▀▀▀▀▀▀▀▀    ▀▀▀ ██   ▀▀▀▀ ▀▀   ▀▀▀▀ ▀▀    ▀▀▀ ▀▀
                           ██


                                  ▄▄▄▄      ▄▄▄▄
                                 ██▀▀▀     ██▀▀▀
  ▄█████▄   ▄████▄    ▄████▄   ███████   ███████   ▄▄█████▄
 ██▀    ▀  ██▀  ▀██  ██▄▄▄▄██    ██        ██      ██▄▄▄▄ ▀
 ██        ██    ██  ██▀▀▀▀▀▀    ██        ██       ▀▀▀▀██▄
 ▀██▄▄▄▄█  ▀██▄▄██▀  ▀██▄▄▄▄█    ██        ██      █▄▄▄▄▄██
   ▀▀▀▀▀     ▀▀▀▀      ▀▀▀▀▀     ▀▀        ▀▀       ▀▀▀▀▀▀
*/


/**
    Type which holds the 5 biquad coefficients.
    Important: Coefficients are considered normalized by a0.

    Note: coeff[0] is b0,
          coeff[1] is b1,
          coeff[2] is b2,
          coeff[3] is a1,
          coeff[4] is a2 in the litterature.
*/
alias BiquadCoeff = double[5];


/**
    Identity biquad, pass signal unchanged.
*/
BiquadCoeff biquadBypass()
{
    return [1.0, 0, 0, 0, 0];
}


/**
    Zero biquad, gives silent output (zeroes).
*/
BiquadCoeff biquadZero()
{
    return [0.0, 0, 0, 0, 0];
}


/**
    Make coefficients for a 1-pole low-pass filter.

    Params:
        fc_hz = Cutoff frequency. -3 dB gain at this point,
                in the valid range.

                Can be >= nyquist, in which case the
                filter asymptotically approaches a
                bypass filter.

                Can be <= 0Hz, in which case the filter
                gives zeroes (DC-normalized).

        sr_hz = Sampling-rate.

    Note: Cutoff frequency can be >= nyquist, in which
          case it asymptotically approaches a bypass.

          This filter is normalized on DC.
          Always have -3 dB at cutoff in the valid range.
*/
BiquadCoeff biquadOnePoleLowPass(double fc_hz,
                                 double sr_hz)
{
    double fc_norm = fc_hz / sr_hz;
    if (fc_norm < 0.0f)
        fc_norm = 0.0f;
    double t2 = fast_exp(-2.0 * PI * fc_norm);
    BiquadCoeff r;
    r[0] = 1 - t2;
    r[1] = 0;
    r[2] = 0;
    r[3] = -t2;
    r[4] = 0;
    return r;
}


/**
    Make coefficients for a 1-pole high-pass filter.

    Params:

        fc_hz = Cutoff frequency. -3 dB gain at this point,
                in the valid range.
                Can be <= 0Hz, in which case the filter
                is a bypass (DC-normalized).

        sr_hz = Sampling-rate.

    Very high cutoff frequency do NOT give zero.

    Reference: https://www.dspguide.com/ch19/2.html
*/
BiquadCoeff biquadOnePoleHighPass(double fc_hz,
                                  double sr_hz)
{
    double fc_norm = fc_hz / sr_hz;
    if (fc_norm < 0.0f)
        fc_norm = 0.0f;
    double t2 = fast_exp(-2.0 * PI * fc_norm);
    BiquadCoeff r;
    r[0] = (1 + t2) * 0.5;
    r[1] = -(1 + t2) * 0.5;
    r[2] = 0;
    r[3] = -t2;
    r[4] = 0;
    return r;
}


/**
    2-pole Bessel design low-pass filter.

    This is fantastic smoother for eg. gain signals that has
    a fast and flat phase response, at the expensive of
    selectivity.
*/
BiquadCoeff biquadBesselLowPass(double fc_hz, double sr_hz)
{
    double normalW = 0;
    Complex!double P0 = Complex!double(-1.5 ,  0.8660);
    Complex!double P1 = Complex!double(-1.5 , -0.8660);
    double fc = fc_hz / sr_hz;
    double T = fc * 2 * PI;
    // matched Z transform
    P0 = complexExp(P0 * T);
    P1 = complexExp(P1 * T);
    Complex!double Z01 = Complex!double(-1.0, 0.0);
    BiquadCoeff coeff = biquad2Poles(P0, Z01, P1, Z01);
    // normalize on DC gain = 1
    double scale = 1 / complexAbs(biquadResponse(coeff, 0));
    return biquadApplyGain(coeff, scale);
}
unittest
{
    BiquadCoeff c = biquadBesselLowPass(20000, 44100);
}


/**
    1-pole low-pass filter, mapping is not precise.
    Not advised! Not accurate across sample rates, but
    coefficient computation is cheap.
*/
deprecated("This will be removed in Dplug v17, try to match"
          ~"with biquadOnePoleLowPass")
BiquadCoeff biquadOnePoleLowPassImprecise(double frequency,
    double samplerate)
{
    double t0 = frequency / samplerate;
    if (t0 > 0.5f)
        t0 = 0.5f;

    double t1 = (1 - 2 * t0);
    double t2  = t1 * t1;

    BiquadCoeff result;
    result[0] = cast(float)(1 - t2);
    result[1] = 0;
    result[2] = 0;
    result[3] = cast(float)(-t2);
    result[4] = 0;
    return result;
}

/**
    1-pole high-pass filter, mapping is not precise.
    Not advised! Not accurate across sample rates, but
    coefficient computation is cheap.
*/
deprecated("This will be removed in Dplug v17, try to match"
          ~"with biquadOnePoleHighPass")
BiquadCoeff biquadOnePoleHighPassImprecise(double frequency,
    double samplerate)
{
    double t0 = frequency / samplerate;
    if (t0 > 0.5f)
        t0 = 0.5f;

    double t1 = (2 * t0);
    double t2 = t1 * t1;

    BiquadCoeff result;
    result[0] = cast(float)(1 - t2);
    result[1] = 0;
    result[2] = 0;
    result[3] = cast(float)(t2);
    result[4] = 0;
    return result;
}

// Cookbook formulae for audio EQ biquad filter coefficients
// by Robert Bristow-Johnson.

/**
    2-pole Low-pass filter (12 dB/oct).
    Follows Robert Bristow-Johnson "RBJ cookbook" formulae.

    Params:
        fc_hz = Cutoff frequency.
        sr_hz = Sample rate.
        Q     = Resonance (or "Quality") parameter.

    Returns:
        Biquad coefficients.

    Note:
        When Q = sqrt(1/2), this is equivalent to a 2-pole
                 Butterworth design (default).
        When Q = 0.5, this is a "critically damped" 2-pole
                 design.
        But this doesn't hold when chaining such filters.

    Important:
        IIR filters with the same design, same cutoff
        frequency, and same Q factor yield the same phase
        response.
*/
BiquadCoeff biquadRBJLowPass(double fc_hz,
                             double sr_hz,
                             double Q = SQRT1_2)
{
    return genRBJBiquad(RBJBiquadType.LOW_PASS_FILTER,
        fc_hz, sr_hz, 0, Q);
}

/**
    2-pole High-pass filter (12 dB/oct).
    Follows Robert Bristow-Johnson "RBJ cookbook" formulae.

    Params:
        fc_hz = Cutoff frequency.
        sr_hz = Sample rate.
        Q     = Resonance (or "Quality") parameter.

    Returns:
        Biquad coefficients.

    Note:
        When Q = sqrt(1/2), this is equivalent to a 2-pole
                 Butterworth design (default).
        When Q = 0.5, this is a "critically damped" 2-pole
                 design.
        But this doesn't hold when chaining such filters.

    Important:
        IIR filters with the same design, same cutoff
        frequency, and same Q factor yield the same phase
        response.
*/
BiquadCoeff biquadRBJHighPass(double fc_hz,
                              double sr_hz, double
                              Q = SQRT1_2)
{
    return genRBJBiquad(RBJBiquadType.HIGH_PASS_FILTER,
        fc_hz, sr_hz, 0, Q);
}


/**
    2-pole All-pass filter.
    Follows Robert Bristow-Johnson "RBJ cookbook" formulae.

    Params:
        fc_hz = Cutoff frequency.
        sr_hz = Sample rate.
        Q     = Resonance (or "Quality") parameter.

    Returns:
        Biquad coefficients.

    Note:
        When Q = sqrt(1/2), this is equivalent to a 2-pole
                 Butterworth design (default).
        When Q = 0.5, this is a "critically damped" 2-pole
                 design.
        But this doesn't hold when chaining such filters.
*/
BiquadCoeff biquadRBJAllPass(double fc_hz,
                             double sr_hz,
                             double Q = SQRT1_2)
{
    return genRBJBiquad(RBJBiquadType.ALL_PASS_FILTER,
        fc_hz, sr_hz, 0, Q);
}


/**
    2-pole Band-pass filter (12 dB/oct).
    Follows Robert Bristow-Johnson "RBJ cookbook" formulae.

    Params:
        fc_hz = Cutoff frequency.
        sr_hz = Sample rate.
        Q     = Resonance (or "Quality") parameter.

    Returns:
        Biquad coefficients.

    Note:
        When Q = sqrt(1/2), this is equivalent to a 2-pole
                 Butterworth design (default).
        When Q = 0.5, this is a "critically damped" 2-pole
                 design.
        But this doesn't hold when chaining such filters.

    Important:
        IIR filters with the same design, same cutoff
        frequency, and same Q factor yield the same phase
        response.
*/
BiquadCoeff biquadRBJBandPass(double fc_hz,
                              double sr_hz,
                              double Q = SQRT1_2)
{
    return genRBJBiquad(RBJBiquadType.BAND_PASS_FILTER,
        fc_hz, sr_hz, 0, Q);
}


/**
    2-pole Notch filter (12 dB/oct).
    Follows Robert Bristow-Johnson "RBJ cookbook" formulae.

    Params:
        fc_hz = Cutoff frequency.
        sr_hz = Sample rate.
        Q     = Resonance (or "Quality") parameter.

    Returns:
        Biquad coefficients.

    Note:
        When Q = sqrt(1/2), this is equivalent to a 2-pole
                 Butterworth design (default).
        When Q = 0.5, this is a "critically damped" 2-pole
                 design.
        But this doesn't hold when chaining such filters.
*/
BiquadCoeff biquadRBJNotch(double fc_hz,
                           double sr_hz,
                           double Q = SQRT1_2)
{
    return genRBJBiquad(RBJBiquadType.NOTCH_FILTER,
        fc_hz, sr_hz, 0, Q);
}

/**
    2-pole Peak filter (12 dB/oct).
    Follows Robert Bristow-Johnson "RBJ cookbook" formulae.

    Params:
        fc_hz   = Cutoff frequency.
        sr_hz   = Sample rate.
        gain_dB = Gain of peak filter at `fc_hz`.
        Q       = Resonance (or "Quality") parameter.

    Returns:
        Biquad coefficients.

    Note:
        When Q = sqrt(1/2), this is equivalent to a 2-pole
                 Butterworth design (default).
        When Q = 0.5, this is a "critically damped" 2-pole
                 design.
        But this doesn't hold when chaining such filters.
*/
BiquadCoeff biquadRBJPeak(double fc_hz,
                          double sr_hz,
                          double gain_dB,
                          double Q = SQRT1_2)
{
    return genRBJBiquad(RBJBiquadType.PEAK_FILTER,
        fc_hz, sr_hz, gain_dB, Q);
}


/**
    2-pole Low-shelf filter.
    Follows Robert Bristow-Johnson "RBJ cookbook" formulae.

    Params:
        fc_hz   = Mid-point frequency.
        sr_hz   = Sample rate.
        gain_dB = Gain at midpoint frequency `fc_hz`.
        Q       = Resonance (or "Quality") parameter.

    Returns:
        Biquad coefficients.

    Warning: Actual shelf gain is twice the `gain_dB`,
        which specifies a gain at the **mid-point**. This
        will break your expectations.

    FUTURE: the commonly accepted way is to be the full
        extent in dB. That would be breaking.
*/
BiquadCoeff biquadRBJLowShelf(double fc_hz,
                              double sr_hz,
                              double gain_dB,
                              double Q = SQRT1_2)
{
    return genRBJBiquad(RBJBiquadType.LOW_SHELF,
        fc_hz, sr_hz, gain_dB, Q);
}


/**
    2-pole High-shelf filter.
    Follows Robert Bristow-Johnson "RBJ cookbook" formulae.

    Params:
        fc_hz   = Mid-point frequency.
        sr_hz   = Sample rate.
        gain_dB = Gain at the midpoint frequency `fc_hz`.
        Q       = Resonance (or "Quality") parameter.

    Returns:
        Biquad coefficients.

    Warning: Actual shelf gain is twice the `gain_dB`,
        which specifies a gain at the **mid-point**. This
        will break your expectations.

    Warning: That one sounds particularly bad near Nyquist.

    FUTURE: the commonly accepted way is to be the full
        extent in dB. That would be breaking.
*/
BiquadCoeff biquadRBJHighShelf(double fc_hz,
                               double sr_hz,
                               double gain_dB,
                               double Q = SQRT1_2)
{
    return genRBJBiquad(RBJBiquadType.HIGH_SHELF,
        fc_hz, sr_hz, gain_dB, Q);
}


/**
    Compute biquad coefficients directly from digital poles
    and zeroes.
*/
BiquadCoeff biquad2Poles(Complex!double pole1,
                         Complex!double zero1,
                         Complex!double pole2,
                         Complex!double zero2)
{
    // Note: either it's a double pole, or two pole on the
    // real axis. Same for zeroes

    assert(complexAbs(pole1) <= 1);
    assert(complexAbs(pole2) <= 1);

    double a1;
    double a2;
    double epsilon = 0;

    if (pole1.im != 0)
    {
        assert(pole1.re == pole2.re);
        assert(pole1.im == -pole2.im);
        a1 = -2 * pole1.re;
        a2 = complexsqAbs(pole1);
    }
    else
    {
        assert(pole2.im == 0);
        a1 = -(pole1.re + pole2.re);
        a2 =   pole1.re * pole2.re;
    }

    const double b0 = 1;
    double b1;
    double b2;

    if (zero1.im != 0)
    {
        assert(zero2.re == zero2.re);
        assert(zero2.im == -zero2.im);
        b1 = -2 * zero1.re;
        b2 = complexsqAbs(zero1);
    }
    else
    {
        assert(zero2.im == 0);
        b1 = -(zero1.re + zero2.re);
        b2 =   zero1.re * zero2.re;
    }

    return [b0, b1, b2, a1, a2];
}

/**
    Apply a gain to a biquad fitler so that the output is
    scaled by a factor `scale`.

    This is achieved by scaling numerator coefficients.

    Params:
        coeffs     = Input biquad coefficients.
        gain_lin   = Linear gain to apply.

    Returns:
        Biquad coefficients whose numerator is scaled.

*/
BiquadCoeff biquadApplyGain(BiquadCoeff coeffs,
                            double gain_lin)
{
    coeffs[0] *= gain_lin;
    coeffs[1] *= gain_lin;
    coeffs[2] *= gain_lin;
    return coeffs;
}
deprecated("Use biquadApplyGain instead")
    alias biquadApplyScale = biquadApplyGain;


/**
    Compute biquad response at the given normalized
    frequency `frequency_norm`.

    Params:
        coeffs = Biquad coefficients.
        frequency_norm = Normalized frequency. 0 means 0 Hz
                         whereas 0.5 means Nyquist.

    Returns:
        Complex response of the filter at that frequency
        (phase and amplitude).
*/
Complex!double biquadResponse(BiquadCoeff coeffs,
                              double frequency_norm)
{
    static Complex!double addmul(Complex!double c,
                                 double v,
                                 Complex!double c1)
    {
        return Complex!double(c.re + v * c1.re,
                              c.im + v * c1.im);
    }

    double w = 2 * PI * frequency_norm;
    Complex!double czn1 = complexFromPolar (1.0,     -w);
    Complex!double czn2 = complexFromPolar (1.0, -2 * w);
    Complex!double ch = 1.0;
    Complex!double cbot = 1.0;
    Complex!double cb = 1.0;
    Complex!double ct = coeffs[0];     // b0
    ct = addmul (ct, coeffs[1], czn1); // b1
    ct = addmul (ct, coeffs[2], czn2); // b2
    cb = addmul (cb, coeffs[3], czn1); // a1
    cb = addmul (cb, coeffs[4], czn2); // a2
    ch   *= ct;
    cbot *= cb;
    return ch / cbot;
}










/*
 ▄▄▄▄▄▄       ██                                         ▄▄
 ██▀▀▀▀██     ▀▀                                         ██
 ██    ██   ████      ▄███▄██  ██    ██   ▄█████▄   ▄███▄██
 ███████      ██     ██▀  ▀██  ██    ██   ▀ ▄▄▄██  ██▀  ▀██
 ██    ██     ██     ██    ██  ██    ██  ▄██▀▀▀██  ██    ██
 ██▄▄▄▄██  ▄▄▄██▄▄▄  ▀██▄▄███  ██▄▄▄███  ██▄▄▄███  ▀██▄▄███
 ▀▀▀▀▀▀▀   ▀▀▀▀▀▀▀▀    ▀▀▀ ██   ▀▀▀▀ ▀▀   ▀▀▀▀ ▀▀    ▀▀▀ ▀▀
                           ██


 ▄▄▄▄▄               ▄▄▄▄
 ██▀▀▀██             ▀▀██
 ██    ██   ▄████▄     ██       ▄█████▄  ▀██  ███
 ██    ██  ██▄▄▄▄██    ██       ▀ ▄▄▄██   ██▄ ██
 ██    ██  ██▀▀▀▀▀▀    ██      ▄██▀▀▀██    ████▀
 ██▄▄▄██   ▀██▄▄▄▄█    ██▄▄▄   ██▄▄▄███     ███
 ▀▀▀▀▀       ▀▀▀▀▀      ▀▀▀▀    ▀▀▀▀ ▀▀     ██
                                          ███
*/


/**
    Basic filter for one channel, maintain state for a
    single biquad.

    Hence, can model two poles and two zeroes.
*/
struct BiquadDelay
{
public nothrow @nogc:

    // State
    double _x0;
    double _x1;
    double _y0;
    double _y1;

    /**
        Initialize to silence. Necessary before processing.
     */
    void initialize()
    {
        _x0 = 0;
        _x1 = 0;
        _y0 = 0;
        _y1 = 0;
    }

    /**
        Process a single sample through the biquad filter.

        Performance: This is rather inefficient, in general
        you'll prefer to use the `nextBuffer` and operate on
        buffers.

        Params:
            input = Input audio sample.
            coeff = Biquad coefficients.

        Returns: Output audio sample.
    */
    float nextSample(float input,
                     const(BiquadCoeff) coeff)
    {
        double x1 = _x0,
               x2 = _x1,
               y1 = _y0,
               y2 = _y1;

        double a0 = coeff[0],
               a1 = coeff[1],
               a2 = coeff[2],
               a3 = coeff[3],
               a4 = coeff[4];

        double cur = a0 * input + a1 * x1 + a2 * x2
                   - a3 * y1 - a4 * y2;
        _x0 = input;
        _x1 = x1;
        _y0 = cur;
        _y1 = y1;

        return cur;
    }
    ///ditto
    double nextSample(double input,
                      const(BiquadCoeff) coeff)
    {
        double x1 = _x0,
               x2 = _x1,
               y1 = _y0,
               y2 = _y1;

        double a0 = coeff[0],
               a1 = coeff[1],
               a2 = coeff[2],
               a3 = coeff[3],
               a4 = coeff[4];

        double cur = a0 * input + a1 * x1 + a2 * x2
                   - a3 * y1 - a4 * y2;

        _x0 = input;
        _x1 = x1;
        _y0 = cur;
        _y1 = y1;

        return cur;
    }


    /**
        Process `frames` samples through the biquad filter.

        Params:
            input  = Input audio samples.
            output = Output audio samples.
            frames = Number of audio samples in buffers.
            coeff  = Biquad coefficients.
    */
    void nextBuffer(const(float)*      input,
                    float*            output,
                    int               frames,
                    const(BiquadCoeff) coeff)
    {
        // This SIMD intrinsics optimization makes 
        // Panagement 2 10% slower in Windows arm64, disabled
        version(LDC)
        {
            version(X86)
                enum bool enableInteli = true;
            else version(X86_64)
                enum bool enableInteli = true;
            else
                enum bool enableInteli = false;
        }
        else 
            enum bool enableInteli = false;


        static if (enableInteli)
        {
            double x0 = _x0,
                   x1 = _x1,
                   y0 = _y0,
                   y1 = _y1;

            double a0 = coeff[0],
                   a1 = coeff[1],
                   a2 = coeff[2],
                   a3 = coeff[3],
                   a4 = coeff[4];

            __m128d XMM0 = _mm_set_pd(x1, x0);
            __m128d XMM1 = _mm_set_pd(y1, y0);
            __m128d XMM2 = _mm_set_pd(a2, a1);
            __m128d XMM3 = _mm_set_pd(a4, a3);
            __m128d XMM4 = _mm_set_sd(a0);

            __m128d XMM6 = _mm_undefined_pd();
            __m128d XMM7 = _mm_undefined_pd();
            __m128d XMM5 = _mm_undefined_pd();

            for (int n = 0; n < frames; ++n)
            {
                __m128 INPUT =  _mm_load_ss(input + n);
                XMM5 = _mm_setzero_pd();
                XMM5 = _mm_cvtss_sd(XMM5,INPUT);
                XMM6 = XMM0;
                XMM7 = XMM1;
                XMM5 = _mm_mul_pd(XMM5, XMM4);
                XMM6 = _mm_mul_pd(XMM6, XMM2);
                XMM7 = _mm_mul_pd(XMM7, XMM3);
                XMM5 = _mm_add_pd(XMM5, XMM6);
                XMM5 = _mm_sub_pd(XMM5, XMM7);
                XMM6 = XMM5;
                XMM0 = cast(double2)
                    _mm_slli_si128!8(cast(__m128i) XMM0);
                XMM6 = cast(double2)
                    _mm_srli_si128!8(cast(__m128i) XMM6);

                XMM0 = _mm_cvtss_sd(XMM0, INPUT);
                XMM5 = _mm_add_pd(XMM5, XMM6);
                XMM7 = cast(double2)
                    _mm_cvtsd_ss(_mm_undefined_ps(), XMM5);
                XMM5 = _mm_unpacklo_pd(XMM5, XMM1);
                XMM1 = XMM5;
                _mm_store_ss(output + n, cast(__m128) XMM7);
            }
            _mm_storel_pd(&x0, XMM0);
            _mm_storeh_pd(&x1, XMM0);
            _mm_storel_pd(&y0, XMM1);
            _mm_storeh_pd(&y1, XMM1);
                _x0 = x0;
                _x1 = x1;
                _y0 = y0;
                _y1 = y1;
        }
        else
        {
            double x0 = _x0,
                   x1 = _x1,
                   y0 = _y0,
                   y1 = _y1;

            double a0 = coeff[0],
                   a1 = coeff[1],
                   a2 = coeff[2],
                   a3 = coeff[3],
                   a4 = coeff[4];

            for(int i = 0; i < frames; ++i)
            {
                double s = a0 * input[i] + a1 * x0 + a2 * x1
                         - a3 * y0 - a4 * y1;

                x1 = x0;
                x0 = input[i];
                y1 = y0;
                y0 = s;
                output[i] = s;
            }

            _x0 = x0;
            _x1 = x1;
            _y0 = y0;
            _y1 = y1;
        }
    }
    ///ditto
    void nextBuffer(const(double)*     input,
                    double*           output,
                    int               frames,
                    const(BiquadCoeff) coeff)
    {
        // PERF: on Windows arm64, this loop makes Selene
        // 5% slower with inteli vs naive. Remove that, but
        // also listen since the result is also quite 
        // different! like -20 dB/RMS, odd

        double x0 = _x0,
               x1 = _x1,
               y0 = _y0,
               y1 = _y1;

        double a0 = coeff[0],
               a1 = coeff[1],
               a2 = coeff[2],
               a3 = coeff[3],
               a4 = coeff[4];

        __m128d XMM0 = _mm_set_pd(x1, x0);
        __m128d XMM1 = _mm_set_pd(y1, y0);
        __m128d XMM2 = _mm_set_pd(a2, a1);
        __m128d XMM3 = _mm_set_pd(a4, a3);
        __m128d XMM4 = _mm_set_sd(a0);

        __m128d XMM6 = _mm_undefined_pd();
        __m128d XMM7 = _mm_undefined_pd();
        __m128d XMM5 = _mm_undefined_pd();

        for (int n = 0; n < frames; ++n)
        {
            __m128d INPUT = _mm_load_sd(input + n);
            XMM5 = INPUT;

            XMM6 = XMM0;
            XMM7 = XMM1;
            XMM5 = _mm_mul_pd(XMM5, XMM4);
            XMM6 = _mm_mul_pd(XMM6, XMM2);
            XMM7 = _mm_mul_pd(XMM7, XMM3);
            XMM5 = _mm_add_pd(XMM5, XMM6);
            XMM5 = _mm_sub_pd(XMM5, XMM7);
            XMM6 = XMM5;

            XMM0 = cast(double2)
                _mm_slli_si128!8(cast(__m128i) XMM0);
            XMM6 = cast(double2)
                _mm_srli_si128!8(cast(__m128i) XMM6);
            XMM0.ptr[0] = INPUT.array[0];
            XMM5 = _mm_add_pd(XMM5, XMM6);
            XMM7 = XMM5;
            XMM5 = _mm_unpacklo_pd(XMM5, XMM1);
            XMM1 = XMM5;
            _mm_store_sd(output + n, XMM7);
        }
        _mm_storel_pd(&x0, XMM0);
        _mm_storeh_pd(&x1, XMM0);
        _mm_storel_pd(&y0, XMM1);
        _mm_storeh_pd(&y1, XMM1);
        _x0 = x0;
        _x1 = x1;
        _y0 = y0;
        _y1 = y1;
    }


    /**
        Process a constant DC input through the biquad
        filter, get back several output samples.

        This can be useful to filter rarely moving values
        such as parameters.

        Params:
            input  = Constant DC value.
            output = Output audio samples.
            frames = Number of audio samples in buffers.
            coeff  = Biquad coefficients.
    */
    void nextBuffer(float input, float* output, int frames,
                    const(BiquadCoeff) coeff)
    {
        double x0 = _x0,
               x1 = _x1,
               y0 = _y0,
               y1 = _y1;

        double a0 = coeff[0],
               a1 = coeff[1],
               a2 = coeff[2],
               a3 = coeff[3],
               a4 = coeff[4];

        for(int i = 0; i < frames; ++i)
        {
            double current = a0 * input + a1 * x0 + a2 * x1
                           - a3 * y0 - a4 * y1;

            x1 = x0;
            x0 = input;
            y1 = y0;
            y0 = current;
            output[i] = current;
        }

        _x0 = x0;
        _x1 = x1;
        _y0 = y0;
        _y1 = y1;
    }
    ///ditto
    void nextBuffer(double input, double* output,
                    int frames, const(BiquadCoeff) coeff)
    {
        double x0 = _x0,
               x1 = _x1,
               y0 = _y0,
               y1 = _y1;

        double a0 = coeff[0],
               a1 = coeff[1],
               a2 = coeff[2],
               a3 = coeff[3],
               a4 = coeff[4];

        for(int i = 0; i < frames; ++i)
        {
            double cur = a0 * input + a1 * x0 + a2 * x1
                       - a3 * y0 - a4 * y1;

            x1 = x0;
            x0 = input;
            y1 = y0;
            y0 = cur;
            output[i] = cur;
        }

        _x0 = x0;
        _x1 = x1;
        _y0 = y0;
        _y1 = y1;
    }
}










/*
  ▄▄▄▄▄▄
  ▀▀██▀▀               ██
    ██     ██▄████▄  ███████    ▄████▄    ██▄████  ██▄███▄
    ██     ██▀   ██    ██      ██▄▄▄▄██   ██▀      ██▀  ▀██
    ██     ██    ██    ██      ██▀▀▀▀▀▀   ██       ██    ██
  ▄▄██▄▄   ██    ██    ██▄▄▄   ▀██▄▄▄▄█   ██       ███▄▄██▀
  ▀▀▀▀▀▀   ▀▀    ▀▀     ▀▀▀▀     ▀▀▀▀▀    ▀▀       ██ ▀▀▀
                                                   ██


 ▄▄▄▄▄▄       ██                                         ▄▄
 ██▀▀▀▀██     ▀▀                                         ██
 ██    ██   ████      ▄███▄██  ██    ██   ▄█████▄   ▄███▄██
 ███████      ██     ██▀  ▀██  ██    ██   ▀ ▄▄▄██  ██▀  ▀██
 ██    ██     ██     ██    ██  ██    ██  ▄██▀▀▀██  ██    ██
 ██▄▄▄▄██  ▄▄▄██▄▄▄  ▀██▄▄███  ██▄▄▄███  ██▄▄▄███  ▀██▄▄███
 ▀▀▀▀▀▀▀   ▀▀▀▀▀▀▀▀    ▀▀▀ ██   ▀▀▀▀ ▀▀   ▀▀▀▀ ▀▀    ▀▀▀ ▀▀
                           ██
*/

/**
    Interpolates the coefficients of a biquad to provide a
    smoothly varying filter.

    Coefficients are smoothed with a LP6.
*/
struct InterpolatedBiquad
{
public nothrow @nogc:

    /**
        Initialize state to silence.

        Params:
            sr            = Sampling Rate.
            decayTimeSecs = Time constant for smoothing.
    */
    void initialize(float sr,
                    float decayTimeSecs = 0.150)
    {
        _sr = sr;
        _state.initialize();
        _smoothDF = expDecayFactor(decayTimeSecs, sr);
        _initialized = false;

    }

    void setTimeConstant(float decayTimeSecs)
    {
        _smoothDF = expDecayFactor(decayTimeSecs, _sr);
    }


    // `input` can overlap with `output`.
    void nextBuffer(const(float)* input,
                    float*       output,
                    int          frames,
                    BiquadCoeff  target)
    {
        // DC Initialization of coeffs.
        // FUTURE: the coefficient smoothing is
        // DC-initialized, but not the smoothing itself.

        if (!_initialized)
        {
            _initialized = true;
            _current = target;
        }

        // Pre-computing coefficients in buffers did not
        // worked out for performance, was much slower.
        // Let's interpolate them instead.
        // Note: this naive version performs better than an
        // intel-intrinsics one, don't try.

        double x0 = _state._x0,
               x1 = _state._x1,
               y0 = _state._y0,
               y1 = _state._y1;

        BiquadCoeff coeffs = _current;
        double smoothDF = _smoothDF;
        for(int i = 0; i < frames; ++i)
        {
            coeffs[0] += (target[0] - coeffs[0]) * smoothDF;
            coeffs[1] += (target[1] - coeffs[1]) * smoothDF;
            coeffs[2] += (target[2] - coeffs[2]) * smoothDF;
            coeffs[3] += (target[3] - coeffs[3]) * smoothDF;
            coeffs[4] += (target[4] - coeffs[4]) * smoothDF;

            double a0 = coeffs[0],
                   a1 = coeffs[1],
                   a2 = coeffs[2],
                   a3 = coeffs[3],
                   a4 = coeffs[4];

            double s = a0 * input[i] + a1 * x0 + a2 * x1
                     - a3 * y0 - a4 * y1;

            x1 = x0;
            x0 = input[i];
            y1 = y0;
            y0 = s;
            output[i] = s;
        }

        _state._x0 = x0;
        _state._x1 = x1;
        _state._y0 = y0;
        _state._y1 = y1;
        _current = coeffs;
    }
    ///ditto
    void nextBuffer(const(double)* input,
                    double*       output,
                    int           frames,
                    BiquadCoeff   target)
    {
        // DC Initialization of coeffs.
        // FUTURE: the coefficient smoothing is
        // DC-initialized, but not the smoothing itself.

        if (!_initialized)
        {
            _initialized = true;
            _current = target;
        }

        double x0 = _state._x0,
               x1 = _state._x1,
               y0 = _state._y0,
               y1 = _state._y1;

        BiquadCoeff coeffs = _current;
        double smoothDF    = _smoothDF;
        for(int i = 0; i < frames; ++i)
        {
            coeffs[0] += (target[0] - coeffs[0]) * smoothDF;
            coeffs[1] += (target[1] - coeffs[1]) * smoothDF;
            coeffs[2] += (target[2] - coeffs[2]) * smoothDF;
            coeffs[3] += (target[3] - coeffs[3]) * smoothDF;
            coeffs[4] += (target[4] - coeffs[4]) * smoothDF;

            double a0 = coeffs[0],
                   a1 = coeffs[1],
                   a2 = coeffs[2],
                   a3 = coeffs[3],
                   a4 = coeffs[4];

            double s = a0 * input[i] + a1 * x0 + a2 * x1
                     - a3 * y0 - a4 * y1;

            x1 = x0;
            x0 = input[i];
            y1 = y0;
            y0 = s;
            output[i] = s;
        }

        _state._x0 = x0;
        _state._x1 = x1;
        _state._y0 = y0;
        _state._y1 = y1;
        _current = coeffs;
    }

private:
    BiquadDelay _state;
    BiquadCoeff _current;
    double _smoothDF;
    bool _initialized;
    float _sr;
}










/*

██ ██    ██  █████  ███    ██ ████████ ███████  ██████  ██    ██ 
██ ██    ██ ██   ██ ████   ██    ██    ██      ██    ██ ██    ██ 
██ ██    ██ ███████ ██ ██  ██    ██    ███████ ██    ██ ██    ██ 
██  ██  ██  ██   ██ ██  ██ ██    ██         ██ ██    ██  ██  ██  
██   ████   ██   ██ ██   ████    ██    ███████  ██████    ████   

*/
/*
    Ivantsov State-Space Filters

    First and second-order linear filters using state-space 
    representation. Provides various filter types with 
    optional frequency warping.

    Translated from C++ implementation. License = MIT.
*/

/// Type of filter.
enum IvantsovType
{
    // 1st order
    highPass1stOrder,
    lowPass1stOrder,
    allPass1stOrder,
    highShelf1stOrder,
    lowShelf1stOrder,

    // 2nd order
    highPass2ndOrder,
    bandPass2ndOrder,
    lowPass2ndOrder,
    allPass2ndOrder,
    notch2ndOrder,
    highShelf2ndOrder,
    lowShelf2ndOrder,
    midShelf2ndOrder
}

/// Apply an 1-pole ivantsov design to audio.
/// This can contain all types.
struct IvantsovIIR
{
pure:
nothrow:
@nogc:

    /// Initialize structure.
    ref IvantsovIIR initialize(float sampleRate)
    {
        _sr = sampleRate;
        _recomputeCoeffs = true;
        _recomputeSigma = true;
        clearState();
        return this;
    }

    /// Clear filter state, keep same sampling-rate.
    void clearState()
    {
        _z0 = 0;
        _z1 = 0;
    }

    /// Set type of filter.
    /// MUST be called before use.
    ref IvantsovIIR setType(IvantsovType newType)
    {
        if (_type != newType)
        {
            _type = newType;
            _recomputeCoeffs = true;
        }
        return this;
    }

    /// Set gain (only applies to shelf filters)
    /// MUST be called before use, in case of shelf.
    ref IvantsovIIR setGain(double gain_linear)
    {
        _b4 = gain_linear;
        _recomputeCoeffs = true;
        return this;
    }

    /// Set cutoff.
    /// MUST be called before use.
    ref IvantsovIIR setCutoff(double fc_Hz)
    {
        if (_fc == fc_Hz)
            return this; // avoid costly recomputes

        _fc = fc_Hz;
        _recomputeCoeffs = true;
        _recomputeSigma = true;
        return this;
    }

    /// Set damping factor
    /// MUST be called before use, in case of 2nd order.    
    ref IvantsovIIR setDamping(double x)
    {
        if (_zeta == x)
            return this;
        _zeta = x;
        _recomputeCoeffs = true;
        return this;
    }

    /// Process a single sample.
    double nextSample(double x)
    {
        recomputeCoeffsIfNeeded();
        double theta = (x - _z0 - _z1 * _b1) * _b0;
        double y = theta * _b3 + _z1 * _b2;
        y = y + _z0 * _cond1;
        _z0 = _z0 + theta;
        _z1 = -_z1 - theta * _b1;
        return y * _cond2;
    }

private:
    IvantsovType _type;
    bool _recomputeCoeffs = true;
    bool _recomputeSigma  = true;

    enum double invPi = 1.0 / PI;
    enum double sqrt2InvPi = SQRT2 / PI;

    // State management.
    double _sr;
    double _sigma = 0; // for warping
    double _w     = 0;
    double _fc;
    double _zeta;

    // Filter current state.
    double _z0, _z1;

    // Filter coefficients.
    double _b0; // Used by order 1 and 2
    double _b1; // Used by order 2 only
    double _b2; // Used by order 2 only
    double _b3; // Used by order 1 and 2
    double _b4; // Used by order 1 and 2, only by shelves

    // To unify all the filter types, need more "coeffs" 
    // as the realizations different depending on type.
    double _cond1;  
    double _cond2;

    void recomputeCoeffsIfNeeded()
    {
        if (!_recomputeCoeffs) 
            return;
        _recomputeCoeffs = false;

        if (_recomputeSigma)
        {
            if (_type <= IvantsovType.lowShelf1stOrder)
            {
                // 1st order
                _w = _sr / (2.0 * PI * _fc);
                if (_w > invPi)
                    _sigma = 0.408249999896 * (0.0584335750974 - _w * _w) / (0.0459329400275 - _w * _w);
                else
                    _sigma = invPi;
            }
            else
            {
                // 2nd order
                _w = _sr / (SQRT2 * PI * _fc);
                double threshold = SQRT2 / PI;
                if (_w > threshold)
                    _sigma = 0.577352686692 * (0.116867150195 - _w * _w) / (0.091865880055 - _w * _w);
                else
                    _sigma = sqrt2InvPi;
                
            }
            _recomputeSigma = false;
        }


        _cond1 = 1;
        _cond2 = 1;

        _b1 = 0;
        _b2 = 0;

        immutable double wSq = _w * _w;
        immutable double sigmaSq = _sigma * _sigma;

        double v, k;
        if (_type > IvantsovType.lowShelf1stOrder) // Is 2nd order
        {
            if (_type == IvantsovType.lowShelf2ndOrder)
                computeVK(wSq * fast_sqrt(_b4), _zeta * _zeta, sigmaSq, v, k); // PERF: sounds unused
            else if (_type == IvantsovType.highShelf2ndOrder)
                computeVK(wSq / fast_sqrt(_b4), _zeta * _zeta, sigmaSq, v, k); // PERF: sounds unused
            else if (_type == IvantsovType.midShelf2ndOrder)
                computeVK(wSq, _zeta * _zeta / _b4, sigmaSq, v, k); // PERF: sounds unused
            else
                computeVK(wSq, _zeta * _zeta, sigmaSq, v, k);

            _b0 = 1.0 / (v + fast_sqrt(v + k) + 0.5);
            _b1 = fast_sqrt(v + v);
        }

        final switch (_type) with (IvantsovType)
        {
            case highPass1stOrder:
                _b0 = 1.0 / (0.5 + warp(_w * _w));
                _b3 = _w;
                _cond1 = 0;
                break;

            case lowPass1stOrder:
                _b0 = 1.0 / (0.5 + warp(_w * _w));
                _b3 = 0.5 + _sigma;
                break;
                    
            case allPass1stOrder:
                _b0 = 1.0 / (0.5 + warp(_w * _w));
                _b3 = 0.5 - warp(_w * _w);
                break;

            case lowShelf1stOrder:
                assert(_b4 != 0); // gain cannot be -inf 
                _b0 = 1.0 / (0.5 + warp(_w * _w * _b4));
                _b3 = 0.5 + warp(_w * _w / _b4);
                _cond2 = _b4;
                break;

            case highShelf1stOrder:
                assert(_b4 != 0); // gain cannot be -inf 
                _b0 = 1.0 / (0.5 + warp(_w * _w / _b4));
                _b3 = 0.5 + warp(_w * _w * _b4);
                break;

                // 2nd order
            case highPass2ndOrder:                
                _b2 = 2.0 * wSq / _b1;
                _b3 = wSq;
                _cond1 = 0;
                break;

            case bandPass2ndOrder:
                _b2 = 4.0 * _w * _zeta * _sigma / _b1;
                _b3 = 2.0 * _w * _zeta * (_sigma + SQRT1_2);
                _cond1 = 0;
                break;

            case lowPass2ndOrder:
                _b2 = 2.0 * sigmaSq / _b1;
                _b3 = sigmaSq + SQRT2 * _sigma + 0.5;
                break;

            case allPass2ndOrder:
                _b2 = _b1;
                _b3 = v - fast_sqrt(v + k) + 0.5;
                break;

            case notch2ndOrder:
                _b2 = 2.0 * (wSq - sigmaSq) / _b1;
                _b3 = wSq - sigmaSq + 0.5;
                break;

            case highShelf2ndOrder:
            {
                double vB, kB;
                computeVK(wSq * fast_sqrt(_b4), _zeta * _zeta, sigmaSq, vB, kB);
                _b2 = 2.0 * vB / _b1;
                _b3 = vB + fast_sqrt(vB + kB) + 0.5;
                break;
            }

            case lowShelf2ndOrder:
            {
                double vB, kB;
                computeVK(wSq / sqrt(_b4), _zeta * _zeta, sigmaSq, vB, kB);
                _cond2 = _b4;
                _b2 = 2.0 * vB / _b1;
                _b3 = vB + fast_sqrt(vB + kB) + 0.5;
                break;
            }

            case midShelf2ndOrder:
            {
                double vB, kB;
                computeVK(wSq, _zeta * _zeta * _b4, sigmaSq, vB, kB);
                _b2 = 2.0 * vB / _b1;
                _b3 = vB + fast_sqrt(vB + kB) + 0.5;
                break;
            }
        }
    }

    // Warp function, 1st order
    double warp(double x)
    {
        return fast_sqrt(x + _sigma * _sigma);
    }

    // Helper function that computes (v, k) pair
    // v = sqrt(x^2 + 2*t*sigma^2 + sigma^4) where t = x*(2y-1)
    // k = t + sigma^2
    static void computeVK(double x, double y, double sigmaSq_, out double v, out double k)
    {
        double t = x * (y + y - 1.0);
        k = t + sigmaSq_;
        // Potential precision note: for very small x, this could lose precision
        v = fast_sqrt(x * x + 2.0 * t * sigmaSq_ + sigmaSq_ * sigmaSq_);
    }
}










/*
  ▄▄▄▄▄▄
  ▀▀██▀▀               ██
    ██     ██▄████▄  ███████    ▄████▄    ██▄████  ██▄████▄
    ██     ██▀   ██    ██      ██▄▄▄▄██   ██▀      ██▀   ██
    ██     ██    ██    ██      ██▀▀▀▀▀▀   ██       ██    ██
  ▄▄██▄▄   ██    ██    ██▄▄▄   ▀██▄▄▄▄█   ██       ██    ██
  ▀▀▀▀▀▀   ▀▀    ▀▀     ▀▀▀▀     ▀▀▀▀▀    ▀▀       ▀▀    ▀▀
*/
private:

enum RBJBiquadType
{
    LOW_PASS_FILTER,
    HIGH_PASS_FILTER,
    BAND_PASS_FILTER,
    NOTCH_FILTER,
    PEAK_FILTER,
    LOW_SHELF,
    HIGH_SHELF,
    ALL_PASS_FILTER
}

// generates RBJ biquad coefficients
BiquadCoeff genRBJBiquad(RBJBiquadType type,
                         double fc_hz,
                         double sr_hz,
                         double gain_dB,
                         double Q)
{
    double A      = pow(10.0, gain_dB / 40);
    double w0     = (2.0 * PI) * fc_hz / sr_hz;
    double sin_w0 = sin(w0);
    double cos_w0 = cos(w0);

    double alpha = sin_w0 / (2 * Q);

    //= sin(w0)*sinh(ln(2)/2 * BW * w0/sin(w0)) (case: BW)
    //= sin(w0)/2 * sqrt((A + 1/A)*(1/S - 1) + 2) (case: S)

    double b0, b1, b2, a0, a1, a2;

    final switch(type) with (RBJBiquadType)
    {
    case LOW_PASS_FILTER:
        b0 = (1 - cos_w0) / 2;
        b1 = 1 - cos_w0;
        b2 = (1 - cos_w0) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cos_w0;
        a2 = 1 - alpha;
        break;

    case HIGH_PASS_FILTER:
        b0 = (1 + cos_w0) / 2;
        b1 = -(1 + cos_w0);
        b2 = (1 + cos_w0) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cos_w0;
        a2 = 1 - alpha;
        break;

    case BAND_PASS_FILTER:
        b0 = alpha;
        b1 = 0;
        b2 = -alpha;
        a0 = 1 + alpha;
        a1 = -2 * cos_w0;
        a2 = 1 - alpha;
        break;

    case NOTCH_FILTER:
        b0 = 1;
        b1 = -2*cos_w0;
        b2 = 1;
        a0 = 1 + alpha;
        a1 = -2*cos(w0);
        a2 = 1 - alpha;
        break;

    case PEAK_FILTER:
        b0 = 1 + alpha * A;
        b1 = -2 * cos_w0;
        b2 = 1 - alpha * A;
        a0 = 1 + alpha / A;
        a1 = -2 * cos_w0;
        a2 = 1 - alpha / A;
        break;

    case LOW_SHELF:
        {
            double ap1 = A + 1;
            double am1 = A - 1;
            double M = 2 * sqrt(A) * alpha;
            b0 = A * (ap1 - am1 * cos_w0 + M);
            b1 = 2 * A * (am1 - ap1 * cos_w0);
            b2 = A * (ap1 - am1 * cos_w0 - M);
            a0 = ap1 + am1 * cos_w0 + M;
            a1 = -2 * (am1 + ap1 * cos_w0);
            a2 = ap1 + am1 * cos_w0 - M;
        }
        break;

    case HIGH_SHELF:
        {
            double ap1 = A + 1;
            double am1 = A - 1;
            double M = 2 * sqrt(A) * alpha;
            b0 = A * (ap1 + am1 * cos_w0 + M);
            b1 = -2 * A * (am1 + ap1 * cos_w0);
            b2 = A * (ap1 + am1 * cos_w0 - M);
            a0 = ap1 - am1 * cos_w0 + M;
            a1 = 2 * (am1 - ap1 * cos_w0);
            a2 = ap1 - am1 * cos_w0 - M;
        }
        break;

    case ALL_PASS_FILTER:
        {
            b0 = 1 - alpha;
            b1 = -2 * cos_w0;
            b2 = 1 + alpha;
            a0 = 1 + alpha;
            a1 = -2 * cos_w0;
            a2 = 1 - alpha;
        }
        break;
    }

    // FUTURE: this sounds useless and harmful to cast
    // to float??? Analyze what it changes in Panagement and
    // Couture.
    BiquadCoeff r;
    r[0] = cast(float)(b0 / a0);
    r[1] = cast(float)(b1 / a0);
    r[2] = cast(float)(b2 / a0);
    r[3] = cast(float)(a1 / a0);
    r[4] = cast(float)(a2 / a0);
    return r;
}
