module dplug.gui.toolkit.element;

public import gfm.math;
public import ae.utils.graphics;
public import dplug.gui.types;
public import dplug.gui.toolkit.context;
public import dplug.gui.toolkit.renderer;
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

    final void render()
    {
        if (!_visible)
            return;

        setViewportToElement();
        if (_backgroundColor.a != 0)
            _context.renderer.viewport.fill(_backgroundColor);
        preRender(_context.renderer);
        foreach(ref child; children)
            child.render();
        setViewportToElement();
        postRender(_context.renderer);
    }

    /// Meant to be overriden for custom behaviour.
    void reflow(box2i availableSpace)
    {
        // default: span the entire available area, and do the same for children
        _position = availableSpace;

        foreach(ref child; children)
            child.reflow(availableSpace);
    }

    final box2i position()
    {
        return _position;
    }

    final ref UIElement[] children()
    {
        return _children;
    }

    final Font font()
    {
        return _context.font;
    }

    final int charWidth() pure const nothrow
    {
        return _context.font.charWidth();
    }

    final int charHeight() pure const nothrow
    {
        return _context.font.charHeight();
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

    final RGBA backgroundColor()
    {
        return _backgroundColor;
    }

    final RGBA backgroundColor(RGBA color)
    {
        return _backgroundColor = color;
    }

    final UIElement parent()
    {
        return _parent;
    }

protected:

    /// Render this element before children.
    /// Meant to be overriden.
    void preRender(UIRenderer renderer)
    {
       // defaults to nothing        
    }

    /// Render this element after children elements.
    /// Meant to be overriden.
    void postRender(UIRenderer renderer)
    {
        // defaults to nothing
    }

    UIElement _parent = null;

    box2i _position;

    RGBA _backgroundColor = RGBA(128, 128, 128, 0); // transparent by default

    UIElement[] _children;

    bool _visible = true;


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

    final UIRenderer renderer()
    {
        return _context.renderer;
    }


private:
    UIContext _context;

    bool _mouseOver = false;

    final void setViewportToElement()
    {
        _context.renderer.setViewport(_position.min.x, _position.min.y, _position.width, _position.height);
    }    
}
