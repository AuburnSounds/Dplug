/**
 * Defines `Vec`, `reallocBuffer` and memory functions.
 *
 * Copyright: Copyright Auburn Sounds 2015-2016
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.core.alignedbuffer;

import std.traits: hasElaborateDestructor;

import core.stdc.stdlib: malloc, free, realloc;
import core.stdc.string: memcpy;

import core.exception;


// This module deals with aligned memory.
// You'll also find here a non-copyable std::vector equivalent `Vec`.

/// Allocates an aligned memory chunk.
/// Functionally equivalent to Visual C++ _aligned_malloc.
/// Do not mix allocations with different alignment.
/// Important: `alignedMalloc(0)` does not necessarily return `null`, and its result 
///            _has_ to be freed with `alignedFree`.
void* alignedMalloc(size_t size, size_t alignment) nothrow @nogc
{
    assert(alignment != 0);

    // Short-cut and use the C allocator to avoid overhead if no alignment
    if (alignment == 1)
    {
        // C99:
        // Implementation-defined behavior
        // Whether the calloc, malloc, and realloc functions return a null pointer
        // or a pointer to an allocated object when the size requested is zero.
        // In any case, we'll have to free() it.
        return malloc(size);
    }

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
    assert(alignment != 0);
    assert(isPointerAligned(aligned, alignment));

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
/// Important: `alignedRealloc(p, 0)` does not necessarily return `null`, and its result 
///            _has_ to be freed with `alignedFree`.
@nogc void* alignedRealloc(void* aligned, size_t size, size_t alignment) nothrow
{
    assert(isPointerAligned(aligned, alignment));

    // If you fail here, it can mean you've used an uninitialized AlignedBuffer.
    assert(alignment != 0);

    // Short-cut and use the C allocator to avoid overhead if no alignment
    if (alignment == 1)
    {
        // C99:
        // Implementation-defined behavior
        // Whether the calloc, malloc, and realloc functions return a null pointer
        // or a pointer to an allocated object when the size requested is zero.
        // In any case, we'll have to `free()` it.
        return realloc(aligned, size);
    }

    if (aligned is null)
        return alignedMalloc(size, alignment);

    size_t previousSize = *cast(size_t*)(cast(char*)aligned - size_t.sizeof * 2);

    void* raw = *cast(void**)(cast(char*)aligned - size_t.sizeof);
    size_t request = requestedSize(size, alignment);

    // Heuristic: if a requested size is within 50% to 100% of what is already allocated
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
    assert(isPointerAligned(newAligned, alignment));
    return newAligned;
}

/// Returns: `true` if the pointer is suitably aligned.
bool isPointerAligned(void* p, size_t alignment) pure nothrow @nogc
{
    assert(alignment != 0);
    return ( cast(size_t)p & (alignment - 1) ) == 0;
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
        assert( isPointerAligned(aligned, alignment) );
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

    void* nullAlloc = alignedMalloc(0, 16);
    assert(nullAlloc != null);
    nullAlloc = alignedRealloc(nullAlloc, 0, 16);
    assert(nullAlloc != null);
    alignedFree(nullAlloc, 16);

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
        assert(p !is null);

        alignedFree(p, alignment);
    }
}



/// Use throughout dplug:dsp to avoid reliance on GC.
/// Important: Size 0 is special-case to free the slice.
/// This works a bit like alignedRealloc except with slices as input.
/// You MUST use consistent alignement thoughout the lifetime of this buffer.
///
/// Params:
///    buffer = Existing allocated buffer. Can be null. 
///             Input slice length is not considered.
///    length = Desired slice length.
///    alignment = Alignement if the slice has allocation requirements, 1 else. 
///                Must match for deallocation.
///
void reallocBuffer(T)(ref T[] buffer, size_t length, int alignment = 1) nothrow @nogc
{
    static if (is(T == struct) && hasElaborateDestructor!T)
    {
        static assert(false); // struct with destructors not supported
    }

    /// Size 0 is special-case to free the slice.
    if (length == 0)
    {
        alignedFree(buffer.ptr, alignment);
        buffer = null;
        return;
    }

    T* pointer = cast(T*) alignedRealloc(buffer.ptr, T.sizeof * length, alignment);
    if (pointer is null)
        buffer = null; // alignement 1 can still return null
    else
        buffer = pointer[0..length];
}


// Note: strangely enough, deprecated alias didn't work for this.
deprecated("Use makeVec!T instead.")
AlignedBuffer!T makeAlignedBuffer(T)(size_t initialSize = 0, int alignment = 1) nothrow @nogc
{
    return AlignedBuffer!T(initialSize, alignment);
}

/// Returns: A newly created `Vec`.
Vec!T makeVec(T)(size_t initialSize = 0, int alignment = 1) nothrow @nogc
{
    return Vec!T(initialSize, alignment);
}

/// Growable array, points to a (optionally aligned) memory location.
/// This can also work as an output range.
/// Bugs: make this class disappear when std.allocator is out.
// Note: strangely enough, deprecated alias didn't work for this.
deprecated("Use Vec!T instead.")
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
            if (_allocated != 0)
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
            if (askedSize > 0 &&_allocated < askedSize)
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

        // Output range support
        alias put = pushBack;

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

        inout(T) opIndex(size_t i) pure nothrow inout @nogc
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

        /// Move. Give up owner ship of the data.
        T[] releaseData() nothrow @nogc
        {
            T[] data = _data[0.._size];
            assert(_alignment == 1); // else would need to be freed with alignedFree.
            this._data = null;
            this._size = 0;
            this._allocated = 0;
            this._alignment = 0;
            return data;
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

struct Vec(T)
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

        // Output range support
        alias put = pushBack;

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
        void pushBack(ref Vec other) nothrow @nogc
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

        inout(T) opIndex(size_t i) pure nothrow inout @nogc
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

        /// Move. Give up owner ship of the data.
        T[] releaseData() nothrow @nogc
        {
            T[] data = _data[0.._size];
            assert(_alignment == 1); // else would need to be freed with alignedFree.
            this._data = null;
            this._size = 0;
            this._allocated = 0;
            this._alignment = 0;
            return data;
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
    import std.range.primitives;
    static assert(isOutputRange!(Vec!ubyte, ubyte));


    import std.random;
    import std.algorithm.comparison;
    int NBUF = 200;

    Xorshift32 rng;
    rng.seed(0xBAADC0DE);

    struct box2i { int a, b, c, d; }
    Vec!box2i[] boxes;
    boxes.length = NBUF;

    foreach(i; 0..NBUF)
    {
        boxes[i] = makeVec!box2i();
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
        auto buf = makeVec!int;
        enum N = 10;
        buf.resize(N);
        foreach(i ; 0..N)
            buf[i] = i;

        foreach(i ; 0..N)
            assert(buf[i] == i);
    }
}
