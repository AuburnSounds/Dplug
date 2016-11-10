/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.window;

import std.math;

import dplug.core.alignedbuffer;

enum WindowType
{
    RECT,
    HANN,
    HAMMING,
    BLACKMANN,
}

void generateWindow(T)(WindowType type, T[] output) pure nothrow @nogc
{
    int N = cast(int)(output.length);
    for (int i = 0; i < N; ++i)
    {
        output[i] = cast(T)(evalWindow(type, i, N));
    }
}

double secondaryLobeAttenuationInDb(WindowType type) pure nothrow @nogc
{
    final switch(type)
    {
        case WindowType.RECT:      return -13.0;
        case WindowType.HANN:      return -32.0;
        case WindowType.HAMMING:   return -42.0;
        case WindowType.BLACKMANN: return -58.0;
    }
}

double evalWindow(WindowType type, int n, int N) pure nothrow @nogc
{
    double phi = (2 * PI * (n + 1)) / (N + 1);

    final switch(type)
    {
        case WindowType.RECT:
            return 1.0;

        case WindowType.HANN:
            return 0.5 - 0.5 * cos(phi);

        case WindowType.HAMMING:
            return 0.54 - 0.46 * cos(phi);

        case WindowType.BLACKMANN:
            return 0.42 - 0.5 * cos(phi) + 0.08 * cos(2 * phi);
    }
}

struct Window(T) if (is(T == float) || is(T == double))
{
    void initialize(WindowType type, int lengthInSamples) nothrow @nogc
    {
        _lengthInSamples = lengthInSamples;
        _window.reallocBuffer(lengthInSamples);
        generateWindow!T(type, _window);
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