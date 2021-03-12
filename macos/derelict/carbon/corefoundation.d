/**
Dynamic bindings to the CoreFoundation framework.

Copyright: Guillaume Piolat 2015.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module derelict.carbon.corefoundation;

import core.stdc.config;

import dplug.core.sharedlib;
import dplug.core.nogc;

version(OSX)
    enum libNames = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
else
    enum libNames = "";


class DerelictCoreFoundationLoader : SharedLibLoader
{
    public
    {
        nothrow @nogc:
        this()
        {
            super(libNames);
        }

        override void loadSymbols()
        {
            bindFunc(cast(void**)&CFRetain, "CFRetain");
            bindFunc(cast(void**)&CFRelease, "CFRelease");
            bindFunc(cast(void**)&CFEqual, "CFEqual");
            bindFunc(cast(void**)&CFHash, "CFHash");
            bindFunc(cast(void**)&CFCopyDescription, "CFCopyDescription");

            bindFunc(cast(void**)&CFArrayCreateMutable, "CFArrayCreateMutable");
            bindFunc(cast(void**)&CFArrayAppendValue, "CFArrayAppendValue");

            bindFunc(cast(void**)&CFAllocatorAllocate, "CFAllocatorAllocate");
            bindFunc(cast(void**)&CFAllocatorDeallocate, "CFAllocatorDeallocate");

            bindFunc(cast(void**)&CFBundleGetMainBundle, "CFBundleGetMainBundle");
            bindFunc(cast(void**)&CFBundleGetBundleWithIdentifier, "CFBundleGetBundleWithIdentifier");
            bindFunc(cast(void**)&CFBundleCopyBundleURL, "CFBundleCopyBundleURL");
            bindFunc(cast(void**)&CFBundleCopyResourcesDirectoryURL, "CFBundleCopyResourcesDirectoryURL");

            bindFunc(cast(void**)&CFURLGetFileSystemRepresentation, "CFURLGetFileSystemRepresentation");

            bindFunc(cast(void**)&CFStringCreateWithCString, "CFStringCreateWithCString");
            bindFunc(cast(void**)&CFStringGetLength, "CFStringGetLength");
            bindFunc(cast(void**)&CFStringGetCString, "CFStringGetCString");
            bindFunc(cast(void**)&CFStringCreateCopy, "CFStringCreateCopy");
            bindFunc(cast(void**)&CFStringCompare, "CFStringCompare");
            bindFunc(cast(void**)&CFStringCreateWithFormat, "CFStringCreateWithFormat");

            bindFunc(cast(void**)&CFDataCreate, "CFDataCreate");
            bindFunc(cast(void**)&CFDataGetLength, "CFDataGetLength");
            bindFunc(cast(void**)&CFDataGetBytePtr, "CFDataGetBytePtr");

            bindFunc(cast(void**)&CFDictionaryCreateMutable, "CFDictionaryCreateMutable");
            bindFunc(cast(void**)&CFDictionaryGetValue, "CFDictionaryGetValue");
            bindFunc(cast(void**)&CFDictionarySetValue, "CFDictionarySetValue");

            bindFunc(cast(void**)&CFNumberCreate, "CFNumberCreate");
            bindFunc(cast(void**)&CFNumberGetValue, "CFNumberGetValue");

            with (kCFTypeArrayCallBacks)
            {
                version_ = 0;
                retain = &myRetainCallBack;
                release = &myReleaseCallBack;
                copyDescription = CFCopyDescription;
                equal = CFEqual;
            }

            with (kCFTypeDictionaryKeyCallBacks)
            {
                version_ = 0;
                retain = &myRetainCallBack;
                release = &myReleaseCallBack;
                copyDescription = CFCopyDescription;
                equal = CFEqual;
                hash = CFHash;
            }

            with (kCFTypeDictionaryValueCallBacks)
            {
                version_ = 0;
                retain = &myRetainCallBack;
                release = &myReleaseCallBack;
                copyDescription = CFCopyDescription;
                equal = CFEqual;
            }
        }
    }
}

private __gshared DerelictCoreFoundationLoader DerelictCoreFoundation;

private __gshared loaderCounterCF = 0;

// Call this each time a novel owner uses these functions
// TODO: hold a mutex, because this isn't thread-safe
void acquireCoreFoundationFunctions() nothrow @nogc
{
    if (DerelictCoreFoundation is null)  // You only live once
    {
        DerelictCoreFoundation = mallocNew!DerelictCoreFoundationLoader();
        DerelictCoreFoundation.load();
    }
}

// Call this each time a novel owner releases a Cocoa functions
// TODO: hold a mutex, because this isn't thread-safe
void releaseCoreFoundationFunctions() nothrow @nogc
{
    /*if (--loaderCounterCF == 0)
    {
        DerelictCoreFoundation.unload();
        DerelictCoreFoundation.destroyFree();
    }*/
}

