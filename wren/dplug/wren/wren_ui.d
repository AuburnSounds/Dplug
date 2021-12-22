module dplug.wren.wren_ui;

import core.stdc.string : strcmp;

import wren.vm;
import wren.common;

import dplug.gui.element;
import dplug.wren.wrensupport;

private static immutable string uiModuleSource = import("ui.wren");

@nogc:

// UI

void ui_width(WrenVM* vm)
{
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    IUIContext context = ws.uiContext();
    vec2i userSize = context.getUISizeInPixelsUser();
    wrenSetSlotDouble(vm, 0, cast(double)(userSize.x));
 }

 void ui_height(WrenVM* vm)
 {
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    IUIContext context = ws.uiContext();
    vec2i userSize = context.getUISizeInPixelsUser();
    wrenSetSlotDouble(vm, 0, cast(double)(userSize.y));
}

void ui_root(WrenVM* vm)
{
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    IUIContext context = ws.uiContext();
    IUIElement root = context.getRootElement();

    UIElementBridge* well = cast(UIElementBridge*) wrenSetSlotNewForeign(vm, 0, 0, UIElementBridge.sizeof);
    well.elem = root;
}

 // Element

void element_width(WrenVM* vm)
{
    wrenSetSlotDouble(vm, 0, cast(double)(0));
}

void element_height(WrenVM* vm)
{
    wrenSetSlotDouble(vm, 0, cast(double)(0));
}

struct UIElementBridge
{
    IUIElement elem;
}

const(char)* wrenUIModuleSource()
{
    return assumeZeroTerminated(uiModuleSource);
}

WrenForeignMethodFn wrenUIBindForeignMethod(WrenVM* vm, const(char)* className, bool isStatic, const(char)* signature) nothrow
{
    if (strcmp(className, "UI") == 0)
    {
        if (isStatic && strcmp(signature, "width") == 0) return &ui_width;
        if (isStatic && strcmp(signature, "height") == 0) return &ui_height;
        if (isStatic && strcmp(signature, "root") == 0) return &ui_root;        
    }

    if (strcmp(className, "Element") == 0)
    {
        if (strcmp(signature, "width") == 0) return &element_width;
        if (strcmp(signature, "height") == 0) return &element_height;
    }
    return null;
}

WrenForeignClassMethods wrenUIForeignClass(WrenVM* vm, const(char)* className) nothrow
{
    WrenForeignClassMethods methods;
    methods.allocate = null;
    methods.finalize = null;
    
    if (strcmp(className, "Element") == 0)
    {
        // impossible to create Element from Wren
    }
    return methods;
}
