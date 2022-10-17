/**
* `UIElement` is the base class of all widgets.
*
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.element;

import core.stdc.stdio;
import core.stdc.string: strlen, strcmp;

import std.algorithm.comparison;
import std.math: round;

public import dplug.math.vector;
public import dplug.math.box;

public import dplug.graphics;

public import dplug.window.window;

public import dplug.core.sync;
public import dplug.core.vec;
public import dplug.core.nogc;

public import dplug.gui.boxlist;
public import dplug.gui.context;

/// Reasonable default value for the Depth channel.
enum ushort defaultDepth = 15000;

/// Reasonable default value for the Roughness channel.
enum ubyte defaultRoughness = 128;

/// Reasonable default value for the Specular channel ("everything is shiny").
enum ubyte defaultSpecular = 128;

/// Reasonable dielectric default value for the Metalness channel.
enum ubyte defaultMetalnessDielectric = 25; // ~ 0.08

/// Reasonable metal default value for the Metalness channel.
enum ubyte defaultMetalnessMetal = 255;

version(legacyMouseOver)
{
    version(futureMouseDrag)
    {
        static assert(false, "Incompatible Dplug options legacyMouseOver and futureMouseDrag");
    }
}

/// Each UIElement class has flags which are used to lessen the number of empty virtual calls.
/// Such flags say which callbacks the `UIElement` need.
alias UIFlags = uint;
enum : UIFlags
{
    /// This `UIElement` draws to the Raw layer and as such `onDrawRaw` should be called when dirtied.
    /// When calling `setDirty(UILayer.guessFromFlags)`, the Raw layer alone will be invalidated.
    flagRaw = 1,

    /// This `UIElement` draws to the PBR layer and as such `onDrawPBR` should be called when dirtied.
    /// Important: `setDirty(UILayer.guessFromFlags)` will lead to BOTH `onDrawPBR` and `onDrawRaw` 
    /// to be called sucessively.
    flagPBR = 2,

    // This `UIElement` is animated and as such the `onAnimate` callback should be called regularly.
    flagAnimated = 4
}

/// Used by `setDirty` calls to figure which layer should be invalidated.
enum UILayer
{
    /// Use the `UIElement` flags to figure which layers to invalidate.
    /// This is what you want most of the time.
    guessFromFlags,

    /// Only the Raw layer is invalidated.
    /// This is what you want if your `UIElement` draw to both Raw and PBR layer, but this 
    /// time you only want to udpate a fast Raw overlay (ie: any PBR widget that still need to be real-time)
    rawOnly,

    /// This is only useful for the very first setDirty call, to mark the whole UI dirty.
    /// For internal Dplug usage.
    allLayers
}

/// The maximum length for an UIElement ID.
enum maxUIElementIDLength = 63;

/// Returns: true if a valid UIlement unique identifier.
/// Chrome rules applies: can't be empty.
static bool isValidElementID(const(char)[] identifier) pure nothrow @nogc @safe
{
    if (identifier.length == 0) return false;
    if (identifier.length > maxUIElementIDLength) return false;
    foreach (char ch; identifier)
    {
        if (ch == 0) // Note: Chrome does actually accept ID with spaces
            return false;
    }
    return true;
}

// An UIElement has 8 void* user pointers (4 reserved for Dplug + 4 for vendors).
// The first two are used by dplug:wren-support.
// Official dplug:wren-support optional extension.
enum UIELEMENT_POINTERID_WREN_EXPORTED_CLASS = 0; /// The cached Wren class of this UIElement.
enum UIELEMENT_POINTERID_WREN_VM_GENERATION  = 1; /// The Wren VM count, as it is restarted. Stored as void*, but is an uint.


/// Base class of the UI widget hierarchy.
///
/// MAYDO: a bunch of stuff in that class is intended specifically for the root element,
///        there is probably a better design to find.
class UIElement
{
public:
nothrow:
@nogc:

    this(UIContext context, uint flags)
    {
        _context = context;
        _flags = flags;
        _localRectsBuf = makeVec!box2i();
        _children = makeVec!UIElement();
        _zOrderedChildren = makeVec!UIElement();
        _idStorage[0] = '\0'; // defaults to no ID

        // Initially set to an empty position
        assert(_position.empty()); 
    }

    ~this()
    {
        foreach(child; _children[])
            child.destroyFree();
    }

    /// Set this element ID.
    /// All UIElement can have a string as unique identifier, similar to HTML.
    /// There is a maximum of 63 characters for this id though.
    /// This ID is supposed to be unique. If it isn't, a search by ID will return `null`.
    /// Chrome rules applies: can't contain any space characters.
    final void setId(const(char)[] identifier) pure
    {
        if (!isValidElementID(identifier))
        {
            // Note: assigning an invalid ID is a silent error. The UIElement ends up with no ID.
            _idStorage[0] = '\0';
            return;
        }
        _idStorage[0..identifier.length] = identifier[0..$];
        _idStorage[identifier.length] = '\0';
    }

    /// Get this element ID.
    /// All UIElement can have a string as unique identifier, similar to HTML.
    /// Returns the empty string "" if there is no ID.
    /// Note: this return an interior slice, and could be invalidated if the ID is reassigned.
    final const(char)[] getId() pure
    {
        if (_idStorage[0] == '\0')
            return "";
        else
        {
            size_t len = strlen(_idStorage.ptr);
            return _idStorage[0..len];
        }
    }

    /// Properties to access this element ID.
    /// See_also: setId, getId.
    final const(char)[] id() pure
    {
        return getId();
    }
    ///ditto
    final void id(const(char)[] identifier)
    {
        setId(identifier);
    }

    /// Returns: `true` if thie UIElement has an ID.
    final bool hasId() pure
    {
        return _idStorage[0] != '\0';
    }

    /// Search subtree for an UIElement with ID `id`. Undefined Behaviour if ID are not unique.
    final UIElement getElementById(const(char)* id)
    {
        if (strcmp(id, _idStorage.ptr) == 0)
            return this;

        foreach(c; _children)
        {
            UIElement r = c.getElementById(id);
            if (r) return r;
        }
        return null;
    }

    /// This method is called for each item in the drawlist that was visible and has a dirty Raw layer.
    /// This is called after compositing, starting from the buffer output by the Compositor.
    final void renderRaw(ImageRef!RGBA rawMap, in box2i[] areasToUpdate)
    {
        // We only consider the part of _position that is actually in the surface
        box2i validPosition = _position.intersection(box2i(0, 0, rawMap.w, rawMap.h));

        // Note: _position can be outside the bounds of a window.

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

        // Crop the composited map to the valid part of _position
        // Drawing outside of _position is disallowed by design.
        ImageRef!RGBA rawMapCropped = rawMap.cropImageRef(validPosition);
        assert(rawMapCropped.w != 0 && rawMapCropped.h != 0); // Should never be an empty area there
        onDrawRaw(rawMapCropped, _localRectsBuf[]);
    }

    /// Returns: true if was drawn, ie. the buffers have changed.
    /// This method is called for each item in the drawlist that was visible and has a dirty PBR layer.
    final void renderPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, in box2i[] areasToUpdate)
    {
        // we only consider the part of _position that is actually in the surface
        box2i validPosition = _position.intersection(box2i(0, 0, diffuseMap.w, diffuseMap.h));

        // Note: _position can be outside the bounds of a window.

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

        // Crop the diffuse, material and depth to the valid part of _position
        // Drawing outside of _position is disallowed by design.
        ImageRef!RGBA diffuseMapCropped = diffuseMap.cropImageRef(validPosition);
        ImageRef!L16 depthMapCropped = depthMap.cropImageRef(validPosition);
        ImageRef!RGBA materialMapCropped = materialMap.cropImageRef(validPosition);

        // Should never be an empty area there
        assert(diffuseMapCropped.w != 0 && diffuseMapCropped.h != 0);
        onDrawPBR(diffuseMapCropped, depthMapCropped, materialMapCropped, _localRectsBuf[]);
    }

    /// The goal of this method is to update positions of childrens. It is called whenever
    /// _position changes.
    ///
    /// It is called after a widget position is changed.
    /// Given information with `position` getter, the widget decides the position of its 
    /// children, by calling their `position` setter (which will call `reflow` itself).
    /// 
    /// `reflow()` cannot be used to set the own position of a widget: it is always done
    /// externally. You shouldn't call reflow yourself, instead use `position = x;`.
    ///
    /// Like in the DOM, children elements don't need to be inside position of their parent.
    /// The _position field is indeed storing an absolute position.
    ///
    /// See_also: `position`, `_position`.
    void reflow()
    {
        // default: do nothing
    }

    /// Returns: Position of the element, that will be used for rendering. 
    /// This getter is typically used in reflow() to adapt resource and children to the new position.
    final box2i position()
    {
        return _position;
    }

    /// Changes the position of the element.
    /// This calls `reflow` if that position has changed.
    /// IMPORTANT: As of today you are not allowed to assign a position outside the extent of the window.
    ///            This is purely a Dplug limitation.
    final void position(box2i p)
    {
        assert(p.isSorted());

        bool moved = (p != _position);
        
        // Make dirty rect in former and new positions.
        if (moved)
        {
            setDirtyWhole();
            _position = p;
            setDirtyWhole();

            // New in Dplug v11: setting position now calls reflow() if position has changed.
            reflow();

            // _position shouldn't be touched by `reflow` calls.
            assert(p == _position);
        }
    }

    /// Changes the position of the element.
    /// This calls `reflow` if that position has changed.
    /// Note: Widget coordinates are always integer coordinates.
    ///       The input rectangle is rounded to nearest integer.
    /// IMPORTANT: As of today you are not allowed to assign a position outside the extent of the window.
    ///            This is purely a Dplug limitation.
    final void position(box2f p)
    {
        int x1 = cast(int) round(p.min.x);
        int y1 = cast(int) round(p.min.y);
        int x2 = cast(int) round(p.max.x);
        int y2 = cast(int) round(p.max.y);
        box2i r = box2i(x1, y1, x2, y2);
        position = r;
    }

    /// Returns: The nth  child of this `UIElement`.
    final UIElement child(int n)
    {
        return _children[n];
    }

    /// Adds an `UIElement`
    /// The addChild method is mandatory.
    /// Such a child MUST be created through `dplug.core.nogc.mallocEmplace`.
    /// Note: to display a newly added widget, use `position` setter.
    final void addChild(UIElement element)
    {
        element._parent = this;
        _children.pushBack(element);

        // Recompute visibility of that element.
        bool parentVisible = isVisible();
        element.recomputeVisibilityStatus(parentVisible);
    }

    /// Removes a child (but does not destroy it, you take back the ownership of it).
    /// Useful for creating dynamic UI's.
    /// MAYDO: there are restrictions for where this is allowed. Find them.
    final void removeChild(UIElement element)
    {
        int index= _children.indexOf(element);
        if(index >= 0)
        {
            // Dirty where the UIElement has been removed
            element.setDirtyWhole();

            _children.removeAndReplaceByLastElement(index);
        }
    }

    /// `onmouseClick` is called for every new click, whether or not you are in a 
    /// dragging operation.
    /// This function is meant to be overriden.
    /// If you return `true`, any existing dragging is stopped, and a new drag operation
    /// is started. `onStopDrag` may be called, than `onBeginDrag`. 
    /// If you return `false`, the click is unprocessed.
    /// Warning: For this reason, check your widgets with several mouse buttons pressed 
    /// at once.
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

    // Called when this Element is clicked and get the focus.
    // This function is meant to be overriden.
    void onFocusEnter()
    {
    }

    // Called when focus is lost because another Element was clicked.
    // This function is meant to be overriden.
    void onFocusExit()
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

    /// Check if given point is within the widget. 
    /// Override this to disambiguate clicks and mouse-over between widgets that 
    /// would otherwise partially overlap.
    /// 
    /// `x` and `y` are given in local widget coordinates.
    /// IMPORTANT: a widget CANNOT be clickable beyond its _position.
    ///            For now, there is no good reason for that, but it could be useful
    ///            in the future if we get acceleration structure for picking elements.
    bool contains(int x, int y)
    {
        return (x < cast(uint)(_position.width ) )
            && (y < cast(uint)(_position.height) );
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
        bool canBeClicked = _visibilityStatus; // cannot be clicked if invisible
        if (canBeClicked && contains(x - _position.min.x, y - _position.min.y))
        {
            if (onMouseClick(x - _position.min.x, y - _position.min.y, button, isDoubleClick, mstate))
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
        version(futureMouseDrag)
        {
            bool wasDragging = (_context.dragged !is null);
        }

        _context.stopDragging();

        version(futureMouseDrag)
        {
            // Enter widget below mouse if a dragged operation was stopped.
            if (wasDragging)
            {
                bool foundOver = mouseMove(x, y, 0, 0, mstate, false);
                if (!foundOver)
                    _context.setMouseOver(null);
            }
        }
    }

    // to be called at top-level when the mouse wheeled
    final bool mouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate)
    {
        recomputeZOrderedChildren();

        // Test children that are displayed above this element first
        foreach(child; _zOrderedChildren[])
        {
            if (child.zOrder >= zOrder)
                if (child.mouseWheel(x, y, wheelDeltaX, wheelDeltaY, mstate))
                    return true;
        }

        bool canBeMouseWheeled = _visibilityStatus; // cannot be mouse-wheeled if invisible
        if (canBeMouseWheeled && contains(x - _position.min.x, y - _position.min.y))
        {
            if (onMouseWheel(x - _position.min.x, y - _position.min.y, wheelDeltaX, wheelDeltaY, mstate))
                return true;
        }

        // Test children that are displayed below this element last
        foreach(child; _zOrderedChildren[])
        {
            if (child.zOrder < zOrder)
                if (child.mouseWheel(x, y, wheelDeltaX, wheelDeltaY, mstate))
                    return true;
        }

        return false;
    }

    version (legacyMouseOver) // FUTURE: remove that on next major
    {
        // to be called when the mouse moved
        final void mouseMove(int x, int y, int dx, int dy, MouseState mstate)
        {
            if (isDragged)
            {
                // EDIT MODE
                // In debug mode, dragging with the right mouse button move elements around
                // and dragging with shift  + right button resize elements around.
                //
                // Additionally, if CTRL is pressed, the increments are only -1 or +1 pixel.
                // 
                // You can see the _position rectangle thanks to `debugLog`.
                bool draggingUsed = false;
                debug
                {
                    if (mstate.rightButtonDown && mstate.shiftPressed)
                    {
                        if (mstate.ctrlPressed)
                        {
                            dx = clamp(dx, -1, +1);
                            dy = clamp(dy, -1, +1);
                        }
                        int nx = _position.min.x;
                        int ny = _position.min.y;
                        int w = _position.width + dx;
                        int h = _position.height + dy;
                        if (w < 5) w = 5;
                        if (h < 5) h = 5;
                        position = box2i(nx, ny, nx + w, ny + h);
                        draggingUsed = true;

                    
                    }
                    else if (mstate.rightButtonDown)
                    {
                        if (mstate.ctrlPressed)
                        {
                            dx = clamp(dx, -1, +1);
                            dy = clamp(dy, -1, +1);
                        }
                        int nx = _position.min.x + dx;
                        int ny = _position.min.y + dy;
                        if (nx < 0) nx = 0;
                        if (ny < 0) ny = 0;
                        position = box2i(nx, ny, nx + position.width, ny + position.height);
                        draggingUsed = true;
                    }

                    // Output the latest position
                    // This is helpful when developing a plug-in UI.
                    if (draggingUsed)
                    {
                        char[128] buf;
                        snprintf(buf.ptr, 128, "position = rectangle(%d, %d, %d, %d)\n", _position.min.x, _position.min.y, _position.width, _position.height);
                        debugLog(buf.ptr);
                    }
                }

                if (!draggingUsed)
                    onMouseDrag(x - _position.min.x, y - _position.min.y, dx, dy, mstate);
            }

            // Note: no z-order for mouse-move, it's called for everything. Is it right? What would the DOM do?

            foreach(child; _children[])
            {
                child.mouseMove(x, y, dx, dy, mstate);
            }

            // Can't be mouse over if not visible.
            bool canBeMouseOver = _visibilityStatus;
            if (canBeMouseOver && contains(x - _position.min.x, y - _position.min.y)) // FUTURE: something more fine-grained?
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
    }
    else
    {
        // To be called when the mouse moved
        // Returns: `true` if one child has taken the mouse-over role globally.
        final bool mouseMove(int x, int y, int dx, int dy, MouseState mstate, bool alreadyFoundMouseOver)
        {
            recomputeZOrderedChildren();

            bool foundMouseOver = alreadyFoundMouseOver;

            // Test children that are displayed above this element first
            foreach(child; _zOrderedChildren[])
            {
                if (child.zOrder >= zOrder)
                {
                    bool found = child.mouseMove(x, y, dx, dy, mstate, foundMouseOver);
                    foundMouseOver = foundMouseOver || found;
                }
            }

            if (isDragged())
            {
                // EDIT MODE
                // In debug mode, dragging with the right mouse button move elements around
                // and dragging with shift  + right button resize elements around.
                //
                // Additionally, if CTRL is pressed, the increments are only -1 or +1 pixel.
                // 
                // You can see the _position rectangle thanks to `debugLog`.
                bool draggingUsed = false;
                debug
                {
                    if (mstate.rightButtonDown && mstate.shiftPressed)
                    {
                        if (mstate.ctrlPressed)
                        {
                            dx = clamp(dx, -1, +1);
                            dy = clamp(dy, -1, +1);
                        }
                        int nx = _position.min.x;
                        int ny = _position.min.y;
                        int w = _position.width + dx;
                        int h = _position.height + dy;
                        if (w < 5) w = 5;
                        if (h < 5) h = 5;
                        position = box2i(nx, ny, nx + w, ny + h);
                        draggingUsed = true;


                    }
                    else if (mstate.rightButtonDown)
                    {
                        if (mstate.ctrlPressed)
                        {
                            dx = clamp(dx, -1, +1);
                            dy = clamp(dy, -1, +1);
                        }
                        int nx = _position.min.x + dx;
                        int ny = _position.min.y + dy;
                        if (nx < 0) nx = 0;
                        if (ny < 0) ny = 0;
                        position = box2i(nx, ny, nx + position.width, ny + position.height);
                        draggingUsed = true;
                    }

                    // Output the latest position
                    // This is helpful when developing a plug-in UI.
                    if (draggingUsed)
                    {
                        char[128] buf;
                        snprintf(buf.ptr, 128, "position = box2i.rectangle(%d, %d, %d, %d)\n", _position.min.x, _position.min.y, _position.width, _position.height);
                        debugLog(buf.ptr);
                    }
                }

                if (!draggingUsed)
                    onMouseDrag(x - _position.min.x, y - _position.min.y, dx, dy, mstate);
            }

            // Can't be mouse over if not visible.
            bool canBeMouseOver = _visibilityStatus;

            version(futureMouseDrag)
            {
                // If dragged, it already received `onMouseDrag`.
                // if something else is dragged, it can be mouse over.
                if (_context.dragged !is null)
                    canBeMouseOver = false;
            }

            if (canBeMouseOver && contains(x - _position.min.x, y - _position.min.y)) // FUTURE: something more fine-grained?
            {
                // Get the mouse-over crown if not taken
                if (!foundMouseOver)
                {
                    foundMouseOver = true;
                    _context.setMouseOver(this);

                    version(futureMouseDrag)
                    {
                        onMouseMove(x - _position.min.x, y - _position.min.y, dx, dy, mstate);
                    }
                }

                version(futureMouseDrag)
                {}
                else
                {
                    onMouseMove(x - _position.min.x, y - _position.min.y, dx, dy, mstate);
                }
            }

            // Test children that are displayed below this element
            foreach(child; _zOrderedChildren[])
            {
                if (child.zOrder < zOrder)
                {
                    bool found = child.mouseMove(x, y, dx, dy, mstate, foundMouseOver);
                    foundMouseOver = foundMouseOver || found;
                }
            }
            return foundMouseOver;
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
    void animate(double dt, double time)
    {
        if (isAnimated)
            onAnimate(dt, time);

        // For some rare widgets, it is important that children are animated
        // _after_ their parent.
        foreach(child; _children[])
            child.animate(dt, time);
    }

    final UIContext context()
    {
        return _context;
    }

    /// A widget is "visible" when it has a true visibility flag, and its parent is itself visible.
    /// Returns: Last computed visibility status.
    final bool isVisible() pure const
    {
        return _visibilityStatus;
    }

    deprecated("use visibility() instead") final void setVisible(bool visible)
    {
        visibility(visible);
    }

    /// Get visibility flag of the widget.
    /// A widget might still be invisible, if one of its parent is not visible.
    final bool visibility() pure const
    {
        return _visibleFlag;
    }

    /// Change visibility flag of the widget. This show and hide all children of this UIElement,
    /// regardless of their position on screen, invalidating their graphics if need be much
    /// like a position change.
    final void visibility(bool visible)
    {
        if (_visibleFlag == visible)
            return; // Nothing to do, this wouldn't change any visibility status in sub-tree.

        _visibleFlag = visible;

        // Get parent visibility status.
        bool parentVisibleStatus = (parent !is null) ? parent.isVisible() : true;

        // Recompute own visibility status.
        recomputeVisibilityStatus(parentVisibleStatus);
    }

    final int zOrder() pure const
    {
        return _zOrder;
    }

    final void setZOrder(int zOrder) pure
    {
        // TODO: this should call setDirty, if Z order changed.
        _zOrder = zOrder;
    }

    /// Mark this element as wholly dirty.
    ///
    /// Params:
    ///     layer which layers need to be redrawn.
    ///
    /// Important: you _can_ call this from the audio thread, HOWEVER it is
    ///            much more efficient to mark the widget dirty with an atomic 
    ///            and call `setDirty` in animation callback.
    void setDirtyWhole(UILayer layer = UILayer.guessFromFlags)
    {
        addDirtyRect(_position, layer);
    }

    /// Mark a part of the element dirty.
    /// This part must be a subrect of its _position.
    ///
    /// Params:
    ///     rect = Position of the dirtied rectangle, in widget coordinates.
    ///
    /// Important: you could call this from the audio thread, however it is
    ///            much more efficient to mark the widget dirty with an atomic 
    ///            and call setDirty in animation callback.
    void setDirty(box2i rect, UILayer layer = UILayer.guessFromFlags)
    {
        /// BUG: it is problematic to allow this from the audio thread,
        /// because the access to _position isn't protected and it could 
        /// create a race in case of concurrent reflow(). Puhsed rectangles
        /// might be out of range, this is workarounded in GUIGraphics currently
        /// for other reasons.
        box2i translatedRect = rect.translate(_position.min);
        assert(_position.contains(translatedRect));
        addDirtyRect(translatedRect, layer);
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

    version(legacyMouseOver)
    {  
        final bool isMouseOver() pure const
        {
            return _mouseOver;
        }
    }
    else
    {
        /// Returns: `true` is this element is hovered by the mouse, and 
        final bool isMouseOver() pure const
        {
            version(futureMouseDrag)
            {
                if (_context.mouseOver !is this)
                {
                    assert(_context.dragged !is this);
                }
            }

            return _context.mouseOver is this;
        }
    }

    final bool isDragged() pure const
    {
        version(futureMouseDrag)
        {
            if (_context.dragged is this)
                assert(isMouseOver());
        }

        return _context.dragged is this;
    }

    final bool isFocused() pure const
    {
        return _context.focused is this;
    }

    final bool drawsToPBR() pure const
    {
        return (_flags & flagPBR) != 0;
    }

    final bool drawsToRaw() pure const
    {
        return (_flags & flagRaw) != 0;
    }

    final bool isAnimated() pure const
    {
        return (_flags & flagAnimated) != 0;
    }

    /// Appends the Elements that should be drawn, in order.
    /// You should empty it before calling this function.
    /// Everything visible get into the draw list, but that doesn't mean they
    /// will get drawn if they don't overlap with a dirty area.
    final void getDrawLists(ref Vec!UIElement listRaw, ref Vec!UIElement listPBR)
    {
        if (_visibilityStatus)
        {
            if (drawsToRaw())
                listRaw.pushBack(this);

            if (drawsToPBR())
                listPBR.pushBack(this);

            // Note: if one widget is not visible, the whole sub-tree can be ignored for drawing.
            // This is because invisibility is inherited without recourse.
            foreach(child; _children[])
                child.getDrawLists(listRaw, listPBR);
        }
    }

    MouseCursor cursorWhenDragged() 
    { 
        return _cursorWhenDragged;
    }

    void setCursorWhenDragged(MouseCursor mouseCursor)
    {
        _cursorWhenDragged = mouseCursor;
    }

    MouseCursor cursorWhenMouseOver()
    {
        return _cursorWhenMouseOver;
    }

    void setCursorWhenMouseOver(MouseCursor mouseCursor)
    {
        _cursorWhenMouseOver = mouseCursor;
    }

    /// Get a user pointer. Allow dplug:gui extensions.
    final void* getUserPointer(int pointerID)
    {
        return _userPointers[pointerID];
    }

    /// Set a user pointer. Allow dplug:gui extensions.
    final void setUserPointer(int pointerID, void* userPointer)
    {
        _userPointers[pointerID] = userPointer;
    }

protected:

    /// Raw layer draw method. This gives you 1 surface cropped by  _position for drawing.
    /// Note that you are not forced to draw to the surfaces at all.
    /// 
    /// `UIElement` are drawn by increasing z-order, or lexical order if lack thereof.
    /// Those elements who have non-overlapping `_position` are drawn in parallel.
    /// Hence you CAN'T draw outside `_position` and receive cropped surfaces.
    ///
    /// IMPORTANT: you MUST NOT draw outside `dirtyRects`. This allows more fine-grained updates.
    /// A `UIElement` that doesn't respect dirtyRects will have PAINFUL display problems.
    void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        // empty by default, meaning this UIElement does not draw on the Raw layer
    }

    /// PBR layer draw method. This gives you 3 surfaces cropped by  _position for drawing.
    /// Note that you are not forced to draw all to the surfaces at all, in which case the
    /// below `UIElement` will be displayed.
    /// 
    /// `UIElement` are drawn by increasing z-order, or lexical order if lack thereof.
    /// Those elements who have non-overlapping `_position` are drawn in parallel.
    /// Hence you CAN'T draw outside `_position` and receive cropped surfaces.
    /// `diffuseMap`, `depthMap` and `materialMap` are made to span _position exactly.
    ///
    /// IMPORTANT: you MUST NOT draw outside `dirtyRects`. This allows more fine-grained updates.
    /// A `UIElement` that doesn't respect dirtyRects will have PAINFUL display problems.
    void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
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
                    materialScan.ptr[x] = RGBA(defaultRoughness, defaultMetalnessDielectric, defaultSpecular, 255);
                }
            }
        }
    }

    /// Called periodically for every `UIElement`.
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

    /// Position is the graphical extent of the element, or something larger.
    /// An `UIElement` is not allowed though to draw further than its _position.
    /// For efficiency it's best to keep `_position` as small as feasible.
    /// This is an absolute "world" positioning data, that doesn't depend on the parent's position.
    box2i _position;

    /// The list of children UI elements.
    Vec!UIElement _children;

    /// Flags, for now immutable
    immutable(uint) _flags;

    /// Higher z-order = above other `UIElement`.
    /// By default, every `UIElement` have the same z-order.
    /// Because the sort is stable, tree traversal order is the default order (depth first).
    /// The children added last with `addChild` is considered above its siblings if you have futureZOrder.
    int _zOrder = 0;

private:

    /// Reference to owning context.
    UIContext _context;

    /// Flag: whether this UIElement has mouse over it or not.
    version(legacyMouseOver) 
    {
        bool _mouseOver = false; 
    }


    // <visibility privates>

    /// If _visibleFlag is false, neither the Element nor its children are drawn.
    /// Each UIElement starts its life being visible.
    bool _visibleFlag = true;

    /// Final visibility value, cached in order to set rectangles dirty.
    /// It is always up to date across the whole UI tree.
    bool _visibilityStatus = true;

    void recomputeVisibilityStatus(bool parentVisibilityStatus)
    {
        bool newVisibleStatus = _visibleFlag && parentVisibilityStatus;

        // has it changed in any way?
        if (newVisibleStatus != _visibilityStatus)
        {
            _visibilityStatus = newVisibleStatus;

            // Dirty the widget position
            setDirtyWhole();

            // Must inform children of the new status of parent.
            foreach(child; _children[])
                child.recomputeVisibilityStatus(newVisibleStatus);
        }
    }

    // </visibility privates>

    /// Dirty rectangles buffer, cropped to _position.
    Vec!box2i _localRectsBuf;

    /// Sorted children in Z-lexical-order (sorted by Z, or else increasing index in _children).
    Vec!UIElement _zOrderedChildren;

    /// The mouse cursor to display when this element is being dragged
    MouseCursor _cursorWhenDragged = MouseCursor.pointer;

    /// The mouse cursor to display when this element is being moused over
    MouseCursor _cursorWhenMouseOver = MouseCursor.pointer;

    /// Identifier storage.
    char[maxUIElementIDLength+1] _idStorage;

    /// Warning: if you store objects here, keep in mind they won't get destroyed automatically.
    /// 4 user pointer in case you'd like to store things in UIElement as a Dplug extension.
    /// id 0..1 are reserved for Wren support.
    /// id 2..3 are reserved for future Dplug extensions.
    /// id 4..7 are for vendor-specific extensions.
    void*[8] _userPointers; // Opaque pointers for Wren VM and things.

    // Sort children in ascending z-order
    // Input: unsorted _children
    // Output: sorted _zOrderedChildren
    // This is not thread-safe.
    // Only one widget in the same UI can sort its children at once, since it uses
    // a UIContext buffer to do so.
    final void recomputeZOrderedChildren()
    {
        // Get a z-ordered list of childrens
        _zOrderedChildren.clearContents();

        /// See: https://github.com/AuburnSounds/Dplug/issues/652
        version(futureZOrder)
        {
            // Adding children in reverse, since children added last are considered having a higher Z order.
            foreach_reverse(child; _children[])
                _zOrderedChildren.pushBack(child);
        }
        else
        {
            foreach(child; _children[])
                _zOrderedChildren.pushBack(child);
        }


       // 

        timSort!UIElement(_zOrderedChildren[],
                            context.sortingScratchBuffer(),
                            (a, b) nothrow @nogc 
                            {
                                if (a.zOrder < b.zOrder) return 1;
                                else if (a.zOrder > b.zOrder) return -1;
                                else return 0;
                            });

    }

    final void addDirtyRect(box2i rect, UILayer layer)
    {
        final switch(layer)
        {
            case UILayer.guessFromFlags:
                if (drawsToPBR())
                {
                    // Note: even if one UIElement draws to both Raw and PBR layers, we are not 
                    // adding this rectangle in `dirtyListRaw` since the Raw layer is automatically
                    // updated when the PBR layer below is.
                    _context.dirtyListPBR.addRect(rect); 
                }
                else if (drawsToRaw())
                {
                    _context.dirtyListRaw.addRect(rect);
                }
                break;

            case UILayer.rawOnly:
                _context.dirtyListRaw.addRect(rect); 
                break;

            case UILayer.allLayers:
                // This will lead the Raw layer to be invalidated too
                _context.dirtyListPBR.addRect(rect);
                break;
        }
    }
}
