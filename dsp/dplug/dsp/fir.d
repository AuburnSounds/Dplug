// See licenses/UNLICENSE.txt
module dplug.dsp.fir;

import std.range,
       std.math,
       std.complex;

import gfm.math.funcs;

import dplug.dsp.funcs,
       dplug.dsp.fft,
       dplug.dsp.delayline,
       dplug.dsp.window;

// TODO:
// - bandstop/bandstop IR
// - naive convolution

// sinc impulse functions

void generateLowpassImpulse(T)(T[] output, double cutoff, double samplerate) nothrow @nogc
{
    checkFilterParams(output.length, cutoff, samplerate);
    double cutoffNormalized = cutoff / samplerate;
    double wc = cutoffNormalized * 2.0 * PI;

    int len = cast(int)(output.length);
    for (int i = 0; i < len; ++i)
    {
        int x = i - (len / 2);
        if (x == 0)
            output[i] = wc;
        else
            output[i] = sin(wc * x) / cast(double)x;
    }
    normalizeImpulse(output);
}

void generateHighpassImpulse(T)(T[] output, double cutoff, double samplerate) nothrow @nogc
{
    checkFilterParams(output.length, cutoff, samplerate);
    double cutoffNormalized = cutoff / samplerate;
    double wc = cutoffNormalized * 2.0 * PI;

    int len = cast(int)(output.length);
    for (int i = 0; i < len; ++i)
    {
        int x = i - (len / 2);
        if (x == 0)
            output[i] = 1 - wc;
        else
            output[i] = -sin(wc * x) / cast(double)x;
    }
    normalizeImpulse(output);
}

void generateHilbertTransformer(T)(T[] outImpulse, WindowType window, double samplerate) nothrow @nogc
{
    int size = cast(int)(outImpulse.length);
    assert(isOdd(size));
    int center = size / 2;

    for (int i = 0; i < center; ++i)
    {
        double x = cast(double)i - cast(double)center;
        double y = x * cast(double)PI / 2;
        double sine = sin(y);
        T value = cast(T)(-sine*sine / y) * evalWindow(window, i, size);
        outImpulse[i] = value;
        outImpulse[size - 1 - i] = -value;
    }
    outImpulse[center] = 0;
    normalizeImpulse(outImpulse);
}


/// Normalize impulse response.
/// Scale to make sum = 1.
void normalizeImpulse(T)(T[] inoutImpulse) nothrow @nogc
{
    int size = cast(int)(inoutImpulse.length);
    double sum = 0;
    for (int i = 0; i < size; ++i)
        sum += inoutImpulse[i];

    double invSum = 1 / sum;
    for (int i = 0; i < size; ++i)
        inoutImpulse[i] = cast(T)(inoutImpulse[i] * invSum);
}

/// From an impulse, computes a minimum-phase impulse
/// Courtesy of kasaudio, based on Aleksey Vaneev's algorithm
/// Warning: allocates memory.
/// See: http://www.kvraudio.com/forum/viewtopic.php?t=197881
/// TODO: does it preserve amplitude?
void minimumPhaseImpulse(T)(T[] inoutImpulse) nothrow @nogc
{
    int fftSize = cast(int)(nextPowerOf2(inoutImpulse.length));
    auto kernel = new Complex!T[fftSize];
    minimumPhaseImpulse(inoutImpulse, kernel[]);
}

void minimumPhaseImpulse(T)(T[] inoutImpulse,  Complex!T[] tempStorage) nothrow @nogc // alloc free version
{
    int size = cast(int)(inoutImpulse.length);
    alias size n;
    int fftSize = cast(int)( nextPowerOf2(inoutImpulse.length) );
    assert(fftSize >= n);
    int halfFFTSize = fftSize / 2;

    if (tempStorage.length < fftSize)
        assert(false); // crash

    auto kernel = new Complex!T[fftSize];

    for (int i = 0; i < n; ++i)
        kernel[i] = inoutImpulse[i];

    for (int i = n; i < fftSize; ++i)
        kernel[i] = 0;

    FFT!T(kernel[], FFTDirection.FORWARD);

    for (int i = 0; i < fftSize; ++i)
        kernel[i] = log(abs(kernel[i]));

    FFT!T(kernel[], FFTDirection.REVERSE);

    for (int i = 1; i < halfFFTSize; ++i)
        kernel[i] *= 2;

    for (int i = halfFFTSize + 1; i < halfFFTSize; ++i)
        kernel[i] = 0;

    FFT!T(kernel[], FFTDirection.FORWARD);

    for (int i = 0; i < fftSize; ++i)
        kernel[i] = complexExp(kernel[i]);

    FFT!T(kernel[], FFTDirection.REVERSE);

    for (int i = 0; i < size; ++i)
        inoutImpulse[i] = kernel[i].re;
}

private Complex!T complexExp(T)(Complex!T z) nothrow @nogc
{
    T mag = exp(z.re);
    return Complex!T(mag * cos(z.re), mag * sin(z.im));
}


private static void checkFilterParams(size_t length, double cutoff, double sampleRate) nothrow @nogc
{
    assert((length & 1) == 0, "FIR impulse length must be odd");
    assert(cutoff * 2 < sampleRate, "2x the cutoff exceed sampling rate, Nyquist disapproving");
}


unittest
{
    double[256] lp_impulse;
    double[256] hp_impulse;
    generateLowpassImpulse(lp_impulse[], 40.0, 44100.0);
    generateHighpassImpulse(hp_impulse[], 40.0, 44100.0);
    minimumPhaseImpulse(lp_impulse[]);

    generateHilbertTransformer(lp_impulse[0..$-1], WindowType.BLACKMANN, 44100.0);
}


// Composed of a delay-line, and an inpulse.
struct FIR(T)
{
    Delayline!T delayline;
    T[] impulse;

    /// Initializes the FIR filter. It's up to you to fill the impulse with something worthwhile.
    void initialize(int sizeOfFilter, int sizeOfImpulse) nothrow @nogc
    {
        delayline.initialize(sizeOfFilter);
        delayline.fillWith(0);
        impulse[] = T.nan;
        impulse.length = sizeOfImpulse;
    }

    /// Returns: Filtered input sample, naive convolution.
    T next(T input) nothrow @nogc
    {
        delayline.feed(input);
        int sum = 0;
        for (int i = 0; i < cast(int)impulse.length; ++i)
            sum += impulse[i] * delayline.sampleFull(i);
        return sum;
    }
}
