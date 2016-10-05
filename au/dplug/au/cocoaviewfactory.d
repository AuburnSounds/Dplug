/*
Cockos WDL License

Copyright (C) 2005 - 2015 Cockos Incorporated
Copyright (C) 2016 Auburn Sounds

Portions copyright other contributors, see each source file for more information

This software is provided 'as-is', without any express or implied warranty.  In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
1. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
1. This notice may not be removed or altered from any source distribution.
*/
module dplug.au.cocoaviewfactory;

import std.string;
import std.uuid;

import derelict.carbon;
import derelict.cocoa;

import dplug.core.runtime;
import dplug.core.nogc;
import dplug.au.client;


import core.stdc.stdio;

// register a view factory object, return the class name
string registerCocoaViewFactory()
{
    DerelictCocoa.load();
    NSApplicationLoad(); // to use Cocoa in Carbon applications
    DPlugCocoaViewFactory.registerSubclass();
    return DPlugCocoaViewFactory.customClassName;
}


struct DPlugCocoaViewFactory
{
    // This class uses a unique class name for each plugin instance
    static __gshared string customClassName = null;

    NSView parent;
    alias parent this;

    // create from an id
    this(id id_)
    {
        this._id = id_;
    }

    ~this() nothrow
    {
    }

    static __gshared Class clazz;

    static void registerSubclass()
    {
        if (customClassName !is null)
            return;

        string uuid = randomUUID().toString();
        customClassName = "DPlugCocoaViewFactory_" ~ uuid;
        clazz = objc_allocateClassPair(cast(Class) lazyClass!"NSObject", toStringz(customClassName), 0);

        class_addMethod(clazz, sel!"description:", cast(IMP) &description, "@@:");
        class_addMethod(clazz, sel!"interfaceVersion", cast(IMP) &interfaceVersion, "I@:");
        class_addMethod(clazz, sel!"uiViewForAudioUnit:withSize:", cast(IMP) &uiViewForAudioUnit, "@@:^{ComponentInstanceRecord=[1q]}{CGSize=dd}");

        // Very important: add an instance variable for the this pointer so that the D object can be
        // retrieved from an id
        class_addIvar(clazz, "this", (void*).sizeof, (void*).sizeof == 4 ? 2 : 3, "^v");

        // Replicates the AUCocoaUIBase protocol.
        // For host to accept that our object follow AUCocoaUIBase, we replicate AUCocoaUIBase
        // with the same name and methods.
        // This protocol has to be created at runtime because we don't have @protocol in D.
        // http://stackoverflow.com/questions/2615725/how-to-create-a-protocol-at-runtime-in-objective-c
        {

            Protocol *protocol = objc_getProtocol("AUCocoaUIBase".ptr);

            if (protocol == null)
            {
                // create it at runtime
                protocol = objc_allocateProtocol("AUCocoaUIBase".ptr);
                protocol_addMethodDescription(protocol, sel!"interfaceVersion", "I@:", YES, YES);
                protocol_addMethodDescription(protocol, sel!"uiViewForAudioUnit:withSize:", "@@:^{ComponentInstanceRecord=[1q]}{CGSize=dd}", YES, YES);
                objc_registerProtocol(protocol);
            }

            class_addProtocol(clazz, protocol);
        }
        objc_registerClassPair(clazz);
    }

    static void unregisterSubclass() nothrow
    {
        // TODO: remove leaking of class and protocol
    }
}

DPlugCocoaViewFactory getInstance(id anId) nothrow
{
    // strange thing: object_getInstanceVariable definition is odd (void**)
    // and only works for pointer-sized values says SO
    void* thisPointer = null;
    Ivar var = object_getInstanceVariable(anId, "this", &thisPointer);
    assert(var !is null);
    assert(thisPointer !is null);
    return *cast(DPlugCocoaViewFactory*)thisPointer;
}

// Overridden function gets called with an id, instead of the self pointer.
// So we have to get back the D class object address.
// Big thanks to Mike Ash (@macdev)
extern(C) nothrow
{
    id description(id self, SEL selector)
    {
        try
        {
            ScopedForeignCallback!(true, false) scopedCallback;
            scopedCallback.enter();

            return NSString.stringWith("Filter View")._id;
        }
        catch(Exception e)
        {
            unrecoverableError();
            return null;
        }
    }

    uint interfaceVersion(id self, SEL selector)
    {
        return 0;
    }

    // Create the Cocoa view and return it
    id uiViewForAudioUnit(id self, SEL selector, AudioUnit audioUnit, NSSize preferredSize)
    {
        try
        {
            ScopedForeignCallback!(true, true) scopedCallback;
            scopedCallback.enter();

            AUClient plugin = cast(AUClient)( cast(void*)GetComponentInstanceStorage(audioUnit) );
            if (plugin)
            {
                return cast(id)( plugin.openGUIAndReturnCocoaView() );
            }
            else
                return null;
        }
        catch(Exception e)
        {
            unrecoverableError();
            return null;
        }
    }
}
