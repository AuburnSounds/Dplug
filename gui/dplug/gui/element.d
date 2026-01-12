/**
    `UIElement` is the base class of all widgets.
    In the Dplug codebase, `UIElement` and "widgets" terms
    are used indifferently.

    Copyright: Copyright Auburn Sounds 2015 and later.
    License:   http://www.boost.org/LICENSE_1_0.txt, BSL-1.0
    Authors:   Guillaume Piolat
*/
module dplug.gui.element;

import core.stdc.stdio;
import core.stdc.string: strlen, strcmp;

import std.math: round;

public import godotmath;
public import dplug.math.vector; // FUTURE: replaced by godot-math
public import dplug.math.box;    // FUTURE: replaced by godot-math

public import dplug.graphics;
public import dplug.window.window;
public import dplug.core.sync;
public import dplug.core.vec;
public import dplug.core.nogc;
public import dplug.gui.boxlist;
public import dplug.gui.context;


/**
    `UIElement` (aka widgets) have various flags.

    Note: For now the UIFlags are fixed over the lifetime of
          a widget, but all of them could eventually
          change at every frame.
*/
alias UIFlags = uint;
enum : UIFlags
{
    /**
        This `UIElement` draws to the Raw layer.
        `onDrawRaw` will be called when widget is dirty.
        When calling `setDirty(UILayer.guessFromFlags)`,
        the Raw layer will be invalidated.

        The Raw layer is "on top" of the PBR layer, and is
        faster to update since it needs no PBR computation.
    */
    flagRaw = 1,

    /**
        This `UIElement` draws to the PBR layer.
        `onDrawPBR` will be called when widget is dirty.

        When calling `setDirty(UILayer.guessFromFlags)`, the
        PBR _and_ Raw layers will be invalidated, since the
        Raw layer is composited over the result of PBR.
    */
    flagPBR = 2,

    /**
        This `UIElement` is animated.
        The `onAnimate` callback should be called regularly.

        If you don't have this flag, only input events and
        parameter changes may change the widget appearance.
    */
    flagAnimated = 4,

    /**
        This `UIElement` cannot be drawn in parallel with
        other widgets, when drawn in the Raw layer.
    */
    flagDrawAloneRaw = 8,

    /**
        This `UIElement` cannot be drawn in parallel with
        other widgets, when drawn in the PBR layer.
    */
    flagDrawAlonePBR = 16,
}


/**
    Reasonable default value for the Depth channel.

    In the Depth channel:
                0  means bottom, further from viewer.
      `ushort.max` means top, closer from viewer.
*/
enum ushort defaultDepth = 15000;


/**
    Reasonable default value for the Roughness channel.

    In the Roughness channel:
        0 means sharpest (more plastic)
      255 means smoothest surface (more polished)
*/
enum ubyte defaultRoughness = 128;


/**
    Reasonable default value for the Specular channel.
    Since "everything is shiny" it' better to always have at
    least a little of specular.

    In the Specul channel:
        0 means no specular reflection.
      255 means specular reflection.

    It changes the amount of specular highlights.
*/
enum ubyte defaultSpecular = 128;


/**
    Reasonable dielectric and metal values for Metalness.

    In the metalness channel:
        0 means no environment reflection.
      255 means more environment (skybox), metallic look.
*/
enum ubyte defaultMetalnessDielectric = 25;
enum ubyte defaultMetalnessMetal = 255; ///ditto


/**
    Used by the `setDirty` calls to figure out which layers
    should be invalidated (there are 2 layers, Raw and PBR).
*/
enum UILayer
{
    /**
        Use the `UIElement` own flags to figure out which
        layers to invalidate.

        This is what you want most of the time, and it the
        default.
    */
    guessFromFlags,

    /**
        Invalidate only the Raw layer but not the PBR layer.
        This is useful for a rare `UIElement` which would
        draw to both the Raw and PBR layers, but only the
        Raw one is animated for performance reasons.
    */
    rawOnly,

    /**
       Internal Dplug usage.
       This is only useful for the very first setDirty call,
       to mark the whole UI dirty.
    */
    allLayers
}


/**
    Result of `onMouseClick`.
*/
enum Click
{
    /**
        Click was handled, consume the click event.
        No dragging was started.
        Widget gets keyboard focus (`isFocused`).
    */
    handled,

    /**
        Click was handled, consume the click event.
        No dragging was started.
        Do NOT get keyboard focus.
        Useful to select another widget on click, or exit a
        widget.
    */
    handledNoFocus,

    /**
        Click handled, consume the click event.
        Widget gets keyboard focus (`isFocused`).

        A drag operation was started which means several
        things:
         - This widget keeps the keyboard and mouse focus
           as long as the drag operation is active.
           Even if the mouse is not inside the widget
           anymore.
         - The plugin window keeps the active focus as long
           as the drag operation is active. Mouse events
           keep being received even if mouse gets outside
           the plugin window.
         - `onStartDrag` and `onStopDrag` get called.
         - `onMouseDrag` is called instead of `onMouseMove`.

        It is a good practice to NOT start another drag
        operation if one is already active (see Issue #822),
        typically it currently happens with another mouse
        button in the wild.

        Note: there is no `onMouseRelease` in Dplug. The way
        to catch the releasesi to start a drag, then catch
        `onStopDrag`.
    */
    startDrag,

    /**
        Click was not handled, pass the event around.
    */
    unhandled
}

/**
    The maximum length for an UIElement ID.
*/
enum maxUIElementIDLength = 63;

/**
    Is this a valid `UIElement` identifier?
    Returns: true if a valid UIlement unique identifier.
    This is mapped on HTML ids.
*/
static bool isValidElementID(const(char)[] identifier)
    pure nothrow @nogc @safe
{
    if (identifier.length == 0)
        return false;
    if (identifier.length > maxUIElementIDLength)
        return false;
    foreach (char ch; identifier)
    {
        // Note: Chrome does actually accept ID with spaces
        if (ch == 0)
            return false;
    }
    return true;
}

