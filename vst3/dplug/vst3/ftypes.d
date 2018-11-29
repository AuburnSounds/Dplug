//-----------------------------------------------------------------------------
// Project     : SDK Core
//
// Category    : SDK Core Interfaces
// Filename    : pluginterfaces/base/ftypes.h
// Filename    : pluginterfaces/base/fplatform.h
// Filename    : pluginterfaces/base/funknown.h
// Filename    : pluginterfaces/base/fstrdefs.h
// Created by  : Steinberg, 01/2004
// Description : Basic data types
//
//-----------------------------------------------------------------------------
// This file is part of a Steinberg SDK. It is subject to the license terms
// in the LICENSE file found in the top-level directory of this distribution
// and at www.steinberg.net/sdklicenses. 
// No part of the SDK, including this file, may be copied, modified, propagated,
// or distributed except according to the terms contained in the LICENSE file.
//-----------------------------------------------------------------------------

module dplug.vst3.ftypes;

enum UNICODE = 1;

import core.stdc.stdint;

nothrow:
@nogc:

alias int8 = byte;
alias uint8 = ubyte;
alias uchar = char;
alias int16 = short;
alias uint16 = ushort;
alias int32 = int;
alias uint32 = uint;

enum int32 kMaxLong = int.max;
enum int32 kMinLong = int.min;
enum int32 kMaxInt32 = kMaxLong;
enum int32 kMinInt32 = kMinLong;

deprecated enum uint32 kMaxInt32u = uint.max;

alias int64 = long;
alias uint64 = ulong;
enum int64 kMaxInt64 = long.max;
enum int64 kMinInt64 = long.min;
enum uint64 kMinInt64u = ulong.max;

alias TSize = int64;
alias tresult = int32;

deprecated enum float kMaxFloat = 3.40282346638528860E38;
deprecated enum double kMaxDouble = 1.7976931348623158E308;

alias TPtrInt = size_t;

alias TBool = uint8;

alias char8 = char;
alias char16 = wchar;
alias tchar = char16;

alias CStringA = const(char8)*;
alias CStringW = const(char16)*;
//alias CString = const(tchar)*;

bool strEmpty (const(tchar)* str) 
{ 
    return (!str || *str == '\0'); 
}

bool str8Empty (const(char8)* str) 
{
    return (!str || *str == '\0'); 
}

bool str16Empty (const(char16)* str) 
{
    return (!str || *str == '\0'); 
}

alias FIDString = const(char8)*; // identifier as string (used for attributes, messages)


// vsttypes.h


static immutable string kVstVersionString = "VST 3.6.11";


alias TChar = char16;           ///< UTF-16 character
alias String128 = TChar[128];   ///< 128 character UTF-16 string

// This conflicts with dplug.core.nogc.CString
//alias CString = const(char8)* ;   ///< C-String

//------------------------------------------------------------------------
// General
//------------------------------------------------------------------------
alias MediaType = int; ///< media type (audio/event)

alias BusDirection = int; ///< bus direction (in/out)

alias BusType = int32;          ///< bus type (main/aux)
alias IoMode = int32;           ///< I/O mode (see \ref vst3IoMode)
alias UnitID = int32;           ///< unit identifier
alias ParamValue = double;      ///< parameter value type
alias ParamID = uint32;         ///< parameter identifier
alias ProgramListID = int32;    ///< program list identifier
alias CtrlNumber = int16;       ///< MIDI controller number (see \ref ControllerNumbers for allowed values)

alias TQuarterNotes = double;   ///< time expressed in quarter notes
alias TSamples = int64;         ///< time expressed in audio samples

alias ColorSpec = uint32;       ///< color defining by 4 component ARGB value (Alpha/Red/Green/Blue)

//------------------------------------------------------------------------
static const ParamID kNoParamId = 0xffffffff;   ///< default for uninitialized parameter ID


//------------------------------------------------------------------------
// Audio Types
//------------------------------------------------------------------------
alias Sample32 = float;             ///< 32-bit precision audio sample
alias Sample64 = double;            ///< 64-bit precision audio sample

alias SampleRate = double; ///< sample rate


//------------------------------------------------------------------------
// Speaker Arrangements Types
//------------------------------------------------------------------------
alias SpeakerArrangement = uint64 ; ///< Bitset of speakers
alias Speaker = uint64 ; ///< Bit for one speaker

//------------------------------------------------------------------------
/** Returns number of channels used in speaker arrangement.
\ingroup speakerArrangements */
/*@{*/
int getChannelCount(SpeakerArrangement arr) pure nothrow @nogc
{
	int count = 0;
	while (arr)
	{
		if (arr & 1)
			++count;
		arr >>= 1;
	}
	return count;
}

SpeakerArrangement getSpeakerArrangement(int numChannels) pure nothrow @nogc
{
    // 0 => 0, 1 => 1, 2 => 3, 3 => 7...
    if (numChannels == 0)
        return 0;
    int arr = 1;
    for (int i = 1; i < numChannels; ++i)
    {
        arr = (arr << 1) | 1;
    }
    return arr;
}


