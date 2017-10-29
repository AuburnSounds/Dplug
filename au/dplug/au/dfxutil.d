/*
    Destroy FX AU Utilities is a collection of helpful utility functions
    for creating and hosting Audio Unit plugins.
    Copyright (C) 2003-2008  Sophia Poirier
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    *   Redistributions of source code must retain the above
        copyright notice, this list of conditions and the
        following disclaimer.
    *   Redistributions in binary form must reproduce the above
        copyright notice, this list of conditions and the
        following disclaimer in the documentation and/or other
        materials provided with the distribution.
    *   Neither the name of Destroy FX nor the names of its
        contributors may be used to endorse or promote products
        derived from this software without specific prior
        written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
    SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
    HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
    STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
    OF THE POSSIBILITY OF SUCH DAMAGE.

    To contact the author, please visit http://destroyfx.org/
    and use the contact form.
*/
// this is a modified version of dfx-au-utilities.h keeping only CFAUPreset related functionality

/**
Audio Unit plug-in client. Port of Destroy FX AU Utilities.

Copyright: Copyright (C) 2003-2008  Sophia Poirier
           Copyright (C) 2016 Guillaume Piolat
*/
module dplug.au.dfxutil;

import core.stdc.stdio: snprintf;

import std.string;
import std.exception: assumeUnique;

import derelict.carbon;

import dplug.core.nogc;

//-----------------------------------------------------------------------------
// The following defines and implements CoreFoundation-like handling of
// an AUPreset container object:  CFAUPreset
//-----------------------------------------------------------------------------

enum UInt32 kCFAUPreset_CurrentVersion = 0;

struct CFAUPreset
{
    AUPreset auPreset;
    uint version_;
    CFAllocatorRef allocator;
    CFIndex retainCount;
}

alias CFAUPresetRef = void*;

//-----------------------------------------------------------------------------
// create an instance of a CFAUPreset object
CFAUPresetRef CFAUPresetCreate(CFAllocatorRef inAllocator, SInt32 inPresetNumber, CFStringRef inPresetName) nothrow @nogc
{
    CFAUPreset * newPreset = cast(CFAUPreset*) CFAllocatorAllocate(inAllocator, CFAUPreset.sizeof, 0);
    if (newPreset != null)
    {
        newPreset.auPreset.presetNumber = inPresetNumber;
        newPreset.auPreset.presetName = null;
        // create our own a copy rather than retain the string, in case the input string is mutable,
        // this will keep it from changing under our feet
        if (inPresetName != null)
            newPreset.auPreset.presetName = CFStringCreateCopy(inAllocator, inPresetName);
        newPreset.version_ = kCFAUPreset_CurrentVersion;
        newPreset.allocator = inAllocator;
        newPreset.retainCount = 1;
    }
    return cast(CFAUPresetRef)newPreset;
}

extern(C)
{
    //-----------------------------------------------------------------------------
    // retain a reference of a CFAUPreset object
    CFAUPresetRef CFAUPresetRetain(void* inPreset) nothrow @nogc
    {
        if (inPreset != null)
        {
            CFAUPreset * incomingPreset = cast(CFAUPreset*) inPreset;
            // retain the input AUPreset's name string for this reference to the preset
            if (incomingPreset.auPreset.presetName != null)
                CFRetain(incomingPreset.auPreset.presetName);
            incomingPreset.retainCount += 1;
        }
        return inPreset;
    }

    //-----------------------------------------------------------------------------
    // release a reference of a CFAUPreset object
    void CFAUPresetRelease(void* inPreset) nothrow @nogc
    {
        CFAUPreset* incomingPreset = cast(CFAUPreset*) inPreset;
        // these situations shouldn't happen
        if (inPreset == null)
            return;
        if (incomingPreset.retainCount <= 0)
            return;

        // first release the name string, CF-style, since it's a CFString
        if (incomingPreset.auPreset.presetName != null)
            CFRelease(incomingPreset.auPreset.presetName);
        incomingPreset.retainCount -= 1;
        // check if this is the end of this instance's life
        if (incomingPreset.retainCount == 0)
        {
            // wipe out the data so that, if anyone tries to access stale memory later, it will be (semi)invalid
            incomingPreset.auPreset.presetName = null;
            incomingPreset.auPreset.presetNumber = 0;
            // and finally, free the memory for the CFAUPreset struct
            CFAllocatorDeallocate(incomingPreset.allocator, cast(void*)inPreset);
        }
    }

    //-----------------------------------------------------------------------------
    // This function is called when an item (an AUPreset) is added to the CFArray,
    // or when a CFArray containing an AUPreset is retained.
    const(void)* CFAUPresetArrayRetainCallBack(CFAllocatorRef inAllocator, const(void)* inPreset) nothrow @nogc
    {
        return CFAUPresetRetain(cast(void*)inPreset); // casting const away here!
    }

    //-----------------------------------------------------------------------------
    // This function is called when an item (an AUPreset) is removed from the CFArray
    // or when the array is released.
    // Since a reference to the data belongs to the array, we need to release that here.
    void CFAUPresetArrayReleaseCallBack(CFAllocatorRef inAllocator, const(void)* inPreset) nothrow @nogc
    {
        CFAUPresetRelease(cast(void*)inPreset); // casting const away here!
    }

    //-----------------------------------------------------------------------------
    // This function is called when someone wants to compare to items (AUPresets)
    // in the CFArray to see if they are equal or not.
    // For our AUPresets, we will compare based on the preset number and the name string.
    Boolean CFAUPresetArrayEqualCallBack(const(void)* inPreset1, const(void)* inPreset2) nothrow @nogc
    {
        AUPreset * preset1 = cast(AUPreset*) inPreset1;
        AUPreset * preset2 = cast(AUPreset*) inPreset2;
        // the two presets are only equal if they have the same preset number and
        // if the two name strings are the same (which we rely on the CF function to compare)
        return (preset1.presetNumber == preset2.presetNumber) &&
                (CFStringCompare(preset1.presetName, preset2.presetName, 0) == kCFCompareEqualTo);
    }

    //-----------------------------------------------------------------------------
    // This function is called when someone wants to get a description of
    // a particular item (an AUPreset) as though it were a CF type.
    // That happens, for example, when using CFShow().
    // This will create and return a CFString that indicates that
    // the object is an AUPreset and tells the preset number and preset name.
    CFStringRef CFAUPresetArrayCopyDescriptionCallBack(const(void)* inPreset) nothrow
    {
        AUPreset * preset = cast(AUPreset*) inPreset;
        return CFStringCreateWithFormat(kCFAllocatorDefault, null,
                                        CFStrLocal.fromString("AUPreset:\npreset number = %d\npreset name = %@"),
                                        cast(int)preset.presetNumber, preset.presetName);
    }
}