/**
    A `UIElement` has 8 `void*` user pointers (4 reserved
    for Dplug + 4 for vendors).
    The first two are used by `dplug:wren-support`.

    user[UIELEMENT_POINTERID_WREN_EXPORTED_CLASS]
        points to a cached Wren class of this UIElement.

    user[UIELEMENT_POINTERID_WREN_VM_GENERATION]
        is the Wren VM counter, is an `uint` not a pointer.
*/
enum UIELEMENT_POINTERID_WREN_EXPORTED_CLASS = 0;
enum UIELEMENT_POINTERID_WREN_VM_GENERATION  = 1; ///ditto

/**
    `UIElement` is the base class of the `dplug:gui` widget
    hierarchy. It is called a "widget" in the Dplug lore.

    MAYDO: a bunch of stuff in that class is intended
           specifically for the root element, there is
           perhaps a better design to find.
*/
class UIElement
{
    // Summary of user APIs in `UIElement`:
    //
    // 1. Creation/destruction API
    //      - this
    //      - ~this
    //
    // 2. Widget positioning API
    //      - position
    //
    // 3. Children API
    //      - context
    //      - parent
    //      - topLevelParent
    //      - child
    //      - addChild
    //      - removeChild
    //
    // 4. Invalidation API
    //      - setDirtyWhole
    //      - setDirty
    //
    // 5. Widget visibility API
    //      - isVisible
    //      - visibility
    //
    // 6. Widget Z-order API
    //      - zOrder
    //
    // 7. Widget identifiers API
    //      - id
    //      - hasId
    //      - getElementById
    //
    // 8. Layout callback
    //      - reflow
    //
    // 9. Status API
    //      - isMouseOver
    //      - isDragged
    //      - isFocused
    //      - drawsToPBR
    //      - drawsToRaw
    //      - isAnimated
    //      - isDrawAloneRaw
    //      - isDrawAlonePBR
    //
    // 10. Mouse Cursor API
    //      - cursorWhenDragged
    //      - setCursorWhenDragged
    //      - cursorWhenMouseOver
    //      - setCursorWhenMouseOver
    //
    // 11. User Pointers API
    //      - getUserPointer
    //      - setUserPointer
    //
    // 12. Contains callback
    //      - contains
    //
    // 13. Mouse Event callbacks
    //      - onMouseEnter
    //      - onMouseExit
    //      - onMouseClick
    //      - onMouseWheel
    //      - onMouseMove
    //
    // 14. Drag Events callbacks
    //      - onBeginDrag
    //      - onStopDrag
    //      - onMouseDrag
    //
    // 15. Keyboard Events callbacks
    //      - onFocusEnter
    //      - onFocusExit
    //      - onKeyDown
    //      - onKeyUp
    //
    // 16. Drawing callbacks.
    //      - onDrawRaw
    //      - onDrawPBR
    //
    // 17. Animation callback
    //      - onAnimate

public:
nothrow:
@nogc:

    //
    //  1. Creation/destruction API.
    //

    /**
        Create a `UIElement`.

        When creating a custom widget, this should be called
        with `super` as a first measure in order to have a
        `UIContext`.

        When created a widget has no position, it should be
        positionned in your gui.d `this()` or `reflow()`.

        Params:
            context = The global UI context of this UI.
            flags   = Flags as defined in `UIFlags`.
    */
    this(UIContext context, uint flags)
    {
        _context          = context;
        _flags            = flags;
        _localRectsBuf    = makeVec!box2i();
        _children         = makeVec!UIElement();
        _zOrderedChildren = makeVec!UIElement();
        _idStorage[0]     = '\0'; // defaults to no ID

        // Initially empty position
        assert(_position.empty());
    }

    /**
        Destroy a `UIElement`.
        Normally this happens naturally, since each widget
        owns its children.
    */
    ~this()
    {
        foreach(child; _children[])
            child.destroyFree();
    }


    //
    //  2. Widget positioning API.
    //

    /**
        Get widget position in the window (absolute).

        You can query this in `.reflow()` to position
        children of this widget.
    */
    final box2i position()
    {
        return _position;
    }

    /**
        Set widget position in the window (absolute).

        Params:
             p New widget position rectangle, sorted,
               rounded to nearest integer coordinates if
               needed.

        If the position changed:
           - call `.setDirtyWhole()` to redraw the affected
             underlying buffers.
           - call `.reflow` to position children.

        Warning:
             Most widget won't crash with:
             - empty position
             - position partially or 100% outside the window

        However, position outside the window will likely
        lead to bad rendering. (See: onDrawRaw TODO)
    */
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

            // New in Dplug v11: setting position now calls
            // reflow() if position has changed.
            reflow();

