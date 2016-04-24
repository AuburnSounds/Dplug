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

import dplug.core;

import std.stdio;

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
    static string customClassName = null;

    NSView parent;
    alias parent this;

    // create from an id
    this(id id_)
    {
        printf("this\n");
        this._id = id_;
    }

    /// Allocates, but do not init
    static DPlugCocoaViewFactory alloc()
    {
        printf("alloc\n");
        alias fun_t = extern(C) id function (id obj, SEL sel);
        return DPlugCocoaViewFactory( (cast(fun_t)objc_msgSend)(getClassID(), sel!"alloc") );
    }

    static Class getClass()
    {
        return cast(Class)( getClassID() );
    }

    static id getClassID()
    {
        assert(customClassName !is null);
        return objc_getClass(customClassName);
    }

    static Class clazz;

    static void registerSubclass()
    {
        import gfm.core;
   //     if (customClassName !is null)
   //         return;
        string uuid = randomUUID().toString();
        customClassName = "DPlugCocoaViewFactory_" ~ uuid;
        clazz = objc_allocateClassPair(cast(Class) lazyClass!"NSObject", toStringz(customClassName), 0);
 //       class_addMethod(clazz, sel!"init:", cast(IMP) &init, "v@:");
        class_addMethod(clazz, sel!"description:", cast(IMP) &description, "@@:");
        class_addMethod(clazz, sel!"interfaceVersion", cast(IMP) &interfaceVersion, "I@:");
        class_addMethod(clazz, sel!"uiViewForAudioUnit:withSize:", cast(IMP) &uiViewForAudioUnit, "@@:^{ComponentInstanceRecord=[1q]}{CGSize=dd}");

        // very important: add an instance variable for the this pointer so that the D object can be
        // retrieved from an id
        class_addIvar(clazz, "this", (void*).sizeof, (void*).sizeof == 4 ? 2 : 3, "^v");

        // Replicates the AUCocoaUIBase protocol
        // Surprinsingly there is no way to have it already without using a @protocol directive.
        // But as it's just runtime documentation, there is no downsize to have it duplicated (hopefully).
        //
        // This protocol is created at runtime because we don't have @protocol in D.
        // http://stackoverflow.com/questions/2615725/how-to-create-a-protocol-at-runtime-in-objective-c
   /*     {

            Protocol *protocol = objc_getProtocol("AUCocoaUIBase".ptr);

            if (protocol == null)
            {
                // create it at runtime
                protocol = objc_allocateProtocol("AUCocoaUIBase".ptr);
                protocol_addMethodDescription(protocol, sel!"interfaceVersion", "I@:", YES, YES);
                protocol_addMethodDescription(protocol, sel!"interfaceVersion:", "@@:^{ComponentInstanceRecord=[1q]}{CGSize=dd}", YES, YES);
                objc_registerProtocol(protocol);
            }

            class_addProtocol(clazz, protocol);

      //      if (!class_conformsToProtocol(clazz, protocol))
        //    {
          //      printf("Does not conform to protocol\n");
            //}
        }*/

/*
            Protocol* baseProtocol = ;
            try
            {
                baseProtocol = objc_getProtocol("AUCocoaUIBase");
            }
            catch(Exception e)
            {
                writeln(e.msg);
            }
            writeln("B");
            class_addProtocol(clazz, baseProtocol);
            writeln("C");
        }*/
        objc_registerClassPair(clazz);
    }

    static void unregisterSubclass()
    {
        // TODO: remove leaking the class
    }

    DPlugCocoaViewFactory getInstance(id anId)
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
    extern(C)
    {
        void init(id self, SEL selector)
        {
            printf("init callbacked\n");
            FPControl fpctrl;
            fpctrl.initialize();
            DPlugCocoaViewFactory factory = getInstance(self);

            // TODO
        }

        id description(id self, SEL selector)
        {
            printf("description callbacked\n");
            FPControl fpctrl;
            fpctrl.initialize();
            DPlugCocoaViewFactory factory = getInstance(self);

            // return ToNSString(PLUG_NAME " View");
            return NSString.stringWith("Filter View")._id;
        }

        uint interfaceVersion(id self, SEL selector)
        {
//            debugBreak();
            printf("interfaceVersion callbacked\n");
            return 0;
        }

        id uiViewForAudioUnit(id self, SEL selector, AudioUnit audioUnit, NSSize preferredSize)
        {
     //       debugBreak();
            printf("uiViewForAudioUnit callbacked\n");
            /*
              mPlug = (IPlugBase*) GetComponentInstanceStorage(audioUnit);
              if (mPlug) {
                IGraphics* pGraphics = mPlug->GetGUI();
                if (pGraphics) {
                  IGRAPHICS_COCOA* pView = (IGRAPHICS_COCOA*) pGraphics->OpenWindow(0);
                  mPlug->OnGUIOpen();
                  return pView;
                }
              }
              */
            return null;
        }
    }

}
