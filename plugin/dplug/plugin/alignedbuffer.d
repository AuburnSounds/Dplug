module dplug.plugin.alignedbuffer;

import std.c.string;

import gfm.core.memory;

/// Growable array, points to a memory aligned location.
/// Bugs: make this class disappear when std.allocator is out.
final class AlignedBuffer(T)
{
    public
    {
        /// Creates an empty aligned buffer.
        this(int alignment = 64) nothrow @nogc
        {
            _size = 0;
            _allocated = 0;
            _data = null;
            _alignment = alignment;
        }

        /// Creates an aligned buffer with given size.
        this(size_t initialSize) nothrow @nogc
        {
            this();
            resize(initialSize);
        }

        /// Creates an aligned buffer by copy.
        this(AlignedBuffer other) nothrow @nogc
        {
            this();
            resize(other.length());
            memcpy(_data, other._data, _size * T.sizeof);
        }

        ~this() nothrow @nogc
        {
            close();
        }

        void close() nothrow @nogc
        {
            if (_data !is null)
            {
                alignedFree(_data);
                _data = null;
                _allocated = 0;
            }
        }

        /// Returns: Length of buffer in elements.
        size_t length() pure const nothrow @nogc
        {
            return _size;
        }

        /// Resizes a buffer to hold $(D askedSize) elements.
        void resize(size_t askedSize) nothrow @nogc
        {
            // grow only
            if (_allocated < askedSize)
            {
                size_t numBytes = askedSize * T.sizeof;
                _data = cast(T*)(alignedRealloc(_data, numBytes, _alignment));
                _allocated = askedSize;
            }
            _size = askedSize;
        }

        /// Append an element to this buffer.
        void pushBack(T x) nothrow @nogc
        {
            size_t i = _size;
            resize(_size + 1);
            _data[i] = x;
        }

        /// Appends another buffer to this buffer.
        void pushBack(AlignedBuffer other) nothrow @nogc
        {
            size_t oldSize = _size;
            resize(_size + other._size);
            memcpy(_data + oldSize, other._data, T.sizeof * other._size);
        }

        /// Retuns: Raw pointer to data.
        @property inout(T)* ptr() inout nothrow @nogc
        {
            return _data;
        }

        T opIndex(size_t i) pure nothrow @nogc
        {
            return _data[i];
        }

        T opIndexAssign(T x, size_t i) nothrow @nogc
        {
            return _data[i] = x;
        }

        void clear() nothrow @nogc
        {
            _size = 0;
        }

        /// Fills the buffer with the same value.
        void fill(T x) nothrow @nogc
        {
            _data[0.._size] = x;
        }
    }

    private
    {
        size_t _size;
        T* _data;
        size_t _allocated;
        size_t _alignment;
    }
}

unittest
{
    auto buf = new AlignedBuffer!int;
    enum N = 10;
    buf.resize(N);
    foreach(i ; 0..N)
        buf[i] = i;

    foreach(i ; 0..N)
        assert(buf[i] == i);
}
