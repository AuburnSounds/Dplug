/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.envelope;

import std.traits;

import dplug.dsp.iir;
import dplug.dsp.smooth;

// Various envelope followers


/// Simple envelope follower, filters the envelope with 24db/oct lowpass.
struct EnvelopeFollower(T) if (isFloatingPoint!T)
{
public:

    // typical frequency would be is 10-30hz
    void initialize(float cutoffInHz, float samplerate) nothrow @nogc
    {
        _coeff = lowpassFilterRBJ!double(cutoffInHz, samplerate);
        _delay0.initialize();
        _delay1.initialize();
    }

    // takes on sample, return mean amplitude
    T nextSample(T x) nothrow @nogc
    {
        T l = abs(x);
        l = _delay0.nextSample(l, _coeff);
        l = _delay1.nextSample(l, _coeff);
        return l;
    }

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for(int i = 0; i < frames; ++i)
            output[i] = abs(input[i]);

        _delay0.nextBuffer(output, output, frames, _coeff);
        _delay1.nextBuffer(output, output, frames, _coeff);
    }

private:
    BiquadCoeff!T _coeff;
    BiquadDelay!T _delay0;
    BiquadDelay!T _delay1;
}

unittest
{
    EnvelopeFollower!float a;
    EnvelopeFollower!double b;
}

/// Get the module of estimate of analytic signal.
/// Phase response depends a lot on input signal, it's not great for bass but gets
/// better in medium frequencies.
struct AnalyticSignal(T) if (isFloatingPoint!T)
{
public:
    void initialize(T samplerate) nothrow @nogc
    {
        _hilbert.initialize(samplerate);
    }

    T nextSample(T input) nothrow @nogc
    {
        T outSine, outCosine;
        _hilbert.nextSample(input, outCosine, outSine);
        return sqrt(input * input + outSine * outSine);
    }

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        // TODO: pass maxFrames and allocate buffers
        for (int i = 0; i < frames; ++i)
            output[i] = nextSample(input[i]);
    }

private:
    HilbertTransformer!T _hilbert;
}

unittest
{
    AnalyticSignal!float a;
    AnalyticSignal!double b;
}


/**
*
* Copyright 1999, by Sean M. Costello
*
* hilbert is an implementation of an IIR Hilbert transformer.
* The structure is based on two 6th-order allpass filters in
* parallel, with a constant phase difference of 90 degrees
* (+- some small amount of error) between the two outputs.
* Allpass coefficients are calculated at i-time.
*
* "Feel free to use the code under whatever license you wish." - Sean Costello
*/

/// Estimate amplitude.
struct HilbertTransformer(T) if (isFloatingPoint!T)
{
public:
    void initialize(float sampleRate) nothrow @nogc
    {
        // pole values taken from Bernie Hutchins, "Musical Engineer's Handbook"
        static immutable double[12] poles =
        [
            0.3609, 2.7412, 11.1573, 44.7581, 179.6242, 798.4578,
            1.2524, 5.5671, 22.3423, 89.6271, 364.7914, 2770.1114
        ];

        float onedsr = 1 / sampleRate;

        // calculate coefficients for allpass filters, based on sampling rate
        for (int j = 0; j < 12; ++j)
        {
            const double polefreq = poles[j] * 15.0;
            const double rc = 1.0 / (2.0 * PI * polefreq);
            const double alpha = 1.0 / rc;
            const double beta = (1.0 - (alpha * 0.5 * onedsr)) / (1.0 + (alpha * 0.5 * onedsr));
            _coef[j] = -beta;
        }

        for (int j = 0; j < 12; ++j)
        {
            _xnm1[j] = 0;
            _ynm1[j] = 0;
        }
    }

    void nextSample(T input, out T out1, out T out2) nothrow @nogc
    {
        T yn1, yn2;
        T xn1 = input;

        /* 6th order allpass filter for sine output. Structure is
        * 6 first-order allpass sections in series. Coefficients
        * taken from arrays calculated at i-time.
        */

        for (int j=0; j < 6; j++)
        {
            yn1 = _coef[j] * (xn1 - _ynm1[j]) + _xnm1[j];
            _xnm1[j] = xn1;
            _ynm1[j] = yn1;
            xn1 = yn1;
        }

        T xn2 = input;

        /* 6th order allpass filter for cosine output. Structure is
        * 6 first-order allpass sections in series. Coefficients
        * taken from arrays calculated at i-time.
        */
        for (int j = 6; j < 12; j++)
        {
            yn2 = _coef[j] * (xn2 - _ynm1[j]) + _xnm1[j];
            _xnm1[j] = xn2;
            _ynm1[j] = yn2;
            xn2 = yn2;
        }
        out1 = cast(T)yn2;
        out2 = cast(T)yn1;
    }

    void nextBuffer(const(T)* input, T* output1, T* output2, int frames) nothrow @nogc
    {
        for (int i = 0; i < frames; ++i)
        {
            T yn1;
            T xn1 = input[i];

            /* 6th order allpass filter for sine output. Structure is
            * 6 first-order allpass sections in series. Coefficients
            * taken from arrays calculated at i-time.
            */
            for (int j=0; j < 6; j++)
            {
                yn1 = _coef[j] * (xn1 - _ynm1[j]) + _xnm1[j];
                _xnm1[j] = xn1;
                _ynm1[j] = yn1;
                xn1 = yn1;
            }
            output2[i] = cast(T)yn1;
        }

        for (int i = 0; i < frames; ++i)
        {
            T yn2;
            T xn2 = input[i];

            /* 6th order allpass filter for cosine output. Structure is
            * 6 first-order allpass sections in series. Coefficients
            * taken from arrays calculated at i-time.
            */
            for (int j = 6; j < 12; j++)
            {
                yn2 = _coef[j] * (xn2 - _ynm1[j]) + _xnm1[j];
                _xnm1[j] = xn2;
                _ynm1[j] = yn2;
                xn2 = yn2;
            }

            output1[i] = cast(T)yn2;
        }

        // Remove small signals
        for (int j = 0; j < 12; ++j)
        {
            _xnm1[j] += 1e-10f;
            _xnm1[j] -= 1e-10f;
            _ynm1[j] += 1e-10f;
            _ynm1[j] -= 1e-10f;
        }
    }

private:
    T[12] _coef;
    T[12] _xnm1;
    T[12] _ynm1;
}

unittest
{
    HilbertTransformer!float a;
    HilbertTransformer!double b;
}

/// Sliding RMS computation
/// To use for coarse grained levels for visual display.
struct CoarseRMS(T) if (isFloatingPoint!T)
{
public:
    void initialize(double sampleRate) nothrow @nogc
    {
        // In Reaper, default RMS window is 500 ms
        _envelope.initialize(20, sampleRate);

        _last = 0;
    }

    /// Process a chunk of samples and return a value in dB (could be -infinity)
    void nextSample(T input) nothrow @nogc
    {
        _last = _envelope.nextSample(input * input);
    }

    void nextBuffer(T* input, int frames) nothrow @nogc
    {
        if (frames == 0)
            return;

        for (int i = 0; i < frames - 1; ++i)
            _envelope.nextSample(input[i] * input[i]);

        _last = _envelope.nextSample(input[frames - 1] * input[frames - 1]);
    }

    T RMS() nothrow @nogc
    {
        return sqrt(_last);
    }

private:
    EnvelopeFollower!T _envelope;
    T _last;
}

unittest
{
    CoarseRMS!float a;
    CoarseRMS!double b;
}
