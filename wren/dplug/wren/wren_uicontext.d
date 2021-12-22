module dplug.wren.wren_uicontext;

import core.stdc.string : strcmp;

import wren.vm;
import wren.common;

import dplug.gui.element;
import dplug.wren.wrensupport;

private static immutable string uiContextModuleSource = import("uicontext.wren");

@nogc:

void uiElement_width(WrenVM* vm)
{
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    IUIContext context = ws.uiContext();
    vec2i userSize = context.getUISizeInPixelsUser();
    wrenSetSlotDouble(vm, 0, cast(double)(userSize.x));
 }

 void uiElement_height(WrenVM* vm)
 {
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    IUIContext context = ws.uiContext();
    vec2i userSize = context.getUISizeInPixelsUser();
    wrenSetSlotDouble(vm, 0, cast(double)(userSize.y));
}

const(char)* wrenUIContextSource()
{
    return uiContextModuleSource.ptr;
}

WrenForeignMethodFn wrenUIContextBindForeignMethod(WrenVM* vm, const(char)* className, bool isStatic, const(char)* signature)
{
    if (isStatic && strcmp(signature, "width") == 0) return &uiElement_width;
    if (isStatic && strcmp(signature, "height") == 0) return &uiElement_height;
    return null;
}
