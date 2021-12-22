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
import std.array: empty;
import std.exception: assumeUnique;

// This module provides many utilities to deal with @nogc nothrow, in a situation with the runtime disabled.

//
// Faking @nogc
//

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
            memcpy(&slice[i], &uninitialized, T.sizeof);
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
    return assumeUnique(mallocDup!T(slice));
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
    return assumeUnique(stringDup(cstr));
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
// @nogc sorting.
//

/// Must return -1 if a < b
///              0 if a == b
///              1 if a > b
alias nogcComparisonFunction(T) = int delegate(in T a, in T b) nothrow @nogc;

//
// STABLE IN-PLACE SORT (implementation is at bottom of file)
//

void grailSort(T)(T[] inoutElements, nogcComparisonFunction!T comparison) nothrow @nogc
{
    GrailSort!T(inoutElements.ptr, cast(int)(inoutElements.length), comparison);
}

unittest
{
    int[2][] testData = [[110, 0], [5, 0], [10, 0], [3, 0], [110, 1], [5, 1], [10, 1], [3, 1]];
    grailSort!(int[2])(testData, (a, b) => (a[0] - b[0]));
    assert(testData == [[3, 0], [3, 1], [5, 0], [5, 1], [10, 0], [10, 1], [110, 0], [110, 1]]);
}


//
// STABLE MERGE SORT
//

/// Stable merge sort, using a temporary array.
/// Array A[] has the items to sort.
/// Array B[] is a work array.
/// `grailSort` is approx. 30% slower but doesn't need a scratchBuffer.
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

/// To call for something that should never happen, but we still
/// want to make a "best effort" at runtime even if it can be meaningless.
/// MAYDO: change that name, it's not actually unrecoverable
/// MAYDO: stop using that function
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
// GRAIL SORT IMPLEMENTATION BELOW
//
// The MIT License (MIT)
//
// Copyright (c) 2013 Andrey Astrelin
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
// the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

private:

void grail_swap1(T)(T *a,T *b){
    T c=*a;
    *a=*b;
    *b=c;
}
void grail_swapN(T)(T *a,T *b,int n){
    while(n--) grail_swap1(a++,b++);
}
void grail_rotate(T)(T *a,int l1,int l2){
    while(l1 && l2){
        if(l1<=l2){
            grail_swapN(a,a+l1,l1);
            a+=l1; l2-=l1;
        } else{
            grail_swapN(a+(l1-l2),a+l1,l2);
            l1-=l2;
        }
    }
}

int grail_BinSearchLeft(T)(T *arr,int len,T *key, nogcComparisonFunction!T comparison){
    int a=-1,b=len,c;
    while(a<b-1){
        c=a+((b-a)>>1);
        if(comparison(arr[c],*key)>=0) b=c;
        else a=c;
    }
    return b;
}
int grail_BinSearchRight(T)(T *arr,int len,T *key, nogcComparisonFunction!T comparison){
    int a=-1,b=len,c;
    while(a<b-1){
        c=a+((b-a)>>1);
        if(comparison(arr[c],*key)>0) b=c;
        else a=c;
    }
    return b;
}

// cost: 2*len+nk^2/2
int grail_FindKeys(T)(T *arr,int len,int nkeys, nogcComparisonFunction!T comparison){
    int h=1,h0=0;  // first key is always here
    int u=1,r;
    while(u<len && h<nkeys){
        r=grail_BinSearchLeft!T(arr+h0,h,arr+u, comparison);
        if(r==h || comparison(arr[u],arr[h0+r])!=0){
            grail_rotate(arr+h0,h,u-(h0+h));
            h0=u-h;
            grail_rotate(arr+(h0+r),h-r,1);
            h++;
        }
        u++;
    }
    grail_rotate(arr,h0,h);
    return h;
}

