module dplug.gui.toolkit.element;

import std.algorithm;

public import gfm.math;
public import ae.utils.graphics;
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
    final void render(ImageRef!RGBA surface)
    {
        onDraw(surface);
    }

    /// Meant to be overriden almost everytime for custom behaviour.
    /// Default behaviour is to span the whole area.
    /// Any layout algorithm is up to you.
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
    // It should return true if the click is handled.
    bool onMousePostClick(int x, int y, int button, bool isDoubleClick)
    {
        return false;
    }

    // This function is meant to be overriden.
    // Happens _before_ checking for children collisions.
    bool onMousePreClick(int x, int y, int button, bool isDoubleClick)
    {
        return false;
    }

    // This function is meant to be overriden.
    // It should return true if the wheel is handled.
    bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY)
    {
        return false;
    }

    // Called when mouse move over this Element.
    void onMouseMove(int x, int y, int dx, int dy)
    {
    }

    // Called when clicked with left/middle/right button
    void onBeginDrag()
    {
    }

    // Called when mouse drag this Element.
    void onMouseDrag(int x, int y, int dx, int dy)
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
    bool mouseClick(int x, int y, int button, bool isDoubleClick)
    {
        if (_position.contains(vec2i(x, y)))
        {
            if(onMousePreClick(x - _position.min.x, y - _position.min.y, button, isDoubleClick))
            {
                _context.beginDragging(this);
                _context.setFocused(this);
                return true;
            }
        }

        foreach(child; _children)
        {
            if (child.mouseClick(x, y, button, isDoubleClick))
                return true;
        }

        if (_position.contains(vec2i(x, y)))
        {
            if(onMousePostClick(x - _position.min.x, y - _position.min.y, button, isDoubleClick))
            {
                _context.beginDragging(this);
                _context.setFocused(this);
                return true;
            }
        }

        return false;
    }

    // to be called at top-level when the mouse is released
    final void mouseRelease(int x, int y, int button)
    {
        _context.stopDragging();
    }

    // to be called at top-level when the mouse wheeled
    final bool mouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY)
    {
        foreach(child; _children)
        {
            if (child.mouseWheel(x, y, wheelDeltaX, wheelDeltaY))
                return true;
        }

        if (_position.contains(vec2i(x, y)))
        {
            if (onMouseWheel(x - _position.min.x, y - _position.min.y, wheelDeltaX, wheelDeltaY))
                return true;
        }

        return false;
    }

    // to be called when the mouse moved
    final void mouseMove(int x, int y, int dx, int dy)
    {
        if (isDragged)
            onMouseDrag(x, y, dx, dy);

        foreach(child; _children)
        {
            child.mouseMove(x, y, dx, dy);
        }

        if (_position.contains(vec2i(x, y)))
        {
            if (!_mouseOver)
                onMouseEnter();
            onMouseMove(x - _position.min.x, y - _position.min.y, dx, dy);
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

    final void setDirty(bool dirty = true)
    {
        _dirty = true;
    }

    /// Returns: Whether the element should drawn at next redraw event.
    /// You can override this function if you want a child update to trigger
    /// a parent update too.
    bool isDirty()
    {
        return _dirty;
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

    /*
    final box2i boundingBox() pure const nothrow
    {
        return _position;
    }*/

    /// Returns the list of Elements that should be drawn, in order.
    /// TODO: reuse draw list
    UIElement[] getDrawList()
    {
        UIElement[] list;
        if (isVisible())
        {
            if (isDirty())
            {
                list ~= this;
                _dirty = false; // clear dirty state, user code is responsible for calling render()
            }

            foreach(child; _children)
                list = list ~ child.getDrawList();

            // Sort by ascending z-order (high z-order gets drawn last)
            // This sort must be stable to avoid messing with tree natural order.
            sort!("a.zOrder() < b.zOrder()", SwapStrategy.stable)(list);
        }
        return list;
    }

protected:

    void onDraw(ImageRef!RGBA surface)
    {
       // defaults to nothing
    }


    UIElement _parent = null;

    /// Position is the graphical extent
    /// An Element is not allowed though to draw further than its _position.
    box2i _position;

    /// Whether this element should be drawn
    bool _dirty = true;

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
