//-----------------------------------------------------------------------------
// Project     : SDK Core
//
// Category    : SDK Core Interfaces
// Filename    : pluginterfaces/base/ftypes.h
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

/+
	const FIDString kPlatformStringWin = "WIN";
	const FIDString kPlatformStringMac = "MAC";
	const FIDString kPlatformStringIOS = "IOS";
	const FIDString kPlatformStringLinux = "Linux";


    #if SMTG_OS_WINDOWS
	const FIDString kPlatformString = kPlatformStringWin;
    #elif SMTG_OS_IOS
	const FIDString kPlatformString = kPlatformStringIOS;
    #elif SMTG_OS_MACOS
	const FIDString kPlatformString = kPlatformStringMac;
    #elif SMTG_OS_LINUX
	const FIDString kPlatformString = kPlatformStringLinux;
    #endif

    //------------------------------------------------------------------------
    /** Coordinates	*/
	typedef int32 UCoord;
	static const UCoord kMaxCoord = ((UCoord)0x7FFFFFFF);
	static const UCoord kMinCoord = ((UCoord)-0x7FFFFFFF);
}	// namespace Steinberg


//----------------------------------------------------------------------------
/** Byte-order Conversion Macros */
//----------------------------------------------------------------------------
#define SWAP_32(l) { \
unsigned char* p = (unsigned char*)& (l); \
unsigned char t; \
t = p[0]; p[0] = p[3]; p[3] = t; t = p[1]; p[1] = p[2]; p[2] = t; }

#define SWAP_16(w) { \
unsigned char* p = (unsigned char*)& (w); \
unsigned char t; \
t = p[0]; p[0] = p[1]; p[1] = t; }

#define SWAP_64(i) { \
unsigned char* p = (unsigned char*)& (i); \
unsigned char t; \
t = p[0]; p[0] = p[7]; p[7] = t; t = p[1]; p[1] = p[6]; p[6] = t; \
t = p[2]; p[2] = p[5]; p[5] = t; t = p[3]; p[3] = p[4]; p[4] = t;}

namespace Steinberg
{
	static inline void FSwap (int8&) {}
	static inline void FSwap (uint8&) {}
	static inline void FSwap (int16& i16) { SWAP_16 (i16) }
	static inline void FSwap (uint16& i16) { SWAP_16 (i16) }
	static inline void FSwap (int32& i32) { SWAP_32 (i32) }
	static inline void FSwap (uint32& i32) { SWAP_32 (i32) }
	static inline void FSwap (int64& i64) { SWAP_64 (i64) }
	static inline void FSwap (uint64& i64) { SWAP_64 (i64) }
}

// always inline macros (only when RELEASE is 1)
//----------------------------------------------------------------------------
#if RELEASE
#if SMTG_OS_MACOS || SMTG_OS_LINUX
#define SMTG_ALWAYS_INLINE	__inline__ __attribute__((__always_inline__))
#define SMTG_NEVER_INLINE __attribute__((noinline))
#elif SMTG_OS_WINDOWS
#define SMTG_ALWAYS_INLINE	__forceinline
#define SMTG_NEVER_INLINE __declspec(noinline)
#endif
#endif

#ifndef SMTG_ALWAYS_INLINE
#define SMTG_ALWAYS_INLINE	inline
#endif
#ifndef SMTG_NEVER_INLINE
#define SMTG_NEVER_INLINE
#endif

#ifndef SMTG_CPP11_STDLIBSUPPORT
// Enable this for old compilers
// #define nullptr NULL
#endif

+/


// vsttypes.h


static immutable string kVstVersionString = "VST 3.6.11";

/+
#define kVstVersionMajor	3
#define kVstVersionMinor	6
#define kVstVersionSub		11

// this allows to write things like: #if VST_VERSION >= 0x030500 // note that 3.10.0 is 0x030a00
#define VST_VERSION ((kVstVersionMajor << 16) | (kVstVersionMinor << 8) | kVstVersionSub)

//------------------------------------------------------------------------
/** \defgroup vst3typedef VST 3 Data Types
*/
/*@{*/
//------------------------------------------------------------------------
// String Types
//------------------------------------------------------------------------
typedef char16 TChar;			///< UTF-16 character
typedef TChar String128[128];	///< 128 character UTF-16 string
typedef const char8* CString;	///< C-String

//------------------------------------------------------------------------
// General
//------------------------------------------------------------------------
typedef int32 MediaType;		///< media type (audio/event)
+/
alias BusDirection = int; ///< bus direction (in/out)
/+
typedef int32 BusType;			///< bus type (main/aux)
typedef int32 IoMode;			///< I/O mode (see \ref vst3IoMode)
typedef int32 UnitID;			///< unit identifier
typedef double ParamValue;		///< parameter value type
typedef uint32 ParamID;			///< parameter identifier
typedef int32 ProgramListID;	///< program list identifier
typedef int16 CtrlNumber;		///< MIDI controller number (see \ref ControllerNumbers for allowed values)

typedef double TQuarterNotes;	///< time expressed in quarter notes
typedef int64 TSamples;			///< time expressed in audio samples

typedef uint32 ColorSpec;		///< color defining by 4 component ARGB value (Alpha/Red/Green/Blue)

//------------------------------------------------------------------------
static const ParamID kNoParamId = 0xffffffff;	///< default for uninitialized parameter ID
// static const ParamID kNoParamId = std::numeric_limits<ParamID>::max ();
+/

//------------------------------------------------------------------------
// Audio Types
//------------------------------------------------------------------------
alias Sample32 = float;				///< 32-bit precision audio sample
alias Sample64 = double;			///< 64-bit precision audio sample

alias SampleRate = double; ///< sample rate


//------------------------------------------------------------------------
// Speaker Arrangements Types
//------------------------------------------------------------------------
alias SpeakerArrangement = uint64 ;	///< Bitset of speakers
alias Speaker = uint64 ; ///< Bit for one speaker




