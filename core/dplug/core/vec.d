/**
Defines `Vec`, `reallocBuffer` and memory functions.

Copyright: Guillaume Piolat 2015-2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Guillaume Piolat
*/
module dplug.core.vec;

import std.traits: hasElaborateDestructor;

import core.stdc.stdlib: malloc, free, realloc;
import core.stdc.string: memcpy, memmove;

import core.exception;
import inteli.xmmintrin;


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
    // Short-cut and use the C allocator to avoid overhead if no alignment
    if (alignment == 1)
        return free(aligned);

    // support for free(NULL)
    if (aligned is null)
        return;

    assert(alignment != 0);
    assert(isPointerAligned(aligned, alignment));

    void** rawLocation = cast(void**)(cast(char*)aligned - size_t.sizeof);
    free(*rawLocation);
}

/// Reallocates an aligned memory chunk allocated by `alignedMalloc` or `alignedRealloc`.
/// Functionally equivalent to Visual C++ `_aligned_realloc`.
/// Do not mix allocations with different alignment.
/// Important: `alignedRealloc(p, 0)` does not necessarily return `null`, and its result 
///            _has_ to be freed with `alignedFree`.
void* alignedRealloc(void* aligned, size_t size, size_t alignment) nothrow @nogc
{
    return alignedReallocImpl!true(aligned, size, alignment);
}


/// Same as `alignedRealloc` but does not preserve data.
void* alignedReallocDiscard(void* aligned, size_t size, size_t alignment) nothrow @nogc
{
    return alignedReallocImpl!false(aligned, size, alignment);
}


/// Returns: `true` if the pointer is suitably aligned.
bool isPointerAligned(void* p, size_t alignment) pure nothrow @nogc
{
    assert(alignment != 0);
    return ( cast(size_t)p & (alignment - 1) ) == 0;
}
unittest
{
    ubyte b;
    align(16) ubyte[5] c;
    assert(isPointerAligned(&b, 1));
    assert(!isPointerAligned(&c[1], 2));
    assert(isPointerAligned(&c[4], 4));
}

/// Does memory slices a[0..a_size] and b[0..b_size] have an overlapping byte?
bool isMemoryOverlapping(const(void)* a, ptrdiff_t a_size, 
                         const(void)* b, ptrdiff_t b_size) pure @trusted
{
    assert(a_size >= 0 && b_size >= 0);

    if (a is null || b is null)
        return false;

    if (a_size == 0 || b_size == 0)
        return false;

    ubyte* lA = cast(ubyte*)a;
    ubyte* hA = lA + a_size;
    ubyte* lB = cast(ubyte*)b;
    ubyte* hB = lB + b_size;

    // There is overlapping, if lA is inside lB..hB, or lB is inside lA..hA

    if (lA >= lB && lA < hB)
        return true;

    if (lB >= lA && lB < hA)
        return true;

    return false;
}
bool isMemoryOverlapping(const(void)[] a, const(void)[] b) pure @trusted
{
    return isMemoryOverlapping(a.ptr, a.length, b.ptr, b.length);
}
unittest
{
    ubyte[100] a;
    assert(!isMemoryOverlapping(null, a));
    assert(!isMemoryOverlapping(a, null));
    assert(!isMemoryOverlapping(a[1..1], a[0..10]));
    assert(!isMemoryOverlapping(a[1..10], a[10..100]));
    assert(!isMemoryOverlapping(a[30..100], a[0..30]));
    assert(isMemoryOverlapping(a[1..50], a[49..100]));
    assert(isMemoryOverlapping(a[49..100], a[1..50]));
    assert(isMemoryOverlapping(a[40..45], a[30..55]));
    assert(isMemoryOverlapping(a[30..55], a[40..45]));
}

