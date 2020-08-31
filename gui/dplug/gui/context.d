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
import dplug.core.sync;

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
        final void setMouseOver(UIElement elem) nothrow @nogc
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

    final void setFocused(UIElement focused) nothrow @nogc
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

    final void beginDragging(UIElement element) nothrow @nogc
    {
        stopDragging();
        dragged = element;
        dragged.onBeginDrag();
    }

    final void stopDragging() nothrow @nogc
    {
        if (dragged !is null)
        {
            dragged.onStopDrag();
            dragged = null;
        }
    }

    final MouseCursor getCurrentMouseCursor() nothrow @nogc
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

DirtyRectList makeDirtyRectList() nothrow @nogc
{
    return DirtyRectList(4);
}

struct DirtyRectList
{
public:
nothrow @nogc:

    this(int dummy) 
    {
        _dirtyRectMutex = makeMutex();
        _dirtyRects = makeVec!box2i(0);
    }

    @disable this(this);

    bool isEmpty() nothrow @nogc
    {
        _dirtyRectMutex.lock();
        bool result = _dirtyRects.length == 0;
        _dirtyRectMutex.unlock();
        return result;
    }

    /// Returns: Array of rectangles in the list, remove them from the list.
    /// Needed to avoid races in repainting.
    void pullAllRectangles(ref Vec!box2i result) nothrow @nogc
    {
        _dirtyRectMutex.lock();

        foreach(rect; _dirtyRects[])
            result.pushBack(rect);

        _dirtyRects.clearContents();

        _dirtyRectMutex.unlock();
    }

    /// Add a rect while keeping the no overlap invariant
    void addRect(box2i rect) nothrow @nogc
    {
        assert(rect.isSorted);

        if (!rect.empty)
        {
            _dirtyRectMutex.lock();
            scope(exit) _dirtyRectMutex.unlock();

            bool processed = false;

            for (int i = 0; i < _dirtyRects.length; ++i)
            {
                box2i other = _dirtyRects[i];
                if (other.contains(rect))
                {
                    // If the rectangle candidate is inside an element of the list, discard it.
                    processed = true;
                    break;
                }
                else if (rect.contains(other)) // remove rect that it contains
                {
                    // If the rectangle candidate contains an element of the list, this element need to go.
                    _dirtyRects[i] = _dirtyRects.popBack();
                    i--;
                }
                else
                {
                    box2i common = other.intersection(rect);
                    if (!common.empty())
                    {
                        // compute other without common
                        box2i D, E, F, G;
                        boxSubtraction(other, common, D, E, F, G);

                        // remove other from list
                        _dirtyRects[i] = _dirtyRects.popBack();
                        i--;

                        // push the sub parts at the end of the list
                        // this is guaranteed to be non-overlapping since the list was non-overlapping before
                        if (!D.empty) _dirtyRects.pushBack(D);
                        if (!E.empty) _dirtyRects.pushBack(E);
                        if (!F.empty) _dirtyRects.pushBack(F);
                        if (!G.empty) _dirtyRects.pushBack(G);
                    }
                    // else no intersection problem, the candidate rectangle will be pushed normally in the list
                }

            }

            if (!processed)
                _dirtyRects.pushBack(rect);

            // Quadratic test, disabled
            // assert(haveNoOverlap(_dirtyRects[]));
        }
    }

private:
    /// The possibly overlapping areas that need updating.
    Vec!box2i _dirtyRects;

    /// This is protected by a mutex, because it is sometimes updated from the host.
    /// Note: we cannot remove this mutex, as host parameter change call setDirtyWhole directly.
    /// TODO: we want to remove this lock, the host thread may avoid doing it directly.
    UncheckedMutex _dirtyRectMutex;
}

