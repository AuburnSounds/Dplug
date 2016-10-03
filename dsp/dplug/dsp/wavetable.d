/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.wavetable;

import std.math;

//import dplug.core.nogc;
import dplug.core.math;
import dplug.core.alignedbuffer;

/// Generate a sine.
/// It turns out it's very stable, stable enough for table generation at least.
/// TODO: resync method
struct SineGenerator(T)
{
    void initialize(T initPhase, T frequency, T samplerate) nothrow @nogc
    {
        T w = frequency * 2 * PI / samplerate;
        _b1 = 2 * cos(w);
        _y1 = sin(initPhase - w);
        _y2 = sin(initPhase - 2 * w);
    }

    T next() nothrow @nogc
    {
        T y0 = _b1 * _y1 - _y2;
        _y2 = _y1;
        _y1 = y0;
        return y0;
    }

    T _y1, _y2;
    T _b1;
}

enum WaveformType
{
    SINE,
    SAWTOOTH,
    SQUARE,
    TRIANGLE
}

// wavetable with mip-maps

/// Generates anti-aliased waveform generation through
/// procedurally generated mipmapped tables.
/// TODO: only integer phase
struct Wavetable
{
    void initialize(int largestSize, WaveformType waveform) nothrow @nogc
    {
        resize(largestSize);
        generate(waveform);  // regenerate tables
    }

    ~this()
    {
        _mipmapData.reallocBuffer(0);
        _wholeBuffer.reallocBuffer(0);
    }

    @disable this(this);

    float lookupLinear(uint phaseIntPart, float phaseFractional, int level) nothrow @nogc
    {
        float* mipmap0 = mipmapData(level);
        int mask = sizeOfMipmap(level) - 1;
        float a = mipmap0[ phaseIntPart & mask  ];
        float b = mipmap0[ ( 1 + phaseIntPart ) & mask ];
        return a * (1 - phaseFractional) + phaseFractional * b;
    }

    float lookupCatmullRom(uint phaseIntPart, float phaseFractional, int level) nothrow @nogc
    {
        float* mipmap0 = mipmapData(level);
        int mask = sizeOfMipmap(level) - 1;
        float p0 = mipmap0[ (phaseIntPart - 1) & mask  ];
        float p1 = mipmap0[ phaseIntPart & mask  ];
        float p2 = mipmap0[ ( 1 + phaseIntPart ) & mask ];
        float p3 = mipmap0[ ( 2 + phaseIntPart ) & mask ];
        float t = phaseFractional;

        return 0.5f * ((2 * p1)
                        + (-p0 + p2) * t
                        + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                        + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t);
    }

    float lookupCatmullRomMipmap(uint phaseIntPart, float phaseFractional, float phaseIncrementSamples) nothrow @nogc
    {

        float level = cast(float)log2(phaseIncrementSamples);
        int level0 = cast(int)floor(level);
        int level1 = level0 + 1;
        if (level0 < 0)
            level0 = 0;
        if (level1 < 0)
            level1 = 0;
        int maxLevel = cast(int)_numTables - 1;
        if (level0 > maxLevel)
            level0 = maxLevel;
        if (level1 > maxLevel)
            level1 = maxLevel;

        if (level1 == 0)
        {
            return lookupCatmullRom(phaseIntPart, phaseFractional, 0);
        }
        else
        {
            float fractionalLevel = level - level0;

            float phaseL0 = (phaseIntPart + phaseFractional) / cast(float)(1 << level0);
            int iPart0 = cast(int)(phaseL0);
            float fractional0 = phaseL0 - iPart0;

            float phaseL1 = (phaseIntPart + phaseFractional) / cast(float)(1 << level1);
            int iPart1 = cast(int)(phaseL1);
            float fractional1 = phaseL1 - iPart1;

            float L0 = lookupCatmullRom(iPart0, fractional0, level0);
            float L1 = lookupCatmullRom(iPart1, fractional1, level1);
            return lerp(L0, L1, fractionalLevel);
        }
    }

    // mimaps levels range from 0 to numMipmaps() - 1
    int numMipmaps() const nothrow @nogc
    {
        return _numTables;
    }

    int sizeOfMipmap(int level) const nothrow @nogc
    {
        return _largestSize >> level;
    }

    float* mipmapData(int level) nothrow @nogc
    {
        return _mipmapData[level];
    }

private:

    int _largestSize;
    int _mast;
    int _numTables;

    float*[] _mipmapData;
    float[] _wholeBuffer;

