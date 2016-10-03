/**
* Copyright: Copyright Auburn Sounds 2015-2016
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.core.nogc;


import core.stdc.stdlib: malloc, free;
import core.memory: GC;
import core.exception: onOutOfMemoryErrorNoGC;

import std.conv: emplace;
import std.traits;

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
        .destroy(p);

        static if (hasIndirections!T)
            GC.removeRange(cast(void*)p);

        free(cast(void*)p);
    }
}

/// Destroys and frees a non-class object created with $(D mallocEmplace).
void destroyFree(T)(T* p) if (!is(T == class))
{
    if (p !is null)
    {
        .destroy(p);

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
    import std.stdio;
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
void nogc_qsort(T)(T[] array, nogcComparisonFunction!T comparison) nothrow @nogc
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
    nogc_qsort!int(testData, (a, b) => (a - b));
    assert(testData == [1, 3, 5, 10, 22, 23, 100, 110]);
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
