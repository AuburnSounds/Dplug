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

/// In the whole package:
/// The diffuse maps contains:
///   RGBA = red/green/blue/emissiveness
/// The depth maps contains depth (0 being lowest, 65535 highest)
/// The material map contains:
///   RGBA = roughness / metalness / specular / unused

alias RMSP = RGBA; // reminder

// Uncomment to benchmark compositing and devise optimizations.
//debug = benchmarkGraphics;

// A GUIGraphics is the interface between a plugin client and a IWindow.
// It is also an UIElement and the root element of the plugin UI hierarchy.
// You have to derive it to have a GUI.
// It dispatches window events to the GUI hierarchy.
class GUIGraphics : UIElement, IGraphics
{
nothrow:
@nogc:

    ICompositor compositor;

    this(int initialWidth, int initialHeight, UIFlags flags)
    {
        _uiContext = mallocNew!UIContext();
        super(_uiContext, flags);

        // Don't like the default rendering? Make another compositor.
        compositor = mallocNew!PBRCompositor();

        _windowListener = mallocNew!WindowListener(this);

        _window = null;
        _askedWidth = initialWidth;
        _askedHeight = initialHeight;

        int numThreads = 0; // auto
        int maxThreads = 2;
        _threadPool = mallocNew!ThreadPool(numThreads, maxThreads);

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


    ~this()
    {
        closeUI();
        _uiContext.destroyFree();

        _threadPool.destroyFree();

        compositor.destroyFree();
        _diffuseMap.destroyFree();
        _materialMap.destroyFree();
        _depthMap.destroyFree();

        _windowListener.destroyFree();
        alignedFree(_compositedBuffer, 16);
        alignedFree(_renderedBuffer, 16);
    }

    // Graphics implementation

    override void* openUI(void* parentInfo, void* controlInfo, DAW daw, GraphicsBackend backend)
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

        // We create this window each time.
        _window = createWindow(WindowUsage.plugin, parentInfo, controlInfo, _windowListener, wbackend, _askedWidth, _askedHeight);

        reflow(box2i(0, 0, _askedWidth, _askedHeight));

        // Sets the whole UI dirty
        setDirtyWhole();

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

    override void getGUISize(int* width, int* height)
    {
        *width = _askedWidth;
        *height = _askedHeight;
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
            outer.mouseRelease(x, y, mb, mstate);
            return true;
        }

        override bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate)
        {
            return outer.mouseWheel(x, y, wheelDeltaX, wheelDeltaY, mstate);
        }

