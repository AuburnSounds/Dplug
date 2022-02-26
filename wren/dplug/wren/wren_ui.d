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
import dplug.wren.describe;


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
    bridge.elem = context.getElementById(id); // Note: could be null
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
    assert(bridge.elem); // TODO error
    double x = wrenGetSlotDouble(vm, 1);
    double y = wrenGetSlotDouble(vm, 2);
    double w = wrenGetSlotDouble(vm, 3);
    double h = wrenGetSlotDouble(vm, 4);
    bridge.elem.position = box2i.rectangle(cast(int)x, cast(int)y, cast(int)w, cast(int)h);
}

void element_setProperty(WrenVM* vm)
{
    UIElementBridge* bridge = cast(UIElementBridge*) wrenGetSlotForeign(vm, 0);
    assert(bridge.elem);  // TODO error

    int classIndex = cast(int) wrenGetSlotDouble(vm, 1);
    int propIndex = cast(int) wrenGetSlotDouble(vm, 2);
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    ScriptPropertyDesc* desc = ws.getScriptProperty(classIndex, propIndex);
    assert(desc !is null);

    ubyte* raw = cast(ubyte*)(cast(void*)bridge.elem) + desc.offset;

    bool changed = false;

    final switch(desc.type)
    {
        case ScriptPropertyType.bool_:
        { 
            bool* valuePtr = cast(bool*)raw;
            bool current = *valuePtr;
            bool newValue = wrenGetSlotBool(vm, 3);
            changed = newValue != current;
            *valuePtr = newValue;
            break;
        }
        case ScriptPropertyType.byte_: 
        { 
            byte* valuePtr = cast(byte*)raw;
            byte current = *valuePtr;
            byte newValue =  cast(byte) wrenGetSlotDouble(vm, 3);
            changed = newValue != current;
            *valuePtr = newValue;
            break;
        }
        case ScriptPropertyType.ubyte_: 
        { 
            ubyte* valuePtr = cast(ubyte*)raw;
            ubyte current = *valuePtr;
            ubyte newValue =  cast(ubyte) wrenGetSlotDouble(vm, 3);
            changed = newValue != current;
            *valuePtr = newValue;
            break;
        }   
        case ScriptPropertyType.short_: 
        { 
            short* valuePtr = cast(short*)raw;
            short current = *valuePtr;
            short newValue =  cast(short) wrenGetSlotDouble(vm, 3);
            changed = newValue != current;
            *valuePtr = newValue;
            break;
        }
        case ScriptPropertyType.ushort_: 
        { 
            ushort* valuePtr = cast(ushort*)raw;
            ushort current = *valuePtr;
            ushort newValue =  cast(ushort) wrenGetSlotDouble(vm, 3);
            changed = newValue != current;
            *valuePtr = newValue;
            break;
        }
        case ScriptPropertyType.int_: 
        { 
            int* valuePtr = cast(int*)raw;
            int current = *valuePtr;
            int newValue =  cast(int) wrenGetSlotDouble(vm, 3);
            changed = newValue != current;
            *valuePtr = newValue;
            break;
        }
        case ScriptPropertyType.uint_: 
        { 
            uint* valuePtr = cast(uint*)raw;
            uint current = *valuePtr;
            uint newValue =  cast(uint) wrenGetSlotDouble(vm, 3);
            changed = newValue != current;
            *valuePtr = newValue;
            break;
        }
        case ScriptPropertyType.float_: 
        { 
            float* valuePtr = cast(float*)raw;
            float current = *valuePtr;
            float newValue =  cast(float) wrenGetSlotDouble(vm, 3);
             changed = !(newValue == current); // so that NaN don't provoke redraw
            *valuePtr = newValue;
            break;
        }
        case ScriptPropertyType.double_: 
        { 
            double* valuePtr = cast(double*)raw;
            double current = *valuePtr;
            double newValue =  wrenGetSlotDouble(vm, 3);
            changed = !(newValue == current); // so that NaN don't provoke redraw
            *valuePtr = newValue;
            break;
        }
        case ScriptPropertyType.RGBA:    assert(false);
    }

    // Changing a @ScriptProperty calls setDirtyWhole on the UIElement if the property changed
    if (changed)
        bridge.elem.setDirtyWhole();
}

