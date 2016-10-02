/**
* Copyright: Copyright Auburn Sounds 2015-2016
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.core.ringbuf;

import core.atomic;

import dplug.core.unchecked_sync;
import dplug.core.funcs;


RingBufferNoGC!T ringBufferNoGC(T)(size_t initialCapacity) nothrow @nogc
{
    return RingBufferNoGC!T(initialCapacity);
}

/// @nogc ring-buffer
struct RingBufferNoGC(T)
{
    public
    {
        /// Create a RingBuffer with specified initial capacity.
        this(size_t initialCapacity) nothrow @nogc
        {
            _data.reallocBuffer(initialCapacity);
            clear();
        }

        @disable this(this);

        ~this() nothrow @nogc
        {
            _data.reallocBuffer(0);
        }

        bool isFull() pure const nothrow
        {
            return _count == _data.length;
        }

        /// Adds an item on the back of the queue.
        void pushBack(T x) nothrow @nogc
        {
            checkOverflow!popFront();
           _data.ptr[(_first + _count) % _data.length] = x;
            ++_count;
        }

        /// Adds an item on the front of the queue.
        void pushFront(T x) nothrow @nogc
        {
            checkOverflow!popBack();
            ++_count;
            _first = (_first - 1 + _data.length) % _data.length;
            _data.ptr[_first] = x;
        }

        /// Removes an item from the front of the queue.
        /// Returns: the removed item.
        T popFront() nothrow @nogc
        {
            T res = _data.ptr[_first];
            _first = (_first + 1) % _data.length;
            --_count;
            return res;
        }

        /// Removes an item from the back of the queue.
        /// Returns: the removed item.
        T popBack() nothrow @nogc
        {
            --_count;
            return _data.ptr[(_first + _count) % _data.length];
        }

        /// Removes all items from the queue.
        void clear() nothrow @nogc
        {
            _first = 0;
            _count = 0;
        }

        /// Returns: number of items in the queue.
        size_t length() pure const nothrow @nogc
        {
            return _count;
        }

        /// Returns: maximum number of items in the queue.
        size_t capacity() pure const nothrow @nogc
        {
            return _data.length;
        }

        /// Returns: item at the front of the queue.
        T front() pure nothrow @nogc
        {
            return _data.ptr[_first];
        }

        /// Returns: item on the back of the queue.
        T back() pure nothrow @nogc
        {
            return _data.ptr[(_first + _count + _data.length - 1) % _data.length];
        }

        /// Returns: item index from the queue.
        T opIndex(size_t index) nothrow @nogc
        {
            // crash if index out-of-bounds (not recoverable)
            if (index > _count)
                assert(0);

            return _data.ptr[(_first + index) % _data.length];
        }
    }

    private
    {
        // element lie from _first to _first + _count - 1 index, modulo the allocated size
        T[] _data;
        size_t _first;
        size_t _count;

        void checkOverflow(alias popMethod)() nothrow
        {
            if (isFull())
                popMethod();
        }
    }
}


unittest
{
    RingBufferNoGC!float a;
}

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

    /// Returns: true of i is a power of 2.
    static bool isPowerOf2(int i) @nogc nothrow
    {
        assert(i >= 0);
        return (i != 0) && ((i & (i - 1)) == 0);
    }

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
        _dataMutex.destroy();
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

            int pointsAvailable = ( (_count < pointsNeeded) ? _count : pointsNeeded);

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


unittest
{
    TimedFIFO!float a;
}