    /// Defines the harmonic rolloff, critical to avoid aliasing around the last mipmap
    /// This is very arbitrary and ultimately power of two mipmaps are maybe not sufficient
    /// to have less aliasing.
    static double rolloffHarmonic(double normalizedFrequency) pure nothrow @nogc // between 0 and 1
    {
        double cosF0 = cos(normalizedFrequency * PI);
        return cosF0 * cosF0;
    }

    void resize(int largestSize) nothrow @nogc
    {
        assert(isPowerOfTwo(largestSize));

        _largestSize = largestSize;
        // compute size for all mipmaps
        int sizeNeeded = 0;
        _numTables = 0;
        int sizeOfTable = largestSize;
        while (sizeOfTable > 0)
        {
            sizeNeeded += sizeOfTable;
            sizeOfTable /= 2;
            _numTables += 1;
        }
            
        _wholeBuffer.reallocBuffer(sizeNeeded);

        // fill table pointers
        {
            _mipmapData.reallocBuffer(_numTables);
            int cumulated = 0;
            for (int level = 0; level < _numTables; ++level)
            {
                _mipmapData[level] = &_wholeBuffer[cumulated];
                cumulated += _largestSize >> level;
            }
        }
    }

    // fill all table with waveform
    void generate(WaveformType waveform) nothrow @nogc
    {
        for (int level = 0; level < _numTables; ++level)
        {
            int size = sizeOfMipmap(level);
            float* data = mipmapData(level);

            for (int t = 0; t < size; ++t)
            {
                data[t] = 0;
            }

            int numHarmonics = size / 2;

            if (size > 2)
            {
                for (int h = 0; h < numHarmonics; ++h)
                {
                    double normalizedFrequency = (1 + h) / cast(double)(numHarmonics - 1);
                    double amplitude = getWaveHarmonicAmplitude(waveform, h + 1) * rolloffHarmonic(normalizedFrequency);

                    for (int t = 0; t < size; ++t)
                    {
                        double x = sin( cast(double)t * (2 * PI) * (h + 1) / cast(double)size ) * amplitude;
                        data[t] += cast(float)x;
                    }
                }
            }

            for (int t = 0; t < size; ++t)
            {
                assert(isFinite(data[t]));
            }
        }
    }
}


struct WavetableOsc
{
public:
    void initialize(Wavetable* wavetable, double samplerate) nothrow @nogc
    {
        _wavetable = wavetable;
        _samplerate = samplerate;
        _phaseIntPart = 0;
        _phaseFractional = 0;
    }

    /// Allows dirty resync
    void resetPhase() nothrow @nogc
    {
        _phaseIntPart = 0;
        _phaseFractional = 0;
    }

    float next(float frequency) nothrow @nogc
    {
        float phaseIncrementSamples = cast(float)(_wavetable.sizeOfMipmap(0) * frequency /  (_samplerate));
        assert(phaseIncrementSamples >= 0);
        int iPart = cast(int)(phaseIncrementSamples);
        _phaseIntPart += iPart;

        _phaseFractional += (phaseIncrementSamples - iPart);
        if (_phaseFractional >= 1)
        {
            _phaseFractional -= 1.0;
            _phaseIntPart += 1;

            // in case the assert above would fail (which happen)
            if (_phaseFractional >= 1)
            {
                _phaseFractional -= 1.0;
                _phaseIntPart += 1;
            }
        }

        assert(_phaseFractional >= 0 && _phaseFractional <= 1);

        return _wavetable.lookupCatmullRomMipmap(_phaseIntPart, cast(float)_phaseFractional, phaseIncrementSamples);
        // return _wavetable->lookupLinear(_phaseIntPart, _phaseFractional, 1);
    }

private:
    uint _phaseIntPart;
    double _phaseFractional;
    Wavetable* _wavetable;
    double _samplerate;
}


private:

double getWaveHarmonicAmplitude(WaveformType waveform, int n) nothrow @nogc
{
    assert(n > 0);
    final switch(waveform)
    {
        case WaveformType.SINE:
        {
            if (n == 1)
                return 1;
            else
                return 0;
        }

        case WaveformType.SAWTOOTH:
        {
            return 1 / cast(double)n;
        }

        case WaveformType.SQUARE:
        {
            if (n % 2 == 0)
                return 0;
            else
                return 1 / cast(double)n;
        }

        case WaveformType.TRIANGLE:
        {
            if (n % 2 == 0)
                return 0;
            else if (n % 4 == 1)
                return 1 / cast(double)(n*n);
            else 
            {
                assert(n % 4 == 3);
                return -1 / cast(double)(n*n);
            }
        }
    }
}
