/**
Dynamic bindings to the Cocoa framework.

Copyright: Guillaume Piolat 2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
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

version(X86)
    version = AnyX86;
version(X86_64)
    version = AnyX86;

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
            version(AnyX86) bindFunc(cast(void**)&objc_msgSend_stret, "objc_msgSend_stret");
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
            NSRunLoopCommonModes = NSString.stringWith("kCFRunLoopCommonModes"w);

            // For debugging purpose
            //NSLog(NSString.stringWith("%@\n")._id, NSDefaultRunLoopMode._id);
            //NSLog(NSString.stringWith("%@\n")._id, NSRunLoopCommonModes._id);

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

private __gshared loaderCounterCocoa = 0;

// Call this each time a new owner uses Cocoa functions
// TODO: hold a mutex, because this isn't thread-safe
// Corrolary: how to protect that mutex creation?
void acquireCocoaFunctions() nothrow @nogc
{
    if (DerelictCocoa is null)  // You only live once
    {
        DerelictCocoa = mallocNew!DerelictCocoaLoader();
        DerelictCocoa.load();
    }
}

// Call this each time a new owner releases a Cocoa functions
// TODO: hold a mutex, because this isn't thread-safe
// Corrolary: how to protect that mutex creation?
void releaseCocoaFunctions() nothrow @nogc
{
    /*if (--loaderCounterCocoa == 0)
    {
        DerelictCocoa.unload();
        DerelictCocoa.destroyFree();
    }*/
}

unittest
{
    version(OSX)
    {
        acquireCocoaFunctions();
        releaseCocoaFunctions();
    }
}
