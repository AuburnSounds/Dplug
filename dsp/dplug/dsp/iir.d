/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.iir;

import std.traits;
public import std.math;
public import gfm.math.vector;


public
{

    /// Maintain state for a filtering operation.
    /// To use an IIR filter you need an IIRDelay + one IIRCoeff.
    struct IIRDelay(T, int order)
    {
        alias Vector!(T, order) delay_t;

        alias Vector!(T, order * 2 + 1) coeff_t; // TODO: be more general

        delay_t x;
        delay_t y;

        void initialize() nothrow @nogc
        {
            for (int i = 0; i < order; ++i)
            {
                x[i] = 0;
                y[i] = 0;
            }
        }

        deprecated("Use initialize() instead") alias clearState = initialize;
        deprecated("Use initialize() instead") alias clear = clearState;

        static if (order == 2)
        {
            T nextSample(T input, const(coeff_t) coeff) nothrow @nogc
            {
                double x1 = x[0],
                       x2 = x[1],
                       y1 = y[0],
                       y2 = y[1];

                double a0 = coeff[0],
                       a1 = coeff[1],
                       a2 = coeff[2],
                       a3 = coeff[3],
                       a4 = coeff[4];

                double current = a0 * input + a1 * x1 + a2 * x2 - a3 * y1 - a4 * y2;

                // kill denormals,and double values that would be converted 
                // to float denormals
                current += 1e-18f;
                current -= 1e-18f;

                x[0] = input;
                x[1] = x1;
                y[0] = current;
                y[1] = y1;
                return current;
            }

            void nextBuffer(const(T)* input, T* output, int frames, const(coeff_t) coeff) nothrow @nogc
            {
                static if (is(T == float) && D_InlineAsm_Any)
                {  
                    static assert(T.sizeof == 4);

                    double x0 = x[0],
                        x1 = x[1],
                        y0 = y[0],
                        y1 = y[1];

                    double a0 = coeff[0],
                        a1 = coeff[1],
                        a2 = coeff[2],
                        a3 = coeff[3],
                        a4 = coeff[4];

                    version(D_InlineAsm_X86)
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
                                jnz loop;

                            movlpd qword ptr x0, XMM0;
                            movhpd qword ptr x1, XMM0;
                            movlpd qword ptr y0, XMM1;
                            movhpd qword ptr y1, XMM1;
                        }
                    }
                    else version(D_InlineAsm_X86_64)
                    {
                        ubyte[16*2] storage;
                        asm nothrow @nogc
                        {
                            movups storage+0, XMM6;
                            movups storage+16, XMM7;

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
                            jnz loop;

                            movlpd qword ptr x0, XMM0;
                            movhpd qword ptr x1, XMM0;
                            movlpd qword ptr y0, XMM1;
                            movhpd qword ptr y1, XMM1;

                            movups XMM6, storage+0; // XMMx with x >= 6 registers need to be preserved
                            movups XMM7, storage+16;
                        }
                    }
                    else
                        static assert(false, "Not implemented for this platform.");

                    // Kill small signals that can cause denormals (no precision loss was measurable)
                    x0 += 1e-18;
                    x0 -= 1e-18;
                    x1 += 1e-18;
                    x1 -= 1e-18;
                    y0 += 1e-18;
                    y0 -= 1e-18;
                    y1 += 1e-18;
                    y1 -= 1e-18;

                    x[0] = x0;
                    x[1] = x1;
                    y[0] = y0;
                    y[1] = y1;
                }
                else
                {
                    double x0 = x[0],
                           x1 = x[1],
                           y0 = y[0],
                           y1 = y[1];

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
                        current += 1e-18f;
                        current -= 1e-18f;

                        x1 = x0;
                        x0 = input[i];
                        y1 = y0;
                        y0 = current;
                        output[i] = current;
                    }

                    x[0] = x0;
                    x[1] = x1;
                    y[0] = y0;
                    y[1] = y1;
                }
            }
        }
    }


    /// Type which hold the biquad coefficients.
    template BiquadCoeff(T)
    {
        alias Vector!(T, 5) BiquadCoeff;
    }

    template BiquadDelay(T)
    {
        alias IIRDelay!(T, 2) BiquadDelay;
    }


    // 1-pole low-pass filter
    BiquadCoeff!T lowpassFilter1Pole(T)(double frequency, double samplerate) nothrow @nogc
    {
        double w0 = 0.5 * frequency / samplerate;
        double t0 = w0 * 0.5;
        double t1 = 2 - cos(t0 * PI);
        double t2 = (1 - 2 * t0) * (1 - 2 * t0);

        BiquadCoeff!T result;
        result[0] = cast(T)(1 - t2);
        result[1] = 0;
        result[2] = 0;
        result[3] = cast(T)(-t2);
        result[4] = 0;
        return result;
    }

    // 1-pole high-pass filter
    BiquadCoeff!T highpassFilter1Pole(T)(double frequency, double samplerate) nothrow @nogc
    {
        double w0 = 0.5 * frequency / samplerate;
        double t0 = w0 * 0.5;
        double t1 = 2 + cos(t0 * PI);
        double t2 = (2 * t0) * (2 * t0);

        BiquadCoeff!T result;
        result[0] = cast(T)(t2 - 1);
        result[1] = 0;
        result[2] = 0;
        result[3] = cast(T)(t2);
        result[4] = 0;
        return result;
    }

    /// Allpass interpolator.
    /// https://ccrma.stanford.edu/~jos/pasp/First_Order_Allpass_Interpolation.html
    /// http://users.spa.aalto.fi/vpv/publications/vesan_vaitos/ch3_pt3_allpass.pdf
    /// It is recommended to use the range [0.5 .. 1.5] for best phase results.
    /// Also known as Thiran filter.
    BiquadCoeff!T allpassThiran1stOrder(T)(double fractionalDelay) nothrow @nogc
    {
        assert(fractionalDelay >= 0);
        double eta = (1 - fractionalDelay) / (1 + fractionalDelay);

        BiquadCoeff!T result;
        result[0] = cast(T)(eta);
        result[1] = 1;
        result[2] = 0;
        result[3] = cast(T)(eta);
        result[4] = 0;
        return result;
    }


    /// Same but 2nd order.
    /// http://users.spa.aalto.fi/vpv/publications/vesan_vaitos/ch3_pt3_allpass.pdf
    BiquadCoeff!T allpassThiran2ndOrder(T)(double fractionalDelay) nothrow @nogc
    {
        assert(fractionalDelay >= 0);
        double a1 = 2 * (2 - fractionalDelay) / (1 + fractionalDelay);
        double a2 = (fractionalDelay - 1) * (fractionalDelay - 2) 
                                          /
                    (fractionalDelay + 1) * (fractionalDelay + 2);

        BiquadCoeff!T result;
        result[0] = cast(T)(a1);
        result[1] = 1;
        result[2] = cast(T)(a2);
        result[3] = cast(T)(a1);
        result[4] = cast(T)(a2);
        return result;
    }

    // Cookbook formulae for audio EQ biquad filter coefficients
    // by Robert Bristow-Johnson

    BiquadCoeff!T lowpassFilterRBJ(T)(double frequency, double samplerate, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad!T(BiquadType.LOW_PASS_FILTER, frequency, samplerate, 0, Q);
    }

    BiquadCoeff!T highpassFilterRBJ(T)(double frequency, double samplerate, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad!T(BiquadType.HIGH_PASS_FILTER, frequency, samplerate, 0, Q);
    }

    BiquadCoeff!T bandpassFilterRBJ(T)(double frequency, double samplerate, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad!T(BiquadType.BAND_PASS_FILTER, frequency, samplerate, 0, Q);
    }

    BiquadCoeff!T notchFilterRBJ(T)(double frequency, double samplerate, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad!T(BiquadType.NOTCH_FILTER, frequency, samplerate, 0, Q);
    }

    BiquadCoeff!T peakFilterRBJ(T)(double frequency, double samplerate, double gain, double Q = SQRT1_2) nothrow @nogc
    {
        return generateBiquad!T(BiquadType.PEAK_FILTER, frequency, samplerate, gain, Q);
    }

    // Initialize with no-op filter
    BiquadCoeff!T bypassFilter(T)() nothrow @nogc
    {
        BiquadCoeff!T result;
        result[0] = 1;
        result[1] = 0;
        result[2] = 0;
        result[3] = 0;
        result[4] = 0;
        return result;
    }

    BiquadCoeff!T zeroFilter(T)() nothrow @nogc
    {
        BiquadCoeff!T result;
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
    BiquadCoeff!T generateBiquad(T)(BiquadType type, double frequency, double samplerate, double gaindB, double Q) nothrow @nogc
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

        BiquadCoeff!T result;
        result[0] = cast(T)(b0 / a0);
        result[1] = cast(T)(b1 / a0);
        result[2] = cast(T)(b2 / a0);
        result[3] = cast(T)(a1 / a0);
        result[4] = cast(T)(a2 / a0);
        return result;
    }
}

unittest
{
    auto a = lowpassFilter1Pole!float(1400.0, 44100.0);
    auto b = highpassFilter1Pole!float(1400.0, 44100.0);
    auto c = allpassThiran1stOrder!double(0.5);
    auto d = allpassThiran2ndOrder!double(0.6);
    auto e = lowpassFilterRBJ!double(1400.0, 44100.0, 0.6);
    auto f = highpassFilterRBJ!double(1400.0, 44100.0);
    auto g = bandpassFilterRBJ!float(10000.0, 44100.0);
    auto h = notchFilterRBJ!real(3000.0, 44100.0);
    auto i = peakFilterRBJ!real(3000.0, 44100.0, 6, 0.5);
    auto j = bypassFilter!float();
    auto k = zeroFilter!float();
}

version(D_InlineAsm_X86)
    private enum D_InlineAsm_Any = true;
else version(D_InlineAsm_X86_64)
    private enum D_InlineAsm_Any = true;
else
    private enum D_InlineAsm_Any = false;