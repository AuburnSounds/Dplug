//-----------------------------------------------------------------------------
// Project     : SDK Core
//
// Category    : SDK Core Interfaces
// Filename    : pluginterfaces/base/ftypes.h
// Filename    : pluginterfaces/base/fplatform.h
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

// #pragma pack translation
// use align(vst3Alignment): inside structs
version(OSX)
{
    static if ((void*).sizeof == 8)
    {
        // 64-bit macOS
        // no need in packing here
        // MAYDO verify what it means because we shouldn't use align in the first place here
        enum vst3Alignment = 1;
    }
    else
    {
        enum vst3Alignment = 1;
    }
}
else version(Windows)
{
    static if ((void*).sizeof == 8)
    {
        // no need in packing here
        // MAYDO verify what it means because we shouldn't use align in the first place here
        enum vst3Alignment = 16;
    }
    else
    {
        enum vst3Alignment = 8;
    }
}
else
{
    enum vst3Alignment = 0;
}