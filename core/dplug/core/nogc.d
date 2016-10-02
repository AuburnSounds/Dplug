/**
* Copyright: Copyright Auburn Sounds 2015-2016
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.core.nogc;

// This module provides many utilities to deal with @nogc





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

/// Use throughout dplug:dsp to avoid reliance on GC.
/// This works like alignedRealloc except with slices as input.
///
/// Params:
///    buffer Existing allocated buffer. Can be null. Input slice length is not considered.
///    length desired slice length
///
void reallocBuffer(T)(ref T[] buffer, size_t length, int alignment = 16) nothrow @nogc
{
    import gfm.core.memory : alignedRealloc;

    T* pointer = cast(T*) alignedRealloc(buffer.ptr, T.sizeof * length, alignment);
    if (pointer is null)
        buffer = null;
    else
        buffer = pointer[0..length];
}

/// A bit faster than a dynamic cast.
/// This is to avoid TypeInfo look-up
T unsafeObjectCast(T)(Object obj)
{
    return cast(T)(cast(void*)(obj));
}