void element_setPropertyRGBA(WrenVM* vm)
{
    UIElementBridge* bridge = cast(UIElementBridge*) wrenGetSlotForeign(vm, 0);
    assert(bridge.elem); // TODO error

    int classIndex = cast(int) wrenGetSlotDouble(vm, 1);
    int propIndex = cast(int) wrenGetSlotDouble(vm, 2);
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    ScriptPropertyDesc* desc = ws.getScriptProperty(classIndex, propIndex);
    assert(desc !is null);
    assert(desc.type == ScriptPropertyType.RGBA);

    ubyte* raw = cast(ubyte*)(cast(void*)bridge.elem) + desc.offset;
    RGBA* pRGBA = cast(RGBA*)(raw);

    double r = wrenGetSlotDouble(vm, 3);
    double g = wrenGetSlotDouble(vm, 4);
    double b = wrenGetSlotDouble(vm, 5);
    double a = wrenGetSlotDouble(vm, 6);
    if (r < 0) r = 0;
    if (g < 0) g = 0;
    if (b < 0) b = 0;
    if (a < 0) a = 0;
    if (r > 255) r = 255;
    if (g > 255) g = 255;
    if (b > 255) b = 255;
    if (a > 255) a = 255;
    RGBA newColor = RGBA(cast(ubyte)r, cast(ubyte)g, cast(ubyte)b, cast(ubyte)a);
    bool changed = newColor != *pRGBA;
    *pRGBA = newColor;

    // Changing a @ScriptProperty calls setDirtyWhole on the UIElement if the property changed
    if (changed)
        bridge.elem.setDirtyWhole();
}

void element_getProperty(WrenVM* vm)
{
    UIElementBridge* bridge = cast(UIElementBridge*) wrenGetSlotForeign(vm, 0);
    assert(bridge.elem); // TODO error

    int classIndex = cast(int) wrenGetSlotDouble(vm, 1);
    int propIndex = cast(int) wrenGetSlotDouble(vm, 2);
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    ScriptPropertyDesc* desc = ws.getScriptProperty(classIndex, propIndex);
    assert(desc !is null);

    ubyte* raw = cast(ubyte*)(cast(void*)bridge.elem) + desc.offset;

    final switch(desc.type)
    {
        case ScriptPropertyType.bool_:   wrenSetSlotBool(vm, 0, *cast(bool*)raw); break;
        case ScriptPropertyType.byte_:   wrenSetSlotDouble(vm, 0, *cast(byte*)raw); break;
        case ScriptPropertyType.ubyte_:  wrenSetSlotDouble(vm, 0, *cast(ubyte*)raw); break;
        case ScriptPropertyType.short_:  wrenSetSlotDouble(vm, 0, *cast(short*)raw); break;
        case ScriptPropertyType.ushort_: wrenSetSlotDouble(vm, 0, *cast(ushort*)raw); break;
        case ScriptPropertyType.int_:    wrenSetSlotDouble(vm, 0, *cast(int*)raw); break;
        case ScriptPropertyType.uint_:   wrenSetSlotDouble(vm, 0, *cast(uint*)raw); break;
        case ScriptPropertyType.float_: 
        {
            float f = *cast(float*)raw;
            wrenSetSlotDouble(vm, 0, f); break;
        }
        case ScriptPropertyType.double_: wrenSetSlotDouble(vm, 0, *cast(double*)raw); break;
        case ScriptPropertyType.RGBA:    assert(false);
    }
}

void element_getPropertyRGBA(WrenVM* vm)
{
    UIElementBridge* bridge = cast(UIElementBridge*) wrenGetSlotForeign(vm, 0);
    assert(bridge.elem); // TODO error

    int classIndex = cast(int) wrenGetSlotDouble(vm, 1);
    int propIndex = cast(int) wrenGetSlotDouble(vm, 2);
    WrenSupport ws = cast(WrenSupport) vm.config.userData;
    ScriptPropertyDesc* desc = ws.getScriptProperty(classIndex, propIndex);
    assert(desc !is null);

    ubyte* raw = cast(ubyte*)(cast(void*)bridge.elem) + desc.offset;
    int channel = cast(int) wrenGetSlotDouble(vm, 3);
    assert(channel >= 0 && channel < 4);
    wrenSetSlotDouble(vm, 0, raw[channel]);
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
        if (strcmp(signature, "setProp_(_,_,_)") == 0) return &element_setProperty;
        if (strcmp(signature, "setPropRGBA_(_,_,_,_,_,_)") == 0) return &element_setPropertyRGBA;
        if (strcmp(signature, "getProp_(_,_)") == 0) return &element_getProperty;
        if (strcmp(signature, "getPropRGBA_(_,_,_)") == 0) return &element_getPropertyRGBA;
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
    }
    return methods;
}
