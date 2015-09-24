/**
 * Copyright: Copyright Auburn Sounds 2015 and later.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.core.alignedbuffer;

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

        ~this()
        {
            if (_data !is null)
            {
                debug ensureNotInGC("AlignedBuffer");
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

        /// Returns: Length of buffer in elements.
        alias opDollar = length;

        /// Resizes a buffer to hold $(D askedSize) elements.
        void resize(size_t askedSize) nothrow @nogc
        {
            // grow only
            if (_allocated < askedSize)
            {
                size_t numBytes = askedSize * 2 * T.sizeof; // gives 2x what is asked to make room for growth

                _data = cast(T*)(alignedRealloc(_data, numBytes, _alignment));

                _allocated = askedSize * 2;
            }
            _size = askedSize;
        }

        /// Pop last element
        T popBack() nothrow @nogc
        {
            assert(_size > 0);
            _size = _size - 1;
            return _data[_size];
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

          /// Appends a slice to this buffer.
        void pushBack(T[] slice) nothrow @nogc
        {
            foreach(item; slice)
            {
                pushBack(item);
            }
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

        deprecated alias clear = clearContents;

        /// Sets size to zero.
        void clearContents() nothrow @nogc
        {
            _size = 0;
        }

        /// Returns: Whole content of the array in one slice.
        inout(T)[] opSlice() inout nothrow @nogc
        {
            return opSlice(0, length());
        }

        /// Returns: A slice of the array.
        inout(T)[] opSlice(size_t i1, size_t i2) inout nothrow @nogc
        {
            return _data[i1 .. i2];
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
    import std.random;
    import std.algorithm;
    int NBUF = 200;

    Xorshift32 rng;
    rng.seed(0xBAADC0DE);
    
    struct box2i { int a, b, c, d; }
    AlignedBuffer!box2i[] boxes;

    foreach(i; 0..NBUF)
        boxes ~= new AlignedBuffer!box2i();

    foreach(j; 0..200)
    {
        foreach(i; 0..NBUF)
        {
            int previousSize = cast(int)(boxes[i].length);
            void* previousPtr = boxes[i].ptr;
            foreach(int k; 0..cast(int)(boxes[i].length))
                boxes[i][k] = box2i(k, k, k, k);

            int newSize = uniform(0, 100, rng);
            boxes[i].resize(newSize);

            int minSize = min(previousSize, boxes[i].length);
            void* newPtr = boxes[i].ptr;
            foreach(int k; 0..minSize)
            {
                box2i item = boxes[i][k];
                box2i shouldBe = box2i(k, k, k, k);
                assert(item == shouldBe);
            }

            int sum = 0;
            foreach(k; 0..newSize)
            {
                box2i bb = boxes[i][k];
                sum += bb.a + bb.b + bb.c + bb.d;
            }
        }
    }

    foreach(i; 0..NBUF)
        boxes[i].destroy();

    {
        auto buf = new AlignedBuffer!int;
        scope(exit) buf.destroy();
        enum N = 10;
        buf.resize(N);
        foreach(i ; 0..N)
            buf[i] = i;

        foreach(i ; 0..N)
            assert(buf[i] == i);
    }
}
