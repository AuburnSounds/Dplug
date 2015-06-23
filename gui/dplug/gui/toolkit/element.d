/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.toolkit.element;

import std.algorithm;

public import gfm.math;
public import ae.utils.graphics;
public import dplug.gui.window;
public import dplug.gui.drawex;
public import dplug.gui.types;
public import dplug.gui.boxlist;
public import dplug.gui.toolkit.context;
public import dplug.gui.toolkit.font;
public import dplug.plugin.unchecked_sync;
public import dplug.plugin.alignedbuffer;
import dplug.dsp.funcs;

/// Base class of the UI widget hierarchy.
///
/// Bugs: a bunch of stuff in that class is intended specifically for the root element, 
///       there is probably a batter design to find

class UIElement
{
public:
    this(UIContext context)
    {
        _context = context;

        _dirtyRectMutex = new UncheckedMutex();
        _dirtyRects = new AlignedBuffer!box2i(4);

    }

    void close()
    {
        foreach(child; children)
            child.close();
        _dirtyRectMutex.close();
        _dirtyRects.close();
    }

    /// Returns: true if was drawn, ie. the buffers have changed.
    /// This method is called for each item in the drawlist that was visible and dirty.
    final void render(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap)
    {
        box2i[] dirtyRects;
        {
            foreach(rect; DirtyRectsRange(this))
                dirtyRects ~= rect;
        }

        if (dirtyRects.length == 0)
            return;

        // Crop the diffuse and depth to the _position
        // This is because drawing outside of _position is disallowed
        ImageRef!RGBA diffuseMapCropped = diffuseMap.cropImageRef(_position);
        ImageRef!RGBA depthMapCropped = depthMap.cropImageRef(_position);

        foreach(ref rect; dirtyRects)
            rect = rect.translate(-_position.min);

        onDraw(diffuseMapCropped, depthMapCropped, dirtyRects);
    }

    /// Meant to be overriden almost everytime for custom behaviour.
    /// Default behaviour is to span the whole area and reflow children.
    /// Any layout algorithm is up to you.
    /// Children elements don't need to be inside their parent.
    void reflow(box2i availableSpace)
    {
        // default: span the entire available area, and do the same for children
        _position = availableSpace;

        foreach(ref child; children)
            child.reflow(availableSpace);
    }

    /// Returns: Position of the element, that will be used for rendering. This 
    /// position is reset when calling reflow.
    final box2i position()
    {
        return _position;
    }

    /// Forces the position of the element. It is typically used in the parent 
    /// reflow() method
    final box2i position(box2i p)
    {
        return _position = p;
    }

    /// Returns: Children of this element.
    final ref UIElement[] children()
    {
        return _children;
    }

    final UIElement child(int n)
    {
        return _children[n];
    }

    // The addChild method is mandatory
    final void addChild(UIElement element)
    {
        element._parent = this;
        _children ~= element;
    }

