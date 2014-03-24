module dplug.dsp.delayline;

import gfm.math.funcs;

import dplug.dsp.funcs;

/// Allow to sample signal back in time.
struct Delayline(T)
{
public:
    
    /// Initialize the delay line. Can delay up to count samples.
    void intialize(int count)
    {
        _index = _indexMask;
        resize(count);
    }

    /// Resize the delay line. Can delay up to count samples.
    void resize(int count)
    {
        if (count <= 0)
            assert(false);

        int toAllocate = nextPowerOf2(count);
        _data.length = toAllocate;
        _indexMask = toAllocate - 1;
    }

    void feed(T x)
    {
        _index = (_index + 1) & _indexMask;
        _data[_index] = x;
    }

    /// Samples the delay-line at integer points.
    /// Delay 0 = last entered sample with feed().
    T sampleFull(int delay)
    {
        assert(delay >= 0);
        return _data[(_index - delay) & _indexMask];
    }

    /// Samples the delay-line with linear interpolation.
    T sampleLinear(float delay)
    {
        assert(delay > 0);
        float sampleLoc = (_index - delay) + 2 * _data.length;
        assert(sampleLoc >= 1);
        int iPart = cast(int)(sampleLoc);
        float fPart = cast(float)(sampleLoc - iPart);
        T x0  = _data[iPart       & _indexMask];
        T x1  = _data[(iPart + 1) & _indexMask];
        return lerp(x0, x1, fPart);
    }

    /// Samples the delay-line with a 3rd order polynomial.
    T sampleHermite(float delay)
    {
        assert(delay > 1);
        float sampleLoc = (_index - delay) + 2 * _data.length;
        assert(sampleLoc >= 1);
        int iPart = cast(int)(sampleLoc);
        float fPart = cast(float)(sampleLoc - iPart);
        assert(fPart >= 0.0f);
        assert(fPart <= 1.0f);
        T xm1 = _data[(iPart - 1) & _indexMask];
        T x0  = _data[ iPart      & _indexMask];
        T x1  = _data[(iPart + 1) & _indexMask];
        T x2  = _data[(iPart + 2) & _indexMask];
        return hermite!float(fPart, xm1, x0, x1, x2);
    }
    
private:
    T[] _data;
    int _index;
    int _indexMask;
}