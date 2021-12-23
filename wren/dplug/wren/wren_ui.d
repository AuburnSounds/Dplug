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
    UIElement root = context.getRootElement();
    UIElementBridge* bridge = cast(UIElementBridge*) wrenSetSlotNewForeign(vm, 0, 0, UIElementBridge.sizeof);
    bridge.elem = root;
}

 // Elements

void element_allocate(WrenVM* vm)
{
    UIElementBridge* bridge = cast(UIElementBridge*)wrenSetSlotNewForeign(vm, 0, 0, UIElementBridge.sizeof);
    
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    IUIContext context = ws.uiContext();
    bridge.elem = null;
}

void element_findIdAndBecomeThat(WrenVM* vm)
{
    UIElementBridge* bridge = cast(UIElementBridge*) wrenGetSlotForeign(vm, 0);
    const(char)* id = wrenGetSlotString(vm, 1);

    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    IUIContext context = ws.uiContext();
    bridge.elem = null;

    // special value "__ROOT__"
    if (strcmp("__ROOT__", id) == 0)
         bridge.elem = context.getRootElement();
}

void element_width(WrenVM* vm)
{
    UIElementBridge* bridge = cast(UIElementBridge*) wrenGetSlotForeign(vm, 0);
    double width = bridge.elem.position.width;    
    wrenSetSlotDouble(vm, 0, width);
}

void element_height(WrenVM* vm)
{
    UIElementBridge* bridge = cast(UIElementBridge*) wrenGetSlotForeign(vm, 0);
    double height = bridge.elem.position.height;    
    wrenSetSlotDouble(vm, 0, height);
}

struct UIElementBridge
{
    UIElement elem;
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
    }

    if (strcmp(className, "Element") == 0)
    {
        if (strcmp(signature, "<allocate>") == 0) return &element_allocate;
        if (strcmp(signature, "width") == 0) return &element_width;
        if (strcmp(signature, "height") == 0) return &element_height;
        if (strcmp(signature, "findIdAndBecomeThat_(_)") == 0) return &element_findIdAndBecomeThat;
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
        methods.allocate = &element_allocate;
        // Note: impossible to create Element from Wren
    }
    return methods;
}