deprecated enum kLittleEndian = 0;
deprecated enum kBigEndian = 1;

version(Windows)
{
    enum COM_COMPATIBLE = 1;
}
else
{
    enum COM_COMPATIBLE = 0;
}

// vststructsizecheck.h

// necessary because D doesn't have the equivalent of #pragma(pack)

template SMTG_TYPE_SIZE_CHECK(T, size_t Platform64Size, size_t MacOS32Size, size_t Win32Size)
{
    enum size = T.sizeof;
    static if ((void*).sizeof == 8)
    {
        // 64-bit
        static assert(size == Platform64Size, "bad size for " ~ T.stringof);
    }
    else version(OSX)
    {
        // OSX 32-bit
        static assert(size == MacOS32Size, "bad size for " ~ T.stringof);
    }
    else version(Windows)
    {        
        // Windows 32-bit
        static assert(size == Win32Size, "bad size for " ~ T.stringof);
    }
}


// funknown.h

static if (COM_COMPATIBLE)
{
    TUID INLINE_UID(uint l1, uint l2, uint l3, uint l4) pure @safe
    {
        return 
        [
            cast(byte)((l1 & 0x000000FF)      ), cast(byte)((l1 & 0x0000FF00) >>  8),
            cast(byte)((l1 & 0x00FF0000) >> 16), cast(byte)((l1 & 0xFF000000) >> 24),
            cast(byte)((l2 & 0x00FF0000) >> 16), cast(byte)((l2 & 0xFF000000) >> 24),
            cast(byte)((l2 & 0x000000FF)      ), cast(byte)((l2 & 0x0000FF00) >>  8),
            cast(byte)((l3 & 0xFF000000) >> 24), cast(byte)((l3 & 0x00FF0000) >> 16),
            cast(byte)((l3 & 0x0000FF00) >>  8), cast(byte)((l3 & 0x000000FF)      ),
            cast(byte)((l4 & 0xFF000000) >> 24), cast(byte)((l4 & 0x00FF0000) >> 16),
            cast(byte)((l4 & 0x0000FF00) >>  8), cast(byte)((l4 & 0x000000FF)      ) 
        ];
    }
}
else
{
    TUID INLINE_UID(uint l1, uint l2, uint l3, uint l4) pure @safe
    {
        return 
        [
            cast(byte)((l1 & 0xFF000000) >> 24), cast(byte)((l1 & 0x00FF0000) >> 16),
            cast(byte)((l1 & 0x0000FF00) >>  8), cast(byte)((l1 & 0x000000FF)      ),
            cast(byte)((l2 & 0xFF000000) >> 24), cast(byte)((l2 & 0x00FF0000) >> 16),
            cast(byte)((l2 & 0x0000FF00) >>  8), cast(byte)((l2 & 0x000000FF)      ),
            cast(byte)((l3 & 0xFF000000) >> 24), cast(byte)((l3 & 0x00FF0000) >> 16),
            cast(byte)((l3 & 0x0000FF00) >>  8), cast(byte)((l3 & 0x000000FF)      ),
            cast(byte)((l4 & 0xFF000000) >> 24), cast(byte)((l4 & 0x00FF0000) >> 16),
            cast(byte)((l4 & 0x0000FF00) >>  8), cast(byte)((l4 & 0x000000FF)      ) 
        ];
    }
}

mixin template IMPLEMENT_REFCOUNT()
{
    public nothrow @nogc
    {
        override uint addRef()
        {
            return atomicAdd(_funknownRefCount, 1);
        }

        override uint release()
        {
            import dplug.core.nogc: destroyFree;

            int decremented = atomicAdd(_funknownRefCount, -1);
            if (decremented == 0)
                destroyFree(this);
            return decremented;
        }
    }

    protected shared(int) _funknownRefCount = 1; // when constructed, first value is 1
}

mixin template QUERY_INTERFACE(Interfaces...)// interfaces)
{
    override tresult queryInterface (ref const TUID _iid, void** obj)
    {
        foreach(initer; Interfaces)
        {
            if (iidEqual (_iid, initer.iid))
            {
                addRef();
                *obj = cast(void*)( cast(initer)(this) );
                return kResultOk;
            }
        }
        *obj = null;
        return kNoInterface;
    }
}

// speical case, when asking for a IUnknown return a richer interface
mixin template QUERY_INTERFACE_SPECIAL_CASE_IUNKNOWN(Interfaces...)// interfaces)
{
    override tresult queryInterface (ref const TUID _iid, void** obj)
    {
        foreach(initer; Interfaces)
        {
            if (iidEqual (_iid, initer.iid))
            {
                addRef();
                *obj = cast(void*)( cast(initer)(this) );
                return kResultOk;
            }
        }

        if (iidEqual (_iid, FUnknown.iid))
        {
            addRef();
            *obj = cast(void*)( cast(Interfaces[0])(this) );
            return kResultOk;
        }

        *obj = null;
        return kNoInterface;
    }
}


