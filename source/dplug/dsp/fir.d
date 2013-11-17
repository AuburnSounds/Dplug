module dplug.dsp.fir;

import std.range;

// TODO:
// - bandstop/bandstop IR
// - naive convolution

// sinc impulse functions
void generateLowpassImpulse(T)(T[] output, double cutoff, double samplerate)
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
}

void generateHighpassImpulse(T)(T[] output, double cutoff, double samplerate)
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
}

private static void checkFilterParams(size_t length, double cutoff, double sampleRate)
{
    assert((length & 1) == 0, "FIR impulse length must be odd");
    assert(cutoff * 2 >= sampleRate, "2x the cutoff exceed sampling rate, Nyquist disapproving");
}