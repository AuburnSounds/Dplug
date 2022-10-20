/**

Various @nogc alternatives. This file includes parts of `std.process`, `std.random`, `std.uuid`.

Authors:
  $(HTTP guillaumepiolat.fr, Guillaume Piolat)
  $(LINK2 https://github.com/kyllingstad, Lars Tandle Kyllingstad),
  $(LINK2 https://github.com/schveiguy, Steven Schveighoffer),
  $(HTTP thecybershadow.net, Vladimir Panteleev)

Copyright:
 Copyright (c) 2016, Guillaume Piolat.
 Copyright (c) 2013, Lars Tandle Kyllingstad (std.process).
 Copyright (c) 2013, Steven Schveighoffer (std.process).
 Copyright (c) 2013, Vladimir Panteleev (std.process).

 License:
   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
*/
module dplug.core.nogc;

import core.stdc.stdarg;
import core.stdc.string: strdup, memcpy, strlen;
import core.stdc.stdlib: malloc, free, getenv;
import core.memory: GC;
import core.exception: onOutOfMemoryErrorNoGC;

import std.conv: emplace;
import std.traits;

import dplug.core.vec: Vec;

// This module provides many utilities to deal with @nogc nothrow, in a situation with the runtime disabled.

//
// Faking @nogc
//

version = useTimSort;

auto assumeNoGC(T) (T t)
{
    static if (isFunctionPointer!T || isDelegate!T)
    {
        enum attrs = functionAttributes!T | FunctionAttribute.nogc;
        return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs)) t;
    }
    else
        static assert(false);
}

auto assumeNothrowNoGC(T) (T t)
{
    static if (isFunctionPointer!T || isDelegate!T)
    {
        enum attrs = functionAttributes!T | FunctionAttribute.nogc | FunctionAttribute.nothrow_;
        return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs)) t;
    }
    else
        static assert(false);
}