    // This function is meant to be overriden.
    // Happens _before_ checking for children collisions.
    bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        return false;
    }

    // Mouse wheel was turned. 
    // This function is meant to be overriden.
    // It should return true if the wheel is handled.
    bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate)
    {
        return false;
    }

    // Called when mouse move over this Element.
    // This function is meant to be overriden.
    void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
    }

    // Called when clicked with left/middle/right button
    // This function is meant to be overriden.
    void onBeginDrag()
    {
    }

    // Called when mouse drag this Element.
    // This function is meant to be overriden.
    void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
    }

    // Called once drag is finished.
    // This function is meant to be overriden.
    void onStopDrag()
    {
    }

    // Called when mouse enter this Element.
    // This function is meant to be overriden.
    void onMouseEnter()
    {
    }

    // Called when mouse enter this Element.
    // This function is meant to be overriden.
    void onMouseExit()
    {
    }

    // Called when a key is pressed. This event bubbles down-up until being processed.
    // Return true if treating the message.
    bool onKeyDown(Key key)
    {
        return false;
    }

    // Called when a key is pressed. This event bubbles down-up until being processed.
    // Return true if treating the message.
    bool onKeyUp(Key key)
    {
        return false;
    }

    // to be called at top-level when the mouse clicked
    final bool mouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        // Test children that are displayed above this element first
        foreach(child; _children)
        {
            if (child.zOrder >= zOrder)
                if (child.mouseClick(x, y, button, isDoubleClick, mstate))
                    return true;
        }

        // Test for collision with this element
        if (_position.contains(vec2i(x, y)))
        {
            if(onMouseClick(x - _position.min.x, y - _position.min.y, button, isDoubleClick, mstate))
            {
                _context.beginDragging(this);
                _context.setFocused(this);
                return true;
            }
        }
        
        // Test children that are displayed below this element last
        foreach(child; _children)
        {
            if (child.zOrder < zOrder)
                if (child.mouseClick(x, y, button, isDoubleClick, mstate))
                    return true;
        }

        return false;
    }

    // to be called at top-level when the mouse is released
    final void mouseRelease(int x, int y, int button, MouseState mstate)
    {
        _context.stopDragging();
    }

    // to be called at top-level when the mouse wheeled
    final bool mouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate)
    {
        foreach(child; _children)
        {
            if (child.mouseWheel(x, y, wheelDeltaX, wheelDeltaY, mstate))
                return true;
        }

        if (_position.contains(vec2i(x, y)))
        {
            if (onMouseWheel(x - _position.min.x, y - _position.min.y, wheelDeltaX, wheelDeltaY, mstate))
                return true;
        }

        return false;
    }

    // to be called when the mouse moved
    final void mouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
        if (isDragged)
            onMouseDrag(x, y, dx, dy, mstate);

        foreach(child; _children)
        {
            child.mouseMove(x, y, dx, dy, mstate);
        }

        if (_position.contains(vec2i(x, y)))
        {
            if (!_mouseOver)
                onMouseEnter();
            onMouseMove(x - _position.min.x, y - _position.min.y, dx, dy, mstate);
            _mouseOver = true;
        }
        else
        {
            if (_mouseOver)
                onMouseExit();
            _mouseOver = false;
        }
    }

    // to be called at top-level when a key is pressed
    final bool keyDown(Key key)
    {
        if (onKeyDown(key))
            return true;

        foreach(child; _children)
        {
            if (child.keyDown(key))
                return true;
        }
        return false;
    }

    // to be called at top-level when a key is released
    final bool keyUp(Key key)
    {
        if (onKeyUp(key))
            return true;

        foreach(child; _children)
        {
            if (child.keyUp(key))
                return true;
        }
        return false;
    }

    // To be called at top-level periodically.
    void animate(double dt, double time)
    {
        onAnimate(dt, time);
        foreach(child; _children)
            child.animate(dt, time);
    }

    final UIContext context()
    {
        return _context;
    }

    final bool isVisible() pure const nothrow @nogc
    {
        return _visible;
    }

    final void setVisible(bool visible) pure nothrow @nogc
    {
        _visible = visible;
    }

    final int zOrder() pure const nothrow @nogc
    {
        return _zOrder;
    }

    final void setZOrder(int zOrder) pure nothrow @nogc
    {
        _zOrder = zOrder;
    }

    final void clearDirty()
    {
        _dirtyRectMutex.lock();
        _dirtyRects.clear(); // TODO do not malloc/free
        _dirtyRectMutex.unlock();

        foreach(child; _children)
            child.clearDirty();
    }

    /// Mark this element dirty and all elements in the same position.
    final void setDirty() nothrow @nogc
    {
        setDirty(_position);
    }

    /// Mark all elements in an area dirty.
    final void setDirty(box2i rect) nothrow @nogc
    {
        topLevelParent().setDirtyRecursive(rect);
    }

    /// Returns: true if any dirty area.
    final bool isDirty() nothrow @nogc
    {
        return DirtyRectsRange(this).length != 0;
    }

    /// Returns: Parent element. `null` if detached or root element.
    final UIElement parent() pure nothrow @nogc
    {
        return _parent;
    }

    /// Returns: Top-level parent. `null` if detached or root element.
    final UIElement topLevelParent() pure nothrow @nogc
    {
        if (_parent is null) 
            return this;
        else
            return _parent.topLevelParent();
    }

    final bool isMouseOver() pure const nothrow
    {
        return _mouseOver;
    }

    final bool isDragged() pure const nothrow
    {
        return _context.dragged is this;
    }

    final bool isFocused() pure const nothrow
    {
        return _context.focused is this;
    }

    /// Appends the Elements that should be drawn, in order.
    /// The slice is reused to take advantage of .capacity
    /// You should empty it before calling this function.
    final void getDrawList(ref UIElement[] list)
    {
        if (isVisible())
        {
            // if the dirty rect isn't empty, add this to the draw list
            if (isDirty())
                list ~= this;

            foreach(child; _children)
                child.getDrawList(list);

            // Sort by ascending z-order (high z-order gets drawn last)
            // This sort must be stable to avoid messing with tree natural order.
            sort!("a.zOrder() < b.zOrder()", SwapStrategy.stable)(list);
        }
    }   

