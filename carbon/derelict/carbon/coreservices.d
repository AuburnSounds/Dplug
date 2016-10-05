/*
* Copyright (c) 2015 Guillaume Piolat
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without
* modification, are permitted provided that the following conditions are
* met:
*
* * Redistributions of source code must retain the above copyright
*   notice, this list of conditions and the following disclaimer.
*
* * Redistributions in binary form must reproduce the above copyright
*   notice, this list of conditions and the following disclaimer in the
*   documentation and/or other materials provided with the distribution.
*
* * Neither the names 'Derelict', 'DerelictSDL', nor the names of its contributors
*   may be used to endorse or promote products derived from this software
*   without specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
* "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
* TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
* PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
* CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
* EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
* PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
* PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
* LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
* NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
* SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
module derelict.carbon.coreservices;

// TODO: this should go in its own Derelict package

version(OSX):

import core.stdc.config;

import derelict.util.system;
import derelict.util.loader;

import derelict.carbon.corefoundation;

static if(Derelict_OS_Mac)
    enum libNames = "/System/Library/Frameworks/CoreServices.framework/CoreServices";
else
    static assert(0, "Need to implement CoreServices libNames for this operating system.");


class DerelictCoreServicesLoader : SharedLibLoader
{
    protected
    {
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

__gshared DerelictCoreServicesLoader DerelictCoreServices;

shared static this()
{
    DerelictCoreServices = new DerelictCoreServicesLoader;
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
    typeDecimalStruct          = CCONST('d', 'e', 'c', 'm')
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


