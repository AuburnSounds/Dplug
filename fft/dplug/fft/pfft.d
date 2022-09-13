//          Copyright Jernej Krempuš 2012
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dplug.fft.pfft;
import core.stdc.stdlib;
import core.stdc.string: memcpy;
import core.exception,
       core.bitop,
       std.array;

template Import(TT)
{
    static if(is(TT == float))
        import impl = dplug.fft.impl_float;
    else static if(is(TT == double))
        import impl = dplug.fft.impl_double;
    else
        static assert(0, "Not implemented");
}

template st(alias a){ enum st = cast(size_t) a; }

/**
A class for calculating discrete fourier transform. The methods of this class
use split format for complex data. This means that a complex data set is
represented as two arrays - one for the real part and one for the imaginary
part. An instance of this class can only be used for transforms of one
particular size. The template parameter is the floating point type that the
methods of the class will operate on.

Example:
---
import std.stdio, std.conv, std.exception;
import pfft.pfft;

void main(string[] args)
{
    auto n = to!int(args[1]);
    enforce((n & (n-1)) == 0, "N must be a power of two.");

    alias Fft!float F;

    F f;
    f.initialize(n);

    auto re = F.allocate(n);
    auto im = F.allocate(n);

    foreach(i, _; re)
        readf("%s %s\n", &re[i], &im[i]);

    f.fft(re, im);

    foreach(i, _; re)
        writefln("%s\t%s", re[i], im[i]);
}
---
 */
struct Fft(T)
{
public:
nothrow:
@nogc:
    mixin Import!T;

    int log2n;
    impl.Table table;

/**
The Fft constructor. The parameter is the size of data sets that $(D fft) and
$(D ifft) will operate on. I will refer to this number as n in the rest of the
documentation for this class.Tables used in fft and ifft are calculated in the
constructor.
 */
    void initialize(size_t n)
    {
        assert((n & (n - 1)) == 0);
        log2n  = bsf(n);
        auto mem = alignedRealloc(table, impl.table_size_bytes(log2n), 64);
        table = impl.fft_table(log2n, mem);
        assert(mem == table);
    }

    ~this()
    {
        alignedFree(table, 64);
    }

/**
Calculates discrete fourier transform. $(D_PARAM re) should contain the real
part of the data and $(D_PARAM im) the imaginary part of the data. The method
operates in place - the result is saved back to $(D_PARAM re) and $(D_PARAM im).
Both arrays must be properly aligned - to obtain a properly aligned array you can
use $(D allocate).
 */
    void fft(T[] re, T[] im)
    {
        assert(re.length == im.length);
        assert(re.length == (st!1 << log2n));
        assert(((impl.alignment(re.length) - 1) & cast(size_t) re.ptr) == 0);
        assert(((impl.alignment(im.length) - 1) & cast(size_t) im.ptr) == 0);

        impl.fft(re.ptr, im.ptr, log2n, table);
    }

/**
Calculates inverse discrete fourier transform scaled by n. The arguments have
the same role as they do in $(D fft).
 */
    void ifft(T[] re, T[] im)
    {
        fft(im, re);
    }

/**
    Returns requited alignment for use with $(D fft), $(D ifft) and
    $(D scale) methods.
 */
    static size_t alignment(size_t n)
    {
        return impl.alignment(n);
    }

/**
Allocates an array that is aligned properly for use with $(D fft), $(D ifft) and
$(D scale) methods.
 */
    static T[] allocate(size_t n)
    {
        size_t bytes = n * T.sizeof;
        T* r = cast(T*) alignedMalloc(bytes, alignment(bytes));
        assert(((impl.alignment(bytes) - 1) & cast(size_t) r) == 0);
        return r[0..n];
    }

/**
Deallocates an array allocated with `allocate`.
*/
    static void deallocate(T[] arr)
    {
        size_t n = arr.length;
        alignedFree(arr.ptr, alignment(n));
    }


/**
Scales an array data by factor k. The array must be properly aligned. To obtain
a properly aligned array, use $(D allocate).
 */
    static void scale(T[] data, T k)
    {
        assert(((impl.alignment(data.length) - 1) & cast(size_t) data.ptr) == 0);
        impl.scale(data.ptr, data.length, k);
    }

}

/**
A class for calculating real discrete fourier transform. The methods of this
class use split format for complex data. This means that complex data set is
represented as two arrays - one for the real part and one for the imaginary
part. An instance of this class can only be used for transforms of one
particular size. The template parameter is the floating point type that the
methods of the class will operate on.

Example:
---
import std.stdio, std.conv, std.exception;
import pfft.pfft;

void main(string[] args)
{
    auto n = to!int(args[1]);
    enforce((n & (n-1)) == 0, "N must be a power of two.");

    alias Rfft!float F;

    F f;
    f.initialize(n);

    auto data = F.allocate(n);

    foreach(ref e; data)
        readf("%s\n", &e);

    f.rfft(data);

    foreach(i; 0 .. n / 2 + 1)
        writefln("%s\t%s", data[i], (i == 0 || i == n / 2) ? 0 : data[i]);
}
---
 */
struct Rfft(T)
{
public:
nothrow:
@nogc:
    mixin Import!T;

