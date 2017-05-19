/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.element;

import std.algorithm.comparison;

public import gfm.math.vector;
public import gfm.math.box;

public import dplug.graphics;

public import dplug.window.window;

public import dplug.core.sync;
public import dplug.core.alignedbuffer;
public import dplug.core.nogc;

public import dplug.graphics.font;
public import dplug.graphics.drawex;

public import dplug.gui.boxlist;
public import dplug.gui.context;

/// Reasonable default value for the Depth channel.
enum ushort defaultDepth = 15000;

/// Reasonable default value for the Roughness channel.
enum ubyte defaultRoughness = 128;

/// Reasonable default value for the Specular channel ("everything is shiny").
enum ubyte defaultSpecular = 128;

/// Reasonable default value for the Physical channel (completely physical).
enum ubyte defaultPhysical = 255;

/// Reasonable dielectric default value for the Metalness channel.
enum ubyte defaultMetalnessDielectric = 25; // ~ 0.08

/// Reasonable metal default value for the Metalness channel.
enum ubyte defaultMetalnessMetal = 255;

/// Base class of the UI widget hierarchy.
///
/// Bugs: a bunch of stuff in that class is intended specifically for the root element,
///       there is probably a batter design to find

class UIElement
{
public:
nothrow:
@nogc:

    this(UIContext context)
    {
        _context = context;
        _localRectsBuf = makeAlignedBuffer!box2i();
        _children = makeAlignedBuffer!UIElement();
        _zOrderedChildren = makeAlignedBuffer!UIElement();
    }

    ~this()
    {
        foreach(child; _children[])
            child.destroyFree();
    }

    /// Returns: true if was drawn, ie. the buffers have changed.
    /// This method is called for each item in the drawlist that was visible and dirty.
    final void render(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, in box2i[] areasToUpdate)
    {
        // List of disjointed dirty rectangles intersecting with valid part of _position
        // A nice thing with intersection is that a disjointed set of rectangles
        // stays disjointed.

        // we only consider the part of _position that is actually in the surface
        box2i validPosition = _position.intersection(box2i(0, 0, diffuseMap.w, diffuseMap.h));

        if (validPosition.empty())
            return; // nothing to draw here

        _localRectsBuf.clearContents();
        {
            foreach(rect; areasToUpdate)
            {
                box2i inter = rect.intersection(validPosition);

                if (!inter.empty) // don't consider empty rectangles
                {
                    // Express the dirty rect in local coordinates for simplicity
                    _localRectsBuf.pushBack( inter.translate(-validPosition.min) );
                }
            }
        }

        if (_localRectsBuf.length == 0)
            return; // nothing to draw here

        // Crop the diffuse and depth to the valid part of _position
        // This is because drawing outside of _position is disallowed by design.
        // Never do that!
        ImageRef!RGBA diffuseMapCropped = diffuseMap.cropImageRef(validPosition);
        ImageRef!L16 depthMapCropped = depthMap.cropImageRef(validPosition);
        ImageRef!RGBA materialMapCropped = materialMap.cropImageRef(validPosition);

        // Should never be an empty area there
        assert(diffuseMapCropped.w != 0 && diffuseMapCropped.h != 0);
        onDraw(diffuseMapCropped, depthMapCropped, materialMapCropped, _localRectsBuf[]);
    }

    /// Meant to be overriden almost everytime for custom behaviour.
    /// Default behaviour is to span the whole area and reflow children.
    /// Any layout algorithm is up to you.
    /// Children elements don't need to be inside their parent.
    void reflow(box2i availableSpace)
    {
        // default: span the entire available area, and do the same for children
        _position = availableSpace;

        foreach(ref child; _children)
            child.reflow(availableSpace);
    }

    /// Returns: Position of the element, that will be used for rendering. This
    /// position is reset when calling reflow.
    final box2i position() nothrow @nogc
    {
        return _position;
    }

    /// Forces the position of the element. It is typically used in the parent
    /// reflow() method
    final box2i position(box2i p) nothrow @nogc
    {
        assert(p.isSorted());
        return _position = p;
    }

    final UIElement child(int n)
    {
        return _children[n];
    }

    // The addChild method is mandatory.
    // Such a child MUST be created through `dplug.core.nogc.mallocEmplace`.
    final void addChild(UIElement element)
    {
        element._parent = this;
        _children.pushBack(element); 
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
        recomputeZOrderedChildren();

        // Test children that are displayed above this element first
        foreach(child; _zOrderedChildren[])
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
        foreach(child; _zOrderedChildren[])
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
        foreach(child; _children[])
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
        {
            // in debug mode, dragging with the right mouse button move elements around
            // and dragging with shift  + right button resize elements around
            bool draggingUsed = false;
            debug
            {
                if (mstate.rightButtonDown && mstate.shiftPressed)
                {
                    int nx = _position.min.x;
                    int ny = _position.min.y;
                    int w = _position.width + dx;
                    int h = _position.height + dy;
                    if (w < 5) w = 5;
                    if (h < 5) h = 5;
                    setDirtyWhole();
                    _position = box2i(nx, ny, nx + w, ny + h);
                    setDirtyWhole();
                    draggingUsed = true;
                }
                else if (mstate.rightButtonDown)
                {
                    int nx = _position.min.x + dx;
                    int ny = _position.min.y + dy;
                    if (nx < 0) nx = 0;
                    if (ny < 0) ny = 0;
                    setDirtyWhole();
                    _position = box2i(nx, ny, nx + _position.width, ny + _position.height);
                    setDirtyWhole();
                    draggingUsed = true;
                }
            }

            if (!draggingUsed)
                onMouseDrag(x - _position.min.x, y - _position.min.y, dx, dy, mstate);
        }

        foreach(child; _children[])
        {
            child.mouseMove(x, y, dx, dy, mstate);
        }

        if (_position.contains(vec2i(x, y))) // FUTURE: something more fine-grained?
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

        foreach(child; _children[])
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

        foreach(child; _children[])
        {
            if (child.keyUp(key))
                return true;
        }
        return false;
    }

