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

nothrow @nogc:

///
/// `WrenSupport` manages interaction between Wren and the plugin. 
/// Such an object is created/destroyed/accessed with `enableWrenSupport()`, `disableWrenSupport()`,
/// and `wrenSupport()`. It is held, as all GUI globals in the `UIContext`.
///
/// Example:
/// ---
/// // Inside your UI constructor
/// mixin(fieldIdentifiersAreIDs!DistortGUI);
/// context.enableWrenSupport();
/// debug
///     context.wrenSupport.addModuleFileWatch("plugin", `/absolute/path/to/my/plugin.wren`); // Live-reload
/// else
///     context.wrenSupport.addModuleSource("plugin", import("plugin.wren"));                 // Final release has static scripts
/// context.wrenSupport.registerScriptExports!DistortGUI;
/// context.wrenSupport.callCreateUI();
///
/// // Inside your UI destructor
/// context.disableWrenSupport();
/// ---
///
/// See_also: `enableWrenSupport()`, `disableWrenSupport()`
///
final class WrenSupport
{
@nogc:

    /// Constructor. Use `context.enableWrenSupport()` instead.
    this(IUIContext uiContext) nothrow
    {
        _uiContext = uiContext; // Note: wren VM start is deferred to first use.
    }

    /// Instantiate that with your main UI widget to register widgets classes.
    /// Foreach member variable of `GUIClass` with the `@ScriptExport` attribute, this registers
    /// a Wren class 
    /// The right Wren class can then be returned by the `$` operator and `UI.getElementById` methods.
    ///
    /// Note: the mirror Wren classes don't inherit from each other. Wren doesn't know our D hierarchy.
    void registerScriptExports(GUIClass)() nothrow
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
    void registerUIElementClass(ElemClass)() nothrow
    {
        // If you fail here: ony UIElement derivatives can have @ScriptExport
        // Maybe you can expose this functionnality in a widget?
        static assert(is(ElemClass: UIElement));

        string name = ElemClass.classinfo.name;

        bool alreadyKnown = false;

        // search if class already known
        IdentifierBloom.HashResult hash = IdentifierBloom.hashOf(name);
        if (_identifierBloom.couldContain(hash))
        {
            foreach(e; _exportedClasses[])
            {
                if (e.fullClassName() == name)
                {
                    alreadyKnown = true;
                    break;
                }
            }
        }

        if (!alreadyKnown)
        {
            _identifierBloom.add(hash);
            ScriptExportClass c = mallocNew!ScriptExportClass(ElemClass.classinfo);
            registerDClass!ElemClass(c);
            _exportedClasses ~= c;
        }
    }
  
    /// Add a read-only Wren module source code, to be loaded once and never changed.
    /// Release purpose. When in developement, you might prefer a reloadable file, with `addModuleFileWatch`.
    void addModuleSource(const(char)[] moduleName, const(char)[] moduleSource) nothrow
    {
        // This forces a zero terminator.
        char* moduleNameZ = stringDup(CString(moduleName).storage).ptr;
        char* moduleSourceZ = stringDup(CString(moduleSource).storage).ptr;

        PreloadedSource ps;
        ps.moduleName = moduleNameZ;
        ps.source = moduleSourceZ;
        _preloadedSources.pushBack(ps);
    }

    /// Add a dynamic reloadable .wren source file. The module is reloaded and compared when `reloadScriptsThatChanged()` is called.
    /// Development purpose. For a release plug-in, you want to use `addModuleSource` instead.
    void addModuleFileWatch(const(char)[] moduleName, const(char)[] wrenFilePath) nothrow
    {
        // This forces a zero terminator.
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
    void callCreateUI() nothrow
    {
        callPluginMethod("createUI");
    }

    /// To call in your UI's `reflow()` method. This call the `Plugin.reflow` Wren method, in module "plugin".
    ///
    /// Note: Changing @ScriptProperty values does not make the elements dirty.
    ///       But since it's called at UI reflow, the whole UI is dirty anyway so it works.
    ///
    void callReflow() nothrow
    {
        callPluginMethod("reflow");
    }

    /// Read live-reload .wren files and restart the Wren VM if they have changed.
    /// Check the registered .wren file and check if they have changed.
    /// Since it (re)starts the Wren VM, it cannot be called from Wren.
    /// Returns: `true` on first load, or if the scripts have changed.
    bool reloadScriptsThatChanged() nothrow
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
        return oneScriptChanged;
    }

