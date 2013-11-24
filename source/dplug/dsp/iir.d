// See licenses/UNLICENSE.txt
module dplug.dsp.iir;

public import std.math;

public import gfm.math.vector;


public
{

    /// Represent IIR coefficients as small vectors.
    /// This makes easy to smooth them over time.
    template IIRCoeff(size_t N, T)
    {
        alias Vector!(T, N) IIRCoeff;
    }

    /// Maintain state for a filtering operation.
    /// To use an IIR filter you need an IIRDelay + one IIRCoeff.
    struct IIRDelay(int order, T)
    {
        alias Vector!(T, order) delay_t;

        delay_t x;
        delay_t y;

        void clear()
        {
            x = x.init; // fill with 0 for floating-point numbers
            y = y.init;
        }

        static if (order == 2)
        {
            T next(U)(T input, const(BiquadCoeff!T) coeff)
            {
                T x1 = state.x[0],
                  x2 = state.x[1],
                  y1 = state.y[0],
                  y2 = state.y[1];

                T a0 = coef[0],
                  a1 = coef[1],
                  a2 = coef[2],
                  a3 = coef[3],
                  a4 = coef[4];

                double T = a0 * input + a1 * x1 + a2 * x2 - a3 * y1 - a4 * y2;

                state.x[0] = x;
                state.x[1] = x1;
                state.y[0] = y;
                state.y[1] = y1;
                return y;
            }
        }
    }



    // --- Biquads ---
    // Biquads (order 2 IIR) are useful since linearly interpolate their coefficients is stable.
    // So they are used a lot in audio-dsp.

    /// Type which hold the biquad coefficients.
    template BiquadCoeff(T)
    {
        alias IIRCoeff!(T, 5) BiquadCoeff;
    }

    template BiquadDelay(T)
    {
        alias IIRDelay!(T, 2) BiquadDelay;
    }


    // Cookbook formulae for audio EQ biquad filter coefficients
    // by Robert Bristow-Johnson 

    BiquadCoeff!T lowpassFilterRBJ(T)(double frequency, double samplerate, double Q = SQRT1_2)
    {
        return generateBiquad!T(BiquadType.LOW_PASS_FILTER, frequency, samplerate, 0, Q);
    }

    BiquadCoeff!T highpassFilterRBJ(T)(double frequency, double samplerate, double  = SQRT1_2)
    {
        return generateBiquad!T(BiquadType.HIGH_PASS_FILTER, frequency, samplerate, 0, Q);
    }

    BiquadCoeff!T bandpassFilterRBJ(T)(double frequency, double samplerate, double Q = SQRT1_2)
    {
        return generateBiquad!T(BiquadType.BAND_PASS_FILTER, frequency, samplerate, 0, Q);
    }

    BiquadCoeff!T notchFilterRBJ(T)(double frequency, double samplerate, double Q = SQRT1_2)
    {
        return generateBiquad!T(BiquadType.NOTCH_FILTER, frequency, samplerate, 0, Q);
    }

    BiquadCoeff!T peakFilterRBJ(T)(double frequency, double samplerate, double gain, double Q = SQRT1_2)
    {
        return generateBiquad!T(BiquadType.PEAK_FILTER, frequency, samplerate, gain, Q);
    }

    // Initialize with no-op filter
    BiquadCoeff!T bypassFilter(T)()
    {
        return BiquadCoeff!T(1, 0, 0, 0, 0);
    }

    BiquadCoeff!T zeroFilter(T)()
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
    BiquadCoeff!T generateBiquad(T)(BiquadType type, double frequency, double samplerate, double gaindB, double Q, double v[5])
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
        }

        return cast(BiquadCoeff!T)(BiquadCoeff!double(b0, b1, b2, a1, a2) / a0);
    }
}

