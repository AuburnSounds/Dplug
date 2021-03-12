/**
Dynamic bindings to the CoreServices framework.

Copyright: Guillaume Piolat 2015.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module derelict.carbon.coreservices;

import core.stdc.config;

import dplug.core.sharedlib;

import derelict.carbon.corefoundation;

import dplug.core.nogc;

version(OSX)
    enum libNames = "/System/Library/Frameworks/CoreServices.framework/CoreServices";
else
    enum libNames = "";


class DerelictCoreServicesLoader : SharedLibLoader
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
            bindFunc(cast(void**)&SetComponentInstanceStorage, "SetComponentInstanceStorage");
            bindFunc(cast(void**)&GetComponentInstanceStorage, "GetComponentInstanceStorage");
            bindFunc(cast(void**)&GetComponentInfo, "GetComponentInfo");
        }
    }
}

private __gshared DerelictCoreServicesLoader DerelictCoreServices;

private __gshared loaderCounterCS = 0;

// Call this each time a novel owner uses these functions
// TODO: hold a mutex, because this isn't thread-safe
void acquireCoreServicesFunctions() nothrow @nogc
{
    if (DerelictCoreServices is null)  // You only live once
    {
        DerelictCoreServices = mallocNew!DerelictCoreServicesLoader();
        DerelictCoreServices.load();
    }
}

// Call this each time a novel owner releases a Cocoa functions
// TODO: hold a mutex, because this isn't thread-safe
void releaseCoreServicesFunctions() nothrow @nogc
{
    /*if (--loaderCounterCS == 0)
    {
        DerelictCoreServices.unload();
        DerelictCoreServices.destroyFree();
    }*/
}

unittest
{
    version(OSX)
    {
        acquireCoreServicesFunctions();
        releaseCoreServicesFunctions();
    }
}

enum : int
{
    typeSInt16                 = CCONST('s', 'h', 'o', 'r'),
    typeUInt16                 = CCONST('u', 's', 'h', 'r'),
    typeSInt32                 = CCONST('l', 'o', 'n', 'g'),
    typeUInt32                 = CCONST('m', 'a', 'g', 'n'),
    typeSInt64                 = CCONST('c', 'o', 'm', 'p'),
    typeUInt64                 = CCONST('u', 'c', 'o', 'm'),
    typeIEEE32BitFloatingPoint = CCONST('s', 'i', 'n', 'g'),
    typeIEEE64BitFloatingPoint = CCONST('d', 'o', 'u', 'b'),
    type128BitFloatingPoint    = CCONST('l', 'd', 'b', 'l'),
    typeDecimalStruct          = CCONST('d', 'e', 'c', 'm'),
    typeChar                   = CCONST('T', 'E', 'X', 'T'),
}

// <CarbonCore/MacErrors.h>
enum : int
{
    badComponentInstance = cast(int)0x80008001,
    badComponentSelector = cast(int)0x80008002
}

enum
{
    coreFoundationUnknownErr      = -4960,
}


// <CarbonCore/Components.h>

// LP64 => "long and pointers are 64-bit"
static if (size_t.sizeof == 8 && c_long.sizeof == 8)
    private enum __LP64__ = 1;
else
    private enum __LP64__ = 0;

alias Component = void*;
alias ComponentResult = int;

alias ComponentInstance = void*;

struct ComponentParameters
{
    UInt8               flags;
    UInt8               paramSize;
    SInt16              what;
    static if (__LP64__)
        UInt32          padding;
    c_long[1]           params;
}

static if (__LP64__)
{
    static assert(ComponentParameters.sizeof == 16);
}

enum : int
{
    kComponentOpenSelect          = -1,
    kComponentCloseSelect         = -2,
    kComponentCanDoSelect         = -3,
    kComponentVersionSelect       = -4,
    kComponentRegisterSelect      = -5,
    kComponentTargetSelect        = -6,
    kComponentUnregisterSelect    = -7,
    kComponentGetMPWorkFunctionSelect = -8,
    kComponentExecuteWiredActionSelect = -9,
    kComponentGetPublicResourceSelect = -10
};

struct ComponentDescription
{
    OSType              componentType;
    OSType              componentSubType;
    OSType              componentManufacturer;
    UInt32              componentFlags;
    UInt32              componentFlagsMask;
}

extern(C) nothrow @nogc
{
    alias da_SetComponentInstanceStorage = void function(ComponentInstance, Handle);
    alias da_GetComponentInfo = OSErr function(Component, ComponentDescription*, Handle, Handle, Handle);
    alias da_GetComponentInstanceStorage = Handle function(ComponentInstance aComponentInstance);
}

__gshared
{
    da_SetComponentInstanceStorage SetComponentInstanceStorage;
    da_GetComponentInfo GetComponentInfo;
    da_GetComponentInstanceStorage GetComponentInstanceStorage;
}