unittest
{
    void funcThatDoesGC()
    {
        int a = 4;
        int[] b = [a, a, a];
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
auto mallocNew(T, Args...)(Args args)
{
    static if (is(T == class))
        immutable size_t allocSize = __traits(classInstanceSize, T);
    else
        immutable size_t allocSize = T.sizeof;

    void* rawMemory = malloc(allocSize);
    if (!rawMemory)
        onOutOfMemoryErrorNoGC();

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
        free(cast(void*)here);
    }
}

/// Destroys and frees a non-class object created with $(D mallocEmplace).
void destroyFree(T)(T* p) if (!is(T == class))
{
    if (p !is null)
    {
        destroyNoGC(p);
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
        A a = mallocNew!A(4);
        destroyFree(a);

        B* b = mallocNew!B(5);
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
T[] mallocSlice(T)(size_t count) nothrow @nogc
{
    T[] slice = mallocSliceNoInit!T(count);
    static if (is(T == struct))
    {
        // we must avoid calling struct destructors with uninitialized memory
        for(size_t i = 0; i < count; ++i)
        {
            T uninitialized;
            memcpy(&slice[i], &uninitialized, T.sizeof); // memcpy OK
        }
    }
    else
        slice[0..count] = T.init;
    return slice;
}

/// Allocates a slice with `malloc`, but does not initialize the content.
T[] mallocSliceNoInit(T)(size_t count) nothrow @nogc
{
    T* p = cast(T*) malloc(count * T.sizeof);
    return p[0..count];
}

/// Frees a slice allocated with `mallocSlice`.
void freeSlice(T)(const(T)[] slice) nothrow @nogc
{
    free(cast(void*)(slice.ptr)); // const cast here
}

/// Duplicates a slice with `malloc`. Equivalent to `.dup`
/// Has to be cleaned-up with `free(slice.ptr)` or `freeSlice(slice)`.
T[] mallocDup(T)(const(T)[] slice) nothrow @nogc if (!is(T == struct))
{
    T[] copy = mallocSliceNoInit!T(slice.length);
    memcpy(copy.ptr, slice.ptr, slice.length * T.sizeof);
    return copy;
}

/// Duplicates a slice with `malloc`. Equivalent to `.idup`
/// Has to be cleaned-up with `free(slice.ptr)` or `freeSlice(slice)`.
immutable(T)[] mallocIDup(T)(const(T)[] slice) nothrow @nogc if (!is(T == struct))
{
    return cast(immutable(T)[]) (mallocDup!T(slice));
}

/// Duplicates a zero-terminated string with `malloc`, return a `char[]` with zero-terminated byte.
/// Has to be cleaned-up with `free(s.ptr)`.
/// Note: The zero-terminating byte is preserved. This allow to have a string which also can be converted
/// to a C string with `.ptr`. However the zero byte is not included in slice length.
char[] stringDup(const(char)* cstr) nothrow @nogc
{
    assert(cstr !is null);
    size_t len = strlen(cstr);
    char* copy = strdup(cstr);
    return copy[0..len];
}

/// Duplicates a zero-terminated string with `malloc`, return a `string`. with zero-terminated byte. 
/// Has to be cleaned-up with `free(s.ptr)`.
/// Note: The zero-terminating byte is preserved. This allow to have a string which also can be converted
/// to a C string with `.ptr`. However the zero byte is not included in slice length.
string stringIDup(const(char)* cstr) nothrow @nogc
{
    return cast(string) stringDup(cstr);
}

unittest
{
    int[] slice = mallocSlice!int(4);
    assert(slice[3] == int.init);
    freeSlice(slice);    

    slice = mallocSliceNoInit!int(4);
    freeSlice(slice);

    slice = mallocSliceNoInit!int(0);
    assert(slice == []);
    freeSlice(slice);
}

/// Semantic function to check that a D string implicitely conveys a
/// termination byte after the slice.
/// (typically those comes from string literals or `stringDup`/`stringIDup`)
const(char)* assumeZeroTerminated(const(char)[] input) nothrow @nogc
{
    if (input.ptr is null)
        return null;

    // Check that the null character is there
    assert(input.ptr[input.length] == '\0');
    return input.ptr;
}

//
// STABLE IN-PLACE SORT (implementation is at bottom of file)
//
// Here is how to use it:
unittest
{
    {
        int[2][] testData = [[110, 0], [5, 0], [10, 0], [3, 0], [110, 1], [5, 1], [10, 1], [3, 1]];
        version(useTimSort)
        {
            Vec!(int[2]) tempBuf;
            timSort!(int[2])(testData, tempBuf, (a, b) => (a[0] - b[0]));        
        }
        assert(testData == [[3, 0], [3, 1], [5, 0], [5, 1], [10, 0], [10, 1], [110, 0], [110, 1]]);
    }    
}


//
// STABLE MERGE SORT
//

/// A bit faster than a dynamic cast.
/// This is to avoid TypeInfo look-up.
T unsafeObjectCast(T)(Object obj)
{
    return cast(T)(cast(void*)(obj));
}

/// Outputs a debug string in either:
///  - stdout on POSIX-like (visible in the command-line)
///  - the Output Windows on Windows (visible withing Visual Studio or with dbgview.exe)
/// Warning: no end-of-line added!
void debugLog(const(char)* message) nothrow @nogc
{
    version(Windows)
    {
        import core.sys.windows.windows;
        OutputDebugStringA(message);
    }
    else
    {
        import core.stdc.stdio;
        printf("%s\n", message);
    }
}

///ditto
extern (C) void debugLogf(const(char)* fmt, ...) nothrow @nogc
{
    import core.stdc.stdio;

    char[256] buffer;
    va_list args;
    va_start (args, fmt);
    vsnprintf (buffer.ptr, 256, fmt, args);
    va_end (args);

    version(Windows)
    {
        import core.sys.windows.windows;
        OutputDebugStringA(buffer.ptr);
    }
    else
    {        
        printf("%s\n", buffer.ptr);
    }
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
    else version(LDC)
    {
    	import ldc.intrinsics;
    	llvm_debugtrap();
    }
    else
    {
        static assert(false, "No debugBreak() for this compiler");
    }
}


// Copy source into dest.
// dest must contain room for maxChars characters
// A zero-byte character is then appended.
void stringNCopy(char* dest, size_t maxChars, const(char)[] source) nothrow @nogc
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


    this(const(CharType)[] s)
    {
        // Always copy. We can't assume anything about the input.
        size_t len = s.length;
        CharType* buffer = cast(CharType*) malloc((len + 1) * CharType.sizeof);
        buffer[0..len] = s[0..len];
        buffer[len] = '\0';
        storage = buffer;
        wasAllocated = true;
    }

    // The constructor taking immutable can safely assume that such memory
    // has been allocated by the GC or malloc, or an allocator that align
    // pointer on at least 4 bytes.
    this(immutable(CharType)[] s)
    {
        // Same optimizations that for toStringz
        if (s.length == 0)
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
        const(CharType)* p = s.ptr + s.length;
        // Is p dereferenceable? A simple test: if the p points to an
        // address multiple of 4, then conservatively assume the pointer
        // might be pointing to another block of memory, which might be
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
    version(linux)
    {
        import core.sys.posix.stdlib;
        import core.stdc.stdio;
        char[256] curl;
        sprintf(curl.ptr, "%s %s", "xdg-open".ptr, CString(url).storage);
        system(curl.ptr);
    }
}

//
// @nogc sorting.
//

/// Must return -1 if a < b
///              0 if a == b
///              1 if a > b
alias nogcComparisonFunction(T) = int delegate(in T a, in T b) nothrow @nogc;


version(useTimSort)
{

    public void timSort(T)(T[] dst, 
                       ref Vec!T storeBuf, // content unimportant, this will be use a temp storage.
                                           // it should be "grow-only"
                       nogcComparisonFunction!T comparison) nothrow @nogc
    {
        const size_t size = dst.length;

        /* don't bother sorting an array of size 1 */
        if (size <= 1) {
            return;
        }

        if (size < 64) 
        {
            // uh... all out test cases are here
            tim_sort_binary_inversion_sort!T(dst.ptr, size, comparison);
            return;
        }

        // Why would it be used only there???
        enum TIM_SORT_STACK_SIZE = 64;
        tim_sort_run_t[TIM_SORT_STACK_SIZE] run_stack;
        size_t stack_curr = 0;
        size_t curr = 0;

        /* compute the minimum run length */
        size_t minrun = tim_sort_compute_minrun(size);

        if (!tim_sort_push_next!T(dst.ptr, size, storeBuf, minrun, run_stack.ptr, &stack_curr, &curr, comparison)) {
            return;
        }

        if (!tim_sort_push_next!T(dst.ptr, size, storeBuf, minrun, run_stack.ptr, &stack_curr, &curr, comparison)) {
            return;
        }

        if (!tim_sort_push_next!T(dst.ptr, size, storeBuf, minrun, run_stack.ptr, &stack_curr, &curr, comparison)) {
            return;
        }

        while (1) {
            if (!tim_sort_check_invariant(run_stack.ptr, cast(int)stack_curr)) {
                stack_curr = tim_sort_collapse!T(dst.ptr, run_stack.ptr, cast(int)stack_curr, storeBuf, size, comparison);
                continue;
            }

            if (!tim_sort_push_next!T(dst.ptr, size, storeBuf, minrun, run_stack.ptr, &stack_curr, &curr, comparison)) {
                return;
            }
        }
    }

    private:


    /* adapted from Hacker's Delight */
    static int clzll(ulong x) pure nothrow @nogc
    {
        if (x == 0)
            return 64;

        // Note: not worth optimizing further with `63 - bsr(x)`
        // It's simply called once.
        int n = 0;

        if (x <= 0x00000000FFFFFFFFL) 
        {
            n = n + 32;
            x = x << 32;
        }

        if (x <= 0x0000FFFFFFFFFFFFL) 
        {
            n = n + 16;
            x = x << 16;
        }

        if (x <= 0x00FFFFFFFFFFFFFFL) 
        {
            n = n + 8;
            x = x << 8;
        }

        if (x <= 0x0FFFFFFFFFFFFFFFL) 
        {
            n = n + 4;
            x = x << 4;
        }

        if (x <= 0x3FFFFFFFFFFFFFFFL) 
        {
            n = n + 2;
            x = x << 2;
        }

        if (x <= 0x7FFFFFFFFFFFFFFFL) 
        {
            n = n + 1;
        }
        return n;
    }
    unittest
    {
        assert(clzll(0) == 64);
        assert(clzll(1) == 63);
        assert(clzll(-1) == 0);
    }

    static int tim_sort_compute_minrun(const ulong size) pure nothrow @nogc
    {
        int top_bit = 64 - clzll(size);
        int maxbit = top_bit > 6 ? top_bit : 6;
        int shift = maxbit - 6;
        int minrun = cast(int)(size >> shift);
        ulong mask = ((cast(ulong)1) << shift) - 1;
        if (mask & size) 
        {
            return minrun + 1;
        }
        return minrun;
    }


    struct tim_sort_run_t
    {
        size_t start;
        size_t length;
    }

    /* Function used to do a binary search for binary insertion sort */
    size_t tim_sort_binary_inversion_find(T)(T *dst, const T x, const size_t size, nogcComparisonFunction!T comparison) nothrow @nogc
    {
        size_t l, c, r;
        T cx;
        l = 0;
        r = size - 1;
        c = r >> 1;

        /* check for out of bounds at the beginning. */
        if (comparison(x, dst[0]) < 0) 
        {
            return 0;
        } else if (comparison(x, dst[r]) > 0) 
        {
            return r;
        }

        cx = dst[c];

        while (1) 
        {
            const int val = comparison(x, cx);

            if (val < 0) 
            {
                if (c - l <= 1) 
                {
                    return c;
                }

                r = c;
            } else 
            { /* allow = for stability. The binary search favors the right. */
                if (r - c <= 1) 
                {
                    return c + 1;
                }
                l = c;
            }

            c = l + ((r - l) >> 1);
            cx = dst[c];
        }
    }

    /* Binary insertion sort, but knowing that the first "start" entries are sorted.  Used in timsort. */
    static void tim_sort_binary_inversion_sort_start(T)(T *dst, 
                                               const size_t start, 
                                               const size_t size, 
                                               nogcComparisonFunction!T comparison) nothrow @nogc 
    {
        size_t i;

        for (i = start; i < size; i++) {
            size_t j;
            T x;
            size_t location;

            /* If this entry is already correct, just move along */
            if (comparison(dst[i - 1], dst[i]) <= 0) {
                continue;
            }

            /* Else we need to find the right place, shift everything over, and squeeze in */
            x = dst[i];
            location = tim_sort_binary_inversion_find!T(dst, x, i, comparison);

            for (j = i - 1; j >= location; j--) {
                dst[j + 1] = dst[j];

                if (j == 0) { /* check edge case because j is unsigned */
                    break;
                }
            }

            dst[location] = x;
        }
    }

    /* Binary insertion sort */
    static void tim_sort_binary_inversion_sort(T)(T *dst, 
                                         const size_t size, 
                                         nogcComparisonFunction!T comparison) 
    {
        /* don't bother sorting an array of size <= 1 */
        if (size <= 1) {
            return;
        }
        tim_sort_binary_inversion_sort_start!T(dst, 1, size, comparison);
    }

    /* timsort implementation, based on timsort.txt */

    static void tim_sort_reverse_elements(T)(T *dst, size_t start, size_t end) 
    {
        while (1) {
            if (start >= end) {
                return;
            }

            T temp = dst[start]; // swap
            dst[start] = dst[end];
            dst[end] = temp;

            start++;
            end--;
        }
    }

    static size_t tim_sort_count_run(T)(T *dst, const size_t start, const size_t size, nogcComparisonFunction!T comparison) 
    {
        size_t curr;

        if (size - start == 1) {
            return 1;
        }

        if (start >= size - 2) {
            if (comparison(dst[size - 2], dst[size - 1]) > 0) 
            {
                // swap
                T temp = dst[size - 2];
                dst[size - 2] = dst[size - 1];
                dst[size - 1] = temp;
            }

            return 2;
        }

        curr = start + 2;

        if (comparison(dst[start], dst[start + 1]) <= 0) {
            /* increasing run */
            while (1) {
                if (curr == size - 1) {
                    break;
                }

                if (comparison(dst[curr - 1], dst[curr]) > 0) {
                    break;
                }

                curr++;
            }

            return curr - start;
        } else {
            /* decreasing run */
            while (1) {
                if (curr == size - 1) {
                    break;
                }

                if (comparison(dst[curr - 1], dst[curr]) <= 0) {
                    break;
                }

                curr++;
            }

            /* reverse in-place */
            tim_sort_reverse_elements!T(dst, start, curr - 1);
            return curr - start;
        }
    }

    static int tim_sort_check_invariant(tim_sort_run_t *stack, const int stack_curr) nothrow @nogc
    {
        size_t A, B, C;

        if (stack_curr < 2) {
            return 1;
        }

        if (stack_curr == 2) {
            const size_t A1 = stack[stack_curr - 2].length;
            const size_t B1 = stack[stack_curr - 1].length;

            if (A1 <= B1) {
                return 0;
            }

            return 1;
        }

        A = stack[stack_curr - 3].length;
        B = stack[stack_curr - 2].length;
        C = stack[stack_curr - 1].length;

        if ((A <= B + C) || (B <= C)) 
        {
            return 0;
        }

        return 1;
    }

    static void tim_sort_merge(T)(T *dst, 
                                  const tim_sort_run_t *stack, 
                                  const int stack_curr,
                                  ref Vec!T storeBuf,
                                  nogcComparisonFunction!T comparison) 
    {
        const size_t A = stack[stack_curr - 2].length;
        const size_t B = stack[stack_curr - 1].length;
        const size_t curr = stack[stack_curr - 2].start;
        
        size_t i, j, k;

        size_t minSize = (A < B) ? A : B;

        storeBuf.resize( minSize );
        T* storage = storeBuf.ptr;

        /* left merge */
        if (A < B) {
            memcpy(storage, &dst[curr], A * T.sizeof);
            i = 0;
            j = curr + A;

            for (k = curr; k < curr + A + B; k++) {
                if ((i < A) && (j < curr + A + B)) {
                    if (comparison(storage[i], dst[j]) <= 0) {
                        dst[k] = storage[i++];
                    } else {
                        dst[k] = dst[j++];
                    }
                } else if (i < A) {
                    dst[k] = storage[i++];
                } else {
                    break;
                }
            }
        } else {
            /* right merge */
            memcpy(storage, &dst[curr + A], B * T.sizeof);
            i = B;
            j = curr + A;
            k = curr + A + B;

            while (k > curr) {
                k--;
                if ((i > 0) && (j > curr)) {
                    if (comparison(dst[j - 1], storage[i - 1]) > 0) {
                        dst[k] = dst[--j];
                    } else {
                        dst[k] = storage[--i];
                    }
                } else if (i > 0) {
                    dst[k] = storage[--i];
                } else {
                    break;
                }
            }
        }
    }

    static int tim_sort_collapse(T)(T *dst, 
                                    tim_sort_run_t *stack, 
                                    int stack_curr,
                                    ref Vec!T storeBuf,
                                    const size_t size, 
                                    nogcComparisonFunction!T comparison) nothrow @nogc
    {
        while (1) 
        {
            size_t A, B, C, D;
            int ABC, BCD, CD;

            /* if the stack only has one thing on it, we are done with the collapse */
            if (stack_curr <= 1) {
                break;
            }

            /* if this is the last merge, just do it */
            if ((stack_curr == 2) && (stack[0].length + stack[1].length == size)) {
                tim_sort_merge!T(dst, stack, stack_curr, storeBuf, comparison);
                stack[0].length += stack[1].length;
                stack_curr--;
                break;
            }
            /* check if the invariant is off for a stack of 2 elements */
            else if ((stack_curr == 2) && (stack[0].length <= stack[1].length)) {
                tim_sort_merge!T(dst, stack, stack_curr, storeBuf, comparison);
                stack[0].length += stack[1].length;
                stack_curr--;
                break;
            } else if (stack_curr == 2) {
                break;
            }

            B = stack[stack_curr - 3].length;
            C = stack[stack_curr - 2].length;
            D = stack[stack_curr - 1].length;

            if (stack_curr >= 4) {
                A = stack[stack_curr - 4].length;
                ABC = (A <= B + C);
            } else {
                ABC = 0;
            }

            BCD = (B <= C + D) || ABC;
            CD = (C <= D);

            /* Both invariants are good */
            if (!BCD && !CD) {
                break;
            }

            /* left merge */
            if (BCD && !CD) {
                tim_sort_merge!T(dst, stack, stack_curr - 1, storeBuf, comparison);
                stack[stack_curr - 3].length += stack[stack_curr - 2].length;
                stack[stack_curr - 2] = stack[stack_curr - 1];
                stack_curr--;
            } else {
                /* right merge */
                tim_sort_merge!T(dst, stack, stack_curr, storeBuf, comparison);
                stack[stack_curr - 2].length += stack[stack_curr - 1].length;
                stack_curr--;
            }
        }

        return stack_curr;
    }

    static int tim_sort_push_next(T)(T *dst,
                            const size_t size,
                            ref Vec!T storeBuf,
                            const size_t minrun,
                            tim_sort_run_t *run_stack,
                            size_t *stack_curr,
                            size_t *curr,
                            nogcComparisonFunction!T comparison) 
    {
        size_t len = tim_sort_count_run!T(dst, *curr, size, comparison);
        size_t run = minrun;

        if (run > size - *curr) {
            run = size - *curr;
        }

        if (run > len) {
            tim_sort_binary_inversion_sort_start!T(&dst[*curr], len, run, comparison);
            len = run;
        }

        run_stack[*stack_curr].start = *curr;
        run_stack[*stack_curr].length = len;
        (*stack_curr)++;
        *curr += len;

        if (*curr == size) {
            /* finish up */
            while (*stack_curr > 1) {
                tim_sort_merge!T(dst, run_stack, cast(int) *stack_curr, storeBuf, comparison);
                run_stack[*stack_curr - 2].length += run_stack[*stack_curr - 1].length;
                (*stack_curr)--;
            }

            return 0;
        }

        return 1;
    }
}