static if (COM_COMPATIBLE)
{
    version(Windows)
    {
    enum : tresult
    {
        kNoInterface        = cast(tresult)(0x80004002L),   // E_NOINTERFACE
        kResultOk           = cast(tresult)(0x00000000L),   // S_OK
        kResultTrue         = kResultOk,
        kResultFalse        = cast(tresult)(0x00000001L),   // S_FALSE
        kInvalidArgument    = cast(tresult)(0x80070057L),   // E_INVALIDARG
        kNotImplemented     = cast(tresult)(0x80004001L),   // E_NOTIMPL
        kInternalError      = cast(tresult)(0x80004005L),   // E_FAIL
        kNotInitialized     = cast(tresult)(0x8000FFFFL),   // E_UNEXPECTED
        kOutOfMemory        = cast(tresult)(0x8007000EL)        // E_OUTOFMEMORY
    }
    }
    else
    {
    enum : tresult
    {
        kNoInterface        = cast(tresult)(0x80000004L),   // E_NOINTERFACE
        kResultOk           = cast(tresult)(0x00000000L),   // S_OK
        kResultTrue         = kResultOk,
        kResultFalse        = cast(tresult)(0x00000001L),   // S_FALSE
        kInvalidArgument    = cast(tresult)(0x80000003L),   // E_INVALIDARG
        kNotImplemented     = cast(tresult)(0x80000001L),   // E_NOTIMPL
        kInternalError      = cast(tresult)(0x80000008L),   // E_FAIL
        kNotInitialized     = cast(tresult)(0x8000FFFFL),   // E_UNEXPECTED
        kOutOfMemory        = cast(tresult)(0x80000002L)        // E_OUTOFMEMORY
    }
    }
}
else
{
enum : tresult
{
    kNoInterface = -1,
    kResultOk,
    kResultTrue = kResultOk,
    kResultFalse,
    kInvalidArgument,
    kNotImplemented,
    kInternalError,
    kNotInitialized,
    kOutOfMemory
}
}

alias LARGE_INT = int64 ; // obsolete

alias TUID = byte[16]; ///< plain UID type

public bool iidEqual (const(TUID) iid1, const(TUID) iid2) pure
{
    return iid1 == iid2;
}

interface IUnknown 
{
public:
@nogc:
nothrow:
    tresult queryInterface(ref const(TUID) _iid, void** obj);
    uint addRef();
    uint release();
}

interface FUnknown : IUnknown
{
    __gshared immutable TUID iid = INLINE_UID(0x00000000, 0x00000000, 0xC0000000, 0x00000046);
}

int atomicAdd(ref shared(int) var, int32 d)
{
    import core.atomic;
    return atomicOp!"+="(var, d); // Note: return the new value
}


// fstrdefs.h

T* _tstrncpy(T) (T* dest, const(T)* source, uint32 count)
{
    T* start = dest;
    while (count && (*dest++ = *source++) != 0) // copy string
        count--;

    if (count) // pad out with zeros
    {
        while (--count)
            *dest++ = 0;
    }
    return start;
}

char8* strncpy8 (char8* dest, const(char8)* source, uint32 count) 
{
    return _tstrncpy!char8(dest, source, count);
}

char16* strncpy16 (char16* dest, const(char16)* source, uint32 count) 
{
    return _tstrncpy!char16(dest, source, count);
}

/// Convert UTF-16 to UTF-8
void str16ToStr8 (char* dst, wchar* src, int32 n = -1)
{
    int32 i = 0;
    for (;;)
    {
        if (i == n)
        {
            dst[i] = 0;
            return;
        }

        wchar codeUnit = src[i];
        if (codeUnit >= 127)
            codeUnit = '?';

        dst[i] = cast(char)(codeUnit); // FUTURE: proper unicode conversion, this is US-ASCII only

        if (src[i] == 0)
            break;
        i++;
    }

    while (n > i)
    {
        dst[i] = 0;
        i++;
    }
}

void str8ToStr16 (char16* dst, string src, int32 n = -1)
{
    int32 i = 0;
    for (;;)
    {
        if (i == src.length)
        {
            dst[i] = 0;
            return;
        }

        if (i == n)
        {
            dst[i] = 0;
            return;
        }

        version(BigEndian)
        {
            char8* pChr = cast(char8*)&dst[i];
            pChr[0] = 0;
            pChr[1] = src[i];
        }
        else
        {
            dst[i] = cast(char16)(src[i]);
        }

        if (src[i] == 0)
            break;

        i++;
    }

    while (n > i)
    {
        dst[i] = 0;
        i++;
    }
}

void str8ToStr16 (char16* dst, const(char8)* src, int32 n = -1)
{
    int32 i = 0;
    for (;;)
    {
        if (i == n)
        {
            dst[i] = 0;
            return;
        }

        version(BigEndian)
        {
            char8* pChr = cast(char8*)&dst[i];
            pChr[0] = 0;
            pChr[1] = src[i];
        }
        else
        {
            dst[i] = cast(char16)(src[i]);
        }

        if (src[i] == 0)
            break;

        i++;
    }

    while (n > i)
    {
        dst[i] = 0;
        i++;
    }
}
