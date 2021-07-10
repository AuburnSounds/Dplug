/**
Naive FIR implementation.

Copyright: Guillaume Piolat 2015.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.dsp.fir;

import core.stdc.complex;

import std.range,
       std.math;

import dplug.core.math,
       dplug.core.vec,
       dplug.core.complex,
       dplug.dsp.fft,
       dplug.dsp.delayline,
       dplug.dsp.window;

// FUTURE:
// - bandstop/bandstop IR
// - naive convolution

// sinc impulse functions

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

/// Returns: Length of temporary buffer needed for `minimumPhaseImpulse`.
int tempBufferSizeForMinPhase(T)(T[] inputImpulse) nothrow @nogc
{
    return cast(int)( nextPow2HigherOrEqual(inputImpulse.length * 4)); // PERF: too much?
}


/// From an impulse, computes a minimum-phase impulse
/// Courtesy of kasaudio, based on Aleksey Vaneev's algorithm
/// See: http://www.kvraudio.com/forum/viewtopic.php?t=197881
/// MAYDO: does it preserve amplitude?
void minimumPhaseImpulse(T)(T[] inoutImpulse, BuiltinComplex!T[] tempStorage) nothrow @nogc // alloc free version
{
    assert(tempStorage.length >= tempBufferSizeForMinPhase(inoutImpulse));

    int N = cast(int)(inoutImpulse.length);
    int fftSize = cast(int)( nextPow2HigherOrEqual(inoutImpulse.length * 4));
    assert(fftSize >= N);
    int halfFFTSize = fftSize / 2;

    if (tempStorage.length < fftSize)
        assert(false); // crash

    auto kernel = tempStorage;

    // Put the real impulse in a larger buffer
    for (int i = 0; i < N; ++i)
        kernel[i] = BuiltinComplex!T(inoutImpulse[i], 0);
    for (int i = N; i < fftSize; ++i)
        kernel[i] = BuiltinComplex!T(0, 0);

    forwardFFT!T(kernel[]);

    // Take the log-modulus of spectrum
    for (int i = 0; i < fftSize; ++i)
        kernel[i] =  BuiltinComplex!T( log(std.complex.abs(kernel[i])), 0);

    // Back to real cepstrum
    inverseFFT!T(kernel[]);

    // Apply a cepstrum window, not sure how this works
    kernel[0] = BuiltinComplex!T(kernel[0].re, 0);
    for (int i = 1; i < halfFFTSize; ++i)
        kernel[i] = BuiltinComplex!T(kernel[i].re * 2, 0);
    kernel[halfFFTSize] = BuiltinComplex!T(kernel[halfFFTSize].re, 0);
    for (int i = halfFFTSize + 1; i < fftSize; ++i)
        kernel[i] = BuiltinComplex!T(0, 0);

    forwardFFT!T(kernel[]);

    for (int i = 0; i < fftSize; ++i)
        kernel[i] = complexExp!T(kernel[i]);

    inverseFFT!T(kernel[]);

    for (int i = 0; i < N; ++i)
        inoutImpulse[i] = kernel[i].re;
}

private BuiltinComplex!T complexExp(T)(BuiltinComplex!T z) nothrow @nogc
{
    T mag = exp(z.re);
    return BuiltinComplex!T( (mag * cos(z.im)) , (mag * sin(z.im)) );
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

    BuiltinComplex!double[] tempStorage = new BuiltinComplex!double[tempBufferSizeForMinPhase(lp_impulse[])];
    minimumPhaseImpulse!double(lp_impulse[], tempStorage);

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
        _tempBuffer.reallocBuffer(0);
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

    void makeMinimumPhase() nothrow @nogc
    {
        int sizeOfTemp = tempBufferSizeForMinPhase(_impulse);
        _tempBuffer.reallocBuffer(sizeOfTemp);
        minimumPhaseImpulse!T(_impulse, _tempBuffer);
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
    BuiltinComplex!T[] _tempBuffer;
    T[] _windowBuffer;
}

unittest
{
    FIR!double fir;
    fir.initialize(32);
    generateLowpassImpulse(fir.impulse(), 40.0, 44100.0);
    fir.makeMinimumPhase();
    fir.applyWindow(WindowDesc(WindowType.hann, WindowAlignment.right));
}
