/**
Dplug's wren bridge. 

Copyright: Guillaume Piolat 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.wren.wrensupport;

import core.stdc.string : strlen, strcmp;
import core.stdc.stdlib : free;
import core.stdc.stdio : snprintf;

import std.traits: getSymbolsByUDA;
import std.meta: staticIndexOf;

import dplug.core.nogc;
import dplug.gui.context;
import dplug.gui.element;
import dplug.graphics.color;

import wren.vm;
import wren.value;
import wren.primitive;
import dplug.wren.describe;
import dplug.wren.wren_ui;

nothrow:

string setUIElementsFieldNamesAsTheirId(T)()
{
    import std.traits: getSymbolsByUDA;
    string s;

    // Automatically set widgets ID. _member.id = "_member";
    static foreach(m; getSymbolsByUDA!(T, ScriptExport))
    {{
        string fieldName = m.stringof;
        s ~= fieldName ~ ".id = \"" ~ fieldName ~ "\";\n";
    }}
    return s;
}

@nogc:

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
            config.dollarOperatorFn    = &dplug_wrenDollarOperator;
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

        foreach(ps; _preloadedSources[])
        {
            free(ps.moduleName);
            free(ps.source);
        }

        foreach(ec; _exportedClasses[])
        {
            destroyFree(ec);
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

    private void registerDClass(alias aClass)(ScriptExportClass classDesc)
    {
        static foreach(P; getSymbolsByUDA!(aClass, ScriptProperty))
        {{
            alias FieldType = typeof(P);

            enum string fieldName = P.stringof;
            enum size_t offsetInClass = P.offsetof;

            ScriptPropertyDesc desc;
            desc.identifier = fieldName;
            desc.offset = offsetInClass;
            static if (is(FieldType == enum))
            {
                // Note: enum are just integers in Wren, no translation of enum value.
                static if (FieldType.sizeof == 1)
                    desc.type = ScriptPropertyType.byte_;
                else static if (FieldType.sizeof == 2)
                    desc.type = ScriptPropertyType.short_;
                else static if (FieldType.sizeof == 4)
                    desc.type = ScriptPropertyType.int_;
                else
                    static assert(false, "Unsupported enum size in @ScriptProperty field " ~ fieldName ~  " of type " ~ FieldType.stringof);
            }
            else static if (is(FieldType == bool))
                desc.type = ScriptPropertyType.bool_;
            else static if (is(FieldType == RGBA))
                desc.type = ScriptPropertyType.RGBA;
            else static if (is(FieldType == ubyte))
                desc.type = ScriptPropertyType.ubyte_;
            else static if (is(FieldType == byte))
                desc.type = ScriptPropertyType.byte_;
            else static if (is(FieldType == ushort))
                desc.type = ScriptPropertyType.ushort_;
            else static if (is(FieldType == short))
                desc.type = ScriptPropertyType.short_;
            else static if (is(FieldType == uint))
                desc.type = ScriptPropertyType.uint_;
            else static if (is(FieldType == int))
                desc.type = ScriptPropertyType.int_;
            else static if (is(FieldType == float))
                desc.type = ScriptPropertyType.float_;
            else static if (is(FieldType == double))
                desc.type = ScriptPropertyType.double_;
            else static if (is(FieldType == L16)) // Note: this is deprecated. L16 properties should be eventually replaced by ushort instead.
                desc.type = ScriptPropertyType.ushort_;
            else
                static assert(false, "No @ScriptProperty support for field " ~ fieldName ~  " of type " ~ FieldType.stringof); // FUTURE: a way to add other types for properties?

            classDesc.addProperty(desc);
        }}
    }

    void registerScriptExports(UIClass)()
    {
        // Automatically set widgets ID. _member.id = "_member";
        static foreach(m; getSymbolsByUDA!(UIClass, ScriptExport))
        {{
            alias dClass = typeof(m);
            string fullClassName = dClass.classinfo.name;
            if (!hasScriptExportClass(fullClassName)) // PERF: this is quadratic
            {
                ScriptExportClass c = mallocNew!ScriptExportClass();
                c.concreteClassInfo = dClass.classinfo;
                registerDClass!dClass(c);
                _exportedClasses ~= c;
            }
        }}
    }

    void callCreateUI()
    {
        static immutable string code =
            "{ \n" ~
            "  import \"plugin\" for Plugin\n" ~
            "  Plugin.createUI()\n" ~
            "}\n";
        interpret(code);
    }

    void callReflow()
    {
        static immutable string code =
        "{ \n" ~
        "  import \"plugin\" for Plugin\n" ~
        "  Plugin.reflow()\n" ~
        "}\n";
        interpret(code);
    }

    /// Add read-only static module source code, to be loaded eventually.
    void addModuleSource(const(char)[] moduleName, const(char)[] moduleSource)
    {
        // This forces a zero terminator.
        // PERF: use less zero-terminated strings in Wren, so that we don't have to do this
        char* moduleNameZ = stringDup(CString(moduleName).storage).ptr;
        char* moduleSourceZ = stringDup(CString(moduleSource).storage).ptr;

        PreloadedSource ps;
        ps.moduleName = moduleNameZ;
        ps.source = moduleSourceZ;
        _preloadedSources.pushBack(ps);
    }

    ScriptPropertyDesc* getScriptProperty(int nthClass, int nthProp)
    {
        ScriptExportClass sec = _exportedClasses[nthClass];
        ScriptPropertyDesc[] descs = sec.properties();
        return &descs[nthProp];
    }

private:

    WrenVM* _vm;
    IUIContext _uiContext;

    static struct PreloadedSource
    {
        char* moduleName;
        char* source;
    }

    /// All known premade modules.
    Vec!PreloadedSource _preloadedSources;

    /// All known D @ScriptExport classes.
    Vec!ScriptExportClass _exportedClasses;

    /// "widgets" module source, recreated on import based upon _exportedClasses content.
    Vec!char _widgetModuleSource;

    bool hasScriptExportClass(string fullName)
    {
        foreach(e; _exportedClasses[])
            if (e.fullClassName() == fullName)
                return true;
        return false;
    }

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
        // Introducing the Dplug-Wren standard library here.
        try
        {
            if (strcmp(module_, "ui") == 0)
            {
                return wrenUIBindForeignMethod(vm, className, isStatic, signature);
            }
            return null;
        }
        catch(Exception e)
        {
            destroyFree(e);
            return null;
        }
    }

    // this is called anytime Wren looks for a foreign class
    WrenForeignClassMethods foreignClass(WrenVM* vm, const(char)* module_, const(char)* className)
    {
        if (strcmp(module_, "ui") == 0)
            return wrenUIForeignClass(vm, className);

        WrenForeignClassMethods methods;
        methods.allocate = null;
        methods.finalize = null;
        return methods;
    }

    WrenLoadModuleResult loadModule(WrenVM* vm, const(char)* name)
    {
        WrenLoadModuleResult res;
        res.source = null;
        res.onComplete = null;
        res.userData = null;

        // Try preloaded source first
        foreach(ps; _preloadedSources[])
        {
            if (strcmp(name, ps.moduleName) == 0)
            {
                res.source = ps.source;
                goto found;
            }
        }

        try
        {   
            if (strcmp(name, "widgets") == 0)
                res.source = widgetModuleSource();

            if (strcmp(name, "ui") == 0)
                res.source = wrenUIModuleSource();
        }
        catch(Exception e)
        {
            destroyFree(e);
            res.source = null;
        }
        found:
        return res;
    }

    // TODO: return the right class, depending on what is imported in the module and its .classinfo

    bool dollarOperator(WrenVM* vm, Value* args)
    {
        try
        {
            if (!IS_STRING(args[0]))
                return false;

            const(char)* id = AS_STRING(args[0]).value.ptr;
            UIElement elem = _uiContext.getElementById(id);

            // Find a Wren class we have to convert it to.
            // $ can be any of the improted classes in "widgets", if not it is an UIElement.
            // Note that both "ui" and "widgets" module MUST be imported.

            ObjModule* uiModule, widgetsModule;
            {
                Value moduleName = wrenStringFormat(vm, "$", "ui".ptr);
                wrenPushRoot(vm, AS_OBJ(moduleName));
                uiModule = getModule(vm, moduleName);
                if (uiModule is null)
                {
                    wrenPopRoot(vm);
                    return RETURN_ERROR(vm, "module \"ui\" is not imported");
                }
                wrenPopRoot(vm);
            }
            {
                Value moduleName = wrenStringFormat(vm, "$", "widgets".ptr);
                wrenPushRoot(vm, AS_OBJ(moduleName));
                widgetsModule = getModule(vm, moduleName);
                if (widgetsModule is null)
                {
                    wrenPopRoot(vm);
                    return RETURN_ERROR(vm, "module \"widgets\" is not imported");
                }
                wrenPopRoot(vm);
            }

            // try to find concrete class directly
            ObjClass* classElement;
            ObjClass* classTarget;
            ScriptExportClass* concreteClassInfo = findExportedClassByClassInfo(elem.classinfo);
            if (concreteClassInfo)
            {
                // PERF: this allocates
                CString nameZ = CString(concreteClassInfo.className());
                classTarget = AS_CLASS(wrenFindVariable(vm, widgetsModule, nameZ.storage));
            }
            else
                classTarget = AS_CLASS(wrenFindVariable(vm, uiModule, "UIElement"));

            classElement = AS_CLASS(wrenFindVariable(vm, uiModule, "Element"));

            if (classTarget is null)
            {
                return RETURN_ERROR(vm, "cannot create a IUElement from operator $");
            }

            Value obj = wrenNewInstance(vm, classTarget);

            // Create new Element foreign
            ObjForeign* foreign = wrenNewForeign(vm, classElement, UIElementBridge.sizeof);
            UIElementBridge* bridge = cast(UIElementBridge*) foreign.data.ptr;
            bridge.elem = elem;

            // Assign it in the first field of the newly created ui.UIElement
            ObjInstance* instance = AS_INSTANCE(obj);
            instance.fields[0] = OBJ_VAL(foreign);

            return RETURN_OBJ(args, AS_INSTANCE(obj));
        }
        catch(Exception e)
        {
            destroyFree(e);
            return false;
        }
    }

    // auto-generate the "widgets" Wren module
    const(char)* widgetModuleSource()
    {
        _widgetModuleSource.clearContents();

        void text(const(char)[] s)
        {
            _widgetModuleSource.pushBack(cast(char[])s); // const_cast here
        }

        void textZ(const(char)* s)
        {
            _widgetModuleSource.pushBack(cast(char[])s[0..strlen(s)]); // const_cast here
        }

        void LF()
        {
            _widgetModuleSource.pushBack('\n');
        }

        text(`import "ui" for UIElement, RGBA`); LF;

        foreach(size_t nthClass, ec; _exportedClasses[])
        {
            text("class "); text(ec.className); text(" is UIElement {"); LF;

            char[16] bufC;
            snprintf(bufC.ptr, 16, "%d", cast(int)nthClass);

            foreach(size_t nth, prop; ec.properties())
            {
                char[16] buf;
                snprintf(buf.ptr, 16, "%d", cast(int)nth);

                bool isRGBA = prop.type == ScriptPropertyType.RGBA;

                if (isRGBA)
                {
                    // setter for a RGBA property
                    text("  "); text(prop.identifier); text("=(c){"); LF;
                    text("    innerElement.setPropRGBA_("); textZ(bufC.ptr); text(","); textZ(buf.ptr); text(",c.r, c.g, c.b, c.a)"); LF;
                    text("  }"); LF;
                }
                else
                {
                    // getter
                    text("  "); text(prop.identifier); text("{"); LF;
                    text("    return innerElement.getProp_("); textZ(bufC.ptr); text(","); textZ(buf.ptr); text(")"); LF;
                    text("  }"); LF;

                    // setter for property (itself a Wren property setter)
                    text("  "); text(prop.identifier); text("=(x){"); LF;
                    text("    innerElement.setProp_("); textZ(bufC.ptr); text(","); textZ(buf.ptr); text(",x)"); LF;
                    text("  }"); LF;
                }
            }
            LF;
            text("}"); LF; LF;
        }

        _widgetModuleSource.pushBack('\0');
        return _widgetModuleSource.ptr;
    }


    ScriptExportClass* findExportedClassByClassInfo(TypeInfo_Class info)
    {
        foreach(ref ScriptExportClass sec; _exportedClasses[])
        {
            if (sec.concreteClassInfo is info)
            {
                // Found
                return &sec;
            }
        }
        return null;
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

bool dplug_wrenDollarOperator(WrenVM* vm, Value* args)
{
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    return ws.dollarOperator(vm, args);
}