// cost: min(L1,L2)^2+max(L1,L2)
void grail_MergeWithoutBuffer(T)(T *arr,int len1,int len2, nogcComparisonFunction!T comparison){
    int h;
    if(len1<len2){
        while(len1){
            h=grail_BinSearchLeft!T(arr+len1,len2,arr, comparison);
            if(h!=0){
                grail_rotate(arr,len1,h);
                arr+=h;
                len2-=h;
            }
            if(len2==0) break;
            do{
                arr++; len1--;
            } while(len1 && comparison(*arr,arr[len1])<=0);
        }
    } else{
        while(len2){
            h=grail_BinSearchRight!T(arr,len1,arr+(len1+len2-1), comparison);
            if(h!=len1){
                grail_rotate(arr+h,len1-h,len2);
                len1=h;
            }
            if(len1==0) break;
            do{
                len2--;
            } while(len2 && comparison(arr[len1-1],arr[len1+len2-1])<=0);
        }
    }
}

// arr[M..-1] - buffer, arr[0,L1-1]++arr[L1,L1+L2-1] -> arr[M,M+L1+L2-1]
void grail_MergeLeft(T)(T *arr,int L1,int L2,int M, nogcComparisonFunction!T comparison){
    int p0=0,p1=L1; L2+=L1;
    while(p1<L2){
        if(p0==L1 || comparison(arr[p0],arr[p1])>0){
            grail_swap1(arr+(M++),arr+(p1++));
        } else{
            grail_swap1(arr+(M++),arr+(p0++));
        }
    }
    if(M!=p0) grail_swapN(arr+M,arr+p0,L1-p0);
}
void grail_MergeRight(T)(T *arr,int L1,int L2,int M, nogcComparisonFunction!T comparison){
    int p0=L1+L2+M-1,p2=L1+L2-1,p1=L1-1;

    while(p1>=0){
        if(p2<L1 || comparison(arr[p1],arr[p2])>0){
            grail_swap1(arr+(p0--),arr+(p1--));
        } else{
            grail_swap1(arr+(p0--),arr+(p2--));
        }
    }
    if(p2!=p0) while(p2>=L1) grail_swap1(arr+(p0--),arr+(p2--));
}

void grail_SmartMergeWithBuffer(T)(T *arr,int *alen1,int *atype,int len2,int lkeys, nogcComparisonFunction!T comparison){
    int p0=-lkeys,p1=0,p2=*alen1,q1=p2,q2=p2+len2;
    int ftype=1-*atype;  // 1 if inverted
    while(p1<q1 && p2<q2){
        if(comparison(arr[p1],arr[p2])-ftype<0) grail_swap1(arr+(p0++),arr+(p1++));
        else grail_swap1(arr+(p0++),arr+(p2++));
    }
    if(p1<q1){
        *alen1=q1-p1;
        while(p1<q1) grail_swap1(arr+(--q1),arr+(--q2));
    } else{
        *alen1=q2-p2;
        *atype=ftype;
    }
}
void grail_SmartMergeWithoutBuffer(T)(T *arr,int *alen1,int *atype,int _len2, nogcComparisonFunction!T comparison){
    int len1,len2,ftype,h;

    if(!_len2) return;
    len1=*alen1;
    len2=_len2;
    ftype=1-*atype;
    if(len1 && comparison(arr[len1-1],arr[len1])-ftype>=0){
        while(len1){
            h=ftype ? grail_BinSearchLeft!T(arr+len1,len2,arr, comparison) : grail_BinSearchRight!T(arr+len1,len2,arr, comparison);
            if(h!=0){
                grail_rotate(arr,len1,h);
                arr+=h;
                len2-=h;
            }
            if(len2==0){
                *alen1=len1;
                return;
            }
            do{
                arr++; len1--;
            } while(len1 && comparison(*arr,arr[len1])-ftype<0);
        }
    }
    *alen1=len2; *atype=ftype;
}

/***** Sort With Extra Buffer *****/

// arr[M..-1] - free, arr[0,L1-1]++arr[L1,L1+L2-1] -> arr[M,M+L1+L2-1]
void grail_MergeLeftWithXBuf(T)(T *arr,int L1,int L2,int M, nogcComparisonFunction!T comparison){
    int p0=0,p1=L1; L2+=L1;
    while(p1<L2){
        if(p0==L1 || comparison(arr[p0],arr[p1])>0) arr[M++]=arr[p1++];
        else arr[M++]=arr[p0++];
    }
    if(M!=p0) while(p0<L1) arr[M++]=arr[p0++];
}