    /// Call this in your `onAnimate` callback. This polls script regularly and force a full redraw.
    ///
    /// Example:
    /// ---
    /// override void onAnimate(double dt, double time)
    /// {
    ///    context.wrenSupport.callReflowWhenScriptsChange(dt);
    /// }
    /// ---
    ///
    void callReflowWhenScriptsChange(double dt) nothrow
    {
        enum CHECK_EVERY_N_SECS = 0.2; // 200 ms
        _timeSinceLastScriptCheck += dt;
        if (_timeSinceLastScriptCheck > CHECK_EVERY_N_SECS)
        {
            _timeSinceLastScriptCheck = 0;
            if (reloadScriptsThatChanged())
            {
                // We detected a change, we need to call Plugin.reflow() in Wren, and invalidate graphics so that everything is redrawn.
                callReflow();
            }
        }
    }

    // <advanced API>

    /// Call Plugin.<methodName>, a static method without arguments in Wren. For advanced users only.
    void callPluginMethod(const(char)* methodName) nothrow
    {
        reloadScriptsThatChanged();
        enum int MAX = 64+MAX_VARIABLE_NAME*2;
        char[MAX] code;
        snprintf(code.ptr, MAX, "{\n \nimport \"plugin\" for Plugin\n Plugin.%s()\n}\n", methodName);
        interpret(code.ptr);
    }

    /// Interpret arbitrary code. For advanced users only.
    void interpret(const(char)* path, const(char)* source) nothrow
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
    void interpret(const(char)* source) nothrow
    {
        interpret("", source);
    }  

    // </advanced API>

    ~this() nothrow
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

    IUIContext uiContext() nothrow
    {
        return _uiContext;
    }

    ScriptPropertyDesc* getScriptProperty(int nthClass, int nthProp) nothrow
    {
        ScriptExportClass sec = _exportedClasses[nthClass];
        ScriptPropertyDesc[] descs = sec.properties();
        return &descs[nthProp];
    }

private:

    WrenVM* _vm = null;
    IUIContext _uiContext;
    double _timeSinceLastScriptCheck = 0; // in seconds
    IdentifierBloom _identifierBloom;

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
            // FUTURE: eventually use stat to get date of change instead
            char* newSource = readWrenFile(); 

            // Sometimes reading the file fails, and then we should just retry later. Report no changes.
            if (newSource is null)
                return false;

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
            return cast(char*) content.ptr; // correct because readFile return one trailing '\0'
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

    /// The number of time a Wren VM has been started. This is to invalidate caching of Wren values.
    uint _vmGeneration = 0;

    /// Wren module, its look-up is cached to speed-up $ operator.
    ObjModule* _cachedUIModule,
               _cachedWidgetsModule;

    // ui.Element class, its look-up is cached to speed-up $ operator.
    ObjClass* _cachedClassElement;

