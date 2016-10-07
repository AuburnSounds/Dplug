/**
 * Copyright: Copyright Auburn Sounds 2015-2016
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.core.alignedbuffer;

import core.stdc.stdlib: malloc, free, realloc;
import core.stdc.string: memcpy;

import core.exception;


// This module deals with aligned memory


/// Allocates an aligned memory chunk.
/// Functionally equivalent to Visual C++ _aligned_malloc.
/// Do not mix allocations with different alignment.
void* alignedMalloc(size_t size, size_t alignment) nothrow @nogc
{
    // Short-cut and use the C allocator to avoid overhead if no alignment
    if (alignment == 1)
        return malloc(size);

    if (size == 0)
        return null;

    size_t request = requestedSize(size, alignment);
    void* raw = malloc(request);

    if (request > 0 && raw == null) // malloc(0) can validly return anything
        onOutOfMemoryError();

    return storeRawPointerPlusSizeAndReturnAligned(raw, size, alignment);
}

/// Frees aligned memory allocated by alignedMalloc or alignedRealloc.
/// Functionally equivalent to Visual C++ _aligned_free.
/// Do not mix allocations with different alignment.
void alignedFree(void* aligned, size_t alignment) nothrow @nogc
{
    // Short-cut and use the C allocator to avoid overhead if no alignment
    if (alignment == 1)
        return free(aligned);

    // support for free(NULL)
    if (aligned is null)
        return;

    void** rawLocation = cast(void**)(cast(char*)aligned - size_t.sizeof);
    free(*rawLocation);
}

/// Reallocates an aligned memory chunk allocated by alignedMalloc or alignedRealloc.
/// Functionally equivalent to Visual C++ _aligned_realloc.
/// Do not mix allocations with different alignment.
@nogc void* alignedRealloc(void* aligned, size_t size, size_t alignment) nothrow
{
    // Short-cut and use the C allocator to avoid overhead if no alignment
    if (alignment == 1)
        return realloc(aligned, size);

    if (aligned is null)
        return alignedMalloc(size, alignment);

    if (size == 0)
    {
        alignedFree(aligned, alignment);
        return null;
    }

    size_t previousSize = *cast(size_t*)(cast(char*)aligned - size_t.sizeof * 2);


    void* raw = *cast(void**)(cast(char*)aligned - size_t.sizeof);
    size_t request = requestedSize(size, alignment);

    // Heuristic: if new requested size is within 50% to 100% of what is already allocated
    //            then exit with the same pointer
    if ( (previousSize < request * 4) && (request <= previousSize) )
        return aligned;

    void* newRaw = malloc(request);
    static if( __VERSION__ > 2067 ) // onOutOfMemoryError wasn't nothrow before July 2014
    {
        if (request > 0 && newRaw == null) // realloc(0) can validly return anything
            onOutOfMemoryError();
    }

    void* newAligned = storeRawPointerPlusSizeAndReturnAligned(newRaw, request, alignment);
    size_t minSize = size < previousSize ? size : previousSize;
    memcpy(newAligned, aligned, minSize);

    // Free previous data
    alignedFree(aligned, alignment);
    return newAligned;
}

private
{
    /// Returns: next pointer aligned with alignment bytes.
    void* nextAlignedPointer(void* start, size_t alignment) pure nothrow @nogc
    {
        return cast(void*)nextMultipleOf(cast(size_t)(start), alignment);
    }

    // Returns number of bytes to actually allocate when asking
    // for a particular alignement
    @nogc size_t requestedSize(size_t askedSize, size_t alignment) pure nothrow
    {
        enum size_t pointerSize = size_t.sizeof;
        return askedSize + alignment - 1 + pointerSize * 2;
    }

    // Store pointer given my malloc, and size in bytes initially requested (alignedRealloc needs it)
    @nogc void* storeRawPointerPlusSizeAndReturnAligned(void* raw, size_t size, size_t alignment) nothrow
    {
        enum size_t pointerSize = size_t.sizeof;
        char* start = cast(char*)raw + pointerSize * 2;
        void* aligned = nextAlignedPointer(start, alignment);
        void** rawLocation = cast(void**)(cast(char*)aligned - pointerSize);
        *rawLocation = raw;
        size_t* sizeLocation = cast(size_t*)(cast(char*)aligned - 2 * pointerSize);
        *sizeLocation = size;
        return aligned;
    }

    // Returns: x, multiple of powerOfTwo, so that x >= n.
    @nogc size_t nextMultipleOf(size_t n, size_t powerOfTwo) pure nothrow
    {
        // check power-of-two
        assert( (powerOfTwo != 0) && ((powerOfTwo & (powerOfTwo - 1)) == 0));

        size_t mask = ~(powerOfTwo - 1);
        return (n + powerOfTwo - 1) & mask;
    }
}

unittest
{
    assert(nextMultipleOf(0, 4) == 0);
    assert(nextMultipleOf(1, 4) == 4);
    assert(nextMultipleOf(2, 4) == 4);
    assert(nextMultipleOf(3, 4) == 4);
    assert(nextMultipleOf(4, 4) == 4);
    assert(nextMultipleOf(5, 4) == 8);

    {
        void* p = alignedMalloc(23, 16);
        assert(p !is null);
        assert(((cast(size_t)p) & 0xf) == 0);

        alignedFree(p, 16);
    }

    assert(alignedMalloc(0, 16) == null);
    alignedFree(null, 16);

    {
        int alignment = 16;
        int* p = null;

        // check if growing keep values in place
        foreach(int i; 0..100)
        {
            p = cast(int*) alignedRealloc(p, (i + 1) * int.sizeof, alignment);
            p[i] = i;
        }

        foreach(int i; 0..100)
            assert(p[i] == i);


        p = cast(int*) alignedRealloc(p, 0, alignment);
        assert(p is null);
    }
}



/// Use throughout dplug:dsp to avoid reliance on GC.
/// This works like alignedRealloc except with slices as input.
/// You MUST use consistent alignement thoughout the lifetime of this buffer.
///
/// Params:
///    buffer Existing allocated buffer. Can be null. Input slice length is not considered.
///    length desired slice length
///
void reallocBuffer(T)(ref T[] buffer, size_t length, int alignment = 1) nothrow @nogc
{
    T* pointer = cast(T*) alignedRealloc(buffer.ptr, T.sizeof * length, alignment);
    if (pointer is null)
        buffer = null;
    else
        buffer = pointer[0..length];
}


/// Returns: A newly created AlignedBuffer.
AlignedBuffer!T alignedBuffer(T)(size_t initialSize = 0, int alignment = 1) nothrow @nogc
{
    return AlignedBuffer!T(initialSize, alignment);
}

/// Growable array, points to a memory aligned location.
/// Bugs: make this class disappear when std.allocator is out.
struct AlignedBuffer(T)
{
    public
    {
        /// Creates an aligned buffer with given initial size.
        this(size_t initialSize, int alignment) nothrow @nogc
        {
            assert(alignment != 0);
            _size = 0;
            _allocated = 0;
            _data = null;
            _alignment = alignment;
            resize(initialSize);
        }

        ~this() nothrow @nogc
        {
            if (_data !is null)
            {
                alignedFree(_data, _alignment);
                _data = null;
                _allocated = 0;
            }
        }

        @disable this(this);

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

        /// Finds an item, returns -1 if not found
        int indexOf(T x) nothrow @nogc
        {
            foreach(int i; 0..cast(int)_size)
                if (_data[i] is x)
                    return i;
            return -1;
        }

        /// Removes an item and replaces it by the last item.
        /// Warning: this reorders the array.
        void removeAndReplaceByLastElement(size_t index) nothrow @nogc
        {
            assert(index < _size);
            _data[index] = _data[--_size];
        }

        /// Appends another buffer to this buffer.
        void pushBack(ref AlignedBuffer other) nothrow @nogc
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

        /// Returns: Raw pointer to data.
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
    import std.algorithm.comparison;
    int NBUF = 200;

    Xorshift32 rng;
    rng.seed(0xBAADC0DE);

    struct box2i { int a, b, c, d; }
    AlignedBuffer!box2i[] boxes;
    boxes.length = NBUF;

    foreach(i; 0..NBUF)
    {
        boxes[i] = alignedBuffer!box2i();
    }

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
        auto buf = alignedBuffer!int;
        enum N = 10;
        buf.resize(N);
        foreach(i ; 0..N)
            buf[i] = i;

        foreach(i ; 0..N)
            assert(buf[i] == i);
    }
}
