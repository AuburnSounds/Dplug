/**
Dplug's wren bridge. 

Copyright: Guillaume Piolat 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.wren.wrensupport;

import core.stdc.string : strcmp;
import std.traits: getSymbolsByUDA;
import std.meta: staticIndexOf;

import dplug.core.nogc;
import dplug.gui.context;
import dplug.gui.element;

import wren.vm;
import wren.value;

import dplug.wren.wren_uicontext;

nothrow @nogc:



string registerUIElements(alias moduleName)()
{
    // WIP
    string s = "context().enableWrenSupport();";

    static foreach(t; __traits(allMembers, moduleName))
    {
        //       pragma(msg, t.stringof);
    }
    return s;
}

/// Manages interaction between Wren and the plugin. 
/// Note: this is interlinked with UIContext.
/// This class could as well be a part of UIContext.
class WrenSupport
{
nothrow @nogc:

    this(IUIContext uiContext)
    {
        _uiContext = uiContext;
        try
        {
            WrenConfiguration config;
            wrenInitConfiguration(&config);

            config.writeFn             = &dplug_wrenPrint;
            config.errorFn             = &dplug_wrenError;
            config.bindForeignMethodFn = &dplug_wrenBindForeignMethod;
            config.bindForeignClassFn  = &dplug_wrenBindForeignClass;
            config.loadModuleFn        = &dplug_wrenLoadModule;
            config.userData            = cast(void*)this;

            // Note: wren defaults for memory usage make a lot of sense.
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

    IUIContext uiContext()
    {
        return _uiContext;
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

    // same but without module name
    void interpret(const(char)[] source)
    {
        interpret("", source);
    }

    void registerUIElement(alias uiClass)() if (is(uiClass: UIElement))
    {
        enum UDAs = __traits(getAttributes, uiClass);
        enum isScripExport = (staticIndexOf!(ScriptExport, UDAs) == -1);
        static assert(isScripExport);
        static foreach(T; getSymbolsByUDA!(uiClass, ScriptProperty))
        {
   //         pragma(msg, T.stringof);

        }
    }    
/*
    void callStaticMethod()
    {
        WrenHandle* wrenMakeCallHandle(WrenVM* vm, const char* signature);
    }*/
/*
    void callReflow()
    {
        try
        {
            WrenHandle* reflowHandle = wrenMakeCallHandle(_vm, "reflow()");
            wrenEnsureSlots(_vm, 1);
            wrenGetVariable(_vm, "main", "Plugin", 0);
            WrenHandle* pluginClass = wrenGetSlotHandle(_vm, 0);
            wrenSetSlotHandle(_vm, 0, pluginClass);
            wrenCall(_vm, reflowHandle);
        }
        catch(Exception e)
        {
            int b = 0;
        }
    } */

private:

    WrenVM* _vm;
    IUIContext _uiContext;

    void print(const(char)* text)
    {
        debugLog(text);
    }

    void error(WrenErrorType type, const(char)* module_, int line, const(char)* message)
    {
        switch(type)
        {
            case WrenErrorType.WREN_ERROR_COMPILE:
                debugLogf("%s(%d): Error: %s\n", module_, line, message);
                break;

            case WrenErrorType.WREN_ERROR_RUNTIME:
                debugLogf("wren crash: %s\n", message);
                break;

            case WrenErrorType.WREN_ERROR_STACK_TRACE:
                debugLogf("  %s.%s:%d\n", module_, message, line);
                break;

            default:
                assert(false);
        }
    }

    // this is called anytime Wren looks for a foreign method
    WrenForeignMethodFn foreignMethod(WrenVM* vm, const(char)* module_, const(char)* className, bool isStatic, const(char)* signature)
    {
        try
        {
            if (strcmp(module_, "ui") == 0)
            {
                if (strcmp(className, "UI") == 0)
                {
                    return wrenUIContextBindForeignMethod(vm, className, isStatic, signature);
                }
            }
            return null;
        }
        catch(Exception e)
        {
            return null;
        }
    }

    // this is called anytime Wren looks for a foreign class
    WrenForeignClassMethods foreignClass(WrenVM* vm, const(char)* module_, const(char)* className)
    {
        // TODO
        WrenForeignClassMethods methods;
        /* if (strcmp(className, "File") == 0)
        {
        methods.allocate = fileAllocate;
        methods.finalize = fileFinalize;
        }
        else */
        {
            // Unknown class.
            methods.allocate = null;
            methods.finalize = null;
        }
        return methods;
    }

    WrenLoadModuleResult loadModule(WrenVM* vm, const(char)* name)
    {
        WrenLoadModuleResult res;
        res.source = null;
        res.onComplete = null;
        res.userData = null;

        try
        {   
            if (strcmp(name, "ui") == 0)
                res.source = wrenUIContextSource();
        }
        catch(Exception e)
        {
            res.source = null;
        }
        return res;
    }
}

private:


void dplug_wrenPrint(WrenVM* vm, const(char)* text)
{
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    ws.print(text);
}

void dplug_wrenError(WrenVM* vm, WrenErrorType type, const(char)* module_, int line, const(char)* message)
{
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    ws.error(type, module_, line, message);
}

WrenForeignMethodFn dplug_wrenBindForeignMethod(WrenVM* vm, const(char)* module_, const(char)* className, bool isStatic, const(char)* signature)
{
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    return ws.foreignMethod(vm, module_, className, isStatic, signature);
}

WrenForeignClassMethods dplug_wrenBindForeignClass(WrenVM* vm, const(char)* module_, const(char)* className)
{
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    return ws.foreignClass(vm, module_, className);
}

WrenLoadModuleResult dplug_wrenLoadModule(WrenVM* vm, const(char)* name)
{
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    return ws.loadModule(vm, name);
}