private nothrow @nogc
{
    void* alignedReallocImpl(bool PreserveDataIfResized)(void* aligned, size_t size, size_t alignment)
    {
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

        assert(alignment != 0);
        assert(isPointerAligned(aligned, alignment));

        size_t previousSize = *cast(size_t*)(cast(char*)aligned - size_t.sizeof * 2);

        void* raw = *cast(void**)(cast(char*)aligned - size_t.sizeof);
        size_t request = requestedSize(size, alignment);
        size_t previousRequest = requestedSize(previousSize, alignment);
        assert(previousRequest - request == previousSize - size); // same alignment

        // Heuristic: if a requested size is within 50% to 100% of what is already allocated
        //            then exit with the same pointer
        if ( (previousRequest < request * 4) && (request <= previousRequest) )
            return aligned;

        void* newRaw = malloc(request);
        static if( __VERSION__ > 2067 ) // onOutOfMemoryError wasn't nothrow before July 2014
        {
            if (request > 0 && newRaw == null) // realloc(0) can validly return anything
                onOutOfMemoryError();
        }

        void* newAligned = storeRawPointerPlusSizeAndReturnAligned(newRaw, size, alignment);

        static if (PreserveDataIfResized)
        {
            size_t minSize = size < previousSize ? size : previousSize;
            memcpy(newAligned, aligned, minSize); // memcpy OK
        }

        // Free previous data
        alignedFree(aligned, alignment);
        assert(isPointerAligned(newAligned, alignment));
        return newAligned;
    }

    /// Returns: next pointer aligned with alignment bytes.
    void* nextAlignedPointer(void* start, size_t alignment) pure
    {
        import dplug.core.math : nextMultipleOf;
        return cast(void*)nextMultipleOf(cast(size_t)(start), alignment);
    }

    // Returns number of bytes to actually allocate when asking
    // for a particular alignement
    size_t requestedSize(size_t askedSize, size_t alignment) pure
    {
        enum size_t pointerSize = size_t.sizeof;
        return askedSize + alignment - 1 + pointerSize * 2;
    }

    // Store pointer given my malloc, and size in bytes initially requested (alignedRealloc needs it)
    void* storeRawPointerPlusSizeAndReturnAligned(void* raw, size_t size, size_t alignment)
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
}

unittest
{
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

    // Verify that same size alloc preserve pointer. 
    {
        void* p = null;
        p = alignedRealloc(p, 254, 16);
        void* p2 = alignedRealloc(p, 254, 16);
        assert(p == p2);

        // Test shrink heuristic
        void* p3 = alignedRealloc(p, 128, 16);
        assert(p == p3);
        alignedFree(p3, 16);
    }
}



/// Used throughout dplug:dsp to avoid reliance on GC.
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
/// Example:
/// ---
/// import std.stdio;
///
/// struct MyDSP
/// {
/// nothrow @nogc:
///
///     void initialize(int maxFrames)
///     {
///         // mybuf points to maxFrames frames
///         mybuf.reallocBuffer(maxFrames);
///     }   
///
///     ~this()
///     {
///         // If you don't free the buffer, it will leak.    
///         mybuf.reallocBuffer(0); 
///     }
///
/// private:
///     float[] mybuf;      
/// }
/// ---
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
        buffer = null; // alignment 1 can still return null
    else
        buffer = pointer[0..length];
}
unittest
{
    int[] arr;
    arr.reallocBuffer(15);
    assert(arr.length == 15);
    arr.reallocBuffer(0);
    assert(arr.length == 0);
}


/// Returns: A newly created `Vec`.
Vec!T makeVec(T)(size_t initialSize = 0, int alignment = 1) nothrow @nogc
{
    return Vec!T(initialSize, alignment);
}

/// Kind of a std::vector replacement.
/// Grow-only array, points to a (optionally aligned) memory location.
/// This can also work as an output range.
/// `Vec` is designed to work even when uninitialized, without `makeVec`.
/// Warning: it is pretty barebones, doesn't respect T.init or call destructors.
///          When used in a GC program, GC roots won't be registered.
struct Vec(T)
{
nothrow:
@nogc:

    static if (is(T == struct) && hasElaborateDestructor!T)
    {
        pragma(msg, "WARNING! struct with destructors were never meant to be supported in Vec!T. This will be removed in Dplug v15.");
    }

