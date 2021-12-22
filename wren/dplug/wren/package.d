/**
Dplug's wren bridge. 

Copyright: Guillaume Piolat 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.wren;

import std.traits: getSymbolsByUDA;
import std.meta: staticIndexOf;

import dplug.core.nogc;
import dplug.gui.context;
import dplug.gui.element;

import wren.vm;

nothrow @nogc:


public import dplug.wren.wrensupport;

/// Create wren support for this UI tree, puts it in UIContext under pimpl idiom.
/// Returns the Wren support object.
/// Call this in your gui.d this.
void enableWrenSupport(IUIContext context)
{
    WrenSupport w = mallocNew!WrenSupport(context);
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
