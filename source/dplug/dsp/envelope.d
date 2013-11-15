module dplug.dsp.hilbert;

//  Envelope followers


/// Get the module of estimate of analytic signal.
/// Phase response depends a lot on input signal, it's not great for bass but gets
/// better in medium frequencies.
struct AnalyticSignal(T)
{
public:
    void init(double samplerate)
    {
        _hilbert.init(samplerate);
    }

    T next(T input)
    {
        double outSine, outCosine;
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
    void init(double samplerate)
    {
        // pole values taken from Bernie Hutchins, "Musical Engineer's Handbook"
        static immutable double poles[12] = 
        [
            0.3609, 2.7412, 11.1573, 44.7581, 179.6242, 798.4578,
            1.2524, 5.5671, 22.3423, 89.6271, 364.7914, 2770.1114
        ];

        double onedsr = 1.0 / samplerate;

        // calculate coefficients for allpass filters, based on sampling rate
        for (int j = 0; j < 12; ++j) 
        {  
            const double polefreq = poles[j] * 15.0;
            const double rc = 1.0 / (2.0 * GFM_PI * polefreq);
            const double alpha = 1.0 / rc;
            const double beta = (1.0 - (alpha * 0.5 * onedsr)) / (1.0 + (alpha * 0.5 * onedsr));
            _xnm1[j] = 0;
            _ynm1[j] = 0;
            _coef[j] = -beta;
        }
    }

    void next (T input, T* out1, T* out2)
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





/// Teager Energy Operator.
/// References: 
/// - "Signal processing using the Teager Energy Operator and other nonlinear operators" Eivind Kvedalen (2003)
/// - http://www.temple.edu/speech_lab/sundaram.PDF
/// I don't really know how it can be used.
struct Teager(T)
{
public:       
    void init()
    {
        _xm1 = 0;
        _xm2 = 0;
    }

    T next(T input)
    {
        T res = _xm1 * _xm1 - input * _xm2;
        _xm2 = _xm1;
        _xm1 = input;
        return res;      
    }

private:
    T _xm1;
    T _xm2;
}

/// Teager estimator    
/// Probably measure energy? Not awesome as an amplitude estimator.        
struct TeagerAmplitude(T)
{
    void init()
    {
        _teager0.init();
        _teager1.init();
        _last = 0;
    }

    T next(T input)
    {
        T teager_Xn = _teager0.next(input);
        T teager_Xn_m_Xnm1 = _teager1.next(input - _last);
        _last = input;

        T num = teager_Xn * teager_Xn * teager_Xn;
        T denom = teager_Xn_m_Xnm1 * (4 * teager_Xn - teager_Xn_m_Xnm1);
        if (abs(denom) < 1e-10)
            return 0;
        double inSqrt = num / denom;
        if (inSqrt <= 0)
            return 0;

        return sqrt(inSqrt);
    }

private:
    Teager!T _teager0;
    Teager!T _teager1;
    T _last;
}