CFArrayCallBacks getCFAUPresetArrayCallBacks() nothrow @nogc
{
    CFArrayCallBacks result;
    with(result)
    {
        version_ = 0; // currently, 0 is the only valid version value for this
        retain = &CFAUPresetArrayRetainCallBack;
        release = &CFAUPresetArrayReleaseCallBack;
        copyDescription = &CFAUPresetArrayCopyDescriptionCallBack;
        equal = &CFAUPresetArrayEqualCallBack;
    }
    return result;
}


// CoreFoundation helpers

struct CFStrLocal
{
nothrow:
@nogc:

    CFStringRef parent;
    alias parent this;

    @disable this();
    @disable this(this);

    static fromString(const(char)[] str)
    {
        CFStrLocal s = void;
        s.parent = toCFString(str);
        return s;
    }

    ~this() nothrow
    {
        CFRelease(parent);
    }
}


/// Creates a CFString from an int give up its ownership.
CFStringRef convertIntToCFString(int number) nothrow @nogc
{
    char[16] str;
    snprintf(str.ptr, str.length, "%d", number); 
    return CFStringCreateWithCString(null, str.ptr, kCFStringEncodingUTF8);
}

/// Creates a CFString from a string and give up its ownership.
CFStringRef toCFString(const(char)[] str) nothrow @nogc
{
    return CFStringCreateWithCString(null, CString(str).storage, kCFStringEncodingUTF8);
}

/// Create string from a CFString, and give up its ownership.
/// Such a string must be deallocated with `free`/`freeSlice`.
/// It is guaranteed to finish with a terminal zero character ('\0').
string mallocStringFromCFString(CFStringRef cfStr) nothrow @nogc
{
    int n = cast(int)CFStringGetLength(cfStr) + 1;
    char[] buf = mallocSlice!char(n);
    CFStringGetCString(cfStr, buf.ptr, n, kCFStringEncodingUTF8);
    return assumeUnique(buf);
}

void putNumberInDict(CFMutableDictionaryRef pDict, const(char)[] key, void* pNumber, CFNumberType type) nothrow @nogc
{
    CFStrLocal cfKey = CFStrLocal.fromString(key);

    CFNumberRef pValue = CFNumberCreate(null, type, pNumber);
    CFDictionarySetValue(pDict, cfKey, pValue);
    CFRelease(pValue);
}

void putStrInDict(CFMutableDictionaryRef pDict, const(char)[] key, const(char)[] value) nothrow @nogc
{
    CFStrLocal cfKey = CFStrLocal.fromString(key);
    CFStrLocal cfValue = CFStrLocal.fromString(value);
    CFDictionarySetValue(pDict, cfKey, cfValue);
}

void putDataInDict(CFMutableDictionaryRef pDict, const(char)[] key, ubyte[] pChunk) nothrow @nogc
{
    CFStrLocal cfKey = CFStrLocal.fromString(key);

    CFDataRef pData = CFDataCreate(null, pChunk.ptr, cast(CFIndex)(pChunk.length));
    CFDictionarySetValue(pDict, cfKey, pData);
    CFRelease(pData);
}


bool getNumberFromDict(CFDictionaryRef pDict, const(char)[] key, void* pNumber, CFNumberType type) nothrow @nogc
{
    CFStrLocal cfKey = CFStrLocal.fromString(key);

    CFNumberRef pValue = cast(CFNumberRef) CFDictionaryGetValue(pDict, cfKey);
    if (pValue)
    {
        CFNumberGetValue(pValue, type, pNumber);
        return true;
    }
    return false;
}

/// Get a string in a dictionnary, and give up its ownership.
bool getStrFromDict(CFDictionaryRef pDict, const(char)[] key, out string value) nothrow @nogc
{
    CFStrLocal cfKey = CFStrLocal.fromString(key);

    CFStringRef pValue = cast(CFStringRef) CFDictionaryGetValue(pDict, cfKey);
    if (pValue)
    {
        value = mallocStringFromCFString(pValue);
        return true;
    }
    return false;
}

/// Gets data from a CFDataRef dictionnary entry and give up its ownership.
/// Must be deallocated with `free`/`freeSlice`.
bool getDataFromDict(CFDictionaryRef pDict, string key, out ubyte[] pChunk) nothrow @nogc
{
    CFStrLocal cfKey = CFStrLocal.fromString(key);
    CFDataRef pData = cast(CFDataRef) CFDictionaryGetValue(pDict, cfKey);
    if (pData)
    {
        int n = cast(int)CFDataGetLength(pData);
        pChunk = ( CFDataGetBytePtr(pData)[0..n] ).mallocDup;
        return true;
    }
    return false;
}