unittest
{
    version(OSX)
    {
        acquireCoreFoundationFunctions();
        releaseCoreFoundationFunctions();
    }
}

// To support character constants
package int CCONST(int a, int b, int c, int d) pure nothrow
{
    return (a << 24) | (b << 16) | (c << 8) | (d << 0);
}


// <MacTypes.h>

alias UInt8 = ubyte;
alias SInt8 = byte;
alias UInt16 = ushort;
alias SInt16 = short;
alias UInt32 = uint;
alias SInt32 = int;
alias UInt64 = ulong;
alias SInt64 = long;


  // binary layout should be what is expected on this platform
version (LittleEndian)
{
    struct wide
    {
        UInt32              lo;
        SInt32              hi;
    }

    struct UnsignedWide
    {
        UInt32              lo;
        UInt32              hi;
    }
}
else
{
    struct wide
    {
        SInt32              hi;
        UInt32              lo;
    }

    struct UnsignedWide
    {
        UInt32              hi;
        UInt32              lo;
    }
}


alias Fixed = SInt32;
alias FixedPtr = Fixed*;
alias Fract = SInt32;
alias FractPtr = Fract*;
alias UnsignedFixed = UInt32;
alias UnsignedFixedPtr = UnsignedFixed*;
alias ShortFixed = short;
alias ShortFixedPtr = ShortFixed*;

alias Float32 = float;
alias Float64 = double;

struct Float32Point
{
    Float32 x;
    Float32 y;
}

alias Ptr = char*;
alias Handle = Ptr*;
alias Size = long;


alias OSErr = SInt16;
alias OSStatus = SInt32;
alias LogicalAddress = void*;
alias ConstLogicalAddress = const(void)*;
alias PhysicalAddress = void*;
alias BytePtr = UInt8*;
alias ByteCount = c_ulong;
alias ByteOffset = c_ulong;
alias Duration = SInt32;
alias AbsoluteTime = UnsignedWide;
alias OptionBits = UInt32;
alias ItemCount = c_ulong;
alias PBVersion = UInt32;
alias ScriptCode = SInt16;
alias LangCode = SInt16;
alias RegionCode = SInt16;
alias FourCharCode = UInt32;
alias OSType = FourCharCode;
alias ResType = FourCharCode;
alias OSTypePtr = OSType*;
alias ResTypePtr = ResType*;

enum
{
    noErr                         = 0,
    kNilOptions                   = 0,
    kInvalidID                    = 0,
    kVariableLengthArray          = 1,
    kUnknownType                  = 0x3F3F3F3F
}

alias UnicodeScalarValue = UInt32;
alias UTF32Char = UInt32;
alias UniChar = UInt16;
alias UTF16Char = UInt16;
alias UTF8Char = UInt8;
alias UniCharPtr = UniChar*;
alias UniCharCount = c_ulong;
alias UniCharCountPtr = UniCharCount*;
alias Str255 = char[256];
alias Str63 = char[64];
alias Str32 = char[33];
alias Str31 = char[32];
alias Str27 = char[28];
alias Str15 = char[16];


// <CoreFoundation/CFBase.h>


alias Boolean = ubyte;

alias StringPtr = char*;
alias ConstStringPtr = const(char)*;
alias ConstStr255Param = const(char)*;
alias Byte = UInt8;
alias SignedByte = SInt8;


