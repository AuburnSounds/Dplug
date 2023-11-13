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

// This module provides many utilities to deal with @nogc nothrow, in a situation with the runtime 
// disabled.

//
// Faking @nogc
//

version(Windows)
{
    import core.sys.windows.winbase;
}

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
/// Note: The zero-terminating byte is preserved. This allow to have a string which also can be 
/// converted to a C string with `.ptr`. However the zero byte is not included in slice length.
char[] stringDup(const(char)* cstr) nothrow @nogc
{
    assert(cstr !is null);
    size_t len = strlen(cstr);
    char* copy = strdup(cstr);
    return copy[0..len];
}

/// Duplicates a zero-terminated string with `malloc`, return a `string`. with zero-terminated 
/// byte. Has to be cleaned-up with `free(s.ptr)`.
///
/// Note: The zero-terminating byte is preserved. This allow to have a string which also can be 
/// converted to a C string with `.ptr`. However the zero byte is not included in slice length.
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
    // This is a complete hack to be able to build in Ubuntu Focal, which distributes D front-ends 
    // based upon DMDFE 2.090. In these compilers, va_start is not marked @nogc.
    static if (__VERSION__ > 2090)
    {
        import core.stdc.stdio;

        char[256] buffer;
        va_list args;
        va_start (args, fmt);
        vsnprintf (buffer.ptr, 256, fmt, args);
        va_end (args);

        version(Windows)
        {
            OutputDebugStringA(buffer.ptr);
        }
        else
        {        
            printf("%s\n", buffer.ptr);
        }
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
        ShellExecuteA(null, CString("open").storage, CString(url).storage, null, null, 
                      SW_SHOWNORMAL);
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

        if (!tim_sort_push_next!T(dst.ptr, size, storeBuf, minrun, run_stack.ptr, &stack_curr, 
                                  &curr, comparison)) 
        {
            return;
        }

        if (!tim_sort_push_next!T(dst.ptr, size, storeBuf, minrun, run_stack.ptr, &stack_curr, 
                                  &curr, comparison)) 
        {
            return;
        }

        if (!tim_sort_push_next!T(dst.ptr, size, storeBuf, minrun, run_stack.ptr, &stack_curr, 
                                  &curr, comparison)) 
        {
            return;
        }

        while (1) {
            if (!tim_sort_check_invariant(run_stack.ptr, cast(int)stack_curr)) {
                stack_curr = tim_sort_collapse!T(dst.ptr, run_stack.ptr, cast(int)stack_curr, 
                                                 storeBuf, size, comparison);
                continue;
            }

            if (!tim_sort_push_next!T(dst.ptr, size, storeBuf, minrun, run_stack.ptr, &stack_curr, 
                                      &curr, comparison)) {
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
    size_t tim_sort_binary_inversion_find(T)(T *dst, const T x, const size_t size, 
                                             nogcComparisonFunction!T comparison) nothrow @nogc
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

    // Binary insertion sort, but knowing that the first "start" entries are sorted.
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


/**
$(H1 @nogc Simple Base64 parsing)

License: $(HTTP www.apache.org/licenses/LICENSE-2.0, Apache-2.0)
Authors: Harrison Ford
Copyright: 2021 Harrison Ford, Symmetry Investments, 2023 Guillaume Piolat
*/
// this is from mir.base64 but a bit stripped down.

private
{

    // NOTE: I do not know if this would work on big-endian systems.
    // Needs further testing to figure out if it *does* work on them.

    // Technique borrowed from:
    // http://0x80.pl/notesen/2016-01-12-sse-base64-encoding.html#branchless-code-for-lookup-table
    ubyte lookup_encoding(ubyte i, char plusChar = '+', char slashChar = '/') 
        pure nothrow @nogc @safe
    {
        assert(i < 64);

        ubyte shift;

        if (i < 26)
        {
            // range A-Z
            shift = 'A';
        }
        else if (i >= 26 && i < 52)
        {
            // range a-z
            shift = 'a' - 26;
        }
        else if (i >= 52 && i < 62)
        {
            // range 0-9
            shift = cast(ubyte)('0' - 52);
        }
        else if (i == 62)
        {
            // character plus
            shift = cast(ubyte)(plusChar - 62);
        }
        else if (i == 63)
        {
            // character slash
            shift = cast(ubyte)(slashChar - 63);
        }

        return cast(char)(i + shift);
    }

    // Do the inverse of above (convert an ASCII value into the Base64 character set)
    ubyte lookup_decoding(ubyte i, char plusChar, char slashChar, bool* err)
        pure nothrow @nogc @safe
    {
        *err = false;
        // Branching bad, but this isn't performance sensitive
        if (i <= 'Z' && i >= 'A') {
            return cast(ubyte)(i - 'A');
        }
        else if (i <= 'z' && i >= 'a') {
            return cast(ubyte)(i - 'a' + 26); 
        }
        else if (i <= '9' && i >= '0') {
            return cast(ubyte)(i - '0' + 52);
        }
        else if (i == plusChar) {
            return 62;
        }
        else if (i == slashChar) {
            return 63;
        }
        // Just return 0 for padding,
        // as it typically means nothing.
        else if (i == '=') {
            return 0;
        }
        else 
        {
            *err = true;
            return 0;
        }
    }
}

/// Decode a Base64 encoded value, returning a buffer to be freed with free().
/// `null` in case of error or zero size.
ubyte[] decodeBase64(scope const(ubyte)[] data, char plusChar = '+', char slashChar = '/') 
    nothrow @nogc @system
{
    Vec!ubyte outBuffer;
    bool err;
    decodeBase64(data, outBuffer, plusChar, slashChar, &err);
    if (err)
        return null;
    return outBuffer.releaseData;
}
///ditto
ubyte[] decodeBase64(scope const(char)[] data, char plusChar = '+', char slashChar = '/') 
    nothrow @nogc @system
{
    return decodeBase64(cast(const(ubyte)[])data, plusChar, slashChar);
}

/// Decode a Base64 encoded value, appending the result onto a `Vec!ubyte`.
/// Reusing the same `Vec!ubyte` allows you to avoid reallocations.
/// Note: `err` must point to a `bool` and cannot be null. Ugly signature sorry.
void decodeBase64(scope const(ubyte)[] data,
                  ref Vec!ubyte outBuffer,
                  char plusChar,  // typically: '+'
                  char slashChar, // typically: '/'
                  bool* err) nothrow @nogc @safe
{
    outBuffer.clearContents();
    *err = false;
    // We expect data should be well-formed (with padding),
    // so we should throw if it is not well-formed.
    if (data.length % 4 != 0)
    {
        *err = true;
        return;
    }

    ubyte[3] decodedByteGroup;
    ubyte sz = 0;

    for (size_t i = 0; i < data.length; i += 4)
    {
        scope const(ubyte)[] group = data[i .. (i + 4)];

        ubyte[4] decodedBytes;
        decodedBytes[0] = lookup_decoding(group[0], plusChar, slashChar, err); if (*err) return;
        decodedBytes[1] = lookup_decoding(group[1], plusChar, slashChar, err); if (*err) return;

        uint transformed_group = (decodedBytes[0] << 26) | (decodedBytes[1] << 20);

        // According to RFC4648 Section 3.3, we don't have to accept extra padding characters,
        // and we can safely throw (and stay within spec).
        // x=== is also invalid, so we can just throw on that here.
        if (group[0] == '=' || group[1] == '=')
        {
            *err = true;
            return;
        }

        // xx=(=)?
        if (group[2] == '=')
        {
            // If we are not at the end of a string, according to RFC4648,
            // we can safely treat a padding character as "non-alphabet data",
            // and as such, we should throw. See RFC4648 Section 3.3 for more information
            if ((i / 4) != ((data.length / 4) - 1))
            {
                *err = true;
                return;
            }

            if (group[3] == '=')
            {
                // xx==
                sz = 1;
            }
            // xx=x (invalid)
            // Padding should not be in the middle of a chunk
            else
            {
                *err = true;
                return;
            }
        }
        // xxx=
        else if (group[3] == '=')
        {
            // If we are not at the end of a string, according to RFC4648,
            // we can safely treat a padding character as "non-alphabet data",
            // and as such, we should throw. See RFC4648 Section 3.3 for more information
            if ((i / 4) != ((data.length / 4) - 1))
            {
                *err = true;
                return;
            }

            decodedBytes[2] = lookup_decoding(group[2], plusChar, slashChar, err); if (*err) return;
            transformed_group |= (decodedBytes[2] << 14);
            sz = 2;
        }
        // xxxx
        else 
        {
            decodedBytes[2] = lookup_decoding(group[2], plusChar, slashChar, err); if (*err) return;
            decodedBytes[3] = lookup_decoding(group[3], plusChar, slashChar, err); if (*err) return;
            transformed_group |= ((decodedBytes[2] << 14) | (decodedBytes[3] << 8)); 
            sz = 3;
        }

        decodedByteGroup[0] = (transformed_group >> 24) & 0xff;
        decodedByteGroup[1] = (transformed_group >> 16) & 0xff;
        decodedByteGroup[2] = (transformed_group >> 8) & 0xff;

        // Only emit the transformed bytes that we got data for. 
        outBuffer.pushBack(decodedByteGroup[0 .. sz]);
    }
}

/// Test decoding of data which has a length which can be
/// cleanly decoded.
@trusted unittest
{   
    // Note: the decoded strings are leaked in this test.
    assert("QUJD".decodeBase64 == "ABC");
    assert("QQ==".decodeBase64 == "A");
    assert("YSBiIGMgZCBlIGYgZyBoIGkgaiBrIGwgbSBuIG8gcCBxIHIgcyB0IHUgdiB3IHggeSB6".decodeBase64 
           == "a b c d e f g h i j k l m n o p q r s t u v w x y z");
    assert("LCAuIDsgLyBbICcgXSBcID0gLSAwIDkgOCA3IDYgNSA0IDMgMiAxIGAgfiAhIEAgIyAkICUgXiAmICogKCApIF8gKyB8IDogPCA+ID8="
           .decodeBase64 == ", . ; / [ ' ] \\ = - 0 9 8 7 6 5 4 3 2 1 ` ~ ! @ # $ % ^ & * ( ) _ + | : < > ?");
    assert("AAA=".decodeBase64 == "\x00\x00");
    assert("AAAABBCC".decodeBase64 == "\x00\x00\x00\x04\x10\x82");
    assert("AA==".decodeBase64 == "\x00");
    assert("AA/=".decodeBase64 == "\x00\x0f");
}

/// Test decoding invalid data
@trusted unittest
{
    void testFail(const(char)[] input) @trusted
    {
        ubyte[] decoded = input.decodeBase64;
        assert(decoded is null);
        free(decoded.ptr);
    }

    testFail("===A");
    testFail("A=");
    testFail("AA=");
    testFail("A=AA");
    testFail("AA=A");
    testFail("AA=A====");
    testFail("=AAA");
    testFail("AAA=QUJD");
    // This fails because we don't allow extra padding (than what is necessary)
    testFail("AA======");
    // This fails because we don't allow padding before the end of the string (otherwise we'd 
    // have a side-channel)
    testFail("QU==QUJD");
    testFail("QU======QUJD");
    // Invalid data that's out of the alphabet
    testFail("!@##@@!@");
}


/// Encode a ubyte array as Base64, returning the encoded value, which shall be destroyed with 
/// `free`.
ubyte[] encodeBase64(scope const(ubyte)[] buf, char plusChar = '+', char slashChar = '/') 
    nothrow @nogc @system
{
    Vec!ubyte outBuf;
    encodeBase64(buf, outBuf, plusChar, slashChar);
    return outBuf.releaseData;
}

/// Encode a ubyte array as Base64, placing the result onto an `Vec!ubyte`.
void encodeBase64(scope const(ubyte)[] input,
                  scope ref Vec!ubyte outBuf,
                  char plusChar = '+',
                  char slashChar = '/') nothrow @nogc @trusted
{
    outBuf.clearContents();

    // Slice our input array so that n % 3 == 0 (we have a multiple of 3) 
    // If we have less then 3, then this is effectively a no-op (will result in a 0-length slice)
    ubyte[4] encodedByteGroup;
    const(ubyte)[] window = input[0 .. input.length - (input.length % 3)];
    assert((window.length % 3) == 0);

    for (size_t n = 0; n < window.length; n += 3)
    {
        uint group = (window[n] << 24) | (window[n+1] << 16) | (window[n+2] << 8);
        const(ubyte) a = (group >> 26) & 0x3f;
        const(ubyte) b = (group >> 20) & 0x3f;
        const(ubyte) c = (group >> 14) & 0x3f;
        const(ubyte) d = (group >> 8) & 0x3f;
        encodedByteGroup[0] = a.lookup_encoding(plusChar, slashChar);
        encodedByteGroup[1] = b.lookup_encoding(plusChar, slashChar);
        encodedByteGroup[2] = c.lookup_encoding(plusChar, slashChar);
        encodedByteGroup[3] = d.lookup_encoding(plusChar, slashChar);
        outBuf.pushBack(encodedByteGroup[]);
    }

    // If it's a clean multiple of 3, then it requires no padding.
    // If not, then we need to add padding.
    if (input.length % 3 != 0)
    {
        window = input[window.length .. input.length];

        uint group = (window[0] << 24);

        if (window.length == 1) {
            const(ubyte) a = (group >> 26) & 0x3f;
            const(ubyte) b = (group >> 20) & 0x3f;
            encodedByteGroup[0] = a.lookup_encoding(plusChar, slashChar);
            encodedByteGroup[1] = b.lookup_encoding(plusChar, slashChar);
            encodedByteGroup[2] = '=';
            encodedByteGroup[3] = '=';
        }
        else 
        {
            // Just in case 
            assert(window.length == 2);

            group |= (window[1] << 16);
            const(ubyte) a = (group >> 26) & 0x3f;
            const(ubyte) b = (group >> 20) & 0x3f;
            const(ubyte) c = (group >> 14) & 0x3f;
            encodedByteGroup[0] = a.lookup_encoding(plusChar, slashChar);
            encodedByteGroup[1] = b.lookup_encoding(plusChar, slashChar);
            encodedByteGroup[2] = c.lookup_encoding(plusChar, slashChar);
            encodedByteGroup[3] = '=';
        }

        outBuf.pushBack(encodedByteGroup[]);
    }
}

@trusted unittest
{
    // Note: encoded data leaked there.
    // 3 bytes
    {
        enum data = cast(immutable(ubyte)[])"ABC";
        assert(data.encodeBase64 == "QUJD");
    }

    // 6 bytes
    {
        enum data = cast(immutable(ubyte)[])"ABCDEF";
        assert(data.encodeBase64 == "QUJDREVG");
    }

    // 9 bytes
    {
        enum data = cast(immutable(ubyte)[])"ABCDEFGHI";
        assert(data.encodeBase64 == "QUJDREVGR0hJ");
    }

    // 12 bytes
    {
        enum data = cast(immutable(ubyte)[])"ABCDEFGHIJKL";
        assert(data.encodeBase64 == "QUJDREVGR0hJSktM");
    }
}

/// Test encoding of data which has a length which CANNOT be cleanly encoded.
/// This typically means that there's padding.
@trusted unittest
{
    // Note: encoded data leaked there.
    // 1 byte 
    {
        enum data = cast(immutable(ubyte)[])"A";
        assert(data.encodeBase64 == "QQ==");
    }
    // 2 bytes
    {
        enum data = cast(immutable(ubyte)[])"AB";
        assert(data.encodeBase64 == "QUI=");
    }
    // 2 bytes
    {
        enum data = [0xFF, 0xFF];
        assert(data.encodeBase64 == "//8=");
    }
    // 4 bytes
    {
        enum data = [0xDE, 0xAD, 0xBA, 0xBE];
        assert(data.encodeBase64 == "3q26vg==");
    }
    // 37 bytes
    {
        enum data = cast(immutable(ubyte)[])"A Very Very Very Very Large Test Blob";
        assert(data.encodeBase64 == "QSBWZXJ5IFZlcnkgVmVyeSBWZXJ5IExhcmdlIFRlc3QgQmxvYg==");
    }
}

/// Test nogc encoding
@trusted unittest
{
    {
        
        enum data = cast(immutable(ubyte)[])"A Very Very Very Very Large Test Blob";
        Vec!ubyte outBuf;
        data.encodeBase64(outBuf); 
        assert(outBuf[] == "QSBWZXJ5IFZlcnkgVmVyeSBWZXJ5IExhcmdlIFRlc3QgQmxvYg==");     
    }

    {
        enum data = cast(immutable(ubyte)[])"abc123!?$*&()'-=@~";
        Vec!ubyte outBuf;
        data.encodeBase64(outBuf);
        assert(outBuf[] == "YWJjMTIzIT8kKiYoKSctPUB+");
    }
}

/// Make sure we can decode what we encode.
@trusted unittest
{
    // Test an example string
    {
        enum data = cast(immutable(ubyte)[])"abc123!?$*&()'-=@~";
        assert(data.encodeBase64.decodeBase64 == data);
    }
    // Test an example from Ion data
    {
        enum data = cast(immutable(ubyte)[])"a b c d e f g h i j k l m n o p q r s t u v w x y z";
        assert(data.encodeBase64.decodeBase64 == data);
    }
}