void grail_SmartMergeWithXBuf(T)(T *arr,int *alen1,int *atype,int len2,int lkeys, nogcComparisonFunction!T comparison){
    int p0=-lkeys,p1=0,p2=*alen1,q1=p2,q2=p2+len2;
    int ftype=1-*atype;  // 1 if inverted
    while(p1<q1 && p2<q2){
        if(comparison(arr[p1],arr[p2])-ftype<0) arr[p0++]=arr[p1++];
        else arr[p0++]=arr[p2++];
    }
    if(p1<q1){
        *alen1=q1-p1;
        while(p1<q1) arr[--q2]=arr[--q1];
    } else{
        *alen1=q2-p2;
        *atype=ftype;
    }
}

// arr - starting array. arr[-lblock..-1] - buffer (if havebuf).
// lblock - length of regular blocks. First nblocks are stable sorted by 1st elements and key-coded
// keys - arrays of keys, in same order as blocks. key<midkey means stream A
// nblock2 are regular blocks from stream A. llast is length of last (irregular) block from stream B, that should go before nblock2 blocks.
// llast=0 requires nblock2=0 (no irregular blocks). llast>0, nblock2=0 is possible.
void grail_MergeBuffersLeftWithXBuf(T)(T *keys,T *midkey,T *arr,int nblock,int lblock,int nblock2,int llast, nogcComparisonFunction!T comparison){
    int l,prest,lrest,frest,pidx,cidx,fnext,plast;

    if(nblock==0){
        l=nblock2*lblock;
        grail_MergeLeftWithXBuf!T(arr,l,llast,-lblock, comparison);
        return;
    }

    lrest=lblock;
    frest=comparison(*keys,*midkey)<0 ? 0 : 1;
    pidx=lblock;
    for(cidx=1;cidx<nblock;cidx++,pidx+=lblock){
        prest=pidx-lrest;
        fnext=comparison(keys[cidx],*midkey)<0 ? 0 : 1;
        if(fnext==frest){
            memcpy(arr+prest-lblock,arr+prest,lrest*T.sizeof);
            prest=pidx;
            lrest=lblock;
        } else{
            grail_SmartMergeWithXBuf!T(arr+prest,&lrest,&frest,lblock,lblock, comparison);
        }
    }
    prest=pidx-lrest;
    if(llast){
        plast=pidx+lblock*nblock2;
        if(frest){
            memcpy(arr+prest-lblock,arr+prest,lrest*T.sizeof);
            prest=pidx;
            lrest=lblock*nblock2;
            frest=0;
        } else{
            lrest+=lblock*nblock2;
        }
        grail_MergeLeftWithXBuf!T(arr+prest,lrest,llast,-lblock, comparison);
    } else{
        memcpy(arr+prest-lblock,arr+prest,lrest*T.sizeof);
    }
}

/***** End Sort With Extra Buffer *****/

