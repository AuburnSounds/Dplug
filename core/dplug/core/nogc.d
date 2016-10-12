/**
*
* Various @nogc alternatives. This file includes parts of std.process, std.random, std.uuid.
*
* Authors:   
*    $(HTTP guillaumepiolat.fr, Guillaume Piolat)
*    $(LINK2 https://github.com/kyllingstad, Lars Tandle Kyllingstad),
*    $(LINK2 https://github.com/schveiguy, Steven Schveighoffer),
*    $(HTTP thecybershadow.net, Vladimir Panteleev)
*
* Copyright:
*   Copyright (c) 2016, Auburn Sounds.
*   Copyright (c) 2013, Lars Tandle Kyllingstad (std.process).
*   Copyright (c) 2013, Steven Schveighoffer (std.process).
*   Copyright (c) 2013, Vladimir Panteleev (std.process).
*
* License:
*   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
*/
module dplug.core.nogc;

import core.stdc.string: strdup;
import core.stdc.stdlib: malloc, free, getenv;
import core.memory: GC;
import core.exception: onOutOfMemoryErrorNoGC;

import std.conv: emplace;
import std.traits;
import std.array: empty;

// This module provides many utilities to deal with @nogc


//
// Faking @nogc
//

auto assumeNoGC(T) (T t) if (isFunctionPointer!T || isDelegate!T)
{
    enum attrs = functionAttributes!T | FunctionAttribute.nogc;
    return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs)) t;
}

auto assumeNothrow(T) (T t) if (isFunctionPointer!T || isDelegate!T)
{
    enum attrs = functionAttributes!T | FunctionAttribute.nothrow_;
    return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs)) t;
}

auto assumeNothrowNoGC(T) (T t) if (isFunctionPointer!T || isDelegate!T)
{
    enum attrs = functionAttributes!T | FunctionAttribute.nogc | FunctionAttribute.nothrow_;
    return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs)) t;
}

unittest
{
    void funcThatDoesGC()
    {
        throw new Exception("hello!");
    }

    void anotherFunction() nothrow @nogc
    {
        assumeNothrowNoGC( (){ funcThatDoesGC(); } )();
    }

    void aThirdFunction() @nogc
    {
        assumeNoGC( () { funcThatDoesGC(); } )();
    }
}


//
// Optimistic .destroy, which is @nogc nothrow by breaking the type-system
//

// for classes
void destroyNoGC(T)(T x) nothrow @nogc if (is(T == class) || is(T == interface))
{
    assumeNothrowNoGC(
        (T x) 
        {
            return destroy(x);
        })(x);
}

// for struct
void destroyNoGC(T)(ref T obj) nothrow @nogc if (is(T == struct))
{
    assumeNothrowNoGC(
        (ref T x) 
        {
            return destroy(x);
        })(obj);
}
/*
void destroyNoGC(T : U[n], U, size_t n)(ref T obj) nothrow @nogc
{
    assumeNothrowNoGC(
        (T x) 
        {
            return destroy(x);
        })(obj);
}*/

void destroyNoGC(T)(ref T obj) nothrow @nogc 
    if (!is(T == struct) && !is(T == class) && !is(T == interface))
{
    assumeNothrowNoGC(
                      (ref T x) 
                      {
                          return destroy(x);
                      })(obj);
}



//
// Constructing and destroying without the GC.
//

/// Allocates and construct a struct or class object.
/// Returns: Newly allocated object.
auto mallocEmplace(T, Args...)(Args args)
{
    static if (is(T == class))
        immutable size_t allocSize = __traits(classInstanceSize, T);
    else
        immutable size_t allocSize = T.sizeof;

    void* rawMemory = malloc(allocSize);
    if (!rawMemory)
        onOutOfMemoryErrorNoGC();

    static if (hasIndirections!T)
        GC.addRange(rawMemory, allocSize);

    static if (is(T == class))
    {
        T obj = emplace!T(rawMemory[0 .. allocSize], args);
    }
    else
    {
        T* obj = cast(T*)rawMemory;
        emplace!T(obj, args);
    }

    return obj;
}

/// Destroys and frees a class object created with $(D mallocEmplace).
void destroyFree(T)(T p) if (is(T == class))
{
    if (p !is null)
    {
        destroyNoGC(p);

        static if (hasIndirections!T)
            GC.removeRange(cast(void*)p);

        free(cast(void*)p);
    }
}

