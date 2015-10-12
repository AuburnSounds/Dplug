module dplug.core.ringbuf;

import dplug.core.funcs;

import std.range;

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