    public
    {
        /// Creates an aligned buffer with given initial size.
        this(size_t initialSize, int alignment) @safe
        {
            assert(alignment != 0);
            _size = 0;
            _allocated = 0;
            _data = null;
            _alignment = alignment;
            resizeExactly(initialSize);
        }

        ~this() @trusted
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
        size_t length() pure const @safe
        {
            return _size;
        }
        ///ditto
        alias size = length;

        /// Returns: Length of buffer in elements, as signed.
        ptrdiff_t slength() pure const @safe
        {
            return _size;
        }
        ///ditto
        alias ssize = length;

        /// Returns: `true` if length is zero.
        bool isEmpty() pure const @safe
        {
            return _size == 0;
        }

        /// Returns: Allocated size of the underlying array.
        size_t capacity() pure const @safe
        {
            return _allocated;
        }

        /// Returns: Length of buffer in elements.
        alias opDollar = length;

        /// Resizes a buffer to hold $(D askedSize) elements.
        void resize(size_t askedSize) @trusted
        {
            resizeExactly(askedSize);
        }

        /// Pop last element
        T popBack() @trusted
        {
            assert(_size > 0);
            _size = _size - 1;
            return _data[_size];
        }

        /// Append an element to this buffer.
        void pushBack(T x) @trusted
        {
            size_t i = _size;
            resizeGrow(_size + 1);
            _data[i] = x;
        }

        // DMD 2.088 deprecates the old D1-operators
        static if (__VERSION__ >= 2088)
        {
            ///ditto
            void opOpAssign(string op)(T x) @safe if (op == "~")
            {
                pushBack(x);
            }
        }
        else
        {
            ///ditto
            void opCatAssign(T x) @safe
            {
                pushBack(x);
            }
        }

        // Output range support
        alias put = pushBack;

        /// Finds an item, returns -1 if not found
        int indexOf(T x) @trusted
        {
            enum bool isStaticArray(T) = __traits(isStaticArray, T);

            static if (isStaticArray!T)
            {
                // static array would be compared by identity as slice, which is not what we want.
                foreach(int i; 0..cast(int)_size)
                    if (_data[i] == x)
                        return i;
            }
            else
            {
                // base types: identity is equality
                // reference types: looking for identity
                foreach(int i; 0..cast(int)_size)
                    if (_data[i] is x)
                        return i;
            }
            return -1;
        }

        /// Removes an item and replaces it by the last item.
        /// Warning: this reorders the array.
        void removeAndReplaceByLastElement(size_t index) @trusted
        {
            assert(index < _size);
            _data[index] = _data[--_size];
        }

        /// Removes an item and shift the rest of the array to front by 1.
        /// Warning: O(N) complexity.
        void removeAndShiftRestOfArray(size_t index) @trusted
        {
            assert(index < _size);
            for (; index + 1 < _size; ++index)
                _data[index] = _data[index+1];
            --_size;
        }

        /// Removes a range of items and shift the rest of the array to front.
        /// Warning: O(N) complexity.
        void removeAndShiftRestOfArray(size_t first, size_t last) @trusted
        {
            assert(first <= last && first <= _size && (last <= _size));
            size_t remain = _size - last;
            for (size_t n = 0; n < remain; ++n)
                _data[first + n] = _data[last + n];
            _size -= (last - first);
        }

        /// Appends another buffer to this buffer.
        void pushBack(ref Vec other) @trusted
        {
            size_t oldSize = _size;
            resizeGrow(_size + other._size);
            memmove(_data + oldSize, other._data, T.sizeof * other._size);
        }

        /// Appends a slice to this buffer.
        /// `slice` should not belong to the same buffer _data.
        void pushBack(T[] slice) @trusted
        {
            size_t oldSize = _size;
            size_t newSize = _size + slice.length;
            resizeGrow(newSize);
            for (size_t n = 0; n < slice.length; ++n)
                _data[oldSize + n] = slice[n];
        }

        /// Returns: Raw pointer to data.
        @property inout(T)* ptr() inout @system
        {
            return _data;
        }

        /// Returns: n-th element.
        ref inout(T) opIndex(size_t i) pure inout @trusted
        {
            return _data[i];
        }

        T opIndexAssign(T x, size_t i) pure @trusted
        {
            return _data[i] = x;
        }

        /// Sets size to zero, but keeps allocated buffers.
        void clearContents() pure @safe
        {
            _size = 0;
        }

        /// Returns: Whole content of the array in one slice.
        inout(T)[] opSlice() inout @safe
        {
            return opSlice(0, length());
        }

        /// Returns: A slice of the array.
        inout(T)[] opSlice(size_t i1, size_t i2) inout @trusted
        {
            return _data[i1 .. i2];
        }

        /// Fills the buffer with the same value.
        void fill(T x) @trusted
        {
            _data[0.._size] = x;
        }

        /// Move. Give up owner ship of the data.
        T[] releaseData() @system
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
        size_t _size = 0;
        T* _data = null;
        size_t _allocated = 0;
        size_t _alignment = 1; // for an unaligned Vec, you probably are not interested in alignment

        /// Used internally to grow in response to a pushBack operation.
        /// Different heuristic, since we know that the resize is likely to be repeated for an 
        /// increasing size later.
        void resizeGrow(size_t askedSize) @trusted
        {
            if (_allocated < askedSize)
            {

                version(all)
                {
                    size_t newCap = computeNewCapacity(askedSize, _size);
                    setCapacity(newCap);
                }
                else
                {
                    setCapacity(2 * askedSize);
                }
            }
            _size = askedSize;
        }

        // Resizes the `Vector` to hold exactly `askedSize` elements.
        // Still if the allocated capacity is larger, do nothing.
        void resizeExactly(size_t askedSize) @trusted
        {
            if (_allocated < askedSize)
            {
                setCapacity(askedSize);
            }
            _size = askedSize;
        }

        // Internal use, realloc internal buffer, copy existing items.
        // Doesn't initialize the new ones.
        void setCapacity(size_t cap)
        {
            size_t numBytes = cap * T.sizeof;
            _data = cast(T*)(alignedRealloc(_data, numBytes, _alignment));
            _allocated = cap;
        }

        // Compute new capacity, while growing.
        size_t computeNewCapacity(size_t newLength, size_t oldLength)
        {
            // Optimal value (Windows malloc) not far from there.
            enum size_t PAGESIZE = 4096; 

            size_t newLengthBytes = newLength * T.sizeof;
            if (newLengthBytes > PAGESIZE)
            {
                // Larger arrays need a smaller growth factor to avoid wasting too much bytes.
                // This was found when tracing curve, not too far from golden ratio for some reason.
                return newLength + newLength / 2 + newLength / 8;
            }
            else
            {
                // For smaller arrays being pushBack, can bring welcome speed by minimizing realloc.
                return newLength * 3;
            }            
        }
    }
}