    void startWrenVM() nothrow
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
            _vmGeneration++;
            _cachedUIModule = null;
            _cachedWidgetsModule = null;
            _cachedClassElement = null;
        }
        catch(Exception e)
        {
            debugLog("VM initialization failed");
            destroyFree(e);
            _vm = null; 
        }
    }

    void stopWrenVM() nothrow
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

    void print(const(char)* text) nothrow
    {
        debugLog(text);
    }

    void error(WrenErrorType type, const(char)* module_, int line, const(char)* message) nothrow
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
    WrenForeignMethodFn foreignMethod(WrenVM* vm, const(char)* module_, const(char)* className, bool isStatic, const(char)* signature) nothrow
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
    WrenForeignClassMethods foreignClass(WrenVM* vm, const(char)* module_, const(char)* className) nothrow
    {
        if (strcmp(module_, "ui") == 0)
            return wrenUIForeignClass(vm, className);

        WrenForeignClassMethods methods;
        methods.allocate = null;
        methods.finalize = null;
        return methods;
    }

    WrenLoadModuleResult loadModule(WrenVM* vm, const(char)* name) nothrow
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

    // Note: return a value whose lifetime is tied to Wren VM.
    ObjModule* getWrenModule(const(char)* name)
    {
        Value moduleName = wrenStringFormat(_vm, "$", name);
        wrenPushRoot(_vm, AS_OBJ(moduleName));
        ObjModule* wModule = getModule(_vm, moduleName);
        wrenPopRoot(_vm);
        return wModule;
    }

    ObjClass* getWrenClassForThisUIELement(UIElement elem)
    {
        // Do we have a valid cached ObjClass* inside the UIElement?
        void* cachedClass = elem.getUserPointer(UIELEMENT_POINTERID_WREN_EXPORTED_CLASS);
        if (cachedClass !is null)
        {
            // Same Wren VM?
            uint cacheGen = cast(uint) elem.getUserPointer(UIELEMENT_POINTERID_WREN_VM_GENERATION);
            if (cacheGen == _vmGeneration)
            {
                // yes, reuse
                return cast(ObjClass*) cachedClass; 
            }
        }

        enum UIELEMENT_POINTERID_WREN_EXPORTED_CLASS = 0; /// The cached Wren class of this UIElement.
        enum UIELEMENT_POINTERID_WREN_VM_GENERATION  = 1; /// The Wren VM count, as it is restarted. Stored as void*, but is an uint.

        // try to find concrete class directly
        ObjClass* classTarget;
        ScriptExportClass concreteClassInfo = findExportedClassByClassInfo(elem.classinfo);
        if (concreteClassInfo)
        {
            const(char)* wrenClassName = concreteClassInfo.wrenClassNameZ();
            classTarget = AS_CLASS(wrenFindVariable(_vm, _cachedWidgetsModule, wrenClassName));
        }
        else
        {
            // $ return a UIElement, no classes were found
            // This is a silent error, properties assignment will silently fail.
            // We still cache that incorrect value, as the real fix is registering the class to Wren.
            classTarget = AS_CLASS(wrenFindVariable(_vm, _cachedUIModule, "UIElement"));
        }

        // Cached return value inside the UIElement, which will speed-up future $
        elem.setUserPointer(UIELEMENT_POINTERID_WREN_VM_GENERATION, classTarget);
        elem.setUserPointer(UIELEMENT_POINTERID_WREN_VM_GENERATION, cast(void*) _vmGeneration);
        return classTarget;
    }

    // Implementation of the $ operator.
    bool dollarOperator(WrenVM* vm, Value* args) nothrow
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

            if (_cachedUIModule is null)
            {
                _cachedUIModule = getWrenModule("ui");
                if (_cachedUIModule is null)
                    return RETURN_ERROR(vm, "module \"ui\" is not imported");
            }

            if (_cachedWidgetsModule is null)
            {
                _cachedWidgetsModule = getWrenModule("widgets");
                if (_cachedWidgetsModule is null)
                    return RETURN_ERROR(vm, "module \"widgets\" is not imported");
            }

            ObjClass* classTarget = getWrenClassForThisUIELement(elem);



            if (_cachedClassElement is null)
            {
                _cachedClassElement = AS_CLASS(wrenFindVariable(vm, _cachedUIModule, "Element"));
            }

            if (classTarget is null)
            {
                return RETURN_ERROR(vm, "cannot create a IUElement from operator $");
            }

            Value obj = wrenNewInstance(vm, classTarget);

            // PERF: could this be also cached? It wouldn't be managed by Wren.
            // Create new Element foreign
            ObjForeign* foreign = wrenNewForeign(vm, _cachedClassElement, UIElementBridge.sizeof);
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
    const(char)* widgetModuleSource() nothrow
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
            text("class "); textZ(ec.wrenClassNameZ); text(" is UIElement {"); LF;

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
                    // PERF: this calls the wren function 4 times
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

    ScriptExportClass findExportedClassByClassInfo(TypeInfo_Class info) nothrow
    {
        // PERF: again, not a simple lookup bt O(num-classes)
        foreach(ScriptExportClass sec; _exportedClasses[])
        {
            if (sec.concreteClassInfo is info)
            {
                // Found
                return sec;
            }
        }
        return null;
    }

    // Add a single UIElement derivative class into the set of known classes in Wren
    // Note that it enumerates all @ScriptProperty from its ancestors too, so it works.
    // Wren code doesn't actually know that UIImageKnob is derived from UIKnob.
    private void registerDClass(alias aClass)(ScriptExportClass classDesc) nothrow
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


// Bloom filter to filter out if an identifier is not defined, quickly.
// Using the 64-bit FNV-1 hash: https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function
struct IdentifierBloom
{
pure nothrow @nogc @safe:
    alias HashResult = ulong;

    ulong bits = 0;

    static HashResult hashOf(const(char)[] identifier)
    {
        ulong hash = 0xcbf29ce484222325;

        foreach(char ch; identifier)
        {
            hash = hash * 0x00000100000001B3;
            hash = hash ^ cast(ulong)(ch);
        }

        return hash;
    }

    bool couldContain(HashResult identifierHash)
    {
        return (_bits & identifierHash) == identifierHash;
    }

    void add(HashResult identifierHash)
    {
        _bits |= identifierHash;
    }

private:
    ulong _bits = 0;
}