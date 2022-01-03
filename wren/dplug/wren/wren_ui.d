/**
Dplug-Wren stdlib. This API is accessed from Wren with `import "ui"`.

Copyright: Guillaume Piolat 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
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

void ui_defaultWidth(WrenVM* vm)
{
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    IUIContext context = ws.uiContext();
    wrenSetSlotDouble(vm, 0, context.getDefaultUIWidth());
}

void ui_defaultHeight(WrenVM* vm)
{
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    IUIContext context = ws.uiContext();
    wrenSetSlotDouble(vm, 0, context.getDefaultUIHeight());
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
    bridge.elem = context.getElementById(id);
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

void element_setposition(WrenVM* vm)
{
    UIElementBridge* bridge = cast(UIElementBridge*) wrenGetSlotForeign(vm, 0);
    if (!bridge.elem)
        return;
    double x = wrenGetSlotDouble(vm, 1);
    double y = wrenGetSlotDouble(vm, 2);
    double w = wrenGetSlotDouble(vm, 3);
    double h = wrenGetSlotDouble(vm, 4);
    bridge.elem.position = box2i.rectangle(cast(int)x, cast(int)y, cast(int)w, cast(int)h);
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
        if (isStatic && strcmp(signature, "defaultWidth") == 0) return &ui_defaultWidth;
        if (isStatic && strcmp(signature, "defaultHeight") == 0) return &ui_defaultHeight;
    }

    if (strcmp(className, "Element") == 0)
    {
        if (strcmp(signature, "<allocate>") == 0) return &element_allocate;
        if (strcmp(signature, "width") == 0) return &element_width;
        if (strcmp(signature, "height") == 0) return &element_height;
        if (strcmp(signature, "setPosition_(_,_,_,_)") == 0) return &element_setposition;
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
