/**
Basic IIR 1-pole and 2-pole filters through biquads. 

Copyright: Guillaume Piolat 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.dsp.iir;

import std.math: SQRT1_2, PI, pow, sin, cos, sqrt;
import std.complex: Complex,
                    complexAbs = abs,
                    complexExp = exp,
                    complexsqAbs = sqAbs,
                    complexFromPolar = fromPolar;
import dplug.core.math;
import inteli.emmintrin;

// TODO: function to make biquads from z-plane poles and zeroes

public
{

    /// Type which hold the biquad coefficients. 
    /// Important: Coefficients are considered always normalized by a0.
    /// Note: coeff[0] is b0,
    ///       coeff[1] is b1,
    ///       coeff[2] is b2,
    ///       coeff[3] is a1,
    ///       coeff[4] is a2 in the litterature.
    alias BiquadCoeff = double[5];

    /// Maintain state for a biquad state.
    /// A biquad is a realization that can model two poles and two zeros.
    struct BiquadDelay
    {
        enum order = 2;

        double _x0;
        double _x1;
        double _y0;
        double _y1;

        void initialize() nothrow @nogc
        {
            _x0 = 0;
            _x1 = 0;
            _y0 = 0;
            _y1 = 0;
        }

        static if (order == 2)
        {
            /// Process a single sample through the biquad filter.
            /// This is rather inefficient, in general you'll prefer to use the `nextBuffer`
            /// functions.
            float nextSample(float input, const(BiquadCoeff) coeff) nothrow @nogc
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

                double current = a0 * input + a1 * x1 + a2 * x2 - a3 * y1 - a4 * y2;

                _x0 = input;
                _x1 = x1;
                _y0 = current;
                _y1 = y1;
                return current;
            }
            ///ditto
            double nextSample(double input, const(BiquadCoeff) coeff) nothrow @nogc
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

                double current = a0 * input + a1 * x1 + a2 * x2 - a3 * y1 - a4 * y2;

                _x0 = input;
                _x1 = x1;
                _y0 = current;
                _y1 = y1;
                return current;
            }

            void nextBuffer(const(float)* input, float* output, int frames, const(BiquadCoeff) coeff) nothrow @nogc
            {
                static if (D_InlineAsm_Any)
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

                    version(LDC)
                    {
                        import inteli.emmintrin;

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
                            XMM5 = _mm_mul_pd(XMM5, XMM4); // input[i]*a0
                            XMM6 = _mm_mul_pd(XMM6, XMM2); // x1*a2 x0*a1
                            XMM7 = _mm_mul_pd(XMM7, XMM3); // y1*a4 y0*a3
                            XMM5 = _mm_add_pd(XMM5, XMM6);
                            XMM5 = _mm_sub_pd(XMM5, XMM7); // x1*a2 - y1*a4 | input[i]*a0 + x0*a1 - y0*a3
                            XMM6 = XMM5;

                            XMM0 = cast(double2) _mm_slli_si128!8(cast(__m128i) XMM0);
                            XMM6 = cast(double2) _mm_srli_si128!8(cast(__m128i) XMM6);

                            XMM0 = _mm_cvtss_sd(XMM0, INPUT);
                            XMM5 = _mm_add_pd(XMM5, XMM6);
                            XMM7 = cast(double2) _mm_cvtsd_ss(_mm_undefined_ps(), XMM5);
                            XMM5 = _mm_unpacklo_pd(XMM5, XMM1);
                            XMM1 = XMM5;
                            _mm_store_ss(output + n, cast(__m128) XMM7);
                        }
                        _mm_storel_pd(&x0, XMM0);
                        _mm_storeh_pd(&x1, XMM0);
                        _mm_storel_pd(&y0, XMM1);
                        _mm_storeh_pd(&y1, XMM1);
                    }
                    else version(D_InlineAsm_X86)
                    {
                        asm nothrow @nogc
                        {
                            mov EAX, input;
                            mov EDX, output;
                            mov ECX, frames;

                            movlpd XMM0, qword ptr x0; // XMM0 = x1 x0
                            movhpd XMM0, qword ptr x1;
                            movlpd XMM1, qword ptr y0; // XMM1 = y1 y0
                            movhpd XMM1, qword ptr y1;

                            movlpd XMM2, qword ptr a1; // XMM2 = a2 a1
                            movhpd XMM2, qword ptr a2;
                            movlpd XMM3, qword ptr a3; // XMM3 = a4 a3
                            movhpd XMM3, qword ptr a4;

                            movq XMM4, qword ptr a0; // XMM4 = 0 a0

                            align 16;
                        loop:
                            pxor XMM5, XMM5;
                            cvtss2sd XMM5, dword ptr [EAX];

                            movapd XMM6, XMM0;
                            movapd XMM7, XMM1;

                            mulpd XMM5, XMM4; // input[i]*a0
                            mulpd XMM6, XMM2; // x1*a2 x0*a1
                            mulpd XMM7, XMM3; // y1*a4 y0*a3

                            addpd XMM5, XMM6;
                            subpd XMM5, XMM7; // x1*a2 - y1*a4 | input[i]*a0 + x0*a1 - y0*a3

                            movapd XMM6, XMM5;
                            pslldq XMM0, 8;
                            psrldq XMM6, 8;

                            cvtss2sd XMM0, dword ptr [EAX]; // XMM0 <- x0 input[i]
                            addpd XMM5, XMM6; // garbage | input[i]*a0 + x0*a1 - y0*a3 + x1*a2 - y1*a4

                            cvtsd2ss XMM7, XMM5;
                            punpcklqdq XMM5, XMM1; // XMM5 <- y0 current
                            add EAX, 4;
                            movd dword ptr [EDX], XMM7;
                            add EDX, 4;
                            movapd XMM1, XMM5;

                            sub ECX, 1;
                            jnz short loop;

                            movlpd qword ptr x0, XMM0;
                            movhpd qword ptr x1, XMM0;
                            movlpd qword ptr y0, XMM1;
                            movhpd qword ptr y1, XMM1;
                        }
                    }
                    else version(D_InlineAsm_X86_64)
                    {
                        ubyte[16] storage0;
                        ubyte[16] storage1;
                        asm nothrow @nogc
                        {
                            movups storage0, XMM6;
                            movups storage1, XMM7;

                            mov RAX, input;
                            mov RDX, output;
                            mov ECX, frames;

                            movlpd XMM0, qword ptr x0; // XMM0 = x1 x0
                            movhpd XMM0, qword ptr x1;
                            movlpd XMM1, qword ptr y0; // XMM1 = y1 y0
                            movhpd XMM1, qword ptr y1;

                            movlpd XMM2, qword ptr a1; // XMM2 = a2 a1
                            movhpd XMM2, qword ptr a2;
                            movlpd XMM3, qword ptr a3; // XMM3 = a4 a3
                            movhpd XMM3, qword ptr a4;

                            movq XMM4, qword ptr a0; // XMM4 = 0 a0

                            align 16;
                        loop:
                            pxor XMM5, XMM5;
                            cvtss2sd XMM5, dword ptr [RAX];

                            movapd XMM6, XMM0;
                            movapd XMM7, XMM1;

                            mulpd XMM5, XMM4; // input[i]*a0
                            mulpd XMM6, XMM2; // x1*a2 x0*a1
                            mulpd XMM7, XMM3; // y1*a4 y0*a3

                            addpd XMM5, XMM6;
                            subpd XMM5, XMM7; // x1*a2 - y1*a4 | input[i]*a0 + x0*a1 - y0*a3

                            movapd XMM6, XMM5;
                            pslldq XMM0, 8;
                            psrldq XMM6, 8;

                            addpd XMM5, XMM6; // garbage | input[i]*a0 + x0*a1 - y0*a3 + x1*a2 - y1*a4
                            cvtss2sd XMM0, dword ptr [RAX]; // XMM0 <- x0 input[i]
                            cvtsd2ss XMM7, XMM5;
                            punpcklqdq XMM5, XMM1; // XMM5 <- y0 current
                            add RAX, 4;
                            movd dword ptr [RDX], XMM7;
                            add RDX, 4;
                            movapd XMM1, XMM5;

                            sub ECX, 1;
                            jnz short loop;

                            movlpd qword ptr x0, XMM0;
                            movhpd qword ptr x1, XMM0;
                            movlpd qword ptr y0, XMM1;
                            movhpd qword ptr y1, XMM1;

                            movups XMM6, storage0; // XMMx with x >= 6 registers need to be preserved
                            movups XMM7, storage1;
                        }
                    }
                    else
                        static assert(false, "Not implemented for this platform.");

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
                        double current = a0 * input[i] + a1 * x0 + a2 * x1 - a3 * y0 - a4 * y1;

                        x1 = x0;
                        x0 = input[i];
                        y1 = y0;
                        y0 = current;
                        output[i] = current;
                    }

                    _x0 = x0;
                    _x1 = x1;
                    _y0 = y0;
                    _y1 = y1;
                }
            }
            ///ditto
            void nextBuffer(const(double)* input, double* output, int frames, const(BiquadCoeff) coeff) nothrow @nogc
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
                    __m128d INPUT = _mm_load_sd(input + n);
                    XMM5 = INPUT;

                    XMM6 = XMM0;
                    XMM7 = XMM1;
                    XMM5 = _mm_mul_pd(XMM5, XMM4); // input[i]*a0
                    XMM6 = _mm_mul_pd(XMM6, XMM2); // x1*a2 x0*a1
                    XMM7 = _mm_mul_pd(XMM7, XMM3); // y1*a4 y0*a3
                    XMM5 = _mm_add_pd(XMM5, XMM6);
                    XMM5 = _mm_sub_pd(XMM5, XMM7); // x1*a2 - y1*a4 | input[i]*a0 + x0*a1 - y0*a3
                    XMM6 = XMM5;

                    XMM0 = cast(double2) _mm_slli_si128!8(cast(__m128i) XMM0);
                    XMM6 = cast(double2) _mm_srli_si128!8(cast(__m128i) XMM6);
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

            /// Special version of biquad processing, for a constant DC input.
            void nextBuffer(float input, float* output, int frames, const(BiquadCoeff) coeff) nothrow @nogc
            {
                // Note: this naive version performs better than an intel-intrinsics one
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
                    double current = a0 * input + a1 * x0 + a2 * x1 - a3 * y0 - a4 * y1;

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
            void nextBuffer(double input, double* output, int frames, const(BiquadCoeff) coeff) nothrow @nogc
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
                    double current = a0 * input + a1 * x0 + a2 * x1 - a3 * y0 - a4 * y1;

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
        }
    }

    /// 1-pole low-pass filter.
    /// Note: the cutoff frequency can be >= nyquist, in which case it asymptotically approaches a bypass.
    ///       the cutoff frequency can be below 0 Hz, in which case it is equal to zero.
    ///       This filter is normalized on DC.
    ///       You always have -3 dB at cutoff in the valid range.
    ///
    /// See_also: http://www.earlevel.com/main/2012/12/15/a-one-pole-filter/
    BiquadCoeff biquadOnePoleLowPass(double frequency, double sampleRate) nothrow @nogc
    {
        double fc = frequency / sampleRate;
        if (fc < 0.0f)
            fc = 0.0f;
        double t2 = fast_exp(-2.0 * PI * fc);
        BiquadCoeff result;
        result[0] = 1 - t2;
        result[1] = 0;
        result[2] = 0;
        result[3] = -t2;
        result[4] = 0;
        return result;
    }

    /// 1-pole high-pass filter.
    /// Note: Like the corresponding one-pole lowpass, this is normalized for DC.
    ///       The cutoff frequency can be <= 0 Hz, in which case it is a bypass.
    ///       Going in very high frequency does NOT give zero.
    ///       You always have -3 dB at cutoff in the valid range.
    ///
    /// See_also: https://www.dspguide.com/ch19/2.html
    BiquadCoeff biquadOnePoleHighPass(double frequency, double sampleRate) nothrow @nogc
    {
        double fc = frequency / sampleRate;
        if (fc < 0.0f)
            fc = 0.0f;
        double t2 = fast_exp(-2.0 * PI * fc);
        BiquadCoeff result;
        result[0] = (1 + t2) * 0.5;
        result[1] = -(1 + t2) * 0.5;
        result[2] = 0;
        result[3] = -t2;
        result[4] = 0;
        return result;
    }

    /// 1-pole low-pass filter, frequency mapping is not precise.
    /// Not accurate across sample rates, but coefficient computation is cheap. Not advised.
    BiquadCoeff biquadOnePoleLowPassImprecise(double frequency, double samplerate) nothrow @nogc
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

    /// 1-pole high-pass filter, frequency mapping is not precise.
    /// Not accurate across sample rates, but coefficient computation is cheap. Not advised.
    BiquadCoeff biquadOnePoleHighPassImprecise(double frequency, double samplerate) nothrow @nogc
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
    // by Robert Bristow-Johnson

    /// Low-pass filter 12 dB/oct as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJLowPass(double frequency, double samplerate, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.LOW_PASS_FILTER, frequency, samplerate, 0, Q);
    }

    /// High-pass filter 12 dB/oct as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJHighPass(double frequency, double samplerate, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.HIGH_PASS_FILTER, frequency, samplerate, 0, Q);
    }

    /// Band-pass filter as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJBandPass(double frequency, double samplerate, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.BAND_PASS_FILTER, frequency, samplerate, 0, Q);
    }

    /// Notch filter as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJNotch(double frequency, double samplerate, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.NOTCH_FILTER, frequency, samplerate, 0, Q);
    }

    /// Peak filter as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJPeak(double frequency, double samplerate, double gain, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.PEAK_FILTER, frequency, samplerate, gain, Q);
    }

    /// Low-shelf filter as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJLowShelf(double frequency, double samplerate, double gain, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.LOW_SHELF, frequency, samplerate, gain, Q);
    }

    /// High-shelf filter as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJHighShelf(double frequency, double samplerate, double gain, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.HIGH_SHELF, frequency, samplerate, gain, Q);
    }

    /// 2nd order All-pass filter as described by Robert Bristow-Johnson.
    /// This is helpful to introduce the exact same phase response as the RBJ low-pass, but doesn't affect magnitude.
    BiquadCoeff biquadRBJAllPass(double frequency, double samplerate, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.ALL_PASS_FILTER, frequency, samplerate, 0, Q);
    }

    /// Identity biquad, pass signal unchanged.
    BiquadCoeff biquadBypass() nothrow @nogc
    {
        BiquadCoeff result;
        result[0] = 1;
        result[1] = 0;
        result[2] = 0;
        result[3] = 0;
        result[4] = 0;
        return result;
    }

    /// Zero biquad, gives zero output.
    BiquadCoeff biquadZero() nothrow @nogc
    {
        BiquadCoeff result;
        result[0] = 0;
        result[1] = 0;
        result[2] = 0;
        result[3] = 0;
        result[4] = 0;
        return result;
    }

    /// Bessel 2-pole lowpass.
    BiquadCoeff biquadBesselLowPass(double frequency, double sampleRate) nothrow @nogc
    {
        double normalGain = 1;
        double normalW = 0;
        Complex!double pole0 = Complex!double(-1.5 , 0.8660);
        Complex!double pole1 = Complex!double(-1.5 , -0.8660);
        double fc = frequency / sampleRate;
        double T = fc * 2 * PI;
        pole0 = complexExp(pole0 * T); // matched Z transform
        pole1 = complexExp(pole1 * T);
        Complex!double zero01 = Complex!double(-1.0, 0.0);
        BiquadCoeff coeff = biquad2Poles(pole0, zero01, pole1, zero01);
        double scaleFactor = 1.0 / complexAbs( biquadResponse(coeff, 0 ));
        return biquadApplyScale(coeff, scaleFactor);
    }
}

private
{
    enum BiquadType
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
    BiquadCoeff generateBiquad(BiquadType type, double frequency, double samplerate, double gaindB, double Q) nothrow @nogc
    {
        // regardless of the output precision, always compute coefficients in double precision

        double A = pow(10.0, gaindB / 40.0);
        double w0 = (2.0 * PI) * frequency / samplerate;
        double sin_w0 = sin(w0);
        double cos_w0 = cos(w0);

        double alpha = sin_w0 / (2 * Q);

        //   = sin(w0)*sinh( ln(2)/2 * BW * w0/sin(w0) )           (case: BW)
        //   = sin(w0)/2 * sqrt( (A + 1/A)*(1/S - 1) + 2 )         (case: S)

        double b0, b1, b2, a0, a1, a2;

        final switch(type)
        {
            case  BiquadType.LOW_PASS_FILTER:
                b0 = (1 - cos_w0) / 2;
                b1 = 1 - cos_w0;
                b2 = (1 - cos_w0) / 2;
                a0 = 1 + alpha;
                a1 = -2 * cos_w0;
                a2 = 1 - alpha;
                break;

            case BiquadType.HIGH_PASS_FILTER:
                b0 = (1 + cos_w0) / 2;
                b1 = -(1 + cos_w0);
                b2 = (1 + cos_w0) / 2;
                a0 = 1 + alpha;
                a1 = -2 * cos_w0;
                a2 = 1 - alpha;
                break;

            case BiquadType.BAND_PASS_FILTER:
                b0 = alpha;
                b1 = 0;
                b2 = -alpha;
                a0 = 1 + alpha;
                a1 = -2 * cos_w0;
                a2 = 1 - alpha;
                break;

            case BiquadType.NOTCH_FILTER:
                b0 = 1;
                b1 = -2*cos_w0;
                b2 = 1;
                a0 = 1 + alpha;
                a1 = -2*cos(w0);
                a2 = 1 - alpha;
                break;

            case BiquadType.PEAK_FILTER:
                b0 = 1 + alpha * A;
                b1 = -2 * cos_w0;
                b2 = 1 - alpha * A;
                a0 = 1 + alpha / A;
                a1 = -2 * cos_w0;
                a2 = 1 - alpha / A;
                break;

            case BiquadType.LOW_SHELF:
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

            case BiquadType.HIGH_SHELF:
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

            case BiquadType.ALL_PASS_FILTER:
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

        BiquadCoeff result;
        result[0] = cast(float)(b0 / a0);  // FUTURE: this sounds useless and harmful to cast to float???
        result[1] = cast(float)(b1 / a0);
        result[2] = cast(float)(b2 / a0);
        result[3] = cast(float)(a1 / a0);
        result[4] = cast(float)(a2 / a0);
        return result;
    }
}


// TODO: deprecated this assembly, sounds useless vs inteli
version(D_InlineAsm_X86)
    private enum D_InlineAsm_Any = true;
else version(D_InlineAsm_X86_64)
    private enum D_InlineAsm_Any = true;
else
    private enum D_InlineAsm_Any = false;


private:



BiquadCoeff biquad2Poles(Complex!double pole1, Complex!double zero1, Complex!double pole2, Complex!double zero2) nothrow @nogc
{
    // Note: either it's a double pole, or two pole on the real axis.
    // Same for zeroes

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

BiquadCoeff biquadApplyScale(BiquadCoeff biquad, double scale) nothrow @nogc
{
    biquad[0] *= scale;
    biquad[1] *= scale;
    biquad[2] *= scale;
    return biquad;
}

// Calculate filter response at the given normalized frequency.
Complex!double biquadResponse(BiquadCoeff coeff, double normalizedFrequency) nothrow @nogc
{
    static Complex!double addmul(Complex!double c, double v, Complex!double c1)
    {
        return Complex!double(c.re + v * c1.re, c.im + v * c1.im);
    }

    double w = 2 * PI * normalizedFrequency;
    Complex!double czn1 = complexFromPolar (1., -w);
    Complex!double czn2 = complexFromPolar (1., -2 * w);
    Complex!double ch = 1.0;
    Complex!double cbot = 1.0;

    Complex!double cb = 1.0;
    Complex!double ct = coeff[0]; // b0
    ct = addmul (ct, coeff[1], czn1); // b1
    ct = addmul (ct, coeff[2], czn2); // b2
    cb = addmul (cb, coeff[3], czn1); // a1
    cb = addmul (cb, coeff[4], czn2); // a2
    ch   *= ct;
    cbot *= cb;
    return ch / cbot;
}

nothrow @nogc unittest 
{
    BiquadCoeff c = biquadBesselLowPass(20000, 44100);
}