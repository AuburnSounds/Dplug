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


/// UIContext contains the "globals" of the UI
/// - current focused element
/// - current dragged element
/// - and stuff that shouldn't be there
class UIContext
{
public:
nothrow:
@nogc:
    this()
    {
        dirtyListPBR = makeDirtyRectList();
        dirtyListRaw = makeDirtyRectList();
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



}