alias CFTypeID = c_ulong;
alias CFOptionFlags = c_ulong;
alias CFHashCode = c_ulong;
alias CFIndex = c_long;

alias CFTypeRef = const(void)*;

alias CFStringRef = void*;
alias CFMutableStringRef = void*;
alias CFAllocatorRef = void*;

enum CFAllocatorRef kCFAllocatorDefault = null;

alias CFPropertyListRef = CFTypeRef;


struct CFRange
{
    CFIndex location;
    CFIndex length;
}

CFRange CFRangeMake(CFIndex loc, CFIndex len)
{
    return CFRange(loc, len);
}

alias CFComparisonResult = CFIndex;
enum : CFComparisonResult
{
    kCFCompareLessThan = -1,
    kCFCompareEqualTo = 0,
    kCFCompareGreaterThan = 1
}

alias CFNullRef = const(void)*;

struct Point
{
    short               v;
    short               h;
}
alias PointPtr = Point*;

struct Rect
{
  short               top;
  short               left;
  short               bottom;
  short               right;
}
alias RectPtr = Rect*;

extern(C) nothrow @nogc
{
    alias da_CFRetain = CFTypeRef function(CFTypeRef cf);
    alias da_CFRelease = void function(CFTypeRef cf);
    alias da_CFEqual = Boolean function(CFTypeRef cf1, CFTypeRef cf2);
    alias da_CFHash = CFHashCode function(CFTypeRef cf);
    alias da_CFCopyDescription = CFStringRef function(CFTypeRef cf);
}

__gshared
{
    da_CFRetain CFRetain;
    da_CFRelease CFRelease;
    da_CFEqual CFEqual;
    da_CFHash CFHash;
    da_CFCopyDescription CFCopyDescription;
}


extern(C) nothrow @nogc
{
    alias da_CFAllocatorAllocate = void* function(CFAllocatorRef allocator, CFIndex size, CFOptionFlags hint);
    alias da_CFAllocatorDeallocate = void function(CFAllocatorRef allocator, void *ptr);
}

__gshared
{
    da_CFAllocatorAllocate CFAllocatorAllocate;
    da_CFAllocatorDeallocate CFAllocatorDeallocate;
}

// <CoreFoundation/CFBundle.h>

alias CFBundleRef = void*;

extern(C) nothrow @nogc
{
    alias da_CFBundleGetBundleWithIdentifier = CFBundleRef function(CFStringRef bundleID);
    alias da_CFBundleCopyBundleURL = CFURLRef function(CFBundleRef bundle);
    alias da_CFBundleGetMainBundle = CFBundleRef function();
    alias da_CFBundleCopyResourcesDirectoryURL = CFURLRef function(CFBundleRef bundle);

    alias da_CFURLGetFileSystemRepresentation = Boolean function(CFURLRef url, Boolean resolveAgainstBase, UInt8* buffer, CFIndex maxBufLen);
}

__gshared
{
    da_CFBundleGetBundleWithIdentifier CFBundleGetBundleWithIdentifier;
    da_CFBundleCopyBundleURL CFBundleCopyBundleURL;
    da_CFBundleGetMainBundle CFBundleGetMainBundle;
    da_CFBundleCopyResourcesDirectoryURL CFBundleCopyResourcesDirectoryURL;

    da_CFURLGetFileSystemRepresentation CFURLGetFileSystemRepresentation;
}


// <CoreFoundation/CFArray.h>

alias CFArrayRef = void*;
alias CFMutableArrayRef = void*;

extern(C) nothrow @nogc
{
    alias CFArrayRetainCallBack = const(void)* function(CFAllocatorRef allocator, const(void)* value);
    alias CFArrayReleaseCallBack = void function(CFAllocatorRef allocator, const(void)* value);
    alias CFArrayEqualCallBack = Boolean function(const(void)* value1, const(void)* value2);
}

// This one isn't forced to be @nogc (this is arbitrary, only nothrow is needed)
extern(C) nothrow
{
    alias CFArrayCopyDescriptionCallBack = CFStringRef function(const(void)* value);
}

