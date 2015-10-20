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
                T x1 = x[0],
                  x2 = x[1],
                  y1 = y[0],
                  y2 = y[1];

                T a0 = coeff[0],
                  a1 = coeff[1],
                  a2 = coeff[2],
                  a3 = coeff[3],
                  a4 = coeff[4];

                T current = a0 * input + a1 * x1 + a2 * x2 - a3 * y1 - a4 * y2;

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
                T x0 = x[0],
                  x1 = x[1],
                  y0 = y[0],
                  y1 = y[1];

                T a0 = coeff[0],
                  a1 = coeff[1],
                  a2 = coeff[2],
                  a3 = coeff[3],
                  a4 = coeff[4];

                for(int i = 0; i < frames; ++i)
                {
                    T current = a0 * input[i] + a1 * x0 + a2 * x1 - a3 * y0 - a4 * y1;

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