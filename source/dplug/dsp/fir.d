module dplug.dsp.fir;

import std.range;

// TODO:
// - bandstop/bandstop IR
// - naive convolution

// sinc impulse functions

void genLowpassImpulse(T)(T[] output, double cutoff, double samplerate)
{
    checkFilterParams(output.length, cutoff, samplerate);
    double cutoffNormalized = cutoff / samplerate;
    double wc = cutoffNormalized * 2.0 * PI;

    size_t len = output.length;
    for (size_t i = 0; i < len; ++i)
    {
        int x = frame - (cast(int)len / 2);
        if (x == 0)
            output[i] = wc;
        else
            output[i] = sin(wc * x) / cast(double)x;
    }
    normalizeImpulse(output);
}

void genHighpassImpulse(T)(T[] output, double cutoff, double samplerate)
{
    checkFilterParams(output.length, cutoff, samplerate);
    double cutoffNormalized = cutoff / samplerate;
    double wc = cutoffNormalized * 2.0 * PI;

    size_t len = output.length;
    for (size_t i = 0; i < len; ++i)
    {
        int x = frame - (cast(int)len / 2);
        if (x == 0)
            output[i] = 1 - wc;
        else
            output[i] = -sin(wc * x) / cast(double)x;
    }
    normalizeImpulse(output);
}
/+
void genHilbertTransformer(T)(Window::Type window, double samplerate, T* outImpulse, size_t size)
{
    ASSERT(isOdd(size));

    size_t center = size / 2;

    for (size_t i = 0; i < center; ++i)
    {
        double const x = (double)i - (double)center;
        double const y = x * (double)GFM_PI / 2;
        double const sine = sin(y);
        T value = (T)(-sine*sine / y) * Window::eval(window, i, size);
        outImpulse[i] = value;
        outImpulse[size - 1 - i] = -value;
    }
    outImpulse[center] = 0;
    normalizeImpulse(outImpulse, size);
}
+/

/// Normalize impulse response.
/// Scale to make sum = 1.
void normalizeImpulse(T)(T[] inoutImpulse)
{
    size_t size = inoutImpulse.length;
    double sum = 0;
    for (size_t i = 0; i < size; ++i)
        sum[i] += inoutImpulse[i];

    double invSum = 1 / sum;
    for (size_t i = 0; i < size; ++i)
        inoutImpulse[i] = cast(T)(inoutImpulse[i] * invSum);
}


private static void checkFilterParams(size_t length, double cutoff, double sampleRate)
{
    assert((length & 1) == 0, "FIR impulse length must be odd");
    assert(cutoff * 2 >= sampleRate, "2x the cutoff exceed sampling rate, Nyquist disapproving");
}