struct CFArrayCallBacks
{
    CFIndex             version_;
    CFArrayRetainCallBack       retain;
    CFArrayReleaseCallBack      release;
    CFArrayCopyDescriptionCallBack  copyDescription;
    CFArrayEqualCallBack        equal;
}

__gshared CFArrayCallBacks kCFTypeArrayCallBacks;

extern(C) nothrow @nogc
{
    alias da_CFArrayCreateMutable = CFMutableArrayRef function(CFAllocatorRef allocator, CFIndex capacity, const(CFArrayCallBacks)* callBacks);
    alias da_CFArrayAppendValue = void function(CFMutableArrayRef theArray, const(void)* value);
}

__gshared
{
    da_CFArrayCreateMutable CFArrayCreateMutable;
    da_CFArrayAppendValue CFArrayAppendValue;
}


// <CoreFoundation/CFData.h>

alias CFDataRef = void*;
alias CFMutableDataRef = void*;

extern(C) nothrow @nogc
{
    alias da_CFDataCreate = CFDataRef function(CFAllocatorRef allocator, const(UInt8)* bytes, CFIndex length);

    alias da_CFDataGetLength = CFIndex function(CFDataRef theData);
    alias da_CFDataGetBytePtr = const(UInt8)* function(CFDataRef theData);
}

__gshared
{
    da_CFDataCreate CFDataCreate;
    da_CFDataGetLength CFDataGetLength;
    da_CFDataGetBytePtr CFDataGetBytePtr;
}

// <CoreFoundation/CFDictionary.h>

extern(C) nothrow @nogc
{
    alias CFDictionaryRetainCallBack = const(void)* function(CFAllocatorRef allocator, const(void)* value);
    alias CFDictionaryReleaseCallBack = void function(CFAllocatorRef allocator, const(void)* value);
    alias CFDictionaryCopyDescriptionCallBack = CFStringRef function(const(void)* value);
    alias CFDictionaryEqualCallBack = Boolean function(const(void)* value1, const(void)* value2);
    alias CFDictionaryHashCallBack = CFHashCode function(const(void)* value);
}


// Dictionnaries callback
private extern(C) nothrow @nogc
{
    const(void)* myRetainCallBack(CFAllocatorRef allocator, const(void)* value)
    {
        // MAYDO: not sure what to do with the allocator
        return CFRetain(value);
    }

    void myReleaseCallBack(CFAllocatorRef allocator, const(void)* value)
    {
        // MAYDO: not sure what to do with the allocator
        return CFRelease(value);
    }
}

struct CFDictionaryKeyCallBacks
{
    CFIndex             version_;
    CFDictionaryRetainCallBack      retain;
    CFDictionaryReleaseCallBack     release;
    CFDictionaryCopyDescriptionCallBack copyDescription;
    CFDictionaryEqualCallBack       equal;
    CFDictionaryHashCallBack        hash;
}

__gshared CFDictionaryKeyCallBacks kCFTypeDictionaryKeyCallBacks;

struct CFDictionaryValueCallBacks
{
    CFIndex             version_;
    CFDictionaryRetainCallBack      retain;
    CFDictionaryReleaseCallBack     release;
    CFDictionaryCopyDescriptionCallBack copyDescription;
    CFDictionaryEqualCallBack       equal;
}

__gshared CFDictionaryValueCallBacks kCFTypeDictionaryValueCallBacks;

alias CFDictionaryRef = void*;
alias CFMutableDictionaryRef = void*;

extern(C) nothrow @nogc
{
    alias da_CFDictionaryCreateMutable = CFMutableDictionaryRef function(CFAllocatorRef, CFIndex, const(CFDictionaryKeyCallBacks)*, const(CFDictionaryValueCallBacks)*);
    alias da_CFDictionaryGetValue = const(void)* function(CFDictionaryRef theDict, const(void) *key);
    alias da_CFDictionarySetValue = void function(CFMutableDictionaryRef theDict, const(void)* key, const(void)* value);
}

__gshared
{
    da_CFDictionaryCreateMutable CFDictionaryCreateMutable;
    da_CFDictionaryGetValue CFDictionaryGetValue;
    da_CFDictionarySetValue CFDictionarySetValue;
}

// <CoreFoundation/CFNumber.h>

