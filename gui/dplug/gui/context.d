/**
* `UIContext` holds global state for the whole UI (current selected widget, etc...).
*
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.context;

import core.stdc.string : strcmp;

import dplug.core.vec;
import dplug.core.nogc;
import dplug.core.thread;

import dplug.window.window;

import dplug.graphics.font;
import dplug.graphics.mipmap;
import dplug.graphics.resizer;

import dplug.gui.element;
import dplug.gui.boxlist;
import dplug.gui.graphics;
import dplug.gui.sizeconstraints;
import dplug.gui.profiler;


/// Work in progress. An ensemble of calls `UIElement` are allowed to make, that
/// concern the whole UI.
/// Whenever an API call makes sense globally for usage in an `UIelement`, it should be moved to `IUIContext`.
interface IUIContext
{
nothrow @nogc:

    /// Returns: Current number of physical pixels for one logical pixel.
    /// There is currently no support for this in Dplug, so it is always 1.0f for now.
    /// The OS _might_ upscale the UI without our knowledge though.
    float getUIScale();

    /// Returns: Current number of user pixels for one logical pixel.
    /// There is currently no user area resize in Dplug, so it is always 1.0f for now.
    float getUserScale();

    /// Get default size of the UI, at creation time, in user pixels.
    vec2i getDefaultUISizeInPixels();

    /// Get default width of the UI, at creation time, in user pixels.
    int getDefaultUIWidth();

    /// Get default width of the UI, at creation time, in user pixels.
    int getDefaultUIHeight();

    /// Get current size of the UI, in user pixels.
    vec2i getUISizeInPixelsUser();

    /// Get current size of the UI, in logical pixels.
    vec2i getUISizeInPixelsLogical();

    /// Get current size of the UI, in physical pixels.
    vec2i getUISizeInPixelsPhysical();

    /// Trigger a resize of the plugin window. This isn't guaranteed to succeed.
    bool requestUIResize(int widthLogicalPixels, int heightLogicalPixels);

    /// Find the nearest valid _logical_ UI size.
    /// Given an input size, get the nearest valid size.
    void getUINearestValidSize(int* widthLogicalPixels, int* heightLogicalPixels);

    /// Returns: `true` if the UI can accomodate several size in _logical_ space.
    ///          (be it by resizing the user area, or rescaling it).
    /// Technically all sizes are supported with black borders or cropping in logical space,
    /// but they don't have to be encouraged if the plugin declares no support for it.
    bool isUIResizable();

    /// A shared image resizer to be used in `reflow()` of element.
    /// Resizing using dplug:graphics use a lot of memory, 
    /// so it can be better if this is a shared resource.
    /// It is lazily constructed.
    /// See_also: `ImageResizer`.
    /// Note: do not use this resizer concurrently (in `onDrawRaw`, `onDrawPBR`, etc.)
    ///       unless you have `flagDrawAloneRaw` or `flagDrawAlonePBR`.
    ///       Usually intended for `reflow()`.
    ImageResizer* globalImageResizer();

    /// A shared threadpool, used to draw widgets concurrently.
    /// NEW: A widget can opt to be drawn alone, and use the threadpool for its own drawing itself.
    /// Can ONLY be called from `onDrawRaw` AND when the flag `flagDrawAloneRaw` is used, 
    ///                 or from `onDrawPBR` AND when the flag `flagDrawAlonePBR` is used.
    ThreadPool* globalThreadPool();

    /// Returns a UI-wide profiler that records UI performance, as long as Dplug_ProfileUI version is 
    /// defined. Else, it is a null IProfiler that forgets everything.
    /// For performance purpose, it is recommended:
    /// 1. not to record profile if Dplug_ProfileUI is not defined, 
    /// 2. and undefine Dplug_ProfileUI if you're not looking for a bottleneck.
    /// See_also: 
    IProfiler profiler();

    /// Store an user-defined pointer globally for the UI. This is useful to implement an optional extension to dplug:gui.
    /// id 0..7 are reserved for future Dplug extensions.
    /// id 8..15 are for vendor-specific extensions.
    /// Warning: if you store an object here, keep in mind they won't get destroyed automatically.
    void setUserPointer(int pointerID, void* userPointer);

    /// Get an user-defined pointer stored globally for the UI. This is useful to implement an optional extension to dplug:gui.
    /// id 0..7 are reserved for future Dplug extensions.
    /// id 8..15 are for vendor-specific extensions.
    void* getUserPointer(int pointerID);

    /// Get root element of the hierarchy.
    UIElement getRootElement();

    /// Get the first `UIElement` with the given ID, or `null`. This just checks for exact id matches, without anything fancy.
    /// If you use `dplug:wren-support`, this is called by the `$` operator or the `UI.getElementById`.
    UIElement getElementById(const(char)* id);
}

// Official dplug:gui optional extension.
enum UICONTEXT_POINTERID_WREN_SUPPORT = 0; /// Official dplug:gui Wren extension. Wren state needs to be stored globally for the UI.

// <wren-specific part>
// See Wiki for how to enable scripting.

/// For a UIElement-derived class, this UDA means its members need to be inspected for registering properties to the script engine.
struct ScriptExport
{
}

/// For a member of a @ScriptExport class, this UDA means the member can is a property to be modified by script (read and write).
struct ScriptProperty
{
}

// </wren-specific part>

/// UIContext contains the "globals" of the UI.
/// It also provides additional APIs for `UIElement`.
class UIContext : IUIContext
{
public:
nothrow:
@nogc:
    this(GUIGraphics owner)
    {
        this._owner = owner;
        dirtyListPBR = makeDirtyRectList();
        dirtyListRaw = makeDirtyRectList();
        _sortingscratchBuffer = makeVec!UIElement();

        version(Dplug_ProfileUI)
        {
            _profiler = createProfiler();
        }
    }

    ~this()
    {
        destroyProfiler(_profiler);
    }

    final override float getUIScale()
    {
        return _owner.getUIScale();
    }

    final override float getUserScale()
    {
        return _owner.getUserScale();
    }

    final override vec2i getDefaultUISizeInPixels()
    {
        return _owner.getDefaultUISizeInPixels();
    }

    final override int getDefaultUIWidth()
    {
        return getDefaultUISizeInPixels().x;
    }

    final override int getDefaultUIHeight()
    {
        return getDefaultUISizeInPixels().y;
    }

    final override vec2i getUISizeInPixelsUser()
    {
        return _owner.getUISizeInPixelsUser();
    }

    final override vec2i getUISizeInPixelsLogical()
    {
        return _owner.getUISizeInPixelsLogical();
    }

    final override vec2i getUISizeInPixelsPhysical()
    {
        return _owner.getUISizeInPixelsLogical();
    }

    final override bool requestUIResize(int widthLogicalPixels, int heightLogicalPixels)
    {
        return _owner.requestUIResize(widthLogicalPixels, heightLogicalPixels);
    }

    final override void getUINearestValidSize(int* widthLogicalPixels, int* heightLogicalPixels)
    {
        _owner.getUINearestValidSize(widthLogicalPixels, heightLogicalPixels);
    }

    final override bool isUIResizable()
    {
        return _owner.isUIResizable();
    }

    final override ImageResizer* globalImageResizer()
    {
        return &_globalResizer;
    }

    final override ThreadPool* globalThreadPool()
    {
        return &_owner._threadPool;
    }

    final override IProfiler profiler()
    {
        return _profiler;
    }

    /// Last clicked element.
    UIElement focused = null;

    /// Currently dragged element.
    UIElement dragged = null;

    /// Currently mouse-over'd element.
    UIElement mouseOver = null;

    // This is the UI-global, disjointed list of rectangles that need updating at the PBR level.
    // Every UIElement touched by those rectangles will have their `onDrawPBR` and `onDrawRaw` 
    // callbacks called successively.
    DirtyRectList dirtyListPBR;

    // This is the UI-global, disjointed list of rectangles that need updating at the Raw level.
    // Every UIElement touched by those rectangles will have its `onDrawRaw` callback called.
    DirtyRectList dirtyListRaw;

    final void setMouseOver(UIElement elem)
    {
        UIElement old = this.mouseOver;
        UIElement new_ = elem;
        if (old is new_)
            return;

        if (old !is null)
            old.onMouseExit();
        this.mouseOver = new_;
        if (new_ !is null)
            new_.onMouseEnter();
    }

    final void setFocused(UIElement focused)
    {
        UIElement old = this.focused;
        UIElement new_ = focused;
        if (old is new_)
            return;

        this.focused = new_;
        if (old !is null)
            old.onFocusExit();
        if (new_ !is null)
            new_.onFocusEnter();
    }

    final void beginDragging(UIElement element)
    {
        // Stop an existing dragging operation.
        stopDragging();

        version(futureMouseDrag)
        {
            setMouseOver(element);
            assert(this.mouseOver is element);
        }
        dragged = element;
        dragged.onBeginDrag();
    }

    final void stopDragging()
    {
        if (dragged !is null)
        {
            version(futureMouseDrag)
            {
                assert(this.mouseOver is dragged);
            }
            dragged.onStopDrag();
            dragged = null;
        }
    }

    final MouseCursor getCurrentMouseCursor()
    {
        MouseCursor cursor = MouseCursor.pointer;

        if (!(mouseOver is null))
        {
            cursor = mouseOver.cursorWhenMouseOver();
        }

        if(!(dragged is null))
        {
            cursor = dragged.cursorWhenDragged();
        }        

        return cursor;
    }

    final override void* getUserPointer(int pointerID)
    {
        return _userPointers[pointerID];
    }

    final override void setUserPointer(int pointerID, void* userPointer)
    {
        _userPointers[pointerID] = userPointer;
    }

    final override UIElement getRootElement()
    {
        return _owner;
    }

    final override UIElement getElementById(const(char)* id)
    {
        if (id is null)
            return null;

        // special value "__ROOT__"
        if (strcmp("__ROOT__", id) == 0)
            return getRootElement();

        // search in whole UI hierarchy
        return _owner.getElementById(id);
    }

    final ref Vec!UIElement sortingScratchBuffer()
    {
        return _sortingscratchBuffer;
    }    

private:
    GUIGraphics _owner;

    ImageResizer _globalResizer;

    /// A UI-global scratch buffer used as intermediate buffer for sorting UIElement.
    Vec!UIElement _sortingscratchBuffer;

    /// Warning: if you store objects here, keep in mind they won't get destroyed automatically.
    /// 16 user pointer in case you'd like to store things in UIContext as a Dplug extension.
    /// id 0..7 are reserved for future Dplug extensions.
    /// id 8..15 are for vendor-specific extensions.
    void*[16] _userPointers; // Opaque pointer for Wren VM and things.

    IProfiler _profiler;
}

