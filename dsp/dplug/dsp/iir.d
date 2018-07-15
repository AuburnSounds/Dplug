/**
* Basic IIR 1-pole and 2-pole filters through biquads. 
*
* Copyright: Copyright Auburn Sounds 2015-2017.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.iir;

import std.math;
import dplug.core.math;

// DMD with a 32-bit target uses the FPU
version(X86)
{
    version(DigitalMars)
    {
        version = killDenormals;
    }
}

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

                // kill denormals,and double values that would be converted
                // to float denormals
                version(killDenormals)
                {
                    current += 1e-18f;
                    current -= 1e-18f;
                }

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

                            XMM0 = _mm_slli_si128!8(XMM0);
                            XMM6 = _mm_srli_si128!8(XMM6);

                            XMM0 = _mm_cvtss_sd(XMM0, INPUT);
                            XMM5 = _mm_add_pd(XMM5, XMM6);
                            XMM7 = _mm_cvtsd_ss(_mm_undefined_ps(), XMM5);
                            XMM5 = _mm_unpacklo_pd(XMM5, XMM1);
                            XMM1 = XMM5;
                            _mm_store_ss(output + n, XMM7);
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

                    // Kill small signals that can cause denormals (no precision loss was measurable)
                    version(killDenormals)
                    {
                        x0 += 1e-10;
                        x0 -= 1e-10;
                        x1 += 1e-10;
                        x1 -= 1e-10;
                        y0 += 1e-10;
                        y0 -= 1e-10;
                        y1 += 1e-10;
                        y1 -= 1e-10;
                    }

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

                        // kill denormals,and double values that would be converted
                        // to float denormals
                        version(killDenormals)
                        {
                            current += 1e-18f;
                            current -= 1e-18f;
                        }

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
        }
    }

    /// 1-pole low-pass filter.
    /// Note: the cutoff frequency can be >= nyquist, in which case it asymptotically approaches a bypass.
    ///       the cutoff frequency can be below 0 Hz, in which case it is equal to zero.
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
    /// Note: the cutoff frequency can be >= nyquist, in which case it is equal to zero.
    ///       the cutoff frequency can be below 0 Hz, in which case it asymptotically approaches a bypass.
    ///       You always have -3 dB at cutoff in the valid range.
    ///
    /// See_also: http://www.earlevel.com/main/2012/12/15/a-one-pole-filter/
    BiquadCoeff biquadOnePoleHighPass(double frequency, double sampleRate) nothrow @nogc
    {
        double fc = frequency / sampleRate;
        if (fc > 0.5f)
            fc = 0.5f;

        double t2 = fast_exp(-2.0 * PI * (0.5 - fc));
        BiquadCoeff result;
        result[0] = 1 - t2;
        result[1] = 0;
        result[2] = 0;
        result[3] = t2;
        result[4] = 0;

        return result;
    }

    deprecated("This function was renamed to biquadOnePoleLowPassImprecise.") 
        alias lowpassFilter1Pole = biquadOnePoleLowPassImprecise;
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

    deprecated("This function was renamed to biquadOnePoleHighPassImprecise.") 
        alias highpassFilter1Pole = biquadOnePoleHighPassImprecise;
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

    /// Allpass interpolator.
    /// https://ccrma.stanford.edu/~jos/pasp/First_Order_Allpass_Interpolation.html
    /// http://users.spa.aalto.fi/vpv/publications/vesan_vaitos/ch3_pt3_allpass.pdf
    /// It is recommended to use the range [0.5 .. 1.5] for best phase results.
    /// Also known as Thiran filter.
    deprecated BiquadCoeff allpassThiran1stOrder(T)(double fractionalDelay) nothrow @nogc
    {
        assert(fractionalDelay >= 0);
        double eta = (1 - fractionalDelay) / (1 + fractionalDelay);

        BiquadCoeff result;
        result[0] = cast(T)(eta);
        result[1] = 1;
        result[2] = 0;
        result[3] = cast(T)(eta);
        result[4] = 0;
        return result;
    }


    /// Same but 2nd order.
    /// http://users.spa.aalto.fi/vpv/publications/vesan_vaitos/ch3_pt3_allpass.pdf
    deprecated BiquadCoeff allpassThiran2ndOrder(T)(double fractionalDelay) nothrow @nogc
    {
        assert(fractionalDelay >= 0);
        double a1 = 2 * (2 - fractionalDelay) / (1 + fractionalDelay);
        double a2 = (fractionalDelay - 1) * (fractionalDelay - 2)
            /
            (fractionalDelay + 1) * (fractionalDelay + 2);

        BiquadCoeff result;
        result[0] = cast(T)(a1);
        result[1] = 1;
        result[2] = cast(T)(a2);
        result[3] = cast(T)(a1);
        result[4] = cast(T)(a2);
        return result;
    }

    // Cookbook formulae for audio EQ biquad filter coefficients
    // by Robert Bristow-Johnson

    deprecated("This function was renamed to biquadRBJLowPass.") 
        alias lowpassFilterRBJ = biquadRBJLowPass;
    /// Low-pass filter 12 dB/oct as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJLowPass(double frequency, double samplerate, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.LOW_PASS_FILTER, frequency, samplerate, 0, Q);
    }

    deprecated("This function was renamed to biquadRBJHighPass.") 
        alias highpassFilterRBJ = biquadRBJHighPass;
    /// High-pass filter 12 dB/oct as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJHighPass(double frequency, double samplerate, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.HIGH_PASS_FILTER, frequency, samplerate, 0, Q);
    }

    deprecated("This function was renamed to biquadRBJBandPass.") 
        alias bandpassFilterRBJ = biquadRBJBandPass;
    /// Band-pass filter as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJBandPass(double frequency, double samplerate, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.BAND_PASS_FILTER, frequency, samplerate, 0, Q);
    }

    deprecated("This function was renamed to biquadRBJNotch.") 
        alias notchFilterRBJ = biquadRBJNotch;
    /// Notch filter as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJNotch(double frequency, double samplerate, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.NOTCH_FILTER, frequency, samplerate, 0, Q);
    }

    deprecated("This function was renamed to biquadRBJPeak.") 
        alias peakFilterRBJ = biquadRBJPeak;
    /// Peak filter as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJPeak(double frequency, double samplerate, double gain, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.PEAK_FILTER, frequency, samplerate, gain, Q);
    }

    deprecated("This function was renamed to biquadRBJLowShelf.") 
        alias lowShelfFilterRBJ = biquadRBJLowShelf;
    /// Low-shelf filter as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJLowShelf(double frequency, double samplerate, double gain, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.LOW_SHELF, frequency, samplerate, gain, Q);
    }

    deprecated("This function was renamed to biquadRBJHighShelf.") 
        alias highShelfFilterRBJ = biquadRBJHighShelf;
    /// High-shelf filter as described by Robert Bristow-Johnson.
    BiquadCoeff biquadRBJHighShelf(double frequency, double samplerate, double gain, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad(BiquadType.HIGH_SHELF, frequency, samplerate, gain, Q);
    }

    deprecated("This function was renamed to biquadBypass.") 
        alias bypassFilter = biquadBypass;
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

    deprecated("This function was renamed to biquadZero.") 
        alias zeroFilter = biquadZero;
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
        HIGH_SHELF
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
        }

        BiquadCoeff result;
        result[0] = cast(float)(b0 / a0);
        result[1] = cast(float)(b1 / a0);
        result[2] = cast(float)(b2 / a0);
        result[3] = cast(float)(a1 / a0);
        result[4] = cast(float)(a2 / a0);
        return result;
    }
}


version(D_InlineAsm_X86)
private enum D_InlineAsm_Any = true;
else version(D_InlineAsm_X86_64)
private enum D_InlineAsm_Any = true;
else
private enum D_InlineAsm_Any = false;