    // To be called at top-level periodically.
    void animate(double dt, double time) nothrow @nogc
    {
        onAnimate(dt, time);
        foreach(child; _children[])
            child.animate(dt, time);
    }

    final UIContext context() nothrow @nogc
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

    /// Mark this element as wholly dirty.
    void setDirtyWhole() nothrow @nogc
    {
        _context.dirtyList.addRect(_position);
    }

    /// Mark a part of the element dirty.
    /// This part must be a subrect of the _position.
    /// Params:
    ///     rect Position of the dirtied rectangle, in widget coordinates.
    void setDirty(box2i rect) nothrow @nogc
    {
        box2i translatedRect = rect.translate(_position.min);
        assert(_position.contains(translatedRect));
        _context.dirtyList.addRect(translatedRect);
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

    final bool isMouseOver() pure const nothrow @nogc
    {
        return _mouseOver;
    }

    final bool isDragged() pure const nothrow @nogc
    {
        return _context.dragged is this;
    }

    final bool isFocused() pure const nothrow @nogc
    {
        return _context.focused is this;
    }

    /// Appends the Elements that should be drawn, in order.
    /// You should empty it before calling this function.
    /// Everything visible get into the draw list, but that doesn't mean they
    /// will get drawn if they don't overlap with a dirty area.
    final void getDrawList(ref AlignedBuffer!UIElement list) nothrow @nogc
    {
        if (isVisible())
        {
            list.pushBack(this);
            foreach(child; _children[])
                child.getDrawList(list);
        }
    }

protected:

    /// Draw method. You should redraw the area there.
    /// For better efficiency, you may only redraw the part in _dirtyRect.
    /// diffuseMap and depthMap are made to span _position exactly,
    /// so you can draw in the area (0 .. _position.width, 0 .. _position.height)
    void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        // defaults to filling with a grey pattern
        RGBA darkGrey = RGBA(100, 100, 100, 0);
        RGBA lighterGrey = RGBA(150, 150, 150, 0);

        foreach(dirtyRect; dirtyRects)
        {
            for (int y = dirtyRect.min.y; y < dirtyRect.max.y; ++y)
            {
                L16[] depthScan = depthMap.scanline(y);
                RGBA[] diffuseScan = diffuseMap.scanline(y);
                RGBA[] materialScan = materialMap.scanline(y);
                for (int x = dirtyRect.min.x; x < dirtyRect.max.x; ++x)
                {
                    diffuseScan.ptr[x] = ( (x >> 3) ^  (y >> 3) ) & 1 ? darkGrey : lighterGrey;
                    depthScan.ptr[x] = L16(defaultDepth);
                    materialScan.ptr[x] = RGBA(defaultRoughness,defaultMetalnessDielectric, defaultSpecular, defaultPhysical);
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
    void onAnimate(double dt, double time) nothrow @nogc
    {
    }

    /// Parent element.
    /// Following this chain gets to the root element.
    UIElement _parent = null;

    /// Position is the graphical extent
    /// An Element is not allowed though to draw further than its _position.
    box2i _position;

    AlignedBuffer!UIElement _children;

    /// If _visible is false, neither the Element nor its children are drawn.
    bool _visible = true;

    /// By default, every Element have the same z-order
    /// Because the sort is stable, tree traversal order is the default order (depth first).
    int _zOrder = 0;

private:

    /// Reference to owning context
    UIContext _context;

    /// Flag: whether this UIElement has mouse over it or not
    bool _mouseOver = false;

    AlignedBuffer!box2i _localRectsBuf;

    /// Necessary for mouse-click to be aware of Z order
    AlignedBuffer!UIElement _zOrderedChildren;

    // Sort children in ascending z-order
    final void recomputeZOrderedChildren()
    {
        // Get a z-ordered list of childrens
        _zOrderedChildren.clearContents();
        foreach(child; _children[])
            _zOrderedChildren.pushBack(child);

        // Note: unstable sort, so do not forget to _set_ z-order in the first place
        //       if you have overlapping UIElement
        quicksort!UIElement(_zOrderedChildren[],  
                             (a, b) nothrow @nogc 
                             {
                                 if (a.zOrder < b.zOrder) return 1;
                                 else if (a.zOrder > b.zOrder) return -1;
                                 else return 0;
                             });
    }
}



