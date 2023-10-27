/**
Naive FIR implementation.

Copyright: Guillaume Piolat 2015.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.dsp.fir;

import core.stdc.complex;

import std.math: PI, sin;
import std.complex;

import dplug.core.math;
import dplug.core.vec;
import dplug.dsp.delayline;
import dplug.dsp.window;

// FUTURE: should probably be removed, not good enough. 
// Need a real convolver library.

// Basic sinc impulse functions

/// Generates a sinc lowpass impulse, centered on floor(output.length / 2).
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
            output[i] = cutoffNormalized * 2.0;
        else
            output[i] = sin(wc * x) / cast(double)(PI * x);
    }
}

/// Generates a sinc highpass impulse, centered on floor(output.length / 2).
/// When convolved with, preserve amplitude of the pass-band.
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
            output[i] = 1.0 - 2 * cutoffNormalized;
        else
            output[i] = sinc(PI * x) / cast(double)(PI * x) - 2.0 * cutoffNormalized * sin(wc * x) / (wc * x);
    }
}

/// Generates a hilbert transformer impulse, centered on floor(output.length / 2).
void generateHilbertTransformer(T)(T[] outImpulse, WindowDesc windowDesc, double samplerate) nothrow @nogc
{
    int size = cast(int)(outImpulse.length);
    assert(isOdd(size));
    int center = size / 2;

    for (int i = 0; i < center; ++i)
    {
        int xi = i - center;
        double x = cast(double)xi;
        if (isEven(xi))
        {
            outImpulse[i] = 0;
            outImpulse[size - 1 - i] = 0;
        }
        else
        {
            double y = x * cast(double)PI / 2;
            double sine = sin(y);
            T value = cast(T)(-sine*sine / y);
            value *= evalWindow(windowDesc, i, size);
            outImpulse[i] = value;
            outImpulse[size - 1 - i] = -value;
        }
    }
    outImpulse[center] = 0;
}

private static void checkFilterParams(size_t length, double cutoff, double sampleRate) nothrow @nogc
{
    assert((length & 1) == 0, "FIR impulse length must be even");
    assert(cutoff * 2 < sampleRate, "2x the cutoff exceed sampling rate, Nyquist disapproving");
}

unittest
{
    double[256] lp_impulse;
    double[256] hp_impulse;
    generateLowpassImpulse(lp_impulse[], 40.0, 44100.0);
    generateHighpassImpulse(hp_impulse[], 40.0, 44100.0);
}

unittest
{
    double[256] lp_impulse;
    generateHilbertTransformer(lp_impulse[0..$-1],
        WindowDesc(WindowType.blackmannHarris,
                   WindowAlignment.right), 44100.0);
}


// Composed of a delay-line, and an inpulse.
struct FIR(T)
{
    /// Initializes the FIR filter. It's up to you to fill the impulse with something worthwhile.
    void initialize(int sizeOfImpulse) nothrow @nogc
    {
        assert(sizeOfImpulse > 0);
        _delayline.initialize(sizeOfImpulse);
        _impulse.reallocBuffer(sizeOfImpulse);
        _impulse[] = T.nan;
    }

    ~this() nothrow @nogc
    {
        _impulse.reallocBuffer(0);
        _windowBuffer.reallocBuffer(0);
    }

    @disable this(this);

    /// Returns: Filtered input sample, naive convolution.
    T nextSample(T input) nothrow @nogc
    {
        _delayline.feedSample(input);
        T sum = 0;
        int N = cast(int)impulse.length;
        for (int i = 0; i < N; ++i)
            sum += _impulse.ptr[i] * _delayline.sampleFull(i);
        return sum;
    }

    void nextBuffer(T* input, T* output, int samples) nothrow @nogc
    {
        for (int i = 0; i < samples; ++i)
        {
            output[i] = nextSample(input[i]);
        }
    }

    /// Returns: Impulse response. If you write it, you can call makeMinimumPhase() next.
    inout(T)[] impulse() inout nothrow @nogc
    {
        return _impulse;
    }

    void applyWindow(WindowDesc windowDesc) nothrow @nogc
    {
        _windowBuffer.reallocBuffer(_impulse.length);
        generateWindow(windowDesc, _windowBuffer);
        foreach(i; 0.._impulse.length)
        {
            _impulse[i] *= _windowBuffer[i];
        }
    }

private:
    T[] _impulse;

    Delayline!T _delayline;
    T[] _windowBuffer;
}

unittest
{
    FIR!double fir;
    fir.initialize(32);
    generateLowpassImpulse(fir.impulse(), 40.0, 44100.0);
    fir.applyWindow(WindowDesc(WindowType.hann, WindowAlignment.right));
}