// build blocks of length K
// input: [-K,-1] elements are buffer
// output: first K elements are buffer, blocks 2*K and last subblock sorted
void grail_BuildBlocks(T)(T *arr,int L,int K,T *extbuf,int LExtBuf, nogcComparisonFunction!T comparison){
    int m,u,h,p0,p1,rest,restk,p,kbuf;
    kbuf=K<LExtBuf ? K : LExtBuf;
    while(kbuf&(kbuf-1)) kbuf&=kbuf-1;  // max power or 2 - just in case

    if(kbuf){
        memcpy(extbuf,arr-kbuf,kbuf*T.sizeof);
        for(m=1;m<L;m+=2){
            u=0;
            if(comparison(arr[m-1],arr[m])>0) u=1;
            arr[m-3]=arr[m-1+u];
            arr[m-2]=arr[m-u];
        }
        if(L%2) arr[L-3]=arr[L-1];
        arr-=2;
        for(h=2;h<kbuf;h*=2){
            p0=0;
            p1=L-2*h;
            while(p0<=p1){
                grail_MergeLeftWithXBuf!T(arr+p0,h,h,-h, comparison);
                p0+=2*h;
            }
            rest=L-p0;
            if(rest>h){
                grail_MergeLeftWithXBuf!T(arr+p0,h,rest-h,-h, comparison);
            } else {
                for(;p0<L;p0++) arr[p0-h]=arr[p0];
            }
            arr-=h;
        }
        memcpy(arr+L,extbuf,kbuf*T.sizeof);
    } else{
        for(m=1;m<L;m+=2){
            u=0;
            if(comparison(arr[m-1],arr[m])>0) u=1;
            grail_swap1(arr+(m-3),arr+(m-1+u));
            grail_swap1(arr+(m-2),arr+(m-u));
        }
        if(L%2) grail_swap1(arr+(L-1),arr+(L-3));
        arr-=2;
        h=2;
    }
    for(;h<K;h*=2){
        p0=0;
        p1=L-2*h;
        while(p0<=p1){
            grail_MergeLeft!T(arr+p0,h,h,-h, comparison);
            p0+=2*h;
        }
        rest=L-p0;
        if(rest>h){
            grail_MergeLeft!T(arr+p0,h,rest-h,-h, comparison);
        } else grail_rotate(arr+p0-h,h,rest);
        arr-=h;
    }
    restk=L%(2*K);
    p=L-restk;
    if(restk<=K) grail_rotate(arr+p,restk,K);
    else grail_MergeRight!T(arr+p,K,restk-K,K, comparison);
    while(p>0){
        p-=2*K;
        grail_MergeRight!T(arr+p,K,K,K, comparison);
    }
}

// arr - starting array. arr[-lblock..-1] - buffer (if havebuf).
// lblock - length of regular blocks. First nblocks are stable sorted by 1st elements and key-coded
// keys - arrays of keys, in same order as blocks. key<midkey means stream A
// nblock2 are regular blocks from stream A. llast is length of last (irregular) block from stream B, that should go before nblock2 blocks.
// llast=0 requires nblock2=0 (no irregular blocks). llast>0, nblock2=0 is possible.
void grail_MergeBuffersLeft(T)(T *keys,T *midkey,T *arr,int nblock,int lblock,bool havebuf,int nblock2,int llast, nogcComparisonFunction!T comparison){
    int l,prest,lrest,frest,pidx,cidx,fnext,plast;

    if(nblock==0){
        l=nblock2*lblock;
        if(havebuf) grail_MergeLeft!T(arr,l,llast,-lblock, comparison);
        else grail_MergeWithoutBuffer!T(arr,l,llast, comparison);
        return;
    }

    lrest=lblock;
    frest=comparison(*keys,*midkey)<0 ? 0 : 1;
    pidx=lblock;
    for(cidx=1;cidx<nblock;cidx++,pidx+=lblock){
        prest=pidx-lrest;
        fnext=comparison(keys[cidx],*midkey)<0 ? 0 : 1;
        if(fnext==frest){
            if(havebuf) grail_swapN(arr+prest-lblock,arr+prest,lrest);
            prest=pidx;
            lrest=lblock;
        } else{
            if(havebuf){
                grail_SmartMergeWithBuffer!T(arr+prest,&lrest,&frest,lblock,lblock, comparison);
            } else{
                grail_SmartMergeWithoutBuffer!T(arr+prest,&lrest,&frest,lblock, comparison);
            }

        }
    }
    prest=pidx-lrest;
    if(llast){
        plast=pidx+lblock*nblock2;
        if(frest){
            if(havebuf) grail_swapN(arr+prest-lblock,arr+prest,lrest);
            prest=pidx;
            lrest=lblock*nblock2;
            frest=0;
        } else{
            lrest+=lblock*nblock2;
        }
        if(havebuf) grail_MergeLeft!T(arr+prest,lrest,llast,-lblock, comparison);
        else grail_MergeWithoutBuffer!T(arr+prest,lrest,llast, comparison);
    } else{
        if(havebuf) grail_swapN(arr+prest,arr+(prest-lblock),lrest);
    }
}

