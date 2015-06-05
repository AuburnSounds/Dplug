// See licenses/UNLICENSE.txt
module dplug.dsp.window;

import std.math,
       std.traits;

import dplug.dsp.funcs;

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
    final switch(type)
    {
        case WindowType.RECT:
            return 1.0;

        case WindowType.HANN:
            return 0.5 - 0.5 * cos((2 * PI * n) / (N - 1));

        case WindowType.HAMMING:
            return 0.54 - 0.46 * cos((2 * PI * n) / (N - 1));

        case WindowType.BLACKMANN:
            {
                double phi = (2 * PI * n) / (N - 1);
                return 0.42 - 0.5 * cos(phi) + 0.08 * cos(2 * phi);
            }
    }
}

struct Window(T) if (isFloatingPoint!T)
{
    void initialize(WindowType type, int lengthInSamples) nothrow @nogc
    {
        _lengthInSamples = lengthInSamples;
        generateWindow!T(type, _window);
        _window.reallocBuffer(lengthInSamples);
    }

    ~this() nothrow @nogc
    {
        _window.reallocBuffer(0);
    }

    @disable this(this);

    T[] _window = null;
    int _lengthInSamples;
    alias _window this;
}