        override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
        {
            version(futureMouseOver)
            {
                bool hitSomething = outer.mouseMove(x, y, dx, dy, mstate, false);
                if (!hitSomething)
                {
                    // Nothing was mouse-over'ed, nothing is `isMouseOver()` anymore
                    outer._uiContext.setMouseOver(null);
                }
            }
            else
            {
                outer.mouseMove(x, y, dx, dy, mstate);
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
            return outer._rectsToDisplay[].boundingBox();
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

    UIContext _uiContext;

    WindowListener _windowListener;

    // An interface to the underlying window
    IWindow _window;

    // Task pool for multi-threaded image work
    ThreadPool _threadPool;

    int _askedWidth = 0;
    int _askedHeight = 0;

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

    /// The list of UIElement to potentially call `onDrawPBR` on.
    // PERF: could be replaced by a range on the UI tree
    Vec!UIElement _elemsToDrawRaw;

    /// The list of UIElement to potentially call `onDrawPBR` on.
    // PERF: could be replaced by a range on the UI tree
    Vec!UIElement _elemsToDrawPBR;

    /// Amount of pixels dirty rectangles are extended with.
    int _updateMargin = 20;

    /// The composited buffer, before the Raw layer is applied.
    ubyte* _compositedBuffer = null;

    /// The final rendered framebuffer. 
    /// This is copied from `_renderedBuffer`, then Raw layer is drawn on top.
    ubyte* _renderedBuffer = null;

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

    // useful to convert 16-byte aligned buffers into an ImageRef!RGBA
    final ImageRef!RGBA toImageRef(ubyte* alignedBuffer)
    {
        ImageRef!RGBA ir = void;
        ir.w = _askedWidth;
        ir.h = _askedHeight;
        ir.pitch = byteStride(_askedWidth);
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
        // Split boxes to avoid overlapped work
        // Note: this is done separately for update areas and render areas
        regenerateMipmaps();
        debug(benchmarkGraphics)
        {
            _mipmapWatch.stop();
            _mipmapWatch.displayMean();
        }

        // D. COMPOSITING
        auto compositedRef = toImageRef(_compositedBuffer);
        debug(benchmarkGraphics)
            _compositingWatch.start();        
        compositeGUI(compositedRef, pf); // Launch the possibly-expensive Compositor step, which implements PBR rendering 
        debug(benchmarkGraphics)
        {
            _compositingWatch.stop();
            _compositingWatch.displayMean();
        }

        // E. COPY FROM "COMPOSITED" TO "RENDERED" BUFFER
        // Copy _compositedBuffer onto _renderedBuffer for every rect that will be changed on display
        auto renderedRef = toImageRef(_renderedBuffer);
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
                _rectsToComposite.pushBack( convertPBRLayerRectToRawLayerRect(rect, _askedWidth, _askedHeight) );
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

    ImageRef!RGBA doResize(int width, int height) nothrow @nogc
    {
        _askedWidth = width;
        _askedHeight = height;

        reflow(box2i(0, 0, _askedWidth, _askedHeight));

        // FUTURE: maybe not destroy the whole mipmap?
        _diffuseMap.size(5, width, height);
        _depthMap.size(4, width, height);
        _materialMap.size(0, width, height);

        // Extends buffer
        size_t sizeNeeded = byteStride(width) * height;
        _compositedBuffer = cast(ubyte*) alignedRealloc(_compositedBuffer, sizeNeeded, 16);
        _renderedBuffer = cast(ubyte*) alignedRealloc(_renderedBuffer, sizeNeeded, 16);

        return toImageRef(_renderedBuffer);
    }

    /// Draw the Raw layer of `UIElement` widgets
    void redrawElementsRaw() nothrow @nogc
    {
        enum bool parallelDraw = true;

        ImageRef!RGBA renderedRef = toImageRef(_renderedBuffer);

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
                void drawOneItem(int i) nothrow @nogc
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
                void drawOneItem(int i) nothrow @nogc
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

    /// Compose lighting effects from depth and diffuse into a result.
    /// takes output image and non-overlapping areas as input
    /// Useful multithreading code.
    void compositeGUI(ImageRef!RGBA wfb, WindowPixelFormat pf) nothrow @nogc
    {
        // Difficult trade-off: we canted the medium size knob to be only one tile.
        // This avoid launching threads for the PBR compositor in this case.
        enum tileWidth = 128;
        enum tileHeight = 128;

        _rectsToCompositeDisjointedTiled.clearContents();
        tileAreas(_rectsToCompositeDisjointed[], tileWidth, tileHeight,_rectsToCompositeDisjointedTiled);

        int numAreas = cast(int)_rectsToCompositeDisjointedTiled.length;

        void compositeOneTile(int i) nothrow @nogc
        {
            compositor.compositeTile(wfb, pf, _rectsToCompositeDisjointedTiled[i],
                                     _diffuseMap, _materialMap, _depthMap, context.skybox);
        }
        _threadPool.parallelFor(numAreas, &compositeOneTile);
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

        // We can't use tiled parallelism for mipmapping here because there is overdraw beyond level 0
        // So instead what we do is using up to 2 threads.
        void processOneMipmap(int i) nothrow @nogc
        {
            if (i == 0)
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

                    foreach(ref area; _updateRectScratch[i])
                    {
                        area = mipmap.generateNextLevel(quality, area, level);
                    }
                }
            }
            else
            {
                // depth
                Mipmap!L16 mipmap = _depthMap;
                foreach(level; 1 .. mipmap.numLevels())
                {
                    auto quality = level >= 3 ? Mipmap!L16.Quality.cubic : Mipmap!L16.Quality.box;
                    foreach(ref area; _updateRectScratch[i])
                    {
                        area = mipmap.generateNextLevel(quality, area, level);
                    }
                }
            }
        }
        _threadPool.parallelFor(2, &processOneMipmap);
    }

    void reorderComponents(WindowPixelFormat pf)
    {
        auto renderedRef = toImageRef(_renderedBuffer);

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
}

enum scanLineAlignment = 4; // could be anything

// given a width, how long in bytes should scanlines be
int byteStride(int width) pure nothrow @nogc
{
    int widthInBytes = width * 4;
    return (widthInBytes + (scanLineAlignment - 1)) & ~(scanLineAlignment-1);
}


static class StopWatch
{
nothrow:
@nogc:
    this(GUIGraphics graphics, string title)
    {
        _graphics = graphics;
        _title = title;
    }

    void start()
    {
        _lastTime = _graphics._window.getTimeMs();
    }

    enum WARMUP = 30;

    void stop()
    {
        uint now = _graphics._window.getTimeMs();
        int timeDiff = cast(int)(now - _lastTime);

        if (times >= WARMUP)
            sum += timeDiff; // first samples are discarded

        times++;
    }

    void displayMean()
    {
        if (times > WARMUP)
        {
            import core.stdc.stdio;
            char[128] buf;
            sprintf(buf.ptr, "%s %2.2f ms mean", _title.ptr, sum / (times - WARMUP));
            debugOutput(buf.ptr);
        }
    }

    void debugOutput(const(char)* a)
    {
        version(Posix)
        {
            import core.stdc.stdio;
            printf("%s\n", a);
        }
        else version(Windows)
        {
            import core.sys.windows.windows;
            OutputDebugStringA(a);
        }
    }

    GUIGraphics _graphics;
    string _title;
    uint _lastTime;
    double sum = 0;
    int times = 0;
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
                __m128i outputBytes = shufflevector!(byte16, 3, 0,  1,  2,
                                                             7, 4,  5,  6,
                                                            11, 8,  9,  10,
                                                            15, 12, 13, 14)(inputBytes, inputBytes);
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
                __m128i outputBytes = shufflevector!(byte16, 2,  1,  0,  3,
                                                              6,  5,  4,  7,
                                                             10,  9,  8, 11,
                                                             14, 13, 12, 15)(inputBytes, inputBytes);
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