unittest
{
    import std.range.primitives;
    static assert(isOutputRange!(Vec!ubyte, ubyte));


    import std.random;
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

            int minSize = previousSize;
            if (minSize > boxes[i].length)
                minSize = cast(int)(boxes[i].length);

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

        auto buf2 = makeVec!int;
        buf2.pushBack(11);
        buf2.pushBack(14);

        // test pushBack(slice)
        buf.clearContents();
        buf.pushBack(buf2[]);
        assert(buf[0] == 11);
        assert(buf[1] == 14);

        // test pushBack(slice)
        buf2[1] = 8;
        buf.clearContents();
        buf.pushBack(buf2);
        assert(buf[0] == 11);
        assert(buf[1] == 8);
    }
}

// Vec should work without any initialization
unittest
{
    Vec!string vec;

    foreach(e; vec[])
    {        
    }

    assert(vec.length == 0);
    assert(vec.size == 0);
    assert(vec.slength == 0);
    assert(vec.ssize == 0);
    vec.clearContents();
    vec.resize(0);
    assert(vec == vec.init);
    vec.fill("filler");
    assert(vec.ptr is null);
}

// Issue #312: vec.opIndex not returning ref which break struct assignment
unittest
{
    static struct A
    {
        int x;
    }
    Vec!A vec = makeVec!A();
    A a;
    vec.pushBack(a);
    vec ~= a;
    vec[0].x = 42; // vec[0] needs to return a ref
    assert(vec[0].x == 42);
}
unittest // removeAndShiftRestOfArray was wrong
{
    Vec!int v;
    v.pushBack(14);
    v.pushBack(27);
    v.pushBack(38);
    assert(v.length == 3);
    v.removeAndShiftRestOfArray(1);
    assert(v.length == 2);    
    assert(v[] == [14, 38]);
}
unittest // removeAndShiftRestOfArray with slice
{
    Vec!int v;
    v.pushBack([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    v.removeAndShiftRestOfArray(3, 5);
    assert(v[] == [0, 1, 2, 5, 6, 7, 8, 9]);
    v.removeAndShiftRestOfArray(0, 4);
    assert(v[] == [6, 7, 8, 9]);
    v.removeAndShiftRestOfArray(2, 4);
    assert(v[] == [6, 7]);
    v.removeAndShiftRestOfArray(2, 2);
    v.removeAndShiftRestOfArray(0, 0);
    v.removeAndShiftRestOfArray(1, 1);
    assert(v[] == [6, 7]);
}



/// Allows to merge the allocation of several arrays, which saves allocation count and can speed up things thanks to locality.
///
/// Example: see below unittest.
struct MergedAllocation
{
nothrow:
@nogc:

    // In debug mode, add stomp detection to `MergedAllocation`.
    // This takes additional complexity to coarse check for stomping nearby buffers.
    debug
    {
        private enum mergedAllocStompWarning = true;
    }
    else
    {
        private enum mergedAllocStompWarning = false;
    }


    // This adds 32-byte of sentinels around each allocation,
    // and check at the end of the program that they were unaffected.
    static if (mergedAllocStompWarning)
    {
        // Number of bytes to write between areas to check for stomping. 
        enum SENTINEL_BYTES = 32; 
    }

    enum maxExpectedAlignment = 32;

    /// Start defining the area of allocations.
    void start()
    {
        // Detect memory errors in former uses.
        static if (mergedAllocStompWarning)
        {
            checkSentinelAreas();
            _allocateWasCalled = false;
        }

        _base = cast(ubyte*)(cast(size_t)0);
    }

    /// Allocate (or count) space needed for `numElems` elements of type `T` with given alignment.
    /// This gets called twice for each array, see example for usage.
    ///
    /// This bumps the internal bump allocator.
    /// Giving null to this chain and converting the result to size_t give the total needed size 
    /// for the merged allocation.
    ///
    /// Warning: 
    ///          - If called after a `start()` call, the area returned are wrong and are only for 
    ///             counting needed bytes. Don't use those.
    ///
    ///          - If called after an `allocate()` call, the area returned are an actual merged 
    ///            allocation (if the same calls are done).
    ///
    /// Warning: Prefer `allocArray` over `alloc` variant, since the extra length field WILL help 
    ///          you catch memory errors before release. Else it is very common to miss buffer 
    ///          overflows in samplerate changes.
    void allocArray(T)(out T[] array, size_t numElems, size_t alignment = 1)
    {
        assert(alignment <= maxExpectedAlignment);
        assert( (alignment != 0) && ((alignment & (alignment - 1)) == 0)); // power of two

        size_t adr = cast(size_t) _base;

        // 1. Align base address
        size_t mask = ~(alignment - 1);
        adr = (adr + alignment - 1) & mask;

        // 2. Assign array and base.
        array = (cast(T*)adr)[0..numElems];
        adr += T.sizeof * numElems;
        _base = cast(ubyte*) adr;

        static if (mergedAllocStompWarning)
        {
            if (_allocateWasCalled && _allocation !is null)
            {
                // Each allocated area followed with SENTINEL_BYTES bytes of value 0xCC
                _base[0..SENTINEL_BYTES] = 0xCC;
                registerSentinel(_base);
            }
            _base += SENTINEL_BYTES;
        }
    }

    ///ditto
    void alloc(T)(out T* array, size_t numElems, size_t alignment = 1)
    {
        T[] arr;
        allocArray(arr, numElems, alignment);
        array = arr.ptr;
    }

    /// Allocate actual storage for the merged allocation. From there, you need to define exactly the same area with `alloc` and `allocArray`.
    /// This time they will get a proper value.
    void allocate()
    {
        static if (mergedAllocStompWarning) _allocateWasCalled = true;

        size_t sizeNeeded =  cast(size_t)_base; // since it was fed 0 at start.

        if (sizeNeeded == 0)
        {
            // If no bytes are requested, it means no buffer were requested, or only with zero size.
            // We will return a null pointer in that case, since accessing them would be illegal anyway.
            _allocation = null;
        }
        else
        {
            // the merged allocation needs to have the largest expected alignment, else the size could depend on the hazards
            // of the allocation. With maximum alignment, padding is the same so long as areas have smaller or equal alignment requirements.
            _allocation = cast(ubyte*) _mm_realloc(_allocation, sizeNeeded, maxExpectedAlignment);
        }

        // So that the next layout call points to the right area.
        _base = _allocation;
    }

    ~this()
    {
        static if (mergedAllocStompWarning)
        {
            checkSentinelAreas();
        }

        if (_allocation != null)
        {
            _mm_free(_allocation);
            _allocation = null;
        }
    }

private:

    // Location of the allocation.
    ubyte* _allocation = null;

    ///
    ubyte* _base = null;

    static if (mergedAllocStompWarning)
    {
        bool _allocateWasCalled = false;

        Vec!(ubyte*) _sentinels; // start of sentinel area (SENTINAL_BYTES long)

        void registerSentinel(ubyte* start)
        {
            _sentinels.pushBack(start);
        }

        bool hasMemoryError() // true if sentinel bytes stomped
        {
            assert(_allocateWasCalled && _allocation !is null);

            foreach(ubyte* s; _sentinels[])
            {
                for (int n = 0; n < 32; ++n)
                {
                    if (s[n] != 0xCC)
                        return true;
                }
            }
            return false;
        }

        // Check existing sentinels, and unregister them
        void checkSentinelAreas()
        {
            if (!_allocateWasCalled)
                return; // still haven't done an allocation, nothing to check.

            if (_allocation is null)
                return; // nothing to check

            // If you fail here, there is a memory error in your access patterns.
            // Sentinel bytes of value 0xCC were overwritten in a `MergedAllocation`.
            // You can use slices with `allocArray` instead of `alloc` to find the faulty 
            // access. This check doesn't catch everything!
            assert(! hasMemoryError());

            _sentinels.clearContents();
        }
    }
}


// Here is how you should use MergedAllocation. 
unittest
{
    static struct MyDSPStruct
    {
    public:
    nothrow:
    @nogc:
        void initialize(int maxFrames)
        {
            _mergedAlloc.start();
            layout(_mergedAlloc, maxFrames); // you need such a layout function to be called twice.
            _mergedAlloc.allocate();
            layout(_mergedAlloc, maxFrames); // the first time arrays area allocated in the `null` area, the second time in
                                             // actually allocated memory (since we now have the needed length).
        }
    
        void layout(ref MergedAllocation ma, int maxFrames)
        {
            // allocate `maxFrames` elems, and return a slice in `_intermediateBuf`.
            ma.allocArray(_intermediateBuf, maxFrames); 

            // allocate `maxFrames` elems, aligned to 16-byte boundaries. Return a pointer to that in `_coeffs`.
            ma.alloc(_coeffs, maxFrames, 16);
        }

    private:
        float[] _intermediateBuf;
        double* _coeffs;
        MergedAllocation _mergedAlloc;
    }

    MyDSPStruct s;
    s.initialize(14);
    s._coeffs[0..14] = 1.0f;
    s._intermediateBuf[0..14] = 1.0f;
    s.initialize(17);
    s._coeffs[0..17] = 1.0f;
    s._intermediateBuf[0..17] = 1.0f;
}

// Should be valid to allocate nothing with a MergedAllocation.
unittest
{
    MergedAllocation ma;
    ma.start();
    ma.allocate();
    assert(ma._allocation == null);
}

// Should be valid to allocate nothing with a MergedAllocation.
unittest
{
    MergedAllocation ma;
    ma.start();
    ubyte[] arr, arr2;
    ma.allocArray(arr, 17);
    ma.allocArray(arr2, 24);
    assert(ma._allocation == null);

    ma.allocate();
    ma.allocArray(arr, 17);
    ma.allocArray(arr2, 24);
    assert(ma._allocation != null);
    assert(arr.length == 17);
    assert(arr2.length == 24);

    // Test memory error detection with a simple case.
    static if (MergedAllocation.mergedAllocStompWarning)
    {
        assert(!ma.hasMemoryError());

        // Create a memory error
        arr.ptr[18] = 2;
        assert(ma.hasMemoryError());
        arr.ptr[18] = 0xCC; // undo the error to avoid stopping the unittests
    }
}
