/**
Dplug's wren bridge. 

Copyright: Guillaume Piolat 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.wren;

import dplug.core.nogc;
import dplug.gui.context;
import dplug.gui.element;

nothrow:


public import dplug.wren.wrensupport;

/// Create wren support for this UI tree, puts it in UIContext under pimpl idiom.
/// Returns the Wren support object.
/// Call this in your gui.d this.
void enableWrenSupport(IUIContext context) @nogc
{
    WrenSupport w = mallocNew!WrenSupport(context);
    context.setUserPointer(UICONTEXT_POINTERID_WREN_SUPPORT, cast(void*)w);
}

/// Disable wren support, meaning it will release the Wren VM and integration.
/// Call this in your gui.d ~this.
void disableWrenSupport(IUIContext context) @nogc
{
    WrenSupport w = wrenSupport(context);
    context.setUserPointer(UICONTEXT_POINTERID_WREN_SUPPORT, null);
    destroyFree(w);
}

/// Get the `WrenSupport` object that holds all wren state and integration with the plugin.
/// The rest of the public API follows in dplug.wren.wrensupport
WrenSupport wrenSupport(IUIContext context) @nogc
{
    return cast(WrenSupport) context.getUserPointer(UICONTEXT_POINTERID_WREN_SUPPORT);
}

/// All widgets (derivatives of UIElement) have a string ID.
/// mixin this code to automatically set widgets ID. 
/// It generates 
///     _member.id = "_member";
/// for every field that is @ScriptExport, in order to find them from Wren.
///
/// Example:
/// ---
/// mixin(fieldIdentifiersAreIDs!MyPluginGUI);
/// ---
string fieldIdentifiersAreIDs(T)()
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