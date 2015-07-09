/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.iir;

public import std.math;

public import gfm.math.vector;


public
{

    /// Represent IIR coefficients as small vectors.
    /// This makes easy to smooth them over time.
    template IIRCoeff(int N, T)
    {
        alias Vector!(T, N) IIRCoeff;
    }

    /// Maintain state for a filtering operation.
    /// To use an IIR filter you need an IIRDelay + one IIRCoeff.
    struct IIRDelay(int order, T)
    {
        alias Vector!(T, order) delay_t;

        alias IIRCoeff!(order * 2 + 1, T) coeff_t; // TODO: be more general...

        delay_t x;
        delay_t y;

        void clear() nothrow @nogc
        {
            for (int i = 0; i < order; ++i)
            {
                x[i] = 0;
                y[i] = 0;
            }
        }

        static if (order == 2)
        {
            T next(T)(T input, const(coeff_t) coeff) nothrow @nogc
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

                x[0] = input;
                x[1] = x1;
                y[0] = current;
                y[1] = y1;
                return current;
            }
        }
    }



    // --- Biquads ---
    // Biquads (order 2 IIR) are useful since linearly interpolate their coefficients is stable.
    // So they are used a lot in audio-dsp.

    /// Type which hold the biquad coefficients.
    template BiquadCoeff(T)
    {
        alias IIRCoeff!(5, T) BiquadCoeff;
    }

    template BiquadDelay(T)
    {
        alias IIRDelay!(2, T) BiquadDelay;
    }


    // 1-pole low-pass filter
    BiquadCoeff!T lowpassFilter1Pole(T)(double frequency, double samplerate) nothrow @nogc
    {
        double w0 = 0.5 * frequency / samplerate;
        double t0 = w0 * 0.5;
        double t1 = 2 - cos(t0 * PI);
        double t2 = (1 - 2 * t0) * (1 - 2 * t0);
        return BiquadCoeff!T( cast(T)(1 - t2), 0, 0, cast(T)(-t2) );
    }

    // 1-pole high-pass filter
    BiquadCoeff!T highpassFilter1Pole(T)(double frequency, double samplerate) nothrow @nogc
    {
        double w0 = 0.5 * frequency / samplerate;
        double t0 = w0 * 0.5;
        double t1 = 2 + cos(t0 * PI);
        double t2 = (2 * t0) * (2 * t0);
        return BiquadCoeff!T( cast(T)(t2 - 1), 0, 0, cast(T)(t2) );
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
        return BiquadCoeff!T(1, 0, 0, 0, 0);
    }

    BiquadCoeff!T zeroFilter(T)() nothrow @nogc
    {
        return BiquadCoeff!T(0, 0, 0, 0, 0);
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
    BiquadCoeff!float = lowpassFilter1Pole!float(1400.0, 44100.0);
    BiquadCoeff!double = highpassFilter1Pole!float(1400.0, 44100.0);

    BiquadCoeff!double = lowpassFilterRBJ!double(1400.0, 44100.0, 0.6);
}