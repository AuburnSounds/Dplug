// See licenses/UNLICENSE.txt
module dplug.dsp.fft;

import core.stdc.string;

public import std.complex;
import std.math;

import gfm.math.funcs;

import dplug.dsp.funcs,
       dplug.dsp.window;


enum FFTDirection
{
    FORWARD = 0,
    REVERSE = 1
}
    
/// Perform in-place FFT.
void FFT(T)(Complex!T[] buffer, FFTDirection direction)
{
    size_t size = buffer.length;
    assert(isPowerOf2(size));
    int m = iFloorLog2(size);

    // do the bit reversal
    int i2 = size / 2;
    int j = 0;
    for (int i = 0; i < size - 1; ++i)
    {
        if (i < j)
        {
            auto tmp = buffer[i];
            buffer[i] = buffer[j];
            buffer[j] = tmp;
        }

        int k = i2;
        while(k <= j)
        {
            j = j - k;
            k = k / 2;
        }
        j += k;
    }

    // compute the FFT
    Complex!T c = Complex!T(-1);
    int l2 = 1;
    for (int l = 0; l < m; ++l)
    {
        int l1 = l2;
        l2 = l2 * 2;
        Complex!T u = 1;
        for (int j2 = 0; j2 < l1; ++j2)
        {
            int i = j2;
            while (i < size)
            {
                int i1 = i + l1;
                Complex!T t1 = u * buffer[i1];
                buffer[i1] = buffer[i] - t1;
                buffer[i] += t1;
                i += l2;
            }
            u = u * c;
        }

        T newImag = sqrt((1 - c.re) / 2);
        if (direction == FFTDirection.FORWARD)
            newImag = -newImag;
        T newReal = sqrt((1 + c.re) / 2);
        c = Complex!T(newReal, newImag);
    }

    // scaling for forward transformation
    if (direction == FFTDirection.FORWARD)
    {
        for (int i = 0; i < size; ++i)
            buffer[i] = buffer[i] / Complex!T(cast(T)size, 0);
    }
}

/// From a signal, output short term FFT data.
/// Variable overlap.
/// Introduces approximately windowSize/2 samples delay.
struct FFTAnalyzer
{
    /// Initialize the FFTAnalyzer
    
    size_t windowSize() const
    {
        return _windowSize;
    }

    size_t analysisPeriod() const
    {
        return _analysisPeriod;
    }

    /// To call at initialization and whenever samplerate changes.
    /// windowSize = size of analysis window, expressed in samples
    /// fftSize = size of FFT. Must be power-of-two and >= windowSize. Missing samples are zero-padded in time domain.
    /// analysisPeriod = period of analysis results, allow to be more precise frequentially, expressed in samples
    /// Basic overlap is achieved with windowSize = 2 * analysisPeriod
    /// if zeroPhaseWindowing = true, "zero phase" windowing is used
    /// (center of window is at first sample, zero-padding happen at center)
    void init(size_t windowSize, size_t fftSize, size_t analysisPeriod, WindowType windowType, bool zeroPhaseWindowing, bool correctWindowLoss)
    {
        _windowType = windowType;
        _zeroPhaseWindowing = zeroPhaseWindowing;
        _correctWindowLoss = correctWindowLoss;

        assert(isPowerOf2(fftSize));
        assert(fftSize >= windowSize);

        assert(windowSize != 1);
        assert(analysisPeriod <= windowSize); // no support for zero overlap

        // 1-sized FFT support
        if (analysisPeriod == 0)
            analysisPeriod = 1;

        _windowSize = windowSize;
        _fftSize = fftSize;
        _analysisPeriod = analysisPeriod;

        // clear input delay
        _audioBuffer.length = _windowSize;
        _index = 0;

        _windowBuffer.length = _windowSize;
        generateWindow(_windowType, _windowBuffer[]);

        _windowGainCorrFactor = 0;
        for (size_t i = 0; i < _windowSize; ++i)
            _windowGainCorrFactor += _windowBuffer[i];
        _windowGainCorrFactor = _windowSize / _windowGainCorrFactor;

        if (_correctWindowLoss)
        {
            for (size_t i = 0; i < _windowSize; ++i)
                _windowBuffer[i] *= _windowGainCorrFactor;
        }

    }

    // Process one sample, eventually return the result of short-term FFT
    // in a given Buffer
    bool feed(float x, Complex!float[] fftData)
    {
        _audioBuffer[_index] = x;
        _index = _index + 1;
        if (_index >= _windowSize)
        {
            fftData.length = _fftSize;

            if (_zeroPhaseWindowing)
            {
                // "Zero Phase" windowing
                // Through clever reordering, phase of ouput coefficients will relate to the
                // center of the window
                //_
                // \_                   _/
                //   \                 /
                //    \               /
                //     \_____________/____
                size_t center = (_windowSize - 1) / 2; // position of center bin
                size_t nLeft = _windowSize - center;
                for (size_t i = 0; i < nLeft; ++i)
                    fftData[i] = _audioBuffer[center + i] * _windowBuffer[center + i];

                size_t nPadding = _fftSize - _windowSize;
                for (size_t i = 0; i < nPadding; ++i)
                    fftData[nLeft + i] = 0.0f;

                for (size_t i = 0; i < center; ++i)
                    fftData[nLeft + nPadding + i] = _audioBuffer[i] * _windowBuffer[i];
            }
            else
            {
                // "Normal" windowing
                // Phase of ouput coefficient will relate to the start of the buffer
                //      _
                //    _/ \_
                //   /     \
                //  /       \
                //_/         \____________

                // fill FFT buffer and multiply by window
                for (size_t i = 0; i < _windowSize; ++i)
                    fftData[i] = _audioBuffer[i] * _windowBuffer[i];

                // zero-padding
                for (size_t i = _windowSize; i < _fftSize; ++i)
                    fftData[i] = 0.0f;
            }

            // perform forward FFT on this slice
            FFT!float(fftData[0.._fftSize], FFTDirection.FORWARD);

            // rotate buffer
            {
                size_t samplesToDrop = _analysisPeriod;
                assert(0 < samplesToDrop && samplesToDrop <= _windowSize);
                size_t remainingSamples = _windowSize - samplesToDrop;

                // TODO: use ring buffer instead of copy
                memmove(_audioBuffer.ptr, _audioBuffer.ptr + samplesToDrop, float.sizeof * remainingSamples);
                _index = remainingSamples;

            }
            return true;
        }
        else
        {
            return false;
        }
    }

private:
    float[] _audioBuffer;
    float[] _windowBuffer;

    size_t _fftSize;        // in samples
    size_t _windowSize;     // in samples
    size_t _analysisPeriod; // in samples

    WindowType _windowType;
    bool _zeroPhaseWindowing;

    size_t _index;

    // should we multiply by _windowGainCorrFactor?
    bool _correctWindowLoss;
    // the factor by which to multiply transformed data to get in range results
    float _windowGainCorrFactor; 
}
