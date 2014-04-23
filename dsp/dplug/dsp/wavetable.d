// See licenses/UNLICENSE.txt
module dplug.dsp.wavetable;

import std.math;

import gfm.math.funcs;

import dplug.dsp.funcs;

/// Generate a sine.
/// It turns out it's very stable, stable enough for table generation at least.
/// TODO: resync method
struct SineGenerator(T)
{
    void initialize(T initPhase, T frequency, T samplerate)
    {
        T w = frequency * 2 * PI / samplerate;
        _b1 = 2 * cos(w);
        _y1 = sin(initPhase - w);
        _y2 = sin(initPhase - 2 * w);
    }

    T next()
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
    void initialize(size_t largestSize, WaveformType waveform)
    {
        resize(largestSize);
        generate(waveform);  // regenerate tables
    }

    float lookupLinear(uint phaseIntPart, float phaseFractional, int level)
    {
        float* mipmap0 = mipmapData(level);
        size_t mask = sizeOfMipmap(level) - 1;
        float a = mipmap0[ phaseIntPart & mask  ];
        float b = mipmap0[ ( 1 + phaseIntPart ) & mask ];
        return a * (1 - phaseFractional) + phaseFractional * b;
    }

    float lookupCatmullRom(uint phaseIntPart, float phaseFractional, int level)
    {
        float* mipmap0 = mipmapData(level);
        size_t mask = sizeOfMipmap(level) - 1;
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

    float lookupCatmullRomMipmap(uint phaseIntPart, float phaseFractional, float phaseIncrementSamples)
    {

        float level = cast(float)log2(phaseIncrementSamples);
        int level0 = cast(int)floor(level);
        int level1 = level0 + 1;
        level0 = clamp!int(level0, 0, cast(int)_numTables - 1);
        level1 = clamp!int(level1, 0, cast(int)_numTables - 1);

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
    size_t numMipmaps() const
    {
        return _numTables;
    }

    size_t sizeOfMipmap(size_t level) const
    {
        return _largestSize >> level;
    }

    float* mipmapData(size_t level)
    {
        return _mipmapData[level];
    }

private:

    size_t _largestSize;
    size_t _mast;
    size_t _numTables;

    float*[] _mipmapData;
    float[] _wholeBuffer;

    /// Defines the harmonic rolloff, critical to avoid aliasing around the last mipmap
    /// This is very arbitrary and ultimately power of two mipmaps are maybe not sufficient
    /// to have less aliasing.
    double rolloffHarmonic(double normalizedFrequency) // between 0 and 1
    {
        double cosF0 = cos(normalizedFrequency * PI);
        return cosF0 * cosF0;
    }

    void resize(size_t largestSize)
    {
        assert(isPowerOf2(largestSize));

        _largestSize = largestSize;
        // compute size for all mipmaps
        size_t sizeNeeded = 0;
        _numTables = 0;
        int sizeOfTable = largestSize;
        while (sizeOfTable > 0)
        {
            sizeNeeded += sizeOfTable;
            sizeOfTable /= 2;
            _numTables += 1;
        }
            
        _wholeBuffer.length = sizeNeeded;

        // fill table pointers
        {
            _mipmapData.length = _numTables;
            size_t cumulated = 0;
            for (size_t level = 0; level < _numTables; ++level)
            {
                _mipmapData[level] = &_wholeBuffer[cumulated];
                cumulated += _largestSize >> level;
            }
        }
    }

    // fill all table with waveform
    void generate(WaveformType waveform)
    {
        for (size_t level = 0; level < _numTables; ++level)
        {
            size_t size = sizeOfMipmap(level);
            float* data = mipmapData(level);

            for (size_t t = 0; t < size; ++t)
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

                    for (size_t t = 0; t < size; ++t)
                    {
                        double x = sin( cast(double)t * TAU * (h + 1) / cast(double)size ) * amplitude;
                        data[t] += cast(float)x;
                    }
                }
            }

            for (size_t t = 0; t < size; ++t)
            {
                assert(isFinite(data[t]));
            }
        }
    }
}


struct WavetableOsc
{
public:
    void initialize(Wavetable* wavetable, double samplerate)
    {
        _wavetable = wavetable;
        _samplerate = samplerate;
        _phaseIntPart = 0;
        _phaseFractional = 0;
    }

    float next(float frequency)
    {
        float phaseIncrementSamples = cast(float)(2 * _wavetable.sizeOfMipmap(0) * frequency /  (_samplerate));
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

double getWaveHarmonicAmplitude(WaveformType waveform, int n)
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
