/**
Dplug's wren bridge. 

Copyright: Guillaume Piolat 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.wren.wrensupport;

import core.stdc.string : memcpy, strlen, strcmp;
import core.stdc.stdlib : malloc, free;
import core.stdc.stdio : snprintf;

import std.traits: getSymbolsByUDA;
import std.meta: staticIndexOf;

import dplug.core.nogc;
import dplug.core.file;
import dplug.gui.context;
import dplug.gui.element;
import dplug.graphics.color;

import wren.vm;
import wren.value;
import wren.primitive;
import wren.common;
import dplug.wren.describe;
import dplug.wren.wren_ui;

nothrow:

/// Automatically set widgets ID. 
/// It generates 
///     _member.id = "_member";
/// for every field that is @ScriptExport, in order to find them from Wren.
string setUIElementsFieldNamesAsTheirId(T)()
{
    import std.traits: getSymbolsByUDA;
    string s;

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
final class WrenSupport
{
nothrow @nogc:

    /// Constructor.
    this(IUIContext uiContext)
    {
        _uiContext = uiContext; // Note: wren VM start is deferred to first use.
    }

    /// Instantiate that with your main UI widget to register widgets classes.
    /// Foreach member variable of `GUIClass` with the `@ScriptExport` attribute, this registers
    /// a Wren class 
    /// The right Wren class can then be returned by the `$` operator and `UI.getElementById` methods.
    ///
    /// Note: the mirror Wren classes don't inherit from each other. Wren doesn't know our D hierarchy.
    void registerScriptExports(GUIClass)()
    {
        // Automatically set widgets ID. _member.id = "_member";
        static foreach(m; getSymbolsByUDA!(GUIClass, ScriptExport))
        {{
            alias dClass = typeof(m);
            registerUIElementClass!dClass();
        }}
    }

    /// Add a UIElement derivative class into the set of known classes in Wren, and all its parent up to UIElement
    /// It is recommended that you use `@ScriptExport` on your fields and `registerScriptExports` instead, but this
    /// can be used to register classes manually.
    ///
    /// Note: the mirror Wren classes don't inherit from each other. Wren doesn't know our D hierarchy.
    void registerUIElementClass(ElemClass)()
    {
        static assert(is(ElemClass: UIElement));
        string fullClassName = ElemClass.classinfo.name;

        if (!hasScriptExportClass(fullClassName)) // PERF: this is quadratic
        {
            ScriptExportClass c = mallocNew!ScriptExportClass();
            c.concreteClassInfo = ElemClass.classinfo;
            registerDClass!ElemClass(c);
            _exportedClasses ~= c;
        }
    }
  
    /// Add a read-only Wren module source code, to be loaded once and never changed.
    /// Release purpose. When in developement, you might prefer a reloadable file, with `addModuleFileWatch`.
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

    /// Add a dynamic reloadable .wren source file. The module is reloaded and compared when `reloadScriptsThatChanged()` is called.
    /// Development purpose. For a release plug-in, you want to use `addModuleSource` instead.
    void addModuleFileWatch(const(char)[] moduleName, const(char)[] wrenFilePath)
    {
        // This forces a zero terminator.
        // PERF: use less zero-terminated strings in Wren, so that we don't have to do this
        char* moduleNameZ = stringDup(CString(moduleName).storage).ptr;
        char* wrenFilePathZ = stringDup(CString(wrenFilePath).storage).ptr;

        FileWatch fw;
        fw.moduleName = moduleNameZ;
        fw.wrenFilePath = wrenFilePathZ;
        fw.lastSource = null;

        _fileSources.pushBack(fw);
    }

    /// To call in your UI's constructor. This call the `Plugin.createUI` Wren method, in module "plugin".
    ///
    /// Note: Changing @ScriptProperty values does not make the elements dirty.
    ///       But since it's called at UI creation, the whole UI is dirty anyway so it works.
    ///
    void callCreateUI()
    {
        callPluginMethod("createUI");
    }

    /// To call in your UI's `reflow()` method. This call the `Plugin.reflow` Wren method, in module "plugin".
    ///
    /// Note: Changing @ScriptProperty values does not make the elements dirty.
    ///       But since it's called at UI reflow, the whole UI is dirty anyway so it works.
    ///
    void callReflow()
    {
        callPluginMethod("reflow");
    }

    // <advanced API>

    /// Call Plugin.<methodName>, a static method without arguments in Wren. For advanced users only.
    void callPluginMethod(const(char)* methodName)
    {
        reloadScriptsThatChanged();
        enum int MAX = 64+MAX_VARIABLE_NAME*2;
        char[MAX] code;
        snprintf(code.ptr, MAX, "{\n \nimport \"plugin\" for Plugin\n Plugin.%s()\n}\n", methodName);
        interpret(code.ptr);
    }

    /// Interpret arbitrary code. For advanced users only.
    void interpret(const(char)* path, const(char)* source)
    {
        try
        {
            WrenInterpretResult result = wrenInterpret(_vm, path, source);
        }
        catch(Exception e)
        {
            // Note: error reported by another mechanism anyway.
            destroyFree(e);
        }
    }

    /// Interpret arbitrary code. For advanced users only.
    void interpret(const(char)* source)
    {
        interpret("", source);
    }  

    // </advanced API>

    ~this()
    {
        stopWrenVM();

        foreach(ps; _preloadedSources[])
        {
            free(ps.moduleName);
            free(ps.source);
        }

        foreach(fw; _fileSources[])
        {
            free(fw.moduleName);
            free(fw.wrenFilePath);
            free(fw.lastSource);
        }

        foreach(ec; _exportedClasses[])
        {
            destroyFree(ec);
        }
    }

package:

    IUIContext uiContext()
    {
        return _uiContext;
    }

    ScriptPropertyDesc* getScriptProperty(int nthClass, int nthProp)
    {
        ScriptExportClass sec = _exportedClasses[nthClass];
        ScriptPropertyDesc[] descs = sec.properties();
        return &descs[nthProp];
    }

private:

    WrenVM* _vm = null;
    IUIContext _uiContext;

    static struct PreloadedSource
    {
        char* moduleName;
        char* source;
    }

    static struct FileWatch
    {
    nothrow:
    @nogc:
        char* moduleName;
        char* wrenFilePath;
        char* lastSource;

        bool updateAndReturnIfChanged()
        {
            char* newSource = readWrenFile();
       
            if ((lastSource is null) || strcmp(lastSource, newSource) != 0)
            {
                free(lastSource);
                lastSource = newSource;
                return true;
            }
            else
                return false;
        }

        char* readWrenFile()
        {
            ubyte[] content = readFile(wrenFilePath);
            scope(exit) free(content.ptr);

            // If you fail here, your absolute path to a .wren script was wrong
            assert(content);

            // PERF: create directly a trailing \0 while reading the file
            char* source = cast(char*) malloc(content.length + 1);
            memcpy(source, content.ptr, content.length); 
            source[content.length] = '\0';
            return source;
        }
    }

    /// All known premade modules.
    Vec!PreloadedSource _preloadedSources;

    /// All known file-watch modules.
    Vec!FileWatch _fileSources;

    /// All known D @ScriptExport classes.
    Vec!ScriptExportClass _exportedClasses;

    /// "widgets" module source, recreated on import based upon _exportedClasses content.
    Vec!char _widgetModuleSource;


    // Check the registered .wren file and check if they have changed.
    // Since it (re)starts the Wren VM, it cannot be called from Wren.
    void reloadScriptsThatChanged()
    {
        bool oneScriptChanged = false;
        foreach(ref fw; _fileSources)
        {
            if (fw.updateAndReturnIfChanged())
                oneScriptChanged = true;
        }

        // If a script changed, we need to restart the whole Wren VM since there is no way to forger about a module!
        if (oneScriptChanged)
            stopWrenVM();

        // then ensure Wren VM is on
        startWrenVM();
    }


    void startWrenVM()
    {
        if (_vm !is null)
            return; // Already started

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

    void stopWrenVM()
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

        // Try file-watch source first
        foreach(fw; _fileSources[])
        {
            if (strcmp(name, fw.moduleName) == 0)
            {
                assert(fw.lastSource); // should have parsed the file preventively
                res.source = fw.lastSource;
                goto found;
            }
        }

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
            instance.fields[0] = OBJ_VAL(foreign); // TODO: field seems to be collected already when VM is terminated

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
                    // getter
                    text("  "); text(prop.identifier); text("{"); LF;
                    text("    return RGBA.new( e.getPropRGBA_("); textZ(bufC.ptr); text(","); textZ(buf.ptr); text(",0),");
                                         text("e.getPropRGBA_("); textZ(bufC.ptr); text(","); textZ(buf.ptr); text(",1),");
                                         text("e.getPropRGBA_("); textZ(bufC.ptr); text(","); textZ(buf.ptr); text(",2),");
                                         text("e.getPropRGBA_("); textZ(bufC.ptr); text(","); textZ(buf.ptr); text(",3))"); LF;
                    text("  }"); LF;

                    // setter for a RGBA property
                    text("  "); text(prop.identifier); text("=(c){"); LF;
                    text("    e.setPropRGBA_("); textZ(bufC.ptr); text(","); textZ(buf.ptr); text(",c.r, c.g, c.b, c.a)"); LF;
                    text("  }"); LF;

                    // same but return this for chaining syntax
                    text("  "); text(prop.identifier); text("(c){"); LF;
                    text("    e.setPropRGBA_("); textZ(bufC.ptr); text(","); textZ(buf.ptr); text(",c.r, c.g, c.b, c.a)"); LF;
                    text("    return this"); LF;
                    text("  }"); LF;
                }
                else
                {
                    // getter
                    text("  "); text(prop.identifier); text("{"); LF;
                    text("    return e.getProp_("); textZ(bufC.ptr); text(","); textZ(buf.ptr); text(")"); LF;
                    text("  }"); LF;

                    // setter for property (itself a Wren property setter)
                    text("  "); text(prop.identifier); text("=(x){"); LF;
                    text("    e.setProp_("); textZ(bufC.ptr); text(","); textZ(buf.ptr); text(",x)"); LF;
                    text("  }"); LF;

                     // same but return this for chaining syntax
                    text("  "); text(prop.identifier); text("(x){"); LF;
                    text("    e.setProp_("); textZ(bufC.ptr); text(","); textZ(buf.ptr); text(",x)"); LF;
                    text("    return this"); LF;
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

    // Add a single UIElement derivative class into the set of known classes in Wren
    // Note that it enumerates all @ScriptProperty from its ancestors too, so it works.
    // Wren code doesn't actually know that UIImageKnob is derived from UIKnob.
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