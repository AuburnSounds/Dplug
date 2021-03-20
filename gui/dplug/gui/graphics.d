/**
* A GUIGraphics is the interface between a plugin client and a IWindow.
*
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.graphics;

import std.math;
import std.algorithm.comparison;
import std.algorithm.sorting;
import std.algorithm.mutation;

import inteli.emmintrin;

import dplug.core.math;
import dplug.core.thread;

import dplug.client.client;
import dplug.client.graphics;
import dplug.client.daw;

import dplug.window.window;

import dplug.graphics.mipmap;

import dplug.gui.boxlist;
import dplug.gui.context;
import dplug.gui.element;
import dplug.gui.compositor;
import dplug.gui.legacypbr;
import dplug.gui.sizeconstraints;

/// In the whole package:
/// The diffuse maps contains:
///   RGBA = red/green/blue/emissiveness
/// The depth maps contains depth (0 being lowest, 65535 highest)
/// The material map contains:
///   RGBA = roughness / metalness / specular / unused

alias RMSP = RGBA; // reminder

// Uncomment to benchmark compositing and devise optimizations.
//debug = benchmarkGraphics;

debug(benchmarkGraphics)
{
    import core.sys.windows.windows;
    extern(Windows) BOOL QueryThreadCycleTime(HANDLE   ThreadHandle, PULONG64 CycleTime) nothrow @nogc;
    enum bool preciseMeasurements = false;
}

// A GUIGraphics is the interface between a plugin client and a IWindow.
// It is also an UIElement and the root element of the plugin UI hierarchy.
// You have to derive it to have a GUI.
// It dispatches window events to the GUI hierarchy.
class GUIGraphics : UIElement, IGraphics
{
nothrow:
@nogc:

    // Max size of tiles when doing the expensive PBR compositing step.
    // Difficult trade-off: we wanted the medium size knob to be only one tile.
    // This avoid launching threads for the PBR compositor in this case.
    enum PBR_TILE_MAX_WIDTH = 128;
    enum PBR_TILE_MAX_HEIGHT = 128;

    this(SizeConstraints sizeConstraints, UIFlags flags)
    {
        _sizeConstraints = sizeConstraints;

        _uiContext = mallocNew!UIContext();
        super(_uiContext, flags);

        _windowListener = mallocNew!WindowListener(this);

        _window = null;

        // Find what size the UI should at first opening.
        _sizeConstraints.suggestDefaultSize(&_currentUserWidth, &_currentUserHeight);
        _currentLogicalWidth = _currentUserWidth;
        _currentLogicalHeight = _currentUserHeight;

        int numThreads = 0; // auto
        int maxThreads = 2;
        _threadPool = mallocNew!ThreadPool(numThreads, maxThreads);

        // Build the compositor
        {
            CompositorCreationContext compositorContext;
            compositorContext.threadPool = _threadPool;
            _compositor = buildCompositor(&compositorContext);
        }

        _rectsToUpdateDisjointedRaw = makeVec!box2i;
        _rectsToUpdateDisjointedPBR = makeVec!box2i;
        _rectsTemp = makeVec!box2i;

        _updateRectScratch[0] = makeVec!box2i;
        _updateRectScratch[1] = makeVec!box2i;

        _rectsToComposite = makeVec!box2i;
        _rectsToCompositeDisjointed = makeVec!box2i;
        _rectsToCompositeDisjointedTiled = makeVec!box2i;

        _rectsToDisplay = makeVec!box2i;
        _rectsToDisplayDisjointed = makeVec!box2i;

        _rectsToResize = makeVec!box2i;
        _rectsToResizeDisjointed = makeVec!box2i;

        _elemsToDrawRaw = makeVec!UIElement;
        _elemsToDrawPBR = makeVec!UIElement;

        debug(benchmarkGraphics)
        {
            _compositingWatch = mallocNew!StopWatch(this, "Compositing = ");
            _drawWatch = mallocNew!StopWatch(this, "Draw PBR = ");
            _mipmapWatch = mallocNew!StopWatch(this, "Mipmap = ");
            _copyWatch = mallocNew!StopWatch(this, "Copy to Raw = ");
            _rawWatch = mallocNew!StopWatch(this, "Draw Raw = ");
            _reorderWatch = mallocNew!StopWatch(this, "Reorder = ");
        }

        _diffuseMap = mallocNew!(Mipmap!RGBA)();
        _materialMap = mallocNew!(Mipmap!RGBA)();
        _depthMap = mallocNew!(Mipmap!L16)();
    }

    // Don't like the default rendering? Override this function and make another compositor.
    ICompositor buildCompositor(CompositorCreationContext* context)
    {        
        return mallocNew!PBRCompositor(context);
    }

    final ICompositor compositor()
    {
        return _compositor;
    }

    ~this()
    {
        closeUI();
        _uiContext.destroyFree();

        _threadPool.destroyFree();

        _compositor.destroyFree();
        _diffuseMap.destroyFree();
        _materialMap.destroyFree();
        _depthMap.destroyFree();

        _windowListener.destroyFree();
        alignedFree(_compositedBuffer, 16);
        alignedFree(_renderedBuffer, 16);
        alignedFree(_resizedBuffer, 16);
    }

    // Graphics implementation

    override void* openUI(void* parentInfo, 
                          void* controlInfo, 
                          DAW daw, 
                          GraphicsBackend backend)
    {
        WindowBackend wbackend = void;
        final switch(backend)
        {
            case GraphicsBackend.autodetect: wbackend = WindowBackend.autodetect; break;
            case GraphicsBackend.win32: wbackend = WindowBackend.win32; break;
            case GraphicsBackend.cocoa: wbackend = WindowBackend.cocoa; break;
            case GraphicsBackend.carbon: wbackend = WindowBackend.carbon; break;
            case GraphicsBackend.x11: wbackend = WindowBackend.x11; break;
        }

        position = box2i(0, 0, _currentUserWidth, _currentUserHeight);

        // Sets the whole UI dirty.
        // This needs to be done _before_ window creation, else there could be a race
        // displaying partial updates to the UI.
        setDirtyWhole(UILayer.allLayers);

        // We create this window each time.
        _window = createWindow(WindowUsage.plugin, parentInfo, controlInfo, _windowListener, wbackend, _currentLogicalWidth, _currentLogicalHeight);

        return _window.systemHandle();
    }

    override void closeUI()
    {
        // Destroy window.
        if (_window !is null)
        {
            _window.destroyFree();
            _window = null;
        }
    }

    override void getGUISize(int* widthLogicalPixels, int* heightLogicalPixels)
    {
        *widthLogicalPixels = _currentLogicalWidth;
        *heightLogicalPixels = _currentLogicalHeight;
    }

    // This class is only here to avoid name conflicts between
    // UIElement and IWindowListener methods :|
    // Explicit outer to avoid emplace crashing
    static class WindowListener : IWindowListener
    {
    nothrow:
    @nogc:
        GUIGraphics outer;

        this(GUIGraphics outer)
        {
            this.outer = outer;
        }

        override bool onMouseClick(int x, int y, MouseButton mb, bool isDoubleClick, MouseState mstate)
        {
            x -= outer._userArea.min.x;
            y -= outer._userArea.min.y;
            bool hitSomething = outer.mouseClick(x, y, mb, isDoubleClick, mstate);
            if (!hitSomething)
            {
                // Nothing was clicked, nothing is focused anymore
                outer._uiContext.setFocused(null);
            }
            return hitSomething;
        }

        override bool onMouseRelease(int x, int y, MouseButton mb, MouseState mstate)
        {
            x -= outer._userArea.min.x;
            y -= outer._userArea.min.y;
            outer.mouseRelease(x, y, mb, mstate);
            return true;
        }

        override bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate)
        {
            x -= outer._userArea.min.x;
            y -= outer._userArea.min.y;
            return outer.mouseWheel(x, y, wheelDeltaX, wheelDeltaY, mstate);
        }

        override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
        {
            x -= outer._userArea.min.x;
            y -= outer._userArea.min.y;
            version(legacyMouseOver)
            {
                outer.mouseMove(x, y, dx, dy, mstate);
            }
            else
            {
                bool hitSomething = outer.mouseMove(x, y, dx, dy, mstate, false);
                if (!hitSomething)
                {
                    // Nothing was mouse-over'ed, nothing is `isMouseOver()` anymore
                    outer._uiContext.setMouseOver(null);
                }
            }
        }

        override void recomputeDirtyAreas()
        {
            return outer.recomputeDirtyAreas();
        }

        override bool onKeyDown(Key key)
        {
            // Sends the event to the last clicked element first
            if (outer._uiContext.focused !is null)
                if (outer._uiContext.focused.onKeyDown(key))
                    return true;

            // else to all Elements
            return outer.keyDown(key);
        }

        override bool onKeyUp(Key key)
        {
            // Sends the event to the last clicked element first
            if (outer._uiContext.focused !is null)
                if (outer._uiContext.focused.onKeyUp(key))
                    return true;
            // else to all Elements
            return outer.keyUp(key);
        }

        /// Returns areas affected by updates.
        override box2i getDirtyRectangle() nothrow @nogc
        {
            return outer._rectsToResize[].boundingBox();
        }

        override ImageRef!RGBA onResized(int width, int height)
        {
            return outer.doResize(width, height);
        }

        override void onDraw(WindowPixelFormat pf) nothrow @nogc
        {
            return outer.doDraw(pf);
        }

        override void onMouseCaptureCancelled()
        {
            // Stop an eventual drag operation
            outer._uiContext.stopDragging();
        }

        override void onAnimate(double dt, double time)
        {
            outer.animate(dt, time);
        }

        override MouseCursor getMouseCursor()
        {
            return outer._uiContext.getCurrentMouseCursor();
        }
    }

    /// Tune this to tune the trade-off between light quality and speed.
    /// The default value was tuned by hand on very shiny light sources.
    /// Too high and processing becomes more expensive.
    /// Too little and the ligth decay doesn't feel natural.
    void setUpdateMargin(int margin = 20) nothrow @nogc
    {
        _updateMargin = margin;
    }

protected:

    ICompositor _compositor;

    UIContext _uiContext;

    WindowListener _windowListener;

    // An interface to the underlying window
    IWindow _window;

    // Task pool for multi-threaded image work
    ThreadPool _threadPool;

    // Size constraints of this UI.
    // Currently can only be a fixed size.
    SizeConstraints _sizeConstraints;

    // The _external_ size in pixels of the plugin interface.
    // This is the size seen by the host/window.
    int _currentLogicalWidth = 0;
    int _currentLogicalHeight = 0;

    // The _internal_ size in pixels of our UI.
    // This is not the same as the size seen by the window ("logical").
    int _currentUserWidth = 0;
    int _currentUserHeight = 0;

    /// the area in logical area where the user area is drawn.
    box2i _userArea; 
    bool _invalidateResizedBuffer; // if true, the whole _userArea must be updated on next draw.
    bool _redrawBlackBorders;      // if true, redraw black borders before resize step.

    // Diffuse color values for the whole UI.
    Mipmap!RGBA _diffuseMap;

    // Depth values for the whole UI.
    Mipmap!L16 _depthMap;

    // Depth values for the whole UI.
    Mipmap!RGBA _materialMap;

    /// The list of areas to be redrawn at the Raw and PBR levels (composited).
    /// These are accumulated over possibly several calls of `recomputeDirtyRects`
    /// and cleared by a call to `onDraw`.
    /// Other lists of areas are purely derived from `_rectsToUpdateDisjointedRaw`
    /// and `_rectsToUpdateDisjointedPBR`.
    Vec!box2i _rectsToUpdateDisjointedRaw;
    ///ditto
    Vec!box2i _rectsToUpdateDisjointedPBR;

    // Used to maintain the _rectsToUpdateXXX invariant of no overlap
    Vec!box2i _rectsTemp;

    // Same, but temporary variable for mipmap generation
    Vec!box2i[2] _updateRectScratch;

    // The areas that must be effectively re-composited.
    Vec!box2i _rectsToComposite;
    Vec!box2i _rectsToCompositeDisjointed; // same list, but reorganized to avoid overlap
    Vec!box2i _rectsToCompositeDisjointedTiled; // same list, but separated in smaller tiles

    // The areas that must be effectively redisplayed, which also mean the Raw layer is redrawn.
    Vec!box2i _rectsToDisplay;
    Vec!box2i _rectsToDisplayDisjointed; // same list, but reorganized to avoid overlap

    // The areas that must be effectively redisplayed, in logical space.
    Vec!box2i _rectsToResize;
    Vec!box2i _rectsToResizeDisjointed;

    /// The list of UIElement to potentially call `onDrawPBR` on.
    Vec!UIElement _elemsToDrawRaw;

    /// The list of UIElement to potentially call `onDrawPBR` on.
    Vec!UIElement _elemsToDrawPBR;

    /// Amount of pixels dirty rectangles are extended with.
    int _updateMargin = 20;

    /// The composited buffer, before the Raw layer is applied.
    ubyte* _compositedBuffer = null;

    /// The rendered framebuffer. 
    /// This is copied from `_renderedBuffer`, then Raw layer is drawn on top.
    /// Components are reordered there.
    ubyte* _renderedBuffer = null;

    /// The final framebuffer.
    /// It is the only buffer to have a size in logical pixels.
    /// Internally the UI has an "user" size.
    /// FUTURE: resize from user size to logical size using a resizer, 
    /// to allow better looking DPI without the OS blurry resizing.
    /// Or to allow higher internal pixel count.
    ubyte* _resizedBuffer = null;

    debug(benchmarkGraphics)
    {
        StopWatch _compositingWatch;
        StopWatch _mipmapWatch;
        StopWatch _drawWatch;
        StopWatch _copyWatch;
        StopWatch _rawWatch;
        StopWatch _reorderWatch;
    }

    void recomputeDrawLists()
    {
        // recompute draw lists
        _elemsToDrawRaw.clearContents();
        _elemsToDrawPBR.clearContents();
        getDrawLists(_elemsToDrawRaw, _elemsToDrawPBR);

        // Sort by ascending z-order (high z-order gets drawn last)
        // This sort must be stable to avoid messing with tree natural order.
        int compareZOrder(in UIElement a, in UIElement b) nothrow @nogc
        {
            return a.zOrder() - b.zOrder();
        }
        grailSort!UIElement(_elemsToDrawRaw[], &compareZOrder);
        grailSort!UIElement(_elemsToDrawPBR[], &compareZOrder);
    }

    // Useful to convert 16-byte aligned buffer into an ImageRef!RGBA
    final ImageRef!RGBA toImageRef(ubyte* alignedBuffer,
                                   int width,
                                   int height)
    {
        ImageRef!RGBA ir = void;
        ir.w = width;
        ir.h = height;
        ir.pitch = byteStride(width);
        ir.pixels = cast(RGBA*)alignedBuffer;
        return ir;
    }
   
    void doDraw(WindowPixelFormat pf) nothrow @nogc
    {
        // A. Recompute draw lists
        // These are the `UIElement`s that _may_ have their onDrawXXX callbacks called.
        recomputeDrawLists();

        // Composite GUI
        // Most of the cost of rendering is here
        // B. 1st PASS OF REDRAW
        // Some UIElements are redrawn at the PBR level
        debug(benchmarkGraphics)
            _drawWatch.start();
        redrawElementsPBR();
        debug(benchmarkGraphics)
        {
            _drawWatch.stop();
            _drawWatch.displayMean();
        }

        // C. MIPMAPPING
        debug(benchmarkGraphics)
            _mipmapWatch.start();
        regenerateMipmaps();
        debug(benchmarkGraphics)
        {
            _mipmapWatch.stop();
            _mipmapWatch.displayMean();
        }

        // D. COMPOSITING
        auto compositedRef = toImageRef(_compositedBuffer, _currentUserWidth, _currentUserHeight);
        debug(benchmarkGraphics)
            _compositingWatch.start();
        compositeGUI(compositedRef); // Launch the possibly-expensive Compositor step, which implements PBR rendering 
        debug(benchmarkGraphics)
        {
            _compositingWatch.stop();
            _compositingWatch.displayMean();
        }

        // E. COPY FROM "COMPOSITED" TO "RENDERED" BUFFER
        // Copy _compositedBuffer onto _renderedBuffer for every rect that will be changed on display
        auto renderedRef = toImageRef(_renderedBuffer, _currentUserWidth, _currentUserHeight);
        debug(benchmarkGraphics)
            _copyWatch.start();
        foreach(rect; _rectsToDisplayDisjointed[])
        {
            auto croppedComposite = compositedRef.cropImageRef(rect);
            auto croppedRendered = renderedRef.cropImageRef(rect);
            croppedComposite.blitTo(croppedRendered); // failure to optimize this: 1
        }
        debug(benchmarkGraphics)
        {
            _copyWatch.stop();
            _copyWatch.displayMean();
        }

        // F. 2nd PASS OF REDRAW
        debug(benchmarkGraphics)
            _rawWatch.start();
        redrawElementsRaw();
        debug(benchmarkGraphics)
        {
            _rawWatch.stop();
            _rawWatch.displayMean();
        }

        // G. Reorder components to the right pixel format
        debug(benchmarkGraphics)
            _reorderWatch.start();
        reorderComponents(pf);
        debug(benchmarkGraphics)
        {
            _reorderWatch.stop();
            _reorderWatch.displayMean();
        }

        // H. Copy updated content to the final buffer.
        resizeContent(pf);

        // Only then is the list of rectangles to update cleared, 
        // before calling `doDraw` such work accumulates
        _rectsToUpdateDisjointedPBR.clearContents();
        _rectsToUpdateDisjointedRaw.clearContents();
    }

    void recomputeDirtyAreas() nothrow @nogc
    {
        // First we pull dirty rectangles from the UI, for the PBR and Raw layers
        // Note that there is indeed a race here (the same UIElement could have pushed rectangles in both
        // at around the same time), but that isn't a problem.
        context().dirtyListRaw.pullAllRectangles(_rectsToUpdateDisjointedRaw);
        context().dirtyListPBR.pullAllRectangles(_rectsToUpdateDisjointedPBR);

        // TECHNICAL DEBT HERE
        // The problem here is that if the window isn't shown there may be duplicates in
        // _rectsToUpdateDisjointedRaw and _rectsToUpdateDisjointedPBR
        // (`recomputeDirtyAreas`called multiple times without clearing those arrays), 
        //  so we have to maintain unicity again.
        //
        {
            // Make _rectsToUpdateDisjointedRaw disjointed
            _rectsTemp.clearContents();
            removeOverlappingAreas(_rectsToUpdateDisjointedRaw, _rectsTemp);
            _rectsToUpdateDisjointedRaw.clearContents();
            _rectsToUpdateDisjointedRaw.pushBack(_rectsTemp);
            assert(haveNoOverlap(_rectsToUpdateDisjointedRaw[]));

            // Make _rectsToUpdateDisjointedPBR disjointed
            _rectsTemp.clearContents();
            removeOverlappingAreas(_rectsToUpdateDisjointedPBR, _rectsTemp);
            _rectsToUpdateDisjointedPBR.clearContents();
            _rectsToUpdateDisjointedPBR.pushBack(_rectsTemp);
            assert(haveNoOverlap(_rectsToUpdateDisjointedPBR[]));
        }

        // Compute _rectsToRender and _rectsToDisplay, purely derived from the above.
        // Note that they are possibly overlapping collections
        // _rectsToComposite <- margin(_rectsToUpdateDisjointedPBR)
        // _rectsToDisplay <- union(_rectsToComposite, _rectsToUpdateDisjointedRaw)
        {
            _rectsToComposite.clearContents();
            foreach(rect; _rectsToUpdateDisjointedPBR)
            {
                assert(rect.isSorted);
                assert(!rect.empty);
                _rectsToComposite.pushBack( convertPBRLayerRectToRawLayerRect(rect, _currentUserWidth, _currentUserHeight) );
            }

            // Compute the non-overlapping version
            _rectsToCompositeDisjointed.clearContents();
            removeOverlappingAreas(_rectsToComposite, _rectsToCompositeDisjointed);

            _rectsToDisplay.clearContents();
            _rectsToDisplay.pushBack(_rectsToComposite);
            foreach(rect; _rectsToUpdateDisjointedRaw)
            {
                assert(rect.isSorted);
                assert(!rect.empty);
                _rectsToDisplay.pushBack( rect );
            }

            // Compute the non-overlapping version
            _rectsToDisplayDisjointed.clearContents();
            removeOverlappingAreas(_rectsToDisplay, _rectsToDisplayDisjointed);
        }

        // Compute _rectsToResize and _rectsToDisplayDisjointed to write resized content to (in the logical pixel area).
        // These rectangle are constrained to update only _userArea.
        {
            _rectsToResize.clearContents();
            foreach(rect; _rectsToDisplay[])
            {
                box2i r = convertUserRectToLogicalRect(rect).intersection(_userArea);
                _rectsToResize.pushBack(r);
            }
            if (_invalidateResizedBuffer)
            {
                // mark _userArea as needing a recompute, since borders were drawn
                _rectsToResize.pushBack(_userArea);
            }
            _rectsToResizeDisjointed.clearContents();
            removeOverlappingAreas(_rectsToResize, _rectsToResizeDisjointed);
        }
    }

    final box2i convertPBRLayerRectToRawLayerRect(box2i rect, int width, int height) nothrow @nogc
    {
        int xmin = rect.min.x - _updateMargin;
        int ymin = rect.min.y - _updateMargin;
        int xmax = rect.max.x + _updateMargin;
        int ymax = rect.max.y + _updateMargin;

        if (xmin < 0) xmin = 0;
        if (ymin < 0) ymin = 0;
        if (xmax > width) xmax = width;
        if (ymax > height) ymax = height;

        // This could also happen if an UIElement is moved quickly
        if (xmax < 0) xmax = 0;
        if (ymax < 0) ymax = 0;
        if (xmin > width) xmin = width;
        if (ymin > height) ymin = height;

        box2i result = box2i(xmin, ymin, xmax, ymax);
        assert(result.isSorted);
        return result;
    }

    ImageRef!RGBA doResize(int widthLogicalPixels, 
                           int heightLogicalPixels) nothrow @nogc
    {
        /// We do receive a new size in logical pixels. 
        /// This is coming from getting the window client area. The reason
        /// for this resize doesn't matter, we must find a mapping that fits
        /// between this given logical size and user size.

        // 1.a Based upon the _sizeConstraints, select a user size in pixels.
        _currentLogicalWidth  = widthLogicalPixels;
        _currentLogicalHeight = heightLogicalPixels;
        _currentUserWidth     = widthLogicalPixels;
        _currentUserHeight    = heightLogicalPixels;
        _sizeConstraints.getNearestValidSize(&_currentUserWidth, &_currentUserHeight);

        // 1.b Update user area rect. We find a suitable space in logical area 
        //     to draw the whole UI.
        {
            int x, y, w, h;
            if (_currentLogicalWidth >= _currentUserWidth)
            {
                x = (_currentLogicalWidth - _currentUserWidth) / 2;
                w = _currentUserWidth;
            }
            else
            {
                x = 0;
                w = _currentLogicalWidth;
            }
            if (_currentLogicalHeight >= _currentUserHeight)
            {
                y = (_currentLogicalHeight - _currentUserHeight) / 2;
                h = _currentUserHeight;
            }
            else
            {
                y = 0;
                h = _currentLogicalHeight;
            }
            _userArea = box2i.rectangle(x, y, w, h);
        }

        // 2. Invalidate UI region if user size change.
        //    Note: _resizedBuffer invalidation is managed otherwise.
        position = box2i(0, 0, _currentUserWidth, _currentUserHeight);
        _invalidateResizedBuffer = true; // TODO: only do this if _userArea changed
        _redrawBlackBorders = true; // TODO: only do this if _userArea changed

        // 3. Resize compositor buffers.
        _compositor.resizeBuffers(_currentUserWidth, _currentUserHeight, PBR_TILE_MAX_WIDTH, PBR_TILE_MAX_HEIGHT);

        _diffuseMap.size(5, _currentUserWidth, _currentUserHeight);
        _depthMap.size(4, _currentUserWidth, _currentUserHeight);

        // The first level of the depth map has a border of 1 pixels and 2 pxiels on the right, to simplify some PBR passes
        int border_1 = 1;
        int rowAlign_1 = 1;
        int xMultiplicity_1 = 1;
        int trailingSamples_2 = 2;
        _depthMap.levels[0].size(_currentUserWidth, _currentUserHeight, border_1, rowAlign_1, xMultiplicity_1, trailingSamples_2);

        _materialMap.size(0, _currentUserWidth, _currentUserHeight);

        // Extends buffers with user size
        size_t sizeNeeded = byteStride(_currentUserWidth) * _currentUserHeight;
        _compositedBuffer = cast(ubyte*) alignedRealloc(_compositedBuffer, sizeNeeded, 16);
        _renderedBuffer = cast(ubyte*) alignedRealloc(_renderedBuffer, sizeNeeded, 16);

        // Extends final buffer with logical size
        sizeNeeded = byteStride(_currentLogicalWidth) * _currentLogicalHeight;
        _resizedBuffer = cast(ubyte*) alignedRealloc(_resizedBuffer, sizeNeeded, 16);

        return toImageRef(_resizedBuffer, _currentLogicalWidth, _currentLogicalHeight);
    }

    /// Draw the Raw layer of `UIElement` widgets
    void redrawElementsRaw() nothrow @nogc
    {
        enum bool parallelDraw = true;

        ImageRef!RGBA renderedRef = toImageRef(_renderedBuffer, _currentUserWidth, _currentUserHeight);

        // No need to launch threads only to have them realize there isn't anything to do
        if (_rectsToDisplayDisjointed.length == 0)
            return;

        static if (parallelDraw)
        {
            int drawn = 0;
            int N = cast(int)_elemsToDrawRaw.length;

            while(drawn < N)
            {
                int canBeDrawn = 1; // at least one can be drawn without collision

                // Search max number of parallelizable draws until the end of the list or a collision is found
                bool foundIntersection = false;
                for ( ; (drawn + canBeDrawn < N); ++canBeDrawn)
                {
                    box2i candidate = _elemsToDrawRaw[drawn + canBeDrawn].position;

                    for (int j = 0; j < canBeDrawn; ++j)
                    {
                        if (_elemsToDrawRaw[drawn + j].position.intersects(candidate))
                        {
                            foundIntersection = true;
                            break;
                        }
                    }
                    if (foundIntersection)
                        break;
                }

                assert(canBeDrawn >= 1);

                // Draw a number of UIElement in parallel
                void drawOneItem(int i, int threadIndex) nothrow @nogc
                {
                    _elemsToDrawRaw[drawn + i].renderRaw(renderedRef, _rectsToDisplayDisjointed[]);
                }
                _threadPool.parallelFor(canBeDrawn, &drawOneItem);

                drawn += canBeDrawn;
                assert(drawn <= N);
            }
            assert(drawn == N);
        }
        else
        {
            foreach(elem; _elemsToDrawRaw)
                elem.renderRaw(renderedRef, _rectsToDisplayDisjointed[]);
        }
    }

    /// Draw the PBR layer of `UIElement` widgets
    void redrawElementsPBR() nothrow @nogc
    {
        enum bool parallelDraw = true;

        auto diffuseRef = _diffuseMap.levels[0].toRef();
        auto depthRef = _depthMap.levels[0].toRef();
        auto materialRef = _materialMap.levels[0].toRef();

        // No need to launch threads only to have them realize there isn't anything to do
        if (_rectsToUpdateDisjointedPBR.length == 0)
            return;

        static if (parallelDraw)
        {
            int drawn = 0;
            int N = cast(int)_elemsToDrawPBR.length;

            while(drawn < N)
            {
                int canBeDrawn = 1; // at least one can be drawn without collision

                // Search max number of parallelizable draws until the end of the list or a collision is found
                bool foundIntersection = false;
                for ( ; (drawn + canBeDrawn < N); ++canBeDrawn)
                {
                    box2i candidate = _elemsToDrawPBR[drawn + canBeDrawn].position;

                    for (int j = 0; j < canBeDrawn; ++j)
                    {
                        if (_elemsToDrawPBR[drawn + j].position.intersects(candidate))
                        {
                            foundIntersection = true;
                            break;
                        }
                    }
                    if (foundIntersection)
                        break;
                }

                assert(canBeDrawn >= 1);
 
                // Draw a number of UIElement in parallel
                void drawOneItem(int i, int threadIndex) nothrow @nogc
                {
                    _elemsToDrawPBR[drawn + i].renderPBR(diffuseRef, depthRef, materialRef, _rectsToUpdateDisjointedPBR[]);
                }
                _threadPool.parallelFor(canBeDrawn, &drawOneItem);

                drawn += canBeDrawn;
                assert(drawn <= N);
            }
            assert(drawn == N);
        }
        else
        {
            // Render required areas in diffuse and depth maps, base level
            foreach(elem; _elemsToDraw)
                elem.renderPBR(diffuseRef, depthRef, materialRef, _rectsToUpdateDisjointedPBR[]);
        }
    }

    /// Do the PBR compositing step. This is the most expensive step in the UI.
    void compositeGUI(ImageRef!RGBA wfb) nothrow @nogc
    {
        _rectsToCompositeDisjointedTiled.clearContents();
        tileAreas(_rectsToCompositeDisjointed[],  PBR_TILE_MAX_WIDTH, PBR_TILE_MAX_HEIGHT, _rectsToCompositeDisjointedTiled);

        _compositor.compositeTile(wfb, 
                                  _rectsToCompositeDisjointedTiled[],
                                  _diffuseMap, 
                                  _materialMap, 
                                  _depthMap);
    }

    /// Compose lighting effects from depth and diffuse into a result.
    /// takes output image and non-overlapping areas as input
    /// Useful multithreading code.
    void regenerateMipmaps() nothrow @nogc
    {
        int numAreas = cast(int)_rectsToUpdateDisjointedPBR.length;

        // No mipmap to update, no need to launch threads
        if (numAreas == 0)
            return;

        // Fill update rect buffer with the content of _rectsToUpdateDisjointedPBR
        for (int i = 0; i < 2; ++i)
        {
            _updateRectScratch[i].clearContents();
            _updateRectScratch[i].pushBack(_rectsToUpdateDisjointedPBR[]);
        }

        // Mipmapping used to be threaded, however because it's completely memory-bound
        // (about 2mb read/sec) and fast enough, it's not worth launching threads for.

        // Generate diffuse mipmap, useful for dealing with emissive
        {
            // diffuse
            Mipmap!RGBA mipmap = _diffuseMap;
            int levelMax = min(mipmap.numLevels(), 5);
            foreach(level; 1 .. mipmap.numLevels())
            {
                Mipmap!RGBA.Quality quality;
                if (level == 1)
                    quality = Mipmap!RGBA.Quality.boxAlphaCovIntoPremul;
                else
                    quality = Mipmap!RGBA.Quality.cubic;
                foreach(ref area; _updateRectScratch[0])
                {
                    area = mipmap.generateNextLevel(quality, area, level);
                }
            }
        }

        // Generate depth mipmap, useful for dealing with ambient occlusion
        {
            int W = _currentUserWidth;
            int H = _currentUserHeight;

            // Depth is special since it has a border!
            // Regenerate the border area that needs to be regenerated
            OwnedImage!L16 level0 = _depthMap.levels[0];
            foreach(box2i area; _updateRectScratch[1])
                level0.replicateBordersTouching(area);

            // DEPTH MIPMAPPING
            Mipmap!L16 mipmap = _depthMap;
            foreach(level; 1 .. mipmap.numLevels())
            {
                auto quality = level >= 3 ? Mipmap!L16.Quality.cubic : Mipmap!L16.Quality.box;
                foreach(ref area; _updateRectScratch[1])
                {
                    area = mipmap.generateNextLevel(quality, area, level);
                }
            }
        }
    }

    void reorderComponents(WindowPixelFormat pf)
    {
        auto renderedRef = toImageRef(_renderedBuffer, _currentUserWidth, _currentUserHeight);

        final switch(pf)
        {
            case WindowPixelFormat.RGBA8:
                foreach(rect; _rectsToDisplayDisjointed[])
                {
                    shuffleComponentsRGBA8ToRGBA8AndForceAlphaTo255(renderedRef.cropImageRef(rect));
                }
                break;

            case WindowPixelFormat.BGRA8:
                foreach(rect; _rectsToDisplayDisjointed[])
                {
                    shuffleComponentsRGBA8ToBGRA8AndForceAlphaTo255(renderedRef.cropImageRef(rect));
                }
                break;
            case WindowPixelFormat.ARGB8:
                foreach(rect; _rectsToDisplayDisjointed[])
                {
                    shuffleComponentsRGBA8ToARGB8AndForceAlphaTo255(renderedRef.cropImageRef(rect));
                }
                break;
        }   
    }

    // From a user area rectangle, return a logical are rectangle with the same size.
    final box2i convertUserRectToLogicalRect(box2i b)
    {
        return b.translate(_userArea.min);
    }

    final box2i convertLogicalRectToUserRect(box2i b)
    {
        return b.translate(-_userArea.min);
    }

    void resizeContent(WindowPixelFormat pf)
    {
        // TODO: eventually resize?
        // For now what we do for logical area is crop and offset.
        // In the future, could be beneficial to resample if needed.

        auto renderedRef = toImageRef(_renderedBuffer, _currentUserWidth, _currentUserHeight);
        auto resizedRef = toImageRef(_resizedBuffer, _currentLogicalWidth, _currentLogicalHeight);

        // If invalidated, the whole buffer needs to be redrawn 
        // (because of borders, or changing offsets of the user area).
        if (_redrawBlackBorders)
        {
            RGBA black;
            final switch(pf)
            {
                case WindowPixelFormat.RGBA8:
                case WindowPixelFormat.BGRA8: black = RGBA(0, 0, 0, 255); break;
                case WindowPixelFormat.ARGB8: black = RGBA(255, 0, 0, 0); break;
            }
            // PERF: Only do this in the location of the black border.
            resizedRef.fillAll(black);
            _redrawBlackBorders = false;
        }

        foreach(rect; _rectsToResizeDisjointed[])
        {
            assert(_userArea.contains(rect));

            int dx = _userArea.min.x;
            int dy = _userArea.min.y;

            for (int j = rect.min.y; j < rect.max.y; ++j)
            {
                RGBA* src  = renderedRef.scanline(j - dy).ptr;
                RGBA* dest = resizedRef.scanline(j).ptr;
                dest[rect.min.x..rect.max.x] = src[(rect.min.x - dx)..(rect.max.x - dx)];
            }
        }
    }
}

enum scanLineAlignment = 4; // could be anything

// given a width, how long in bytes should scanlines be
int byteStride(int width) pure nothrow @nogc
{
    int widthInBytes = width * 4;
    return (widthInBytes + (scanLineAlignment - 1)) & ~(scanLineAlignment-1);
}

debug(benchmarkGraphics)
{
    static class StopWatch
    {
    nothrow:
    @nogc:
        this(GUIGraphics graphics, string title)
        {
            _graphics = graphics;
            _title = title;

            getCurrentThreadHandle();
        }

        void start()
        {
            _lastTime = getTickUs();
        }

        enum WARMUP = 0;

        void stop()
        {
            long now = getTickUs();
            int timeDiff = cast(int)(now - _lastTime);

            //if (times >= WARMUP)
            if (sum < timeDiff)
                sum = timeDiff;
                //sum += timeDiff; // first samples are discarded

            times = 1;
        }

        void displayMean()
        {
            import core.stdc.stdio;
            char[128] buf;
            sprintf(buf.ptr, "%s %2.3f ms mean", _title.ptr, (sum * 0.001) / (times - WARMUP));
            debugOutput(buf.ptr);
        }

        void debugOutput(const(char)* a)
        {
            debugLog(a);
        }

        GUIGraphics _graphics;
        string _title;
        long _lastTime;
        double sum = 0;
        int times = 0;

    
        __gshared HANDLE hThread;

        long qpcFrequency;

        void getCurrentThreadHandle()
        {
            hThread = GetCurrentThread();    
            QueryPerformanceFrequency(&qpcFrequency);
        }

        long getTickUs() nothrow @nogc
        {
            version(Windows)
            {
                static if (preciseMeasurements)
                {
                    // About -precise measurement:
                    // We use the undocumented fact that QueryThreadCycleTime
                    // seem to return a counter in QPC units.
                    // That may not be the case everywhere, so -precise is not reliable and should
                    // never be the default.
                    // Warning: -precise and normal measurements not in the same unit. 
                    //          You shouldn't trust preciseMeasurements to give actual milliseconds values.
                    import core.sys.windows.windows;
                    ulong cycles;
                    BOOL res = QueryThreadCycleTime(hThread, &cycles);
                    assert(res != 0);
                    real us = 1000.0 * cast(real)(cycles) / cast(real)(qpcFrequency);
                    return cast(long)(0.5 + us);
                }
                else
                {
                    import core.sys.windows.windows;
                    LARGE_INTEGER lint;
                    QueryPerformanceCounter(&lint);
                    double seconds = lint.QuadPart / cast(double)(qpcFrequency);
                    long us = cast(long)(seconds * 1_000_000);
                    return us;
                }
            }
            else
            {
                import core.time;
                return convClockFreq(MonoTime.currTime.ticks, MonoTime.ticksPerSecond, 1_000_000);
            }
        }
    }
}
void shuffleComponentsRGBA8ToARGB8AndForceAlphaTo255(ImageRef!RGBA image) pure nothrow @nogc
{
    immutable int w = image.w;
    immutable int h = image.h;
    for (int j = 0; j < h; ++j)
    {
        ubyte* scan = cast(ubyte*)image.scanline(j).ptr;

        int i = 0;
        for( ; i + 3 < w; i += 4)
        {
            __m128i inputBytes = _mm_loadu_si128(cast(__m128i*)(&scan[4*i]));
            inputBytes = _mm_or_si128(inputBytes, _mm_set1_epi32(0xff000000));

            version(LDC)
            {
                import ldc.intrinsics;
                import ldc.simd;
                __m128i outputBytes = cast(__m128i) shufflevector!(byte16, 3, 0,  1,  2,
                                                                           7, 4,  5,  6,
                                                                           11, 8,  9,  10,
                                                                           15, 12, 13, 14)(cast(byte16)inputBytes, cast(byte16)inputBytes);
                _mm_storeu_si128(cast(__m128i*)(&scan[4*i]), outputBytes);
            }
            else
            {
                // convert to ushort
                __m128i zero = _mm_setzero_si128();
                __m128i e0_7 = _mm_unpacklo_epi8(inputBytes, zero);
                __m128i e8_15 = _mm_unpackhi_epi8(inputBytes, zero);

                enum int swapRB = _MM_SHUFFLE(2, 1, 0, 3);
                e0_7 = _mm_shufflelo_epi16!swapRB(_mm_shufflehi_epi16!swapRB(e0_7));
                e8_15 = _mm_shufflelo_epi16!swapRB(_mm_shufflehi_epi16!swapRB(e8_15));
                __m128i outputBytes = _mm_packus_epi16(e0_7, e8_15);
                _mm_storeu_si128(cast(__m128i*)(&scan[4*i]), outputBytes);
            }
        }

        for(; i < w; i ++)
        {
            ubyte r = scan[4*i];
            ubyte g = scan[4*i+1];
            ubyte b = scan[4*i+2];
            scan[4*i] = 255;
            scan[4*i+1] = r;
            scan[4*i+2] = g;
            scan[4*i+3] = b;
        }
    }
}

void shuffleComponentsRGBA8ToBGRA8AndForceAlphaTo255(ImageRef!RGBA image) pure nothrow @nogc
{
    immutable int w = image.w;
    immutable int h = image.h;
    for (int j = 0; j < h; ++j)
    {
        ubyte* scan = cast(ubyte*)image.scanline(j).ptr;

        int i = 0;
        for( ; i + 3 < w; i += 4)
        {
            __m128i inputBytes = _mm_loadu_si128(cast(__m128i*)(&scan[4*i]));
            inputBytes = _mm_or_si128(inputBytes, _mm_set1_epi32(0xff000000));

            version(LDC)
            {
                import ldc.intrinsics;
                import ldc.simd;
                __m128i outputBytes = cast(__m128i) shufflevector!(byte16, 2,  1,  0,  3,
                                                                           6,  5,  4,  7,
                                                                          10,  9,  8, 11,
                                                                          14, 13, 12, 15)(cast(byte16)inputBytes, cast(byte16)inputBytes);
                _mm_storeu_si128(cast(__m128i*)(&scan[4*i]), outputBytes);
            }
            else
            {
                // convert to ushort
                __m128i zero = _mm_setzero_si128();
                __m128i e0_7 = _mm_unpacklo_epi8(inputBytes, zero);
                __m128i e8_15 = _mm_unpackhi_epi8(inputBytes, zero);

                // swap red and green
                enum int swapRB = _MM_SHUFFLE(3, 0, 1, 2);
                e0_7 = _mm_shufflelo_epi16!swapRB(_mm_shufflehi_epi16!swapRB(e0_7));
                e8_15 = _mm_shufflelo_epi16!swapRB(_mm_shufflehi_epi16!swapRB(e8_15));
                __m128i outputBytes = _mm_packus_epi16(e0_7, e8_15);
                _mm_storeu_si128(cast(__m128i*)(&scan[4*i]), outputBytes);
            }
        }

        for(; i < w; i ++)
        {
            ubyte r = scan[4*i];
            ubyte g = scan[4*i+1];
            ubyte b = scan[4*i+2];
            scan[4*i] = b;
            scan[4*i+1] = g;
            scan[4*i+2] = r;
            scan[4*i+3] = 255;
        }
    }
}

void shuffleComponentsRGBA8ToRGBA8AndForceAlphaTo255(ImageRef!RGBA image) pure nothrow @nogc
{
    immutable int w = image.w;
    immutable int h = image.h;
    for (int j = 0; j < h; ++j)
    {
        ubyte* scan = cast(ubyte*)image.scanline(j).ptr;

        int i = 0;
        for( ; i + 3 < w; i += 4)
        {
            __m128i inputBytes = _mm_loadu_si128(cast(__m128i*)(&scan[4*i]));
            inputBytes = _mm_or_si128(inputBytes, _mm_set1_epi32(0xff000000));
            // No reordering to do
            _mm_storeu_si128(cast(__m128i*)(&scan[4*i]), inputBytes);
        }

        for(; i < w; i ++)
        {
            scan[4*i+3] = 255;
        }
    }
}
