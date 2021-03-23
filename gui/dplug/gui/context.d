/**
* `UIContext` holds global state for the whole UI (current selected widget, etc...).
*
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.context;

import dplug.core.vec;
import dplug.core.nogc;

import dplug.window.window;

import dplug.graphics.font;
import dplug.graphics.mipmap;

import dplug.gui.element;
import dplug.gui.boxlist;
import dplug.gui.graphics;


/// Work in progress. An ensemble of calls `UIElement` are allowed to make, that
/// concern the whole UI.
/// Whenever an API call makes sense globally for `UIelement`, 
/// it should be moved to IUIContext.
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

    /// Get current size of the UI, in user pixels.
    vec2i getUISizeInPixelsUser();

    /// Get current size of the UI, in logical pixels.
    vec2i getUISizeInPixelsLogical();

    /// Get current size of the UI, in physical pixels.
    vec2i getUISizeInPixelsPhysical();

    /// Trigger a resize of the plugin window. This isn't guaranteed to succeed.
    bool requestUIResize(int widthLogicalPixels, int heightLogicalPixels);
}


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
    }

    final override float getUIScale()
    {
        return _owner.getUIScale();
    }

    final override float getUserScale()
    {
        return _owner.getUserScale();
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

    /// Last clicked element.
    UIElement focused = null;

    /// Currently dragged element.
    UIElement dragged = null;

    version(legacyMouseOver) {}
    else
    {
        /// Currently mouse-over'd element.
        UIElement mouseOver = null;
    }

    // This is the UI-global, disjointed list of rectangles that need updating at the PBR level.
    // Every UIElement touched by those rectangles will have their `onDrawPBR` and `onDrawRaw` 
    // callbacks called successively.
    DirtyRectList dirtyListPBR;

    // This is the UI-global, disjointed list of rectangles that need updating at the Raw level.
    // Every UIElement touched by those rectangles will have its `onDrawRaw` callback called.
    DirtyRectList dirtyListRaw;

    version(legacyMouseOver) {}
    else
    {
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
    }

    final void setFocused(UIElement focused)
    {
        UIElement old = this.focused;
        UIElement new_ = focused;
        if (old is new_)
            return;

        if (old !is null)
            old.onFocusExit();
        this.focused = new_;
        if (new_ !is null)
            new_.onFocusEnter();
    }

    final void beginDragging(UIElement element)
    {
        stopDragging();
        dragged = element;
        dragged.onBeginDrag();
    }

    final void stopDragging()
    {
        if (dragged !is null)
        {
            dragged.onStopDrag();
            dragged = null;
        }
    }

    final MouseCursor getCurrentMouseCursor()
    {
        MouseCursor cursor = MouseCursor.pointer;

        version(legacyMouseOver) { cursor = MouseCursor.pointer;}
        else
        {
            if (!(mouseOver is null))
            {
                cursor = mouseOver.cursorWhenMouseOver();
            }
        }

        if(!(dragged is null))
        {
            cursor = dragged.cursorWhenDragged();
        }        

        return cursor;
    }

private:
    GUIGraphics _owner;

}

