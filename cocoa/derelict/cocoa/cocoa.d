/*
* Copyright (c) 2004-2015 Derelict Developers
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
module derelict.cocoa.cocoa;

import dplug.core.sharedlib;
import dplug.core.nogc;

import derelict.cocoa.runtime;
import derelict.cocoa.foundation;
import derelict.cocoa.appkit;
import derelict.cocoa.coreimage;


version(OSX)
    enum libNames = "/System/Library/Frameworks/Cocoa.framework/Cocoa";
else
    enum libNames = "";


class DerelictCocoaLoader : SharedLibLoader
{
    public
    {
        this() nothrow @nogc
        {
            super(libNames);
        }

        override void loadSymbols() nothrow @nogc
        {
            // Runtime
            bindFunc(cast(void**)&objc_registerClassPair, "objc_registerClassPair");
            bindFunc(cast(void**)&varclass_addIvar, "class_addIvar");
            bindFunc(cast(void**)&varclass_addMethod, "class_addMethod");
            bindFunc(cast(void**)&varobjc_allocateClassPair, "objc_allocateClassPair");
            bindFunc(cast(void**)&objc_disposeClassPair, "objc_disposeClassPair");
            bindFunc(cast(void**)&varobjc_getClass, "objc_getClass");
            bindFunc(cast(void**)&varobjc_lookUpClass, "objc_lookUpClass");

            bindFunc(cast(void**)&objc_msgSend, "objc_msgSend");
            bindFunc(cast(void**)&objc_msgSendSuper, "objc_msgSendSuper");
            bindFunc(cast(void**)&objc_msgSend_stret, "objc_msgSend_stret");
            version(X86) bindFunc(cast(void**)&objc_msgSend_fpret, "objc_msgSend_fpret");

            bindFunc(cast(void**)&varobject_getClassName, "object_getClassName");
            bindFunc(cast(void**)&object_getInstanceVariable, "object_getInstanceVariable");
            bindFunc(cast(void**)&object_setInstanceVariable, "object_setInstanceVariable");
            bindFunc(cast(void**)&varsel_registerName, "sel_registerName");

            bindFunc(cast(void**)&varclass_getInstanceMethod, "class_getInstanceMethod");
            bindFunc(cast(void**)&method_setImplementation, "method_setImplementation");

            bindFunc(cast(void**)&class_addProtocol, "class_addProtocol");
            bindFunc(cast(void**)&objc_getProtocol, "objc_getProtocol");
            bindFunc(cast(void**)&objc_allocateProtocol, "objc_allocateProtocol"); // min 10.7
            bindFunc(cast(void**)&objc_registerProtocol, "objc_registerProtocol"); // min 10.7
            bindFunc(cast(void**)&class_conformsToProtocol, "class_conformsToProtocol"); // min 10.5
            bindFunc(cast(void**)&protocol_addMethodDescription, "protocol_addMethodDescription"); // min 10.7

            // Foundation
            bindFunc(cast(void**)&NSLog, "NSLog");
            bindFunc(cast(void**)&NSAllocateMemoryPages, "NSAllocateMemoryPages");
            bindFunc(cast(void**)&NSDeallocateMemoryPages, "NSDeallocateMemoryPages");

            // MAYDO: load from proper global variables
            NSDefaultRunLoopMode = NSString.stringWith("kCFRunLoopDefaultMode"w);
            NSRunLoopCommonModes = NSString.stringWith("kCFRunLoopCommonModes"w);

            // Appkit
            bindFunc(cast(void**)&NSApplicationLoad, "NSApplicationLoad");

            // Core Image
            // MAYDO load from proper global variables
            kCIFormatARGB8 = 23;
            kCIFormatRGBA16 = 27;
            kCIFormatRGBAf = 34;
            kCIFormatRGBAh = 31;
        }
    }
}


private __gshared DerelictCocoaLoader DerelictCocoa;

private __gshared loaderCounter = 0;

// Call this each time a new owner uses Cocoa functions
// TODO: hold a mutex, because this isn't thread-safe
// Corrolary: how to protect that mutex creation?
void acquireCocoaFunctions() nothrow @nogc
{
    if (loaderCounter++ == 0)  // You only live once
    {
        import core.stdc.stdio;
        DerelictCocoa = mallocEmplace!DerelictCocoaLoader();
        DerelictCocoa.load();
    }
}

// Call this each time a new owner releases a Cocoa functions
// TODO: hold a mutex, because this isn't thread-safe
// Corrolary: how to protect that mutex creation?
void releaseCocoaFunctions() nothrow @nogc
{
    if (--loaderCounter == 0)
    {
        DerelictCocoa.unload();
        DerelictCocoa.destroyFree();
    }
}

unittest
{
    version(OSX)
    {
        acquireCocoaFunctions();
        releaseCocoaFunctions();
    }
}