    int log2n;
    Fft!T _complex;
    impl.RTable rtable;
    impl.ITable itable;

/**
The Rfft constructor. The parameter is the size of data sets that $(D rfft) will
operate on. I will refer to this number as n in the rest of the documentation
for this class. All tables used in rfft are calculated in the constructor.
 */
    void initialize(size_t n)
    {
        // Doesn't work with lower size, but I'm unable to understand why
        assert(n >= 128); 

        assert((n & (n - 1)) == 0);
        log2n  = bsf(n);

        _complex.initialize(n / 2);

        auto mem = alignedRealloc(rtable, impl.rtable_size_bytes(log2n), 64);
        rtable = impl.rfft_table(log2n, mem);
        assert(mem == rtable);

        mem = alignedRealloc(itable, impl.itable_size_bytes(log2n), 64);
        itable = impl.interleave_table(log2n, mem);
        assert(mem == itable);
    }

    ~this()
    {
        alignedFree(rtable, 64);
        alignedFree(itable, 64);
    }

/**
Calculates discrete fourier transform of the real valued sequence in data.
The method operates in place. When the method completes, data contains the
result. First $(I n / 2 + 1) elements contain the real part of the result and
the rest contains the imaginary part. Imaginary parts at position 0 and
$(I n / 2) are known to be equal to 0 and are not stored, so the content of
data looks like this:

 $(D r(0), r(1), ... r(n / 2), i(1), i(2), ... i(n / 2 - 1))


The elements of the result at position greater than n / 2 can be trivially
calculated from the relation $(I DFT(f)[i] = DFT(f)[n - i]*) that holds
because the input sequence is real.


The length of the array must be equal to n and the array must be properly
aligned. To obtain a properly aligned array you can use $(D allocate).
 */
    void rfft(T[] data)
    {
        assert(data.length == (st!1 << log2n));
        assert(((impl.alignment(data.length) - 1) & cast(size_t) data.ptr) == 0);

        impl.deinterleave(data.ptr, log2n, itable);
        impl.rfft(data.ptr, data[$ / 2 .. $].ptr, log2n, _complex.table, rtable);
    }

/**
Calculates the inverse of $(D rfft), scaled by n (You can use $(D scale)
to normalize the result). Before the method is called, data should contain a
complex sequence in the same format as the result of $(D rfft). It is
assumed that the input sequence is a discrete fourier transform of a real
valued sequence, so the elements of the input sequence not stored in data
can be calculated from $(I DFT(f)[i] = DFT(f)[n - i]*). When the method
completes, the array contains the real part of the inverse discrete fourier
transform. The imaginary part is known to be equal to 0.

The length of the array must be equal to n and the array must be properly
aligned. To obtain a properly aligned array you can use $(D allocate).
 */
    void irfft(T[] data)
    {
        assert(data.length == (st!1 << log2n));
        assert(((impl.alignment(data.length) - 1) & cast(size_t) data.ptr) == 0);

        impl.irfft(data.ptr, data[$ / 2 .. $].ptr, log2n, _complex.table, rtable);
        impl.interleave(data.ptr, log2n, itable);
    }

/// An alias for Fft!T.allocate
    alias Fft!(T).allocate allocate;

/// An alias for Fft!T.deallocate
    alias Fft!(T).deallocate deallocate;

/// An alias for Fft!T.scale
    alias Fft!(T).scale scale;

    /// An alias for Fft!T.alignment
    alias Fft!(T).alignment alignment;

    @property complex(){ return _complex; }
}


private:

/// Returns: `true` if the pointer is suitably aligned.
bool isPointerAligned(void* p, size_t alignment) pure nothrow @nogc
{
    assert(alignment != 0);
    return ( cast(size_t)p & (alignment - 1) ) == 0;
}

/// Allocates an aligned memory chunk.
/// Functionally equivalent to Visual C++ _aligned_malloc.
/// Do not mix allocations with different alignment.
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
        void* res = malloc(size);
        if (size == 0)
            return null;
    }

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
    assert(alignment != 0);

    // Short-cut and use the C allocator to avoid overhead if no alignment
    if (alignment == 1)
        return free(aligned);

    // support for free(NULL)
    if (aligned is null)
        return;

    void** rawLocation = cast(void**)(cast(char*)aligned - size_t.sizeof);
    free(*rawLocation);
}

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

/// Reallocates an aligned memory chunk allocated by alignedMalloc or alignedRealloc.
/// Functionally equivalent to Visual C++ _aligned_realloc.
/// Do not mix allocations with different alignment.
@nogc void* alignedRealloc(void* aligned, size_t size, size_t alignment) nothrow
{
    assert(isPointerAligned(aligned, alignment));

    // If you fail here, it can mean you've used an uninitialized AlignedBuffer.
    assert(alignment != 0);

    // Short-cut and use the C allocator to avoid overhead if no alignment
    if (alignment == 1)
    {
        void* res = realloc(aligned, size);

        // C99: 
        // Implementation-defined behavior
        // Whether the calloc, malloc, and realloc functions return a null pointer 
        // or a pointer to an allocated object when the size requested is zero.
        if (size == 0)
            return null;

        return res;
    }

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
    memcpy(newAligned, aligned, minSize); // memcpy OK

    // Free previous data
    alignedFree(aligned, alignment);
    isPointerAligned(newAligned, alignment);
    return newAligned;
}


unittest
{
    {
        int n = 16;
        Fft!float A;
        A.initialize(n);
        float[] re = A.allocate(n);
        float[] im = A.allocate(n);
        scope(exit) A.deallocate(re);
        scope(exit) A.deallocate(im);
        re[] = 1.0f;
        im[] = 0.0f;
        A.fft(re, im);
        A.ifft(re, im);
    }

    {
        int n = 128;
        Rfft!float B;
        B.initialize(n);
        float[] data = B.allocate(n);
        scope(exit) B.deallocate(data);
        data[] = 1.0f;
        B.rfft(data);
        B.irfft(data);
    }
}