void grail_SortIns(T)(T *arr,int len, nogcComparisonFunction!T comparison){
    int i,j;
    for(i=1;i<len;i++){
        for(j=i-1;j>=0 && comparison(arr[j+1],arr[j])<0;j--) grail_swap1(arr+j,arr+(j+1));
    }
}

void grail_LazyStableSort(T)(T *arr,int L, nogcComparisonFunction!T comparison){
    int m,u,h,p0,p1,rest;
    for(m=1;m<L;m+=2){
        u=0;
        if(comparison(arr[m-1],arr[m])>0) grail_swap1(arr+(m-1),arr+m);
    }
    for(h=2;h<L;h*=2){
        p0=0;
        p1=L-2*h;
        while(p0<=p1){
            grail_MergeWithoutBuffer!T(arr+p0,h,h, comparison);
            p0+=2*h;
        }
        rest=L-p0;
        if(rest>h) grail_MergeWithoutBuffer!T(arr+p0,h,rest-h, comparison);
    }
}

// keys are on the left of arr. Blocks of length LL combined. We'll combine them in pairs
// LL and nkeys are powers of 2. (2*LL/lblock) keys are guarantied
void grail_CombineBlocks(T)(T *keys,T *arr,int len,int LL,int lblock,bool havebuf,T *xbuf, nogcComparisonFunction!T comparison){
    int M,nkeys,b,NBlk,midkey,lrest,u,p,v,kc,nbl2,llast;
    T *arr1;

    M=len/(2*LL);
    lrest=len%(2*LL);
    nkeys=(2*LL)/lblock;
    if(lrest<=LL){
        len-=lrest;
        lrest=0;
    }
    if(xbuf) memcpy(xbuf,arr-lblock,lblock*T.sizeof);
    for(b=0;b<=M;b++){
        if(b==M && lrest==0) break;
        arr1=arr+b*2*LL;
        NBlk=(b==M ? lrest : 2*LL)/lblock;
        grail_SortIns!T(keys,NBlk+(b==M ? 1 : 0), comparison);
        midkey=LL/lblock;
        for(u=1;u<NBlk;u++){
            p=u-1;
            for(v=u;v<NBlk;v++){
                kc=comparison(arr1[p*lblock],arr1[v*lblock]);
                if(kc>0 || (kc==0 && comparison(keys[p],keys[v])>0)) p=v;
            }
            if(p!=u-1){
                grail_swapN(arr1+(u-1)*lblock,arr1+p*lblock,lblock);
                grail_swap1(keys+(u-1),keys+p);
                if(midkey==u-1 || midkey==p) midkey^=(u-1)^p;
            }
        }
        nbl2=llast=0;
        if(b==M) llast=lrest%lblock;
        if(llast!=0){
            while(nbl2<NBlk && comparison(arr1[NBlk*lblock],arr1[(NBlk-nbl2-1)*lblock])<0) nbl2++;
        }
        if(xbuf) grail_MergeBuffersLeftWithXBuf!T(keys,keys+midkey,arr1,NBlk-nbl2,lblock,nbl2,llast, comparison);
        else grail_MergeBuffersLeft!T(keys,keys+midkey,arr1,NBlk-nbl2,lblock,havebuf,nbl2,llast, comparison);
    }
    if(xbuf){
        for(p=len;--p>=0;) arr[p]=arr[p-lblock];
        memcpy(arr-lblock,xbuf,lblock*T.sizeof);
    }else if(havebuf) while(--len>=0) grail_swap1(arr+len,arr+len-lblock);
}