            // If you fail here, it's because your
            // custom widget changed its own position in
            // `.reflow`.
            // But, `_position` shouldn't be touched by
            // `.reflow()` calls.
            assert(p == _position);
        }
    }
    ///ditto
    final void position(box2f p)
    {
        int x1 = cast(int) round(p.min.x);
        int y1 = cast(int) round(p.min.y);
        int x2 = cast(int) round(p.max.x);
        int y2 = cast(int) round(p.max.y);
        box2i r = box2i(x1, y1, x2, y2);
        position = r;
    }    
    ///ditto
    final void position(Rect2i p)
    {
        position = box2i(p.left, p.top, p.right, p.bottom);
    }
    ///ditto
    final void position(Rect2 p)
    {
        int x1 = cast(int) round(p.left);
        int y1 = cast(int) round(p.top);
        int x2 = cast(int) round(p.right);
        int y2 = cast(int) round(p.bottom);
        box2i r = box2i(x1, y1, x2, y2);
        position = r;
    }


    //
    // 3. Children API
    //

    /**
        Get the UI context, which is an additional API for
        widgets to use (though quite a bit of methods are
        internals there).
    */
    final UIContext context()
    {
        return _context;
    }

    /**
        Get parent widget, if any.
        Returns: Parent element.
                 `null` if detached or root element.
    */
    final UIElement parent() pure nothrow @nogc
    {
        return _parent;
    }

    /**
        Get top-level parent, if any.
        Returns: Top-level parent.
                 `this` if detached or root element.
    */
    final UIElement topLevelParent() pure nothrow @nogc
    {
        if (_parent is null)
            return this;
        else
            return _parent.topLevelParent();
    }

    /**
        Returns: The nth  child of this `UIElement`.
    */
    final UIElement child(int n)
    {
        return _children[n];
    }

    /**
        Add a `UIElement` as child to another.

        Such a child MUST be created through `mallocNew`.
        Its ownership is given to is parent.
    */
    final void addChild(UIElement element)
    {
        element._parent = this;
        _children.pushBack(element);

        // Recompute visibility of that element.
        bool parentVisible = isVisible();
        element.recomputeVisibilityStatus(parentVisible);
    }

    /**
       Removes a child from its parent.
       Useful for creating dynamic UI's.

       Warning: For now, it's way better to create all the
       widgets in advance and use `.visibility` to make them
       coexist.

       FUTURE: there are restrictions and lots of races for
       where this is actually allowed. Find them.
    */
    final void removeChild(UIElement element)
    {
        int index = _children.indexOf(element);
        if(index >= 0)
        {
            // Dirty where the UIElement has been removed
            element.setDirtyWhole();

            _children.removeAndReplaceByLastElement(index);
        }
    }



    //
    // 4. Invalidation API.
    // Explanation: provokes all widget redraws.
    //

    /**
        Mark this element as "dirty" on its whole position.

        This leads to a repaint of this widget and all other
        widget parts in the neighbourhood.

        Params:
            layer = Which layers need to be redrawn.

        Important: While you _can_ call this from the audio
                   thread, it is much more efficient to mark
                   the widget dirty with an atomic and call
                   `.setDirty()/.setDirtyWhole()` in an
                   `.onAnimate()` callback.
    */
    void setDirtyWhole(UILayer layer =
        UILayer.guessFromFlags)
    {
        addDirtyRect(_position, layer);
    }

    /**
        Mark a sub-part of the element "dirty".

        This leads to a repaint of this widget's part, and
        all other widget parts in the neighbourhood.

        Params:
            rect  =  Position of the dirtied rectangle,
                     given in **local coordinates**.
            layer =  Which layers need to be redrawn.

        Warning: `rect` must be inside `.position()`, but
            is given in widget (local) coordinates.

        Important: While you _can_ call this from the audio
                   thread, it is much more efficient to mark
                   the widget dirty with an atomic and call
                   `.setDirty()/.setDirtyWhole()` in an
                   `.onAnimate()` callback.
    */
    void setDirty(box2i   rect,
                  UILayer layer = UILayer.guessFromFlags)
    {
        // BUG: it is actually problematic to allow this
        // from the audio thread, because the access to
        // _position isn't protected and it could create a
        // race in case of concurrent reflow(). Pushed
        // rectangles might be out of range, this is
        // workarounded in GUIGraphics currently
        /// for other reasons.
        box2i translatedRect = rect.translate(_position.min);
        assert(_position.contains(translatedRect));
        addDirtyRect(translatedRect, layer);
    }



    //
    // 5. Widget visibility API
    // Explanation: an invisible widget is not displayed
    //              nor considered for most events.
    // Widgets start their life being visible.
    // THIS SHALL NOT BE USED FROM THE AUDIO THREAD.
    //

    /**
        A widget is "visible" when it has a true visibility
        flag, and its parent is itself visible.

        Returns: Last computed visibility status.
    */
    final bool isVisible() pure const
    {
        return _visibilityStatus;
    }

    /**
        Get visibility flag of the widget.

        This is only the visibility of this widget.
        A widget might still be invisible, if one of its
        parent is not visible. To know that, use the
        `isVisible()` call.
    */
    final bool visibility() pure const
    {
        return _visibleFlag;
    }

    /**
        Change visibility flag of the widget. Show or hide
        all children of this `UIElement`, regardless of
        their position on screen, invalidating their
        graphics if need be (much like a position change).
    */
    final void visibility(bool visible)
    {
        if (_visibleFlag == visible)
        {
            // Nothing to do, this wouldn't change any
            // visibility status in sub-tree.
            return;
        }

        _visibleFlag = visible;

        // Get parent visibility status.
        bool parentVisibleStatus = true;
        if (parent)
            parentVisibleStatus = parent.isVisible();

        // Recompute own visibility status.
        recomputeVisibilityStatus(parentVisibleStatus);
    }


    //
    // 6. Widget Z-order API
    //


    /**
        Set/get widget Z-order (default = 0).

        However, keep in mind the Raw layer is always on top
        of anything PBR.

        Order of draw (lower is earlier):
            [ Raw widget with zOrder=10]
            [ Raw widget with zOrder=-4]
            [ PBR widget with zOrder=2]
            [ PBR widget with zOrder=0]

        The higher the Z-order, the later it is composited.
        In case of identical Z-order, the widget that comes
        after in the children tree is drawn after.

    */
    final int zOrder() pure const
    {
        return _zOrder;
    }
    ///ditto
    final void zOrder(int zOrder)
    {
        if (_zOrder != zOrder)
        {
            setDirtyWhole();
            _zOrder = zOrder;
        }
    }

    // TODO: how to depreciate that? Wren will stumble upon
    // every deprecated fields unfortunately.
    alias setZOrder = zOrder;



    //
    // 7. Widget identifiers API
    //

    /**
        Set widget ID.

        All UIElement may have a string as unique identifier
        like in HTML.

        This identifier is supposed to be unique. If it
        isn't, a search by ID will be Undefined Behaviour.

        Params:
            identifier A valid HTML-like identifier.
                   Can't contain spaces or null characters.
                   Must be below a maximum of 63 characters.
    */
    final void setId(const(char)[] identifier) pure
    {
        if (!isValidElementID(identifier))
        {
            // Note: assigning an invalid ID is a silent
            // error. The UIElement ends up with no ID.
            _idStorage[0] = '\0';
            return;
        }
        _idStorage[0..identifier.length] = identifier[0..$];
        _idStorage[identifier.length] = '\0';
    }
    ///ditto
    final void id(const(char)[] identifier)
    {
        setId(identifier);
    }

    /**
        Get widget ID.

        All UIElement may have a string as unique identifier
        like in HTML

        Returns: The widget identifier, or `""` if no ID.
                 The result is an interior slice, that is
                 invalidated if the ID is reassigned.
    */
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
    ///ditto
    final const(char)[] id() pure
    {
        return getId();
    }

    /**
       Has this widget an identifier?

       Returns: `true` if this `UIElement` has an ID.
    */
    final bool hasId() pure
    {
        return _idStorage[0] != '\0';
    }

    /**
         Search subtree for an UIElement with ID `id`.
         Undefined Behaviour if ID are not unique.
     */
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

    //
    // 8. Layout callback.
    //

    /**
        The `.reflow()` callback is called whenver the
        `.position` of a widget changes.

        You MUST NOT call `reflow()` yourself, to do that
        use `.position = someRect`.

        However but you can override it and if you want a
        resizeable UI you will have at least one `.reflow()`
        override in your `gui.d`.

        The role of this method is to update positions of
        children, hence you can implement any kind of
        descending layout.

        Inside this call, getting own position with
        `.position()` is encouraged.

        Pseudo-code:

            override void reflow()
            {
               box2i p = this.position();
               child[n].position = something(p)
            }

        Note: Widget positions are absolute. As such,
              children don't need to be inside position of
              their parent at all.

        See_also: `position`
    */
    void reflow()
    {
        // By default: do nothing, do not position children
    }


    //
    // 9. Status API.
    // Typically used to change the display of a widget.
    //

    /**
        Widget hovered by mouse?

        Between `onMouseEnter` and `onMouseExit`,
        `isMouseOver` will return `true`.
    */
    final bool isMouseOver() pure const
    {
        version(legacyMouseDrag)
        {}
        else
        {
            if (_context.mouseOver !is this)
            {
                // in newer mouse drag behaviour
                // the dragged item is always also mouseOver
                assert(_context.dragged !is this);
            }
        }

        return _context.mouseOver is this;
    }

    /**
        Widget dragged by mouse?

        Between `.onBeginDrag()` and `.onStopDrag()`,
        `isDragged` returns `true`.

    */
    final bool isDragged() pure const
    {
        version(legacyMouseDrag)
        {}
        else
        {
            if (_context.dragged is this)
                assert(isMouseOver());
        }

        return _context.dragged is this;
    }

    /**
        Widget has keyboard focused? (last clicked)
    */
    final bool isFocused() pure const
    {
        return _context.focused is this;
    }

    /**
        Widget draws on the PBR layer?
    */
    final bool drawsToPBR() pure const
    {
        return (_flags & flagPBR) != 0;
    }

    /**
        Widget draws on the Raw layer?
    */
    final bool drawsToRaw() pure const
    {
        return (_flags & flagRaw) != 0;
    }

    /**
        Is widget animated? (onAnimate called)
    */
    final bool isAnimated() pure const
    {
        return (_flags & flagAnimated) != 0;
    }

    /**
        Should widget be drawn alone in Raw layer?
    */
    final bool isDrawAloneRaw() pure const
    {
        return (_flags & flagDrawAloneRaw) != 0;
    }

    /**
        Should widget be drawn alone in PBR layer?
    */
    final bool isDrawAlonePBR() pure const
    {
        return (_flags & flagDrawAlonePBR) != 0;
    }


    //
    // 10. Mouse Cursor API
    // FUTURE: need redo/clarify this API.
    //

    ///
    MouseCursor cursorWhenDragged()
    {
        return _cursorWhenDragged;
    }

    ///
    void setCursorWhenDragged(MouseCursor mouseCursor)
    {
        _cursorWhenDragged = mouseCursor;
    }

    ///
    MouseCursor cursorWhenMouseOver()
    {
        return _cursorWhenMouseOver;
    }

    ///
    void setCursorWhenMouseOver(MouseCursor mouseCursor)
    {
        _cursorWhenMouseOver = mouseCursor;
    }


    //
    // 11. User Pointers API
    //

    /**
        Set/Get a user pointer.
        This allow `dplug:gui` extensions.
    */
    final void* getUserPointer(int pointerID)
    {
        return _userPointers[pointerID];
    }
    ///ditto
    final void setUserPointer(int pointerID, void* user)
    {
        _userPointers[pointerID] = user;
    }

    //
    // 12. Contains callback.
    //

    /**
        Check if given point is considered in the widget,
        for clicks, mouse moves, etc.
        This function is meant to be overridden.

        It is meant for widgets that aren't rectangles, and
        is relatively rare in practice.

        It can be useful to disambiguate clicks and
        mouse-over between widgets that would otherwise
        overlap (you can also use Z-order to solve that).

        Params:
            x = X position in local coordinates.
            x = Y position in local coordinates.

        Returns: `true` if point `(x, y)` is inside widget.

        Note:
            This is unusual, but it seems a widget could be
            clickable beyond its `.position()`. It won't be
            able to draw there, though.
            So it's advised to not exceed `_position`.
    */
    bool contains(int x, int y)
    {
        // FUTURE: should be onContains to disambiguate

        // By default: true if (x, y) inside _position.
        return (x < cast(uint)(_position.width ) )
            && (y < cast(uint)(_position.height) );
    }


    //
    // 13. Mouse Events callbacks.
    // All of the following function can be (optionally)
    // overridden.
    //

    /**
        Called when mouse enter or exits a widget.
        This function is meant to be overridden.

        Typically used to call `.setDirtyWhole` in order to
        display/hide a mouse highlight if clickable.
    */
    void onMouseEnter()
    {
    }
    ///ditto
    void onMouseExit()
    {
    }

    /**
        `.onMouseClick()` is called for every new click.

        This function is meant to be overridden.

        Params:
            x = Mouse X position in local coordinates.
            y = Mouse Y position in local coordinates.
            button = Button that was just clicked.
            isDoubleClick = `true` if double-click.
            mstate = General mouse state.

        Returns: What do with the click event. This is the
        only place where you can start a drag operation.

        Warning: Called Whether or not you are in a dragging
            operation! For this reason, check your widgets
            with several mouse buttons pressed at once.

        See_also: `Click`
    */
    Click onMouseClick(int x, int y, int button,
                       bool isDoubleClick,
                       MouseState mstate)
    {
        // By default, do nothing.
        return Click.unhandled;
    }

    /**
        Mouse wheel was turned.
        This function is meant to be overridden.

        Params:
            x = Mouse X position in local coordinates.
            y = Mouse Y position in local coordinates.
            wheelDeltaX = Amount of mouse X wheel (rare).
            wheelDeltaY = Amount of mouse Y wheel.
            mstate = General mouse state.

        Returns: `true` if the wheel event was handlded,
            else propagated.
    */
    bool onMouseWheel(int x, int y,
                      int wheelDeltaX, int wheelDeltaY,
                      MouseState mstate)
    {
        // By default, do nothing.
        return false;
    }

    /**
        Called when the mouse moves over this widget area.
        This function is meant to be overridden.

        Params:
            x = Mouse X position in local coordinates.
            y = Mouse Y position in local coordinates.
            dx = Mouse X relative displacement.
            dy = Mouse Y relative displacement.
            mstate = General mouse state.

        Warning: If `legacyMouseDrag` version identifier is
            used, this will be called even during a drag.
            Else this cannot happen in a drag.
    */
    void onMouseMove(int x, int y,
                     int dx, int dy,
                     MouseState mstate)
    {
        // By default: do nothing
    }


    //
    // 14. Drag Events callbacks.
    // All of the following function can be (optionally)
    // overridden.
    //
    // A drag operation is started by a click, and last as
    // long as no mouse buttons is released.
    // There cannot be concurrent drags, but right now
    // `onMouseClick` will still be called during a drag.
    //

    /**
        Called when a drag operation starts or ends.
        This function is meant to be overridden.

        Typically:
          - Call `beginParamEdit` from `.onBeginDrag()` or
            better, `onMouseClick` (more context in
            `.onMouseClick()`).

          - Call `endParamEdit()` from `.onStopDrag()`.
          - Call `.setDirtyWhole()` to account from drag
            state being seen.
          - `.onStopDrag()` is only way to catch mouse
            button release events.
          - etc...
    */
    void onBeginDrag()
    {
        // Do nothing.
        // Often, onMouseClick is the right place for what
        // you may do here.
    }
    ///ditto
    void onStopDrag()
    {
        // Do nothing.
        // Often the place to do `.endParamEdit`.
    }

    /**
        Called when the mouse moves while dragging this
        widget.

        Typically used for knobs and sliders widgets.
        Mouse movement will be the place to call
        `param.setFromGUI()`.

        Params:
            x = Mouse X position in local coordinates.
            y = Mouse Y position in local coordinates.
            dx = Mouse X relative displacement.
            dy = Mouse Y relative displacement.
            mstate = General mouse state.
    */
    void onMouseDrag(int x, int y, int dx, int dy,
        MouseState mstate)
    {
    }


    //
    // 15. Keyboard Events Callback
    //

    /**
        Called when this widget is clicked and get the
         "focus" (ie. meaning the keyboard focus).
         This function is meant to be overridden.
    */
    void onFocusEnter()
    {
    }

    /**
        This widget lost the keyboard focus.
        This function is meant to be overridden.

        Typically used to close a pop-up widget.

        Called when keyboard focus is lost (typically
        because another widget was clicked, or mouse clicked
        outside the window).
    */
    void onFocusExit()
    {
    }

    /**
        Called when a key is pressed/released.
        Functiosn meant to be overridden.

        Key events bubbles towards the top until being
        processed, eventually the DAW will get it.

        Returns: `true` if event handled.
    */
    bool onKeyDown(Key key)
    {
        return false;
    }
    ///ditto
    bool onKeyUp(Key key)
    {
        return false;
    }


