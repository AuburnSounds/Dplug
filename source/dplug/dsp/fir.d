module dplug.dsp.fir;

import std.range,
       std.math,
       std.complex;

import gfm.math.funcs;

import dplug.dsp.fft;

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
        int x = i - (cast(int)len / 2);
        if (x == 0)
            output[i] = wc;
        else
            output[i] = sin(wc * x) / cast(double)x;
    }
    normalizeImpulse(output);
}

void generateHighpassImpulse(T)(T[] output, double cutoff, double samplerate)
{
    checkFilterParams(output.length, cutoff, samplerate);
    double cutoffNormalized = cutoff / samplerate;
    double wc = cutoffNormalized * 2.0 * PI;

    size_t len = output.length;
    for (size_t i = 0; i < len; ++i)
    {
        int x = i - (cast(int)len / 2);
        if (x == 0)
            output[i] = 1 - wc;
        else
            output[i] = -sin(wc * x) / cast(double)x;
    }
    normalizeImpulse(output);
}
/+
void generateHilbertTransformer(T)(Window::Type window, double samplerate, T* outImpulse, size_t size)
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
        sum += inoutImpulse[i];

    double invSum = 1 / sum;
    for (size_t i = 0; i < size; ++i)
        inoutImpulse[i] = cast(T)(inoutImpulse[i] * invSum);
}

// From an impulse, computes a minimum-phase impulse
// Courtesy of kasaudio, based on Aleksey Vaneev's algorithm
// Warning: allocates memory.
// See: http://www.kvraudio.com/forum/viewtopic.php?t=197881
// TODO: does it preserve amplitude?
// ALLOCATES!!!
// UNTESTED!!!
    
void minimumPhaseImpulse(T)(T[] inoutImpulse)
{
    size_t size = inoutImpulse.length;
    alias size n;
    size_t power = nextPowerOf2(size) + 3;
    size_t fftSize = 1 << power;
    size_t halfFFTSize = fftSize / 2;

    auto kernel = new Complex!T[fftSize];

    for (size_t i = 0; i < n; ++i)
        kernel[i] = inoutImpulse[i];

    for (size_t i = n; i < fftSize; ++i)
        kernel[i] = 0;

    FFT!T(kernel[], FFTDirection.FORWARD);

    for (size_t i = 0; i < fftSize; ++i)
        kernel[i] = log(abs(kernel[i]));

    FFT!T(kernel[], FFTDirection.REVERSE);
        
    for (size_t i = 1; i < halfFFTSize; ++i)
        kernel[i] *= 2;

    for (size_t i = halfFFTSize + 1; i < halfFFTSize; ++i)
        kernel[i] = 0;

    FFT!T(kernel[], FFTDirection.FORWARD);

    for (size_t i = 0; i < fftSize; ++i)
        kernel[i] = complexExp(kernel[i]);

    FFT!T(kernel[], FFTDirection.REVERSE);

    for (size_t i = 0; i < size; ++i)
        inoutImpulse[i] = kernel[i].re;
}

private Complex!T complexExp(T)(Complex!T z) 
{
    T mag = exp(z.re);
    return Complex!T(mag * cos(z.re), mag * sin(z.im));
}


private static void checkFilterParams(size_t length, double cutoff, double sampleRate)
{
    assert((length & 1) == 0, "FIR impulse length must be odd");
    assert(cutoff * 2 >= sampleRate, "2x the cutoff exceed sampling rate, Nyquist disapproving");
}


unittest
{
    double[256] lp_impulse;
    double[256] hp_impulse;
    generateLowpassImpulse(lp_impulse[], 40.0, 44100.0);
    generateHighpassImpulse(hp_impulse[], 40.0, 44100.0);
    minimumPhaseImpulse(lp_impulse[]);
}