void grail_commonSort(T)(T *arr,int Len,T *extbuf,int LExtBuf, nogcComparisonFunction!T comparison){
    int lblock,nkeys,findkeys,ptr,cbuf,lb,nk;
    bool havebuf,chavebuf;
    long s;

    if(Len<16){
        grail_SortIns!T(arr,Len, comparison);
        return;
    }

    lblock=1;
    while(lblock*lblock<Len) lblock*=2;
    nkeys=(Len-1)/lblock+1;
    findkeys=grail_FindKeys!T(arr,Len,nkeys+lblock, comparison);
    havebuf=true;
    if(findkeys<nkeys+lblock){
        if(findkeys<4){
            grail_LazyStableSort!T(arr,Len, comparison);
            return;
        }
        nkeys=lblock;
        while(nkeys>findkeys) nkeys/=2;
        havebuf=false;
        lblock=0;
    }
    ptr=lblock+nkeys;
    cbuf=havebuf ? lblock : nkeys;
    if(havebuf) grail_BuildBlocks!T(arr+ptr,Len-ptr,cbuf,extbuf,LExtBuf, comparison);
    else grail_BuildBlocks!T(arr+ptr,Len-ptr,cbuf,null,0, comparison);

    // 2*cbuf are built
    while(Len-ptr>(cbuf*=2)){
        lb=lblock;
        chavebuf=havebuf;
        if(!havebuf){
            if(nkeys>4 && nkeys/8*nkeys>=cbuf){
                lb=nkeys/2;
                chavebuf=true;
            } else{
                nk=1;
                s=cast(long)cbuf*findkeys/2;
                while(nk<nkeys && s!=0){
                    nk*=2; s/=8;
                }
                lb=(2*cbuf)/nk;
            }
        }
        grail_CombineBlocks!T(arr,arr+ptr,Len-ptr,cbuf,lb,chavebuf,chavebuf && lb<=LExtBuf ? extbuf : null, comparison);
    }
    grail_SortIns!T(arr,ptr, comparison);
    grail_MergeWithoutBuffer!T(arr,ptr,Len-ptr, comparison);
}

void GrailSort(T)(T *arr, int Len, nogcComparisonFunction!T comparison){
    grail_commonSort!T(arr,Len,null,0, comparison);
}

void GrailSortWithBuffer(T)(T *arr,int Len, nogcComparisonFunction!T comparison){
    T[128] ExtBuf;
    grail_commonSort!T(arr,Len,ExtBuf.ptr,128, comparison);
}

/****** classic MergeInPlace *************/

void grail_RecMerge(T)(T *A,int L1,int L2, nogcComparisonFunction!T comparison){
    int K,k1,k2,m1,m2;
    if(L1<3 || L2<3){
        grail_MergeWithoutBuffer(A,L1,L2); return;
    }
    if(L1<L2) K=L1+L2/2;
    else K=L1/2;
    k1=k2=grail_BinSearchLeft(A,L1,A+K);
    if(k2<L1 && comparison(A+k2,A+K)==0) k2=grail_BinSearchRight(A+k1,L1-k1,A+K)+k1;
    m1=grail_BinSearchLeft(A+L1,L2,A+K);
    m2=m1;
    if(m2<L2 && comparison(A+L1+m2,A+K)==0) m2=grail_BinSearchRight(A+L1+m1,L2-m1,A+K)+m1;
    if(k1==k2) grail_rotate(A+k2,L1-k2,m2);
    else{
        grail_rotate(A+k1,L1-k1,m1);
        if(m2!=m1) grail_rotate(A+(k2+m1),L1-k2,m2-m1);
    }
    grail_RecMerge(A+(k2+m2),L1-k2,L2-m2);
    grail_RecMerge(A,k1,m1);
}
void RecStableSort(T)(T *arr,int L){
    int u,m,h,p0,p1,rest;

    for(m=1;m<L;m+=2){
        u=0;
        if(comparison(arr+m-1,arr+m)>0) grail_swap1(arr+(m-1),arr+m);
    }
    for(h=2;h<L;h*=2){
        p0=0;
        p1=L-2*h;
        while(p0<=p1){
            grail_RecMerge(arr+p0,h,h);
            p0+=2*h;
        }
        rest=L-p0;
        if(rest>h) grail_RecMerge(arr+p0,h,rest-h);
    }
}