protected:

    //
    // 16. Drawing callbacks.
    //

    /**
        Raw layer draw method.
        This function is meant to be overridden.

        `UIElement` are drawn on the Raw layer by increasing
        z-order, or lexical order if lack thereof.

        The widgets who have non-overlapping positions are
        drawn in parallel if their flags allow it.

        One MUST NOT draw outsides the given `dirtyRects`.
        This allows fast and fine-grained updates.
        A `UIElement` that doesn't respect dirtyRects WILL
        have bad rendering with surrounding updates.

        Params:
            rawMap     = Raw RGBA pixels (input and output),
                         cropped to widget position.
                         Blending allowed.
            dirtyRects = Where to draw in this rawMap.

        TODO: Not sure if dirtyRects are widget-space or
          cropped-space.
    */
    void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        // By default: invisible
    }

    /**
        PBR layer draw method.
        This function is meant to be overridden.

        `UIElement` are drawn on the Raw layer by increasing
        z-order, or lexical order if lack thereof.
        However, all PBR stuff is composited and computed
        before Raw is drawn on top of that (cached) result.

        The widgets who have non-overlapping positions are
        drawn in parallel if their flags allow it.

        One MUST NOT draw outsides the given `dirtyRects`.
        This allows fast and fine-grained updates.
        A `UIElement` that doesn't respect dirtyRects WILL
        have bad rendering with surrounding updates.

        Params:
            diffuse     = Contain 4 channels:
                          Red, Green, Blue, Emissive.
            depth       = One channel of 16-bit depth.
            material    = Contain 3 channels:
                          Roughness, Metalness, Specular, and
                          a unused 4th channel.
            dirtyRects = Where to draw in these maps.

        TODO: Not sure if dirtyRects are widget-space or
          cropped-space.
    */
    void onDrawPBR(ImageRef!RGBA diffuse,
                   ImageRef!L16  depth,
                   ImageRef!RGBA material,
                   box2i[] dirtyRects)
    {
        // By default: checkerboard pattern
        RGBA darkGrey    = RGBA(100, 100, 100, 0);
        RGBA lighterGrey = RGBA(150, 150, 150, 0);

        // This is a typical draw function:
        // for each r in dirtyRects
        //   crop inputs by r
        //   show something in it
        // You don't have to fill everything though.
        foreach(r; dirtyRects)
        {
            for (int y = r.min.y; y < r.max.y; ++y)
            {
                L16[] depthScan     = depth.scanline(y);
                RGBA[] diffuseScan  = diffuse.scanline(y);
                RGBA[] materialScan = material.scanline(y);
                for (int x = r.min.x; x < r.max.x; ++x)
                {
                    RGBA col = ((x>>3)^(y>>3))&1 ? darkGrey
                                              : lighterGrey;
                    diffuseScan.ptr[x] = col;
                    depthScan.ptr[x] = L16(defaultDepth);
                    RGBA m = RGBA(defaultRoughness,
                                 defaultMetalnessDielectric,
                                 defaultSpecular,
                                 255);
                    materialScan.ptr[x] = m;
                }
            }
        }
    }

    //
    // 17. Animation callback.
    //

    /**
        Called periodically for every `UIElement` that has
        `flagAnimated`.
        Override this to create animations.

        Using `.setDirty()` there allows to redraw a widget
        continuously (like a meter or an animated object).
        This is typically used to poll DSP state from the
        UI.

        Warning: Summing `dt` will not lead to a time that
                 increase like `time`.
                 `time` may go backwards if the window was
                 reopen after a while being closed (???)
                 `time` is guaranteed to increase as fast as
                 system time but is not synced to audio
                 time.

        Note: `.onAnimate` is called even if the widget is
              not visible! (use `.isVisible()` to know).
    */
    void onAnimate(double dt, double time)
    {
    }



