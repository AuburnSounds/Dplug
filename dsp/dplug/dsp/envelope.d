/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.envelope;

import dplug.dsp.iir;
import dplug.dsp.smooth;

// Various envelope followers


/// Simple envelope follower, filters the envelope with 24db/oct lowpass.
struct EnvelopeFollower(T)
{
public:

    // typical frequency would be is 10-30hz
    void initialize(double cutoffInHz, double samplerate) nothrow @nogc
    {
        _coeff = lowpassFilterRBJ!double(cutoffInHz, samplerate);
        _delay0.clear();
        _delay1.clear();
    }

    // takes on sample, return mean amplitude
    T next(T x) nothrow @nogc
    {
        T l = abs(x);
        l = _delay0.next(l, _coeff);
        l = _delay1.next(l, _coeff);
        return l;
    }

private:
    BiquadCoeff!T _coeff;
    BiquadDelay!T _delay0;
    BiquadDelay!T _delay1;
}

struct AttackReleaseFollower(T)
{
public:

    void initialize(double samplerate, float timeAttack, float timeRelease) nothrow @nogc
    {
        _expSmoother.initialize(0, timeAttack, timeRelease, samplerate, T.epsilon);
    }

    T next(T input) nothrow @nogc
    {
        return _expSmoother.next(abs(input));
    }

private:
    ExpSmoother!T _expSmoother;
}

/// Get the module of estimate of analytic signal.
/// Phase response depends a lot on input signal, it's not great for bass but gets
/// better in medium frequencies.
struct AnalyticSignal(T)
{
public:
    void initialize(T samplerate) nothrow @nogc
    {
        _hilbert.initialize(samplerate);
    }

    T next(T input) nothrow @nogc
    {
        T outSine, outCosine;
        _hilbert.next(input, &outCosine, &outSine);
        return sqrt(input * input + outSine * outSine);
    }

private:
    HilbertTransformer!T _hilbert;
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
struct HilbertTransformer(T)
{
public:
    void initialize(double samplerate) nothrow @nogc
    {
        // pole values taken from Bernie Hutchins, "Musical Engineer's Handbook"
        static immutable double[12] poles =
        [
            0.3609, 2.7412, 11.1573, 44.7581, 179.6242, 798.4578,
            1.2524, 5.5671, 22.3423, 89.6271, 364.7914, 2770.1114
        ];

        double onedsr = 1.0 / samplerate;

        // calculate coefficients for allpass filters, based on sampling rate
        for (int j = 0; j < 12; ++j)
        {
            const double polefreq = poles[j] * 15.0;
            const double rc = 1.0 / (2.0 * PI * polefreq);
            const double alpha = 1.0 / rc;
            const double beta = (1.0 - (alpha * 0.5 * onedsr)) / (1.0 + (alpha * 0.5 * onedsr));
            _xnm1[j] = 0;
            _ynm1[j] = 0;
            _coef[j] = -beta;
        }
    }

    void next (T input, T* out1, T* out2) nothrow @nogc
    {
        double yn1, yn2;
        double xn1 = input;

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

        double xn2 = input;

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
        *out1 = cast(T)yn2;
        *out2 = cast(T)yn1;
    }

private:
    double[12] _coef;
    double[12] _xnm1;
    double[12] _ynm1;
}

struct RMSEnvelope(T)
{
public:
    void initialize(double samplerate) nothrow @nogc
    {        
        // TODO
        assert(false);        
    }

    T next(T input) nothrow @nogc
    {
        // TODO
        assert(false);
    }

private:



}