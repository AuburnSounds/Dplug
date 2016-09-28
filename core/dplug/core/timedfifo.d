/**
* Copyright: Copyright Auburn Sounds 2016
* License:   All Rights Reserved.
* Authors:   Guillaume Piolat
*/
module dplug.core.timedfifo;

import core.atomic;

import dplug.core.unchecked_sync;
import dplug.core.funcs;

/// Reusable mechanism to provide the UI with continuously available non-critical data from the audio thread.
/// eg: for waveforms, analyzers, displays, etc...
/// In the case where the FIFO is empty, it may be that there is nothing to draw or audio processing has stopped.
/// And because audio buffers may be long, we can't just use atomics and avoid updating the UI when the buffer has already been processed.
/// It would cause slowness with small buffers.
struct TimedFIFO(T)
{
private:

    T[] _data;
    int _count;
    int _readIndex;
    int _inputTimestamp;

    // Note: information about sample-rate is passed through atomics, out-of-band
    shared(float) _sampleRate = 44100.0f;

    int _indexMask;
    int _dividerMask;
    float _invDivider;

    // protects: _readIndex, _count, _data
    UncheckedMutex _dataMutex;

    float _timeDebt;
    float _integerDebt; // because of rounding

public:

    /// Params:
    ///     size = size of the buffer
    ///     divider = only one in divider sample(s) is actually pushed in the FIFO.
    void initialize(int size, int divider = 1)
    {
        assert(isPowerOf2(size));
        assert(isPowerOf2(divider));

        _count = 0; // no data at start
        _readIndex = 0; 
        _indexMask = size - 1;
        _inputTimestamp = 0;
        _dividerMask = divider - 1;
        _invDivider = 1.0f / divider;

        _data.reallocBuffer(size);
        _dataMutex = uncheckedMutex();

        _timeDebt = 0;
        _integerDebt = 0;

    }

    ~this()
    {
        _data.reallocBuffer(0);
    }

    void pushData(T[] input, float sampleRate) nothrow @nogc
    {
        // Here we are in the audio thread, so blocking is not welcome
        atomicStore(_sampleRate, sampleRate);

        // push new data, but it's not that bad if we miss some
        if (_dataMutex.tryLock())
        {
            foreach (i; 0..input.length)
            {
                _inputTimestamp++;
                if ( (_inputTimestamp & _dividerMask) == 0 ) // should depend on samplerate?
                {
                    _data[ (_readIndex + _count) & _indexMask ] = input[i];
                    if (_count >= _data.length)
                        ++_readIndex; // overflow, drop older data
                    else
                        ++_count; // grow buffer
                }
            }
            _dataMutex.unlock();
        }
    }

    /// Same but with 1 element.
    void pushData(T input, float sampleRate) nothrow @nogc
    {
        pushData( (&input)[0..1], sampleRate);
    }

    // Get some amount of oldest samples in the FIFO
    // The drop some amount of samples that correspond to time passing of dt
    // Returns: the number of sample data returned. Also return no data if tryLock failed to take the lock.
    // Note that there is a disconnect between the data that is dropped, and the data that is returned.
    // The same data may well be returned multiple time given a large buffer, or zero time.
    int readOldestDataAndDropSome(T[] output, double dt, int keepAtLeast = 0) nothrow @nogc
    {        
        assert(dt >= 0);
        _timeDebt += dt * 1.01; // add 1% because it's better to be a bit short in buffer than too large.
        if (_dataMutex.tryLock())
        {
            scope(exit) _dataMutex.unlock();

            int pointsNeeded = cast(int)(output.length);
            int pointsAvailable = min(_count, pointsNeeded);

            bool noData = (pointsAvailable == 0);

            if (noData)
                return 0;

            foreach (i ; 0..pointsAvailable)
            {
                output[i] = _data[ (_readIndex + i) & _indexMask ];
            }

            // drop samples
            float sampleRate = atomicLoad(_sampleRate);

            float samplesToDrop = _timeDebt * sampleRate * _invDivider + _integerDebt;
            int maxDroppable = _count - keepAtLeast;
            if (samplesToDrop > maxDroppable)
                samplesToDrop = maxDroppable;
            if (samplesToDrop < 0)
                samplesToDrop = 0;

            int numSamplesToDrop = cast(int)(samplesToDrop);
            _timeDebt = 0;
            _integerDebt = (samplesToDrop - numSamplesToDrop);

            _count -= numSamplesToDrop;
            _readIndex += numSamplesToDrop;
            return pointsAvailable;
        } 
        else
            return 0;
    }

    // Same but with one element
    bool readOldestDataAndDropSome(T* output, double dt) nothrow @nogc
    {
        return readOldestDataAndDropSome(output[0..1], dt) != 0;
    }
}