public:

    //
    // Private Dplug API, used by graphics.d mostly.
    // (internal)
    // Normally you can ignore all of this as a user.
    //

    /*
        This method is called for each item in the drawlist
        that was visible and has a dirty Raw layer.
        This is called after compositing, starting from the
        buffer output by the Compositor.
    */
    final void renderRaw(ImageRef!RGBA rawMap,
                         in box2i[] areasToUpdate)
    {
        // We only consider the part of _position that is
        // actually in the surface.
        // Indeed, `_position` should not be outside the
        // bounds of a window (most widgets will support
        // that), but most widgets will render that badly.
        box2i surPos = box2i(0, 0, rawMap.w, rawMap.h);
        box2i vPos = _position.intersection(surPos);

        // Widget inside the window?
        if (vPos.empty())
            return;

        // Create a list of dirty rectangles for this widget
        // in local coordinates, for the Raw layer.
        _localRectsBuf.clearContents();
        foreach(rect; areasToUpdate)
        {
            box2i inter = rect.intersection(vPos);
            if (!inter.empty)
            {
                box2i tr = inter.translate(-vPos.min);
                _localRectsBuf.pushBack(tr);
            }
        }

        // Any dirty part in widget?
        if (_localRectsBuf.length == 0)
            return;

        // Crop output image to valid part of _position.
        // Drawing outside of _position is thus not doable.
        ImageRef!RGBA rawCrop = rawMap.cropImageRef(vPos);
        assert(rawCrop.w != 0 && rawCrop.h != 0);

        // Call repaint function
        onDrawRaw(rawCrop, _localRectsBuf[]);
    }

    /*
        This method is called for each item in the drawlist
        that is visible and has a dirty PBR layer.
    */
    final void renderPBR(ImageRef!RGBA diffuse,
                         ImageRef!L16  depth,
                         ImageRef!RGBA material,
                         in box2i[] areasToUpdate)
    {
        int W = diffuse.w;
        int H = diffuse.h;

        // We only consider the part of _position that is
        // actually in the surface.
        // Indeed, `_position` should not be outside the
        // bounds of a window (most widgets will support
        // that), but most widgets will render that badly.
        box2i surPos = box2i(0, 0, W, H);
        box2i vPos = _position.intersection(surPos);

        // Widget inside the window?
        if (vPos.empty())
            return;

        // Create a list of dirty rectangles for this widget
        // in local coordinates, for the PBR layer.
        _localRectsBuf.clearContents();
        foreach(rect; areasToUpdate)
        {
            box2i inter = rect.intersection(vPos);
            if (!inter.empty)
            {
                box2i tr = inter.translate(-vPos.min);
                _localRectsBuf.pushBack(tr);
            }
        }

        // Any dirty part in widget?
        if (_localRectsBuf.length == 0)
            return;

        // Crop output image to valid part of _position.
        // Drawing outside of _position is thus not doable.
        ImageRef!RGBA cDiffuse = diffuse.cropImageRef(vPos);
        ImageRef!L16  cDepth   =   depth.cropImageRef(vPos);
        ImageRef!RGBA cMaterial=material.cropImageRef(vPos);

        assert(cDiffuse.w != 0 && cDiffuse.h != 0);

        // Call repaint function
        onDrawPBR(cDiffuse, cDepth, cMaterial,
            _localRectsBuf[]);
    }

    // to be called at top-level when the mouse clicked
    final bool mouseClick(int x, int y, int button,
        bool isDoubleClick, MouseState mstate)
    {
        recomputeZOrderedChildren();

        // Test children that are displayed above this
        // element first
        foreach(child; _zOrderedChildren[])
        {
            if (child.zOrder >= zOrder)
                if (child.mouseClick(x, y, button,
                    isDoubleClick, mstate))
                    return true;
        }

        // Test for collision with this element
        int px = _position.min.x;
        int py = _position.min.y;
        if (_visibilityStatus && contains(x - px, y - py))
        {
            Click click = onMouseClick(x - px,
                y - py, button, isDoubleClick, mstate);

            final switch(click)
            {
                case Click.handled:
                    _context.setFocused(this);
                    return true;

                case Click.handledNoFocus:
                    return true;

                case Click.startDrag:
                    _context.beginDragging(this);
                    goto case Click.handled;

                case Click.unhandled:
                    return false;
            }
        }

        foreach(child; _zOrderedChildren[])
        {
            if (child.zOrder < zOrder)
                if (child.mouseClick(x, y, button,
                    isDoubleClick, mstate))
                    return true;
        }

        return false;
    }

    // to be called at top-level when the mouse is released
    final void mouseRelease(int x, int y,
                            int button, MouseState mstate)
    {
        version(legacyMouseDrag)
        {}
        else
        {
            bool wasDragging = (_context.dragged !is null);
        }

        _context.stopDragging();

        version(legacyMouseDrag)
        {}
        else
        {
            // Enter widget below mouse if a dragged
            // operation was stopped.
            if (wasDragging)
            {
                bool ok = mouseMove(x, y, 0, 0, mstate,
                                    false);
                if (!ok)
                    _context.setMouseOver(null);
            }
        }
    }

    // to be called at top-level when the mouse wheeled
    final bool mouseWheel(int x, int y,
                          int wheelDeltaX, int wheelDeltaY,
                          MouseState mstate)
    {
        recomputeZOrderedChildren();

        // Test children that are displayed above this
        // element first
        foreach(child; _zOrderedChildren[])
        {
            if (child.zOrder >= zOrder)
                if (child.mouseWheel(x, y, wheelDeltaX,
                    wheelDeltaY, mstate))
                    return true;
        }

        int dx = x - _position.min.x;
        int dy = y - _position.min.y;

        // cannot be mouse-wheeled if invisible
        bool canBeMouseWheeled = _visibilityStatus;
        if (canBeMouseWheeled && contains(dx, dy))
        {
            if (onMouseWheel(dx, dy, wheelDeltaX,
                wheelDeltaY, mstate))
                return true;
        }

        // Test children that are displayed below this
        // element last
        foreach(child; _zOrderedChildren[])
        {
            if (child.zOrder < zOrder)
                if (child.mouseWheel(x, y, wheelDeltaX,
                    wheelDeltaY, mstate))
                    return true;
        }

        return false;
    }

    // To be called when the mouse moved
    final bool mouseMove(int x, int y, int dx, int dy,
        MouseState mstate, bool alreadyFoundMouseOver)
    {
        recomputeZOrderedChildren();

        // "found" is whether we have found the hovered
        // thing (mouseOver)
        bool found = alreadyFoundMouseOver;

        // Test children that are displayed above this
        // element first
        foreach(child; _zOrderedChildren[])
        {
            if (child.zOrder >= zOrder)
            {
                bool here = child.mouseMove(x, y, dx, dy,
                    mstate, found);
                found = found || here;
            }
        }

        if (isDragged())
        {
            // EDIT MODE
            // With version `Dplug_RightClickMoveWidgets`,
            // dragging with the right mouse button move
            // elements around.
            // Dragging with shift  + right button resize
            // elements around.
            //
            // Additionally, if CTRL is pressed, the
            // increments are only -1 or +1 pixel.
            //
            // You can see the _position rectangle thanks to
            // `debugLog`.
            bool draggingUsed = false;
            version(Dplug_RightClickMoveWidgets)
            {
                if (mstate.rightButtonDown
                    && mstate.shiftPressed)
                {
                    if (mstate.ctrlPressed)
                    {
                        if (dx < -1) dx = -1;
                        if (dx >  1) dx =  1;
                        if (dy < -1) dy = -1;
                        if (dy >  1) dy =  1;
                    }
                    int nx = _position.min.x;
                    int ny = _position.min.y;
                    int w = _position.width + dx;
                    int h = _position.height + dy;
                    if (w < 5) w = 5;
                    if (h < 5) h = 5;
                    position = box2i(nx, ny, nx+w, ny+h);
                    draggingUsed = true;
                }
                else if (mstate.rightButtonDown)
                {
                    if (mstate.ctrlPressed)
                    {
                        if (dx < -1) dx = -1;
                        if (dx >  1) dx =  1;
                        if (dy < -1) dy = -1;
                        if (dy >  1) dy =  1;
                    }
                    int nx = _position.min.x + dx;
                    int ny = _position.min.y + dy;
                    if (nx < 0) nx = 0;
                    if (ny < 0) ny = 0;
                    position = box2i(nx, ny,
                                     nx + position.width,
                                     ny + position.height);
                    draggingUsed = true;
                }

                if (draggingUsed)
                {
                    char[128] buf;
                    snprintf(buf.ptr, 128,
                        "rectangle(%d, %d, %d, %d)\n",
                        _position.min.x, _position.min.y,
                        _position.width, _position.height);
                    debugLog(buf.ptr);
                }
            }

            if (!draggingUsed)
                onMouseDrag(x - _position.min.x,
                            y - _position.min.y,
                            dx, dy, mstate);
        }

        // Can't be mouse over if not visible.
        bool canBeMouseOver = _visibilityStatus;

        version(legacyMouseDrag)
        {}
        else
        {
            // If dragged, already received `onMouseDrag`.
            // if something else dragged, cannot be hovered.
            if (_context.dragged !is null)
                canBeMouseOver = false;
        }

        // FUTURE: something more fine-grained?
        if (canBeMouseOver && contains(x - _position.min.x,
                                       y - _position.min.y))
        {
            // Get the mouse-over crown if not taken
            if (!found)
            {
                found = true;
                _context.setMouseOver(this);

                version(legacyMouseDrag)
                {}
                else
                {
                    onMouseMove(x - _position.min.x,
                                y - _position.min.y,
                                dx, dy, mstate);
                }
            }

            version(legacyMouseDrag)
            {
                onMouseMove(x - _position.min.x,
                            y - _position.min.y,
                            dx, dy, mstate);
            }
        }

        // Test children that are displayed below this
        foreach(child; _zOrderedChildren[])
        {
            if (child.zOrder < zOrder)
            {
                bool hit;
                hit = child.mouseMove(x, y, dx, dy, mstate,
                                      found);
                found = found || hit;
            }
        }
        return found;
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
    // TODO why this isn't final?
    void animate(double dt, double time)
    {
        if (isAnimated)
            onAnimate(dt, time);

        // For some rare widgets, it is important that
        // children are animated
        // _after_ their parent.
        foreach(child; _children[])
            child.animate(dt, time);
    }

    // Appends the Elements that should be drawn, in order.
    // You should empty it before calling this function.
    // Everything visible get into the draw list, but that
    // doesn't mean they will get drawn if they don't
    // overlap with a dirty area.
    final void getDrawLists(ref Vec!UIElement listRaw,
                            ref Vec!UIElement listPBR)
    {
        if (_visibilityStatus)
        {
            if (drawsToRaw())
                listRaw.pushBack(this);

            if (drawsToPBR())
                listPBR.pushBack(this);

            // Note: if one widget is not visible, the whole
            // sub-tree can be ignored for drawing.
            // This is because invisibility is inherited
            // without recourse.
            foreach(child; _children[])
                child.getDrawLists(listRaw, listPBR);
        }
    }

    // Parent element.
    // Following this chain gets to the root element.
    UIElement _parent = null;

    // Position is the graphical extent of the element, or
    // something larger.
    // An `UIElement` is not allowed though to draw further
    // than its _position. For efficiency it's best to keep
    // `_position` as small as feasible.
    // This is an absolute "world" positioning data, that
    // doesn't depend on the parent's position.
    box2i _position;

    // The list of children UI elements.
    Vec!UIElement _children;

    // Flags, for now immutable
    immutable(uint) _flags;

    // Higher z-order = above other `UIElement`.
    // By default, every `UIElement` have the same z-order.
    // Because the sort is stable, tree traversal order is
    // the default order (depth first).
    // The children added last with `addChild` is considered
    // above its siblings if you don't have legacyZOrder.
    int _zOrder = 0;

private:

    // Reference to owning context.
    UIContext _context;

    // <visibility privates>

    // If _visibleFlag is false, neither the Element nor its
    // children are drawn.
    bool _visibleFlag = true;

    // Final visibility value, cached in order to set
    // rectangles dirty.
    // It is always up to date across the whole UI tree.
    bool _visibilityStatus = true;

    void recomputeVisibilityStatus(bool parentStatus)
    {
        bool newStatus = _visibleFlag && parentStatus;

        // has it changed in any way?
        if (newStatus != _visibilityStatus)
        {
            _visibilityStatus = newStatus;

            // Dirty the widget position
            setDirtyWhole();

            // Inform children of the new parent status
            foreach(child; _children[])
                child.recomputeVisibilityStatus(newStatus);
        }
    }

    // </visibility privates>

    // Dirty rectangles buffer, cropped to _position.
    // Technically would only need that as a temporary
    // array in TLS, but well.
    Vec!box2i _localRectsBuf;

    // Sorted children.
    Vec!UIElement _zOrderedChildren;

    // Cursor to display when widget is being dragged
    MouseCursor _cursorWhenDragged = MouseCursor.pointer;

    // Cursor to display when widget is mouseover
    MouseCursor _cursorWhenMouseOver = MouseCursor.pointer;

    // Identifier storage.
    char[maxUIElementIDLength+1] _idStorage;

    // Warning: if you store objects here, keep in mind
    // they won't get destroyed automatically.
    // 4 user pointer in case you'd like to store things in
    // `UIElement` as a Dplug extension.
    // id 0..1 are reserved for Wren support.
    // id 2..3 are reserved for future Dplug extensions.
    // id 4..7 are for vendor-specific extensions.
    void*[8] _userPointers; // User pointers

    // Sort children in ascending z-order
    // Input: unsorted _children
    // Output: sorted _zOrderedChildren
    // This is not thread-safe.
    // Only one widget in the same UI can sort its children
    // at once, since it uses
    // a UIContext buffer to do so.
    final void recomputeZOrderedChildren()
    {
        // Get a z-ordered list of childrens
        _zOrderedChildren.clearContents();

        version(legacyZOrder)
        {
            // See: Dplug Issue #652
            foreach(child; _children[])
                _zOrderedChildren.pushBack(child);
        }
        else
        {
            // Adding children in reverse, since children
            // added last are considered having a higher
            // Z-order.
            foreach_reverse(child; _children[])
                _zOrderedChildren.pushBack(child);
        }

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
                    // Note: even if one UIElement draws to
                    // both Raw and PBR layers, we are not
                    // adding this rect in `dirtyListRaw`
                    // since the Raw layer is automatically
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
                // This will lead the Raw layer to be
                // invalidated too
                _context.dirtyListPBR.addRect(rect);
                break;
        }
    }
}

version(legacyMouseOver)
{
    // legacyMouseOver was removed in Dplug v13.
    // Please see Release Notes.
    static assert(false);
}