/// Destroys and frees an interface object created with $(D mallocEmplace).
void destroyFree(T)(T p) if (is(T == interface))
{
    if (p !is null)
    {
        void* here = cast(void*)(cast(Object)p);
        destroyNoGC(p);

        static if (hasIndirections!T)
            GC.removeRange(here);

        free(cast(void*)p);
    }
}

/// Destroys and frees a non-class object created with $(D mallocEmplace).
void destroyFree(T)(T* p) if (!is(T == class))
{
    if (p !is null)
    {
        destroyNoGC(p);

        static if (hasIndirections!T)
            GC.removeRange(cast(void*)p);

        free(cast(void*)p);
    }
}


unittest
{
    class A
    {
        int _i;
        this(int i)
        {
            _i = i;
        }
    }

    struct B
    {
        int i;
    }

    void testMallocEmplace()
    {
        A a = mallocEmplace!A(4);
        destroyFree(a);

        B* b = mallocEmplace!B(5);
        destroyFree(b);
    }

    testMallocEmplace();
}

version( D_InlineAsm_X86 )
{
    version = AsmX86;
}
else version( D_InlineAsm_X86_64 )
{
    version = AsmX86;
}

/// Allocates a slice with `malloc`.
/// This does not add GC roots so when using the runtime do not use such slice as traceable.
T[] mallocSlice(T)(size_t count) nothrow @nogc
{
    T[] slice = mallocSliceNoInit!T(count);
    slice[0..count] = T.init;
    return slice;
}

/// Allocates a slice with `malloc`, but does not initialize the content.
/// This does not add GC roots so when using the runtime do not use such slice as traceable.
T[] mallocSliceNoInit(T)(size_t count) nothrow @nogc
{
    T* p = cast(T*) malloc(count * T.sizeof);
    return p[0..count];
}

/// Free a slice allocated with `mallocSlice`.
void freeSlice(T)(const(T)[] slice) nothrow @nogc
{
    free(cast(void*)(slice.ptr)); // const cast here
}

unittest
{
    int[] slice = mallocSlice!int(4);
    freeSlice(slice);
    assert(slice[3] == int.init);

    slice = mallocSliceNoInit!int(4);
    freeSlice(slice);

    slice = mallocSliceNoInit!int(0);
    assert(slice == []);
    freeSlice(slice);
}


//
// GC-proof resources: for when the GC does exist.
// 

/// Destructors called by the GC enjoy a variety of limitations and
/// relying on them is dangerous.
/// See_also: $(WEB p0nce.github.io/d-idioms/#The-trouble-with-class-destructors)
/// Example:
/// ---
/// class Resource
/// {
///     ~this()
///     {
///         if (!alreadyClosed)
///         {
///             if (isCalledByGC())
///                 assert(false, "Resource release relies on Garbage Collection");
///             alreadyClosed = true;
///             releaseResource();
///         }
///     }
/// }
/// ---
bool isCalledByGC() nothrow
{
    import core.exception;
    try
    {
        import core.memory;
        cast(void) GC.malloc(1); // not ideal since it allocates
        return false;
    }
    catch(InvalidMemoryOperationError e)
    {
        return true;
    }
}

unittest
{
    class A
    {
        ~this()
        {
            assert(!isCalledByGC());
        }
    }
    import std.typecons;
    auto a = scoped!A();
}




//
// @nogc sorting.
//

/// Must return -1 if a < b
///              0 if a == b
///              1 if a > b
alias nogcComparisonFunction(T) = int delegate(in T a, in T b) nothrow @nogc;

/// @nogc quicksort
/// From the excellent: http://codereview.stackexchange.com/a/77788
void quicksort(T)(T[] array, nogcComparisonFunction!T comparison) nothrow @nogc
{
    if (array.length < 2)
        return;

    static void swapElem(ref T lhs, ref T rhs)
    {
        T tmp = lhs;
        lhs = rhs;
        rhs = tmp;
    }

    int partition(T* arr, int left, int right) nothrow @nogc
    {
        immutable int mid = left + (right - left) / 2;
        T pivot = arr[mid];
        // move the mid point value to the front.
        swapElem(arr[mid],arr[left]);
        int i = left + 1;
        int j = right;
        while (i <= j)
        {
            while(i <= j && comparison(arr[i], pivot) <= 0 )
                i++;

            while(i <= j && comparison(arr[j], pivot) > 0)
                j--;

            if (i < j)
                swapElem(arr[i], arr[j]);
        }
        swapElem(arr[i - 1], arr[left]);
        return i - 1;
    }

    void doQsort(T* array, int left, int right) nothrow @nogc
    {
        if (left >= right)
            return;

        int part = partition(array, left, right);
        doQsort(array, left, part - 1);
        doQsort(array, part + 1, right);
    }

    doQsort(array.ptr, 0, cast(int)(array.length) - 1);
}

