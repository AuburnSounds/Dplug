module dplug.gui.toolkit.element;

import std.algorithm;

public import gfm.math;
public import ae.utils.graphics;
public import dplug.gui.window;
public import dplug.gui.types;
public import dplug.gui.toolkit.context;
public import dplug.gui.toolkit.font;

class UIElement
{
public:
    this(UIContext context)
    {
        _context = context;
    }

    void close()
    {
        foreach(child; children)
            child.close();
    }

    /// Returns: true if was drawn, ie. the buffers have changed.
    /// This method is called for each item in the drawlist that was visible and dirty.
    final void render(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap)
    {
        onDraw(diffuseMap, depthMap);
    }

    /// Meant to be overriden almost everytime for custom behaviour.
    /// Default behaviour is to span the whole area.
    /// Any layout algorithm is up to you.
    /// Children elements don't need to be inside their parent.
    void reflow(box2i availableSpace)
    {
        // default: span the entire available area, and do the same for children
        _position = _dirtyRect = availableSpace;

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
        _dirtyRect = p;

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

    final bool isVisible()
    {
        return _visible;
    }

    final void setVisible(bool visible)
    {
        _visible = visible;
    }

    final int zOrder()
    {
        return _zOrder;
    }

    final void setZOrder(int zOrder)
    {
        _zOrder = zOrder;
    }

    final void clearDirty()
    {
        _dirtyRect = box2i(0, 0, 0, 0);

        foreach(child; _children)
            child.clearDirty();
    }

    final void setDirty()
    {
        setDirty(_position);
    }

    final void setDirty(box2i rect)
    {
        box2i inter = _position.intersection(rect);
        if (_dirtyRect.empty())
        {
            assert(inter.isSorted());
            _dirtyRect = inter;
        }
        else
        {
            assert(_dirtyRect.isSorted());
            _dirtyRect = _dirtyRect.expand(inter);
            assert(_dirtyRect.isSorted());
        }

        assert(_dirtyRect.empty() || _position.contains(_dirtyRect));

        foreach(child; _children)
            child.setDirty(rect); 
    }

    /// Returns: dirty area. Supposed to be empty or inside position.
    box2i dirtyRect() pure const nothrow @nogc
    {
        assert(_dirtyRect.isSorted());
        return _dirtyRect;
    }

    /// Given an ImageRef!RGBA, return this view cropped to the dirty rectangle.
    /// This is useful to redraw part of an UIElement only if necessary.
    auto dirtyView(ImageRef!RGBA surface)
    {
        return surface.crop(_dirtyRect.min.x, _dirtyRect.min.y, _dirtyRect.max.x, _dirtyRect.max.y);
    }

    /// Returns: Parent element. `null` if detached or root element.
    final UIElement parent()
    {
        return _parent;
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
            assert(dirtyRect.isSorted);

            // if the dirty rect isn't empty
            if (!dirtyRect().empty())
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
    /// Warning: `onDraw` must only draw in the _position rectangle.
    void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap)
    {
        // defaults to filling with a grey pattern
        RGBA darkGrey = RGBA(100, 100, 100, 0);
        RGBA lighterGrey = RGBA(150, 150, 150, 0);

        for (int y = _dirtyRect.min.y; y < _dirtyRect.max.y; ++y)
        {
            RGBA[] depthScan = depthMap.scanline(y);
            RGBA[] diffuseScan = diffuseMap.scanline(y);
            for (int x = _dirtyRect.min.x; x < _dirtyRect.max.x; ++x)
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

    UIElement[] _children;

    /// If _visible is false, neither the Element nor its children are drawn.
    bool _visible = true;

    /// By default, every Element have the same z-order
    /// Because the sort is stable, tree traversal order is the default order (depth first).
    int _zOrder = 0;

private:
    UIContext _context;

    bool _mouseOver = false;    
}
