/**
* Various window types.
*
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.window;

import std.math;

import dplug.core.vec;

// Useful reference:
// https://en.wikipedia.org/wiki/Window_function


enum WindowType
{
    RECT,
    BARTLETT,
    HANN,
    HAMMING,
    NUTTALL,
    BLACKMANN_NUTTALL, 
    BLACKMANN_HARRIS,
    FLATTOP_SR785,    // Flat top window
    KAISER_BESSEL,   // Kaiser-Bessel window, this one need a parameter alpha (typical values: 1.0 to 4.0)
}

struct WindowDesc
{
    WindowType type;
    float param;
}

void generateWindow(T)(WindowDesc desc, T[] output) pure nothrow @nogc
{
    int N = cast(int)(output.length);
    for (int i = 0; i < N; ++i)
    {
        output[i] = cast(T)(evalWindow(desc, i, N));
    }
}

void generateNormalizedWindow(T)(WindowDesc desc, T[] output) pure nothrow @nogc
{
    int N = cast(int)(output.length);
    T sum = 0;
    for (int i = 0; i < N; ++i)
    {
        output[i] = cast(T)(evalWindow(desc, i, N));
        sum += output[i];
    }
    T invSum = 1 / sum;
    for (int i = 0; i < N; ++i)
        output[i] *= invSum;    
}

deprecated("This function disappeared.") double secondaryLobeAttenuationInDb(WindowType type) pure nothrow @nogc
{
   return double.nan;
}

double evalWindow(WindowDesc desc, int n, int N) pure nothrow @nogc
{
    static double computeKaiserFunction(double alpha, int n, int N) pure nothrow @nogc
    {
        static double I0(double x) pure nothrow @nogc
        {
            double sum = 1;
            double mx = x * 0.5;
            double denom = 1;
            double numer = 1;
            for (int m = 1; m <= 32; m++) 
            {
                numer *= mx;
                denom *= m;
                double term = numer / denom;
                sum += term * term;
            }
            return sum;
        }

        double piAlpha = PI * alpha;
        double C = 2.0 * n / (N - 1.0) - 1.0; 
        double result = I0(piAlpha * sqrt(1.0 - C * C)) / I0(piAlpha);
        return result;
    }

    final switch(desc.type)
    {
        case WindowType.RECT:
            return 1.0;

        case WindowType.BARTLETT:
        {
            double nm1 = (N - 1.0)/2;
            return 1 - abs(n - nm1) / nm1;
        }

        case WindowType.HANN:
        {
            double phi = (2 * PI * n ) / (N - 1);
            return 0.5 - 0.5 * cos(phi);
        }

        case WindowType.HAMMING:
        {
            double phi = (2 * PI * n ) / (N - 1);
            return 0.54 - 0.46 * cos(phi);
        }

        case WindowType.NUTTALL:
        {
            double phi = (2 * PI * n ) / (N - 1);
            return 0.355768 - 0.487396 * cos(phi) + 0.144232 * cos(2 * phi) - 0.012604 * cos(3 * phi);            
        }

        case WindowType.BLACKMANN_HARRIS:
        {
            double phi = (2 * PI * n ) / (N - 1);
            return 0.35875 - 0.48829 * cos(phi) + 0.14128 * cos(2 * phi) - 0.01168 * cos(3 * phi);
        }

        case WindowType.BLACKMANN_NUTTALL:
        {
            double phi = (2 * PI * n ) / (N - 1);
            return 0.3635819 - 0.4891775 * cos(phi) + 0.1365995 * cos(2 * phi) - 0.0106411 * cos(3 * phi);
        }

        case WindowType.FLATTOP_SR785:
        {
            double phi = (2 * PI * n ) / (N - 1);
            return 1 - 1.93 * cos(phi) + 1.29 * cos(2 * phi) - 0.388 * cos(3 * phi) + 0.028 * cos(4 * phi);
        }

        case WindowType.KAISER_BESSEL:
            return computeKaiserFunction(desc.param, n, N);
    }
}

struct Window(T) if (is(T == float) || is(T == double))
{
    void initialize(WindowDesc desc, int lengthInSamples) nothrow @nogc
    {
        _lengthInSamples = lengthInSamples;
        _window.reallocBuffer(lengthInSamples);
        generateWindow!T(desc, _window);
    }

    ~this() nothrow @nogc
    {
        _window.reallocBuffer(0);
    }

    double sumOfWindowSamples() pure const nothrow @nogc
    {
        double result = 0;
        foreach(windowValue; _window)
            result += windowValue;
        return result;
    }

    @disable this(this);

    T[] _window = null;
    int _lengthInSamples;
    alias _window this;
}