unittest
{
    int[] testData = [110, 5, 10, 3, 22, 100, 1, 23];
    quicksort!int(testData, (a, b) => (a - b));
    assert(testData == [1, 3, 5, 10, 22, 23, 100, 110]);
}


//
// STABLE MERGE SORT
//

// Stable merge sort, using a temporary array.
// Array A[] has the items to sort.
// Array B[] is a work array.
void mergeSort(T)(T[] inoutElements, T[] scratchBuffer, nogcComparisonFunction!T comparison) nothrow @nogc
{
    // Left source half is A[ iBegin:iMiddle-1].
    // Right source half is A[iMiddle:iEnd-1   ].
    // Result is            B[ iBegin:iEnd-1   ].
    void topDownMerge(T)(T* A, int iBegin, int iMiddle, int iEnd, T* B) nothrow @nogc
    {
        int i = iBegin;
        int j = iMiddle;

        // While there are elements in the left or right runs...
        for (int k = iBegin; k < iEnd; k++) 
        {
            // If left run head exists and is <= existing right run head.
            if ( i < iMiddle && ( j >= iEnd || (comparison(A[i], A[j]) <= 0) ) ) 
            {
                B[k] = A[i];
                i = i + 1;
            } 
            else 
            {
                B[k] = A[j];
                j = j + 1;    
            }
        } 
    }

    // Sort the given run of array A[] using array B[] as a source.
    // iBegin is inclusive; iEnd is exclusive (A[iEnd] is not in the set).
    void topDownSplitMerge(T)(T* B, int iBegin, int iEnd, T* A) nothrow @nogc
    {
        if(iEnd - iBegin < 2)                       // if run size == 1
            return;                                 //   consider it sorted
        // split the run longer than 1 item into halves
        int iMiddle = (iEnd + iBegin) / 2;              // iMiddle = mid point
        // recursively sort both runs from array A[] into B[]
        topDownSplitMerge!T(A, iBegin,  iMiddle, B);  // sort the left  run
        topDownSplitMerge!T(A, iMiddle,    iEnd, B);  // sort the right run
        // merge the resulting runs from array B[] into A[]
        topDownMerge!T(B, iBegin, iMiddle, iEnd, A);
    }

    assert(inoutElements.length == scratchBuffer.length);
    int n = cast(int)inoutElements.length;
    scratchBuffer[] = inoutElements[]; // copy data into temporary buffer
    topDownSplitMerge(scratchBuffer.ptr, 0, n, inoutElements.ptr);
}

unittest
{
    int[2][] scratch;
    scratch.length = 8;
    int[2][] testData = [[110, 0], [5, 0], [10, 0], [3, 0], [110, 1], [5, 1], [10, 1], [3, 1]];
    mergeSort!(int[2])(testData, scratch, (a, b) => (a[0] - b[0]));
    assert(testData == [[3, 0], [3, 1], [5, 0], [5, 1], [10, 0], [10, 1], [110, 0], [110, 1]]);
}



//
// Unrelated things that hardly goes anywhere
//

/// Crash if the GC is running.
/// Useful in destructors to avoid reliance GC resource release.
/// However since this is not @nogc, this is not suitable in runtime-less D.
/// See_also: $(WEB p0nce.github.io/d-idioms/#GC-proof-resource-class)
void ensureNotInGC(string resourceName = null) nothrow
{
    import core.exception;
    try
    {
        import core.memory;
        cast(void) GC.malloc(1); // not ideal since it allocates
        return;
    }
    catch(InvalidMemoryOperationError e)
    {
        import core.stdc.stdio;
        fprintf(stderr, "Error: clean-up of %s incorrectly depends on destructors called by the GC.\n",
                resourceName ? resourceName.ptr : "a resource".ptr);
        assert(false); // crash
    }
}



