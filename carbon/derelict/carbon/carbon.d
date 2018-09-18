/**
Dynamic bindings to the Carbon framework.

Copyright: Guillaume Piolat 2015.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module derelict.carbon.carbon;


import dplug.core.sharedlib;

import derelict.carbon.hitoolbox;

import dplug.core.nogc;

version(OSX)
    enum libNames = "/System/Library/Frameworks/Carbon.framework/Carbon";
else
    enum libNames = "";


class DerelictCarbonLoader : SharedLibLoader
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
            // hitoolbox
            bindFunc(cast(void**)&GetMainEventLoop, "GetMainEventLoop");
            bindFunc(cast(void**)&InstallEventHandler, "InstallEventHandler");
            bindFunc(cast(void**)&GetControlEventTarget, "GetControlEventTarget");
            bindFunc(cast(void**)&GetWindowEventTarget, "GetWindowEventTarget");

           // Not available in macOS 10.12 in 64-bit
            static if (size_t.sizeof == 4)
                bindFunc(cast(void**)&CreateUserPaneControl, "CreateUserPaneControl");

            bindFunc(cast(void**)&GetWindowAttributes, "GetWindowAttributes");
            bindFunc(cast(void**)&HIViewGetRoot, "HIViewGetRoot");
            bindFunc(cast(void**)&HIViewFindByID, "HIViewFindByID");
            bindFunc(cast(void**)&HIViewSetNeedsDisplayInRect, "HIViewSetNeedsDisplayInRect");
            bindFunc(cast(void**)&HIViewAddSubview, "HIViewAddSubview");

            // Removed for no reason, still here in macOS 10.12
            //bindFunc(cast(void**)&GetRootControl, "GetRootControl");
            //bindFunc(cast(void**)&CreateRootControl, "CreateRootControl");
            //static if (size_t.sizeof == 4)
            //    bindFunc(cast(void**)&EmbedControl, "EmbedControl");

            bindFunc(cast(void**)&SizeControl, "SizeControl");
            bindFunc(cast(void**)&GetEventClass, "GetEventClass");
            bindFunc(cast(void**)&GetEventKind, "GetEventKind");
            bindFunc(cast(void**)&GetEventParameter, "GetEventParameter");
            bindFunc(cast(void**)&RemoveEventLoopTimer, "RemoveEventLoopTimer");
            bindFunc(cast(void**)&RemoveEventHandler, "RemoveEventHandler");
            bindFunc(cast(void**)&InstallEventLoopTimer, "InstallEventLoopTimer");
            bindFunc(cast(void**)&HIPointConvert, "HIPointConvert");
            bindFunc(cast(void**)&HIViewGetBounds, "HIViewGetBounds");
        }
    }
}


private __gshared DerelictCarbonLoader DerelictCarbon;

private __gshared loaderCounterCarbon = 0;

// Call this each time a novel owner uses these functions
// TODO: hold a mutex, because this isn't thread-safe
void acquireCarbonFunctions() nothrow @nogc
{
    if (DerelictCarbon is null)  // You only live once
    {
        DerelictCarbon = mallocNew!DerelictCarbonLoader();
        DerelictCarbon.load();
    }
}

// Call this each time a novel owner releases a Cocoa functions
// TODO: hold a mutex, because this isn't thread-safe
void releaseCarbonFunctions() nothrow @nogc
{
    /*if (--loaderCounterCarbon == 0)
    {
        DerelictCarbon.unload();
        DerelictCarbon.destroyFree();
    }*/
}

unittest
{
    version(OSX)
    {
        acquireCarbonFunctions();
        releaseCarbonFunctions();
    }
}
