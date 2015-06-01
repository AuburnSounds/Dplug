module dplug.gui.toolkit.element;

import std.algorithm;

public import gfm.math;
public import ae.utils.graphics;
public import dplug.gui.window;
public import dplug.gui.drawex;
public import dplug.gui.types;
public import dplug.gui.toolkit.context;
public import dplug.gui.toolkit.font;
public import dplug.plugin.unchecked_sync;

class UIElement
{
public:
    this(UIContext context)
    {
        _context = context;

        _dirtyRectMutex = new UncheckedMutex();
    }

    void close()
    {
        foreach(child; children)
            child.close();
        _dirtyRectMutex.close();
    }

    /// Returns: true if was drawn, ie. the buffers have changed.
    /// This method is called for each item in the drawlist that was visible and dirty.
    final void render(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap)
    {
        box2i dirtyRect = void;
        _dirtyRectMutex.lock();
        dirtyRect = _dirtyRect;
        _dirtyRectMutex.unlock();

        // Crop the diffuse and depth to the _position
        // This is because drawing outside of _position is disallowed
        // TODO: support out-of-bounds _position ?
        ImageRef!RGBA diffuseMapCropped = diffuseMap.cropImageRef(_position);
        ImageRef!RGBA depthMapCropped = depthMap.cropImageRef(_position);

        onDraw(diffuseMapCropped, depthMapCropped, dirtyRect.translate(-_position.min) );
    }

    /// Meant to be overriden almost everytime for custom behaviour.
    /// Default behaviour is to span the whole area.
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
        // also mark all dirty
        _dirtyRectMutex.lock();
        _dirtyRect = p;
        _dirtyRectMutex.unlock();

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

    // This function is meant to be overriden.
    // It should return true if the wheel is handled.
    bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate)
    {
        return false;
    }

    // Called when mouse move over this Element.
    void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
    }

    // Called when clicked with left/middle/right button
    void onBeginDrag()
    {
    }

    // Called when mouse drag this Element.
    void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
    }

    // Called once drag is finished
    void onStopDrag()
    {
    }

    // Called when mouse enter this Element.
    void onMouseEnter()
    {
    }

    // Called when mouse enter this Element.
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
    bool mouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
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

    final void clearDirty() nothrow @nogc
    {
        _dirtyRectMutex.lock();
        _dirtyRect = box2i(0, 0, 0, 0);
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

    /// Returns: dirty area. Supposed to be empty or inside position.
    box2i getDirtyRect() nothrow @nogc
    {
        _dirtyRectMutex.lock();
        scope(exit) _dirtyRectMutex.unlock();
        assert(_dirtyRect.isSorted());
        return _dirtyRect;
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

    /// Returns the list of Elements that should be drawn, in order.
    /// TODO: reuse draw list
    UIElement[] getDrawList()
    {
        UIElement[] list;
        if (isVisible())
        {
            box2i dirty = getDirtyRect();

            // if the dirty rect isn't empty, add this to the draw list
            if (!dirty.empty())
                list ~= this;

            foreach(child; _children)
                list = list ~ child.getDrawList();

            // Sort by ascending z-order (high z-order gets drawn last)
            // This sort must be stable to avoid messing with tree natural order.
            sort!("a.zOrder() < b.zOrder()", SwapStrategy.stable)(list);
        }
        return list;
    }

protected:

    /// Draw method. You should redraw the area there.
    /// For better efficiency, you may only redraw the part in _dirtyRect.
    /// diffuseMap and depthMap are made to span _position exactly, 
    /// so you can draw in the area (0 .. _position.width, 0 .. _position.height)
    /// Warning: _dirtyRect should not be used instead of dirtyRect for threading reasons.
    void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap, box2i dirtyRect)
    {
        // defaults to filling with a grey pattern
        RGBA darkGrey = RGBA(100, 100, 100, 0);
        RGBA lighterGrey = RGBA(150, 150, 150, 0);

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


    UIElement _parent = null;

    /// Position is the graphical extent
    /// An Element is not allowed though to draw further than its _position.
    box2i _position;

    /// The fraction of position that is to be redrawn.
    box2i _dirtyRect;

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
        {
            _dirtyRectMutex.lock();
            scope(exit) _dirtyRectMutex.unlock();
            assert(_dirtyRect.isSorted());
            _dirtyRect = _dirtyRect.expand(inter);
            assert(_dirtyRect.isSorted());
            assert(_dirtyRect.empty() || _position.contains(_dirtyRect));
        }

        foreach(child; _children)
            child.setDirtyRecursive(rect); 
    }
}