/// To call for something that should never happen, but we still
/// want to make a "best effort" at runtime even if it can be meaningless.
/// TODO: change that name, it's not actually unrecoverable
void unrecoverableError() nothrow @nogc
{
    debug
    {
        // Crash unconditionally
        assert(false); 
    }
    else
    {
        // There is a trade-off here, if we crash immediately we will be 
        // correctly identified by the user as the origin of the bug, which
        // is always helpful.
        // But crashing may in many-case also crash the host, which is not very friendly.
        // Eg: a plugin not instancing vs host crashing.
        // The reasoning is that the former is better from the user POV.
    }
}


/// A bit faster than a dynamic cast.
/// This is to avoid TypeInfo look-up.
T unsafeObjectCast(T)(Object obj)
{
    return cast(T)(cast(void*)(obj));
}


/// Inserts a breakpoint instruction. useful to trigger the debugger.
void debugBreak() nothrow @nogc
{
    version( AsmX86 )
    {
        asm nothrow @nogc
        {
            int 3;
        }
    }
    else version( GNU )
    {
        // __builtin_trap() is not the same thing unfortunately
        asm
        {
            "int $0x03" : : : ;
        }
    }
    else
    {
        static assert(false, "No debugBreak() for this compiler");
    }
}


// Copy source into dest.
// dest must contain room for maxChars characters
// A zero-byte character is then appended.
void stringNCopy(char* dest, size_t maxChars, string source) nothrow @nogc
{
    if (maxChars == 0)
        return;

    size_t max = maxChars < source.length ? maxChars - 1 : source.length;
    for (int i = 0; i < max; ++i)
        dest[i] = source[i];
    dest[max] = '\0';
}


//
// Low-cost C string conversions
//
alias CString = CStringImpl!char;
alias CString16 = CStringImpl!wchar;

/// Zero-terminated C string, to replace toStringz and toUTF16z
struct CStringImpl(CharType) if (is(CharType: char) || is(CharType: wchar))
{
public:
nothrow:
@nogc:

    const(CharType)* storage = null;
    alias storage this;

    this(immutable(CharType)[] s)
    {    
        // Same optimizations that for toStringz
        if (s.empty)
        {
            enum emptyString = cast(CharType[])"";
            storage = emptyString.ptr;
            return;
        }

        /* Peek past end of s[], if it's 0, no conversion necessary.
        * Note that the compiler will put a 0 past the end of static
        * strings, and the storage allocator will put a 0 past the end
        * of newly allocated char[]'s.
        */
        immutable p = s.ptr + s.length;
        // Is p dereferenceable? A simple test: if the p points to an
        // address multiple of 4, then conservatively assume the pointer
        // might be pointing to a new block of memory, which might be
        // unreadable. Otherwise, it's definitely pointing to valid
        // memory.
        if ((cast(size_t) p & 3) && *p == 0)
        {
            storage = s.ptr;
            return;
        }

        size_t len = s.length;
        CharType* buffer = cast(CharType*) malloc((len + 1) * CharType.sizeof);
        buffer[0..len] = s[0..len];
        buffer[len] = '\0';
        storage = buffer;
        wasAllocated = true;
    }

    ~this()
    {
        if (wasAllocated)
            free(cast(void*)storage);
    }

    @disable this(this);

private:
    bool wasAllocated = false;
}


//
// Launch browser, replaces std.process.browse
//

void browseNoGC(string url) nothrow @nogc
{
    version(Windows)
    {
        import core.sys.windows.winuser;
        import core.sys.windows.shellapi;
        ShellExecuteA(null, CString("open").storage, CString(url).storage, null, null, SW_SHOWNORMAL);
    }

    version(OSX)
    {
        import core.sys.posix.unistd;
        const(char)*[5] args;

        auto curl = CString(url).storage;
        const(char)* browser = getenv("BROWSER");
        if (browser)
        {   
            browser = strdup(browser);
            args[0] = browser;
            args[1] = curl;
            args[2] = null;
        }
        else
        {
            args[0] = "open".ptr;
            args[1] = curl;
            args[2] = null;
        }

        auto childpid = core.sys.posix.unistd.fork();
        if (childpid == 0)
        {
            core.sys.posix.unistd.execvp(args[0], cast(char**)args.ptr);
            return;
        }
        if (browser)
            free(cast(void*)browser);
    }
}

