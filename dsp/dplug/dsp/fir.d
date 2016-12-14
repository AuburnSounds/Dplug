/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.fir;

import std.range,
       std.math,
       std.complex;

import dplug.core,
       dplug.dsp.fft,
       dplug.dsp.delayline,
       dplug.dsp.window;

// FUTURE:
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

void generateHilbertTransformer(T)(T[] outImpulse, WindowDesc windowDesc, double samplerate) nothrow @nogc
{
    int size = cast(int)(outImpulse.length);
    assert(isOdd(size));
    int center = size / 2;

    for (int i = 0; i < center; ++i)
    {
        double x = cast(double)i - cast(double)center;
        double y = x * cast(double)PI / 2;
        double sine = sin(y);
        T value = cast(T)(-sine*sine / y) * evalWindow(windowDesc, i, size);
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

/// Returns: Length of temporary buffer needed for `minimumPhaseImpulse`.
int tempBufferSizeForMinPhase(T)(T[] inputImpulse) nothrow @nogc
{
    return cast(int)( nextPowerOf2(inputImpulse.length) );
}

/// From an impulse, computes a minimum-phase impulse
/// Courtesy of kasaudio, based on Aleksey Vaneev's algorithm
/// See: http://www.kvraudio.com/forum/viewtopic.php?t=197881
/// MAYDO: does it preserve amplitude?
void minimumPhaseImpulse(T)(T[] inoutImpulse,  Complex!T[] tempStorage) nothrow @nogc // alloc free version
{
    assert(tempStorage.length >= tempBufferSizeForMinPhase(inoutImpulse));

    int N = cast(int)(inoutImpulse.length);
    int fftSize = cast(int)( nextPowerOf2(inoutImpulse.length) );
    assert(fftSize >= N);
    int halfFFTSize = fftSize / 2;

    if (tempStorage.length < fftSize)
        assert(false); // crash

    auto kernel = tempStorage;

    for (int i = 0; i < N; ++i)
        kernel[i] = inoutImpulse[i];

    for (int i = N; i < fftSize; ++i)
        kernel[i] = 0;

    forwardFFT!T(kernel[]);

    for (int i = 0; i < fftSize; ++i)
        kernel[i] = log(abs(kernel[i]));

    inverseFFT!T(kernel[]);

    for (int i = 1; i < halfFFTSize; ++i)
        kernel[i] *= 2;

    for (int i = halfFFTSize + 1; i < halfFFTSize; ++i)
        kernel[i] = 0;

    forwardFFT!T(kernel[]);

    for (int i = 0; i < fftSize; ++i)
        kernel[i] = complexExp(kernel[i]);

    inverseFFT!T(kernel[]);

    for (int i = 0; i < N; ++i)
        inoutImpulse[i] = kernel[i].re;
}

private Complex!T complexExp(T)(Complex!T z) nothrow @nogc
{
    T mag = exp(z.re);
    return Complex!T(mag * cos(z.re), mag * sin(z.im));
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

    Complex!double[] tempStorage = new Complex!double[tempBufferSizeForMinPhase(lp_impulse[])];
    minimumPhaseImpulse(lp_impulse[], tempStorage);

    generateHilbertTransformer(lp_impulse[0..$-1], WindowDesc(WindowType.BLACKMANN_HARRIS), 44100.0);
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

    /// Returns: Impulse response. If you write it, you can call makeMinimumPhase() next.
    inout(T)[] impulse() inout nothrow @nogc
    {
        return _impulse;
    }

    void makeMinimumPhase() nothrow @nogc
    {
        int sizeOfTemp = tempBufferSizeForMinPhase(_impulse);
        _tempBuffer.reallocBuffer(sizeOfTemp);
        minimumPhaseImpulse(_impulse, _tempBuffer);
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
    Complex!double[] _tempBuffer;
    T[] _windowBuffer;
}

unittest
{
    FIR!double fir;
    fir.initialize(32);
    generateLowpassImpulse(fir.impulse(), 40.0, 44100.0);
    fir.makeMinimumPhase();
    fir.applyWindow(WindowDesc(WindowType.HANN));
}
