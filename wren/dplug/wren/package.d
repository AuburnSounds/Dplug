/**
Dplug's wren bridge. 

Copyright: Guillaume Piolat 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.wren;


import std.meta: staticIndexOf;

import dplug.core.nogc;
import dplug.gui.context;
import dplug.gui.element;

import wren.vm;

nothrow @nogc:

/// Create wren support for this UI tree, puts it in UIContext under pimpl idiom.
/// Returns the Wren support object.
/// Call this in your gui.d this.
void enableWrenSupport(IUIContext context)
{
    WrenSupport w = mallocNew!WrenSupport();
    context.setUserPointer(UICONTEXT_POINTERID_WREN_SUPPORT, cast(void*)w);
}

/// Disable wren support, meaning it will release the Wren VM and integration.
/// Call this in your gui.d ~this.
void disableWrenSupport(IUIContext context)
{
    WrenSupport w = wrenSupport(context);
    context.setUserPointer(UICONTEXT_POINTERID_WREN_SUPPORT, null);
}

/// Get the `WrenSupport` object that holds all wren state and integration with the plugin.
WrenSupport wrenSupport(IUIContext context)
{
    return cast(WrenSupport) context.getUserPointer(UICONTEXT_POINTERID_WREN_SUPPORT);
}

string registerUIElements(alias moduleName)()
{
    string s = "context().enableWrenSupport();";

    static foreach(t; __traits(allMembers, moduleName))
    {
 //       pragma(msg, t.stringof);
    }
    return s;
}

class WrenSupport
{
nothrow @nogc:

    this()
    {
        try
        {
            WrenConfiguration config;
            wrenInitConfiguration(&config);
        
            config.writeFn = &wrenPrint;
            config.errorFn = &wrenError;
            config.userData = cast(void*)this;

            // Since we're running in a standalone process, be generous with memory.
            config.initialHeapSize = 1024 * 1024 * 10;
            _vm = wrenNewVM(&config);
        }
        catch(Exception e)
        {
            debugLog("VM initialization failed");
            destroyFree(e);
            _vm = null; 
        }
    }

    ~this()
    {
        if (_vm !is null)
        {
            try
            {
                wrenFreeVM(_vm);
            }
            catch(Exception e)
            {
                destroyFree(e);
            }
            _vm = null;
        }
    }

    // Important: path and source MUST be zero terminated.
    void interpret(const(char)[] path, const(char)[] source)
    {
        const(char)* sourceZ = assumeZeroTerminated(source);
        const(char)* pathZ = assumeZeroTerminated(path);
        try
        {
            WrenInterpretResult result = wrenInterpret(_vm, pathZ, sourceZ);
        }
        catch(Exception e)
        {
            // Note: error reported by another mechanism anyway.
            destroyFree(e);
        }
    }

    void registerUIElement(alias uiClass)() if (is(uiClass: UIElement))
    {
        enum UDAs = __traits(getAttributes, uiClass);
        bool isScripExport = (staticIndexOf!(ScriptExport, UDAs) == -1);
        assert(isScripExport);       

        foreach (memberName; __traits(allMembers, uiClass))
        {
        //    pragma(msg, memberName);
        }
    }    

private:

    WrenVM* _vm;

    void print(const(char)* text)
    {
        debugLog(text);
    }

    void error(WrenErrorType type, const(char)* module_, int line, const(char)* message)
    {
        switch(type)
        {
            case WrenErrorType.WREN_ERROR_COMPILE:
                debugLogf("%s(%d): Error: %s", module_, line, message);
                break;

            case WrenErrorType.WREN_ERROR_RUNTIME:
                debugLogf("wren crash: %s", message);
                break;

            case WrenErrorType.WREN_ERROR_STACK_TRACE:
                debugLogf("  %s.%s:%d", module_, message, line);
                break;

            default:
                assert(false);
        }
    }
}

private:


void wrenPrint(WrenVM* vm, const(char)* text)
{
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    ws.print(text);
}

void wrenError(WrenVM* vm, WrenErrorType type, const(char)* module_, int line, const(char)* message)
{
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    ws.error(type, module_, line, message);
}