alias CFNumberRef = void*;

alias CFNumberType = CFIndex;
enum : CFNumberType
{
    kCFNumberSInt8Type = 1,
    kCFNumberSInt16Type = 2,
    kCFNumberSInt32Type = 3,
    kCFNumberSInt64Type = 4,
    kCFNumberFloat32Type = 5,
    kCFNumberFloat64Type = 6,
    kCFNumberCharType = 7,
    kCFNumberShortType = 8,
    kCFNumberIntType = 9,
    kCFNumberLongType = 10,
    kCFNumberLongLongType = 11,
    kCFNumberFloatType = 12,
    kCFNumberDoubleType = 13,
    kCFNumberCFIndexType = 14,
    kCFNumberNSIntegerType = 15,
    kCFNumberCGFloatType = 16,
    kCFNumberMaxType = 16
}

extern(C) nothrow @nogc
{
    alias da_CFNumberCreate = CFNumberRef function(CFAllocatorRef allocator, CFNumberType theType, const(void) *valuePtr);
    alias da_CFNumberGetValue = Boolean function(CFNumberRef number, CFNumberType theType, void *valuePtr);
}

__gshared
{
    da_CFNumberCreate CFNumberCreate;
    da_CFNumberGetValue CFNumberGetValue;
}

// <CoreFoundation/CFString.h>

alias CFStringEncoding = UInt32;
alias CFStringBuiltInEncodings = CFStringEncoding;
enum : CFStringBuiltInEncodings
{
    kCFStringEncodingMacRoman = 0,
    kCFStringEncodingWindowsLatin1 = 0x0500,
    kCFStringEncodingISOLatin1 = 0x0201,
    kCFStringEncodingNextStepLatin = 0x0B01,
    kCFStringEncodingASCII = 0x0600,
    kCFStringEncodingUnicode = 0x0100,
    kCFStringEncodingUTF8 = 0x08000100,
    kCFStringEncodingNonLossyASCII = 0x0BFF,

    kCFStringEncodingUTF16 = 0x0100,
    kCFStringEncodingUTF16BE = 0x10000100,
    kCFStringEncodingUTF16LE = 0x14000100,

    kCFStringEncodingUTF32 = 0x0c000100,
    kCFStringEncodingUTF32BE = 0x18000100,
    kCFStringEncodingUTF32LE = 0x1c000100
}

alias CFStringCompareFlags = CFOptionFlags;
enum : CFStringCompareFlags
{
    kCFCompareCaseInsensitive = 1,
    kCFCompareBackwards = 4,
    kCFCompareAnchored = 8,
    kCFCompareNonliteral = 16,
    kCFCompareLocalized = 32,
    kCFCompareNumerically = 64,
    kCFCompareDiacriticInsensitive = 128,
    kCFCompareWidthInsensitive = 256,
    kCFCompareForcedOrdering = 512
}

extern(C) nothrow @nogc
{
    alias da_CFStringCreateWithCString = CFStringRef function(CFAllocatorRef, const(char)*, CFStringEncoding);
    alias da_CFStringGetLength = CFIndex function(CFStringRef);
    alias da_CFStringGetCString = Boolean function(CFStringRef, char*, CFIndex, CFStringEncoding);
    alias da_CFStringCreateCopy = CFStringRef function(CFAllocatorRef alloc, CFStringRef theString);
    alias da_CFStringCompare = CFComparisonResult function(CFStringRef theString1, CFStringRef theString2, CFStringCompareFlags compareOptions);
    alias da_CFStringCreateWithFormat = CFStringRef function(CFAllocatorRef alloc, CFDictionaryRef formatOptions, CFStringRef format, ...);
}

__gshared
{
    da_CFStringCreateWithCString CFStringCreateWithCString;
    da_CFStringGetLength CFStringGetLength;
    da_CFStringGetCString CFStringGetCString;
    da_CFStringCreateCopy CFStringCreateCopy;
    da_CFStringCompare CFStringCompare;
    da_CFStringCreateWithFormat CFStringCreateWithFormat;
}

// <CoreFoundation/CFURL.h>

alias CFURLRef = void*;