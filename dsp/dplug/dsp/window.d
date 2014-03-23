// See licenses/UNLICENSE.txt
module dplug.dsp.window;

import std.math,
       std.traits;

enum WindowType
{
    RECT,
    HANN,
    HAMMING,
    BLACKMANN,
}

void generateWindow(T)(WindowType type, T[] output)
{
    size_t N = output.length;
    for (size_t i = 0; i < N; ++i)
    {
        output[i] = cast(T)(evalWindow(type, i, N));
    }
}

double secondaryLobeAttenuationInDb(WindowType type)
{
    final switch(type)
    {
        case WindowType.RECT:      return -13.0;
        case WindowType.HANN:      return -32.0;
        case WindowType.HAMMING:   return -42.0;
        case WindowType.BLACKMANN: return -58.0;
    }
}

double evalWindow(WindowType type, size_t n, size_t N)
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
    void initialize(WindowType type, int lengthInSamples)
    {
        data.length = lengthInSamples;
        generateWindow!T(type, data[]);
    }

    T[] data;
    alias data this;
}