protected:

    /// Draw method. You should redraw the area there.
    /// For better efficiency, you may only redraw the part in _dirtyRect.
    /// diffuseMap and depthMap are made to span _position exactly, 
    /// so you can draw in the area (0 .. _position.width, 0 .. _position.height)
    /// Warning: _dirtyRect should not be used instead of dirtyRect for threading reasons.
    void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap, box2i[] dirtyRects)
    {
        // defaults to filling with a grey pattern
        RGBA darkGrey = RGBA(100, 100, 100, 0);
        RGBA lighterGrey = RGBA(150, 150, 150, 0);

        foreach(dirtyRect; dirtyRects)
        {
            for (int y = dirtyRect.min.y; y < dirtyRect.max.y; ++y)
            {
                RGBA[] depthScan = depthMap.scanline(y);
                RGBA[] diffuseScan = diffuseMap.scanline(y);
                for (int x = dirtyRect.min.x; x < dirtyRect.max.x; ++x)
                {
                    diffuseScan.ptr[x] = ( (x >> 3) ^  (y >> 3) ) & 1 ? darkGrey : lighterGrey;
                    ubyte depth = 58;
                    ubyte shininess = 64;
                    depthScan.ptr[x] = RGBA(depth, shininess, 0, 0);
                }
            }
        }
    }

    /// Called periodically.
    /// Override this to create animations.
    /// Using setDirty there allows to redraw an element continuously (like a meter or an animated object).
    /// Warning: Summing `dt` will not lead to a time that increase like `time`.
    ///          `time` can go backwards if the window was reopen.
    ///          `time` is guaranteed to increase as fast as system time but is not synced to audio time.
    void onAnimate(double dt, double time)
    {
    }

    /// Parent element.
    /// Following this chain gets to the root element.
    UIElement _parent = null;

    /// Position is the graphical extent
    /// An Element is not allowed though to draw further than its _position.
    box2i _position;

    /// The possibly overlapping areas that need updating.
    AlignedBuffer!box2i _dirtyRects;

    /// This is protected by a mutex, because it is sometimes updated from the host.
    UncheckedMutex _dirtyRectMutex;

    UIElement[] _children;

    /// If _visible is false, neither the Element nor its children are drawn.
    bool _visible = true;

    /// By default, every Element have the same z-order
    /// Because the sort is stable, tree traversal order is the default order (depth first).
    int _zOrder = 0;

private:
    UIContext _context;

    bool _mouseOver = false;

    /// Sets an area dirty and all its children.
    /// Because nothing is guaranteed about what will be drawn in the onDraw method, we have
    /// no choice but to dirty the whole stack of elements in this rectangle.
    final void setDirtyRecursive(box2i rect) nothrow @nogc
    {
        box2i inter = _position.intersection(rect);
        assert(inter.isSorted());
        assert(rect.isSorted());
        assert(_position.isSorted());
        if (!inter.empty)
        {
            _dirtyRectMutex.lock();
            scope(exit) _dirtyRectMutex.unlock();

            bool processed = false;

            for (int i = 0; i < _dirtyRects.length; ++i)
            {
                box2i other = _dirtyRects[i];
                if (other.contains(inter))
                {
                    processed = true; // do not push if contained in existing rect
                    break;
                }
                else if (inter.contains(other)) // remove rect that it contains
                {
                    _dirtyRects[i] = _dirtyRects.popBack();
                    i--;
                }

                // TODO: partial intersection? Or we have overdraw
            }

            if (!processed)
                _dirtyRects.pushBack(inter);

            assert(haveNoOverlap(_dirtyRects[]));
        }       

        foreach(child; _children)
            child.setDirtyRecursive(rect); 
    }
}


// Iterates over dirty rectangle while holding the dirty lock
struct DirtyRectsRange
{
    int index = 0;
    UIElement _element;

    this(UIElement element) nothrow @nogc
    {
        _element = element;
        _element._dirtyRectMutex.lock();
    }

    ~this() nothrow @nogc
    {
        _element._dirtyRectMutex.unlock();
    }

    @disable this(this);

    @property int length() pure nothrow @nogc
    {
        return cast(int)(_element._dirtyRects.length) - index;
    }

    @property empty() nothrow @nogc
    {
        return index >= _element._dirtyRects.length;
    }

    @property box2i front() nothrow @nogc
    {
        return _element._dirtyRects[index];
    }    

    void popFront() nothrow @nogc
    {
        index++;
    }
}
