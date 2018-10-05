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
/// The depth maps contains depth.
/// The material map contains:
///   RGBA = roughness / metalness / specular / physical (allows to bypass PBR)

alias RMSP = RGBA; // reminder

// Uncomment to benchmark compositing and devise optimizations.
//version = BenchmarkCompositing;

// A GUIGraphics is the interface between a plugin client and a IWindow.
// It is also an UIElement and the root element of the plugin UI hierarchy.
// You have to derive it to have a GUI.
// It dispatches window events to the GUI hierarchy.
class GUIGraphics : UIElement, IGraphics
{
nothrow:
@nogc:

    ICompositor compositor;

    this(int initialWidth, int initialHeight)
    {
        _uiContext = mallocNew!UIContext();
        super(_uiContext);

        // Don't like the default rendering? Make another compositor.
        compositor = mallocNew!PBRCompositor();

        _windowListener = mallocNew!WindowListener(this);

        _window = null;
        _askedWidth = initialWidth;
        _askedHeight = initialHeight;

        _threadPool = mallocNew!ThreadPool();

        _areasToUpdateNonOverlappingRaw = makeVec!box2i;
        _areasToUpdateNonOverlappingPBR = makeVec!box2i;
        _areasTemp = makeVec!box2i;

        _updateRectScratch[0] = makeVec!box2i;
        _updateRectScratch[1] = makeVec!box2i;

        _areasToComposite = makeVec!box2i;
        _areasToCompositeNonOverlapping = makeVec!box2i;
        _areasToCompositeNonOverlappingTiled = makeVec!box2i;

        _areasToDisplay = makeVec!box2i;
        _areasToDisplayNonOverlapping = makeVec!box2i;

        _elemsToDraw = makeVec!UIElement;

        version(BenchmarkCompositing)
        {
            _compositingWatch = new StopWatch("Compositing = ");
            _drawWatch = new StopWatch("Draw = ");
            _mipmapWatch = new StopWatch("Mipmap = ");
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

    version(BenchmarkCompositing)
    {
        class StopWatch
        {
            this(string title)
            {
                _title = title;
            }

            void start()
            {
                _lastTime = _window.getTimeMs();
            }

            enum WARMUP = 30;

            void stop()
            {
                uint now = _window.getTimeMs();
                int timeDiff = cast(int)(now - _lastTime);

                if (times >= WARMUP)
                    sum += timeDiff; // first samples are discarded

                times++;
                string msg = _title ~ to!string(timeDiff) ~ " ms";
                _window.debugOutput(msg);
            }

            void displayMean()
            {
                if (times > WARMUP)
                {
                    string msg = _title ~ to!string(sum / (times - WARMUP)) ~ " ms mean";
                    _window.debugOutput(msg);
                }
            }

            string _title;
            uint _lastTime;
            double sum = 0;
            int times = 0;
        }
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
            return outer.mouseClick(x, y, mb, isDoubleClick, mstate);
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
            outer.mouseMove(x, y, dx, dy, mstate);
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
            return outer._areasToDisplay[].boundingBox();
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

    // The list of areas to be redrawn at the Raw level (composited)
    Vec!box2i _areasToUpdateNonOverlappingRaw;

    // The list of areas to be redrawn at the PBR level (diffuse/depth/material)
    Vec!box2i _areasToUpdateNonOverlappingPBR;

    // Used to maintain the _areasToUpdateXXX invariant of no overlap
    Vec!box2i _areasTemp;

    // Same, but temporary variable for mipmap generation
    Vec!box2i[2] _updateRectScratch;

    // The list of areas that must be effectively re-composited.
    Vec!box2i _areasToComposite;
    Vec!box2i _areasToCompositeNonOverlapping; // same list, but reorganized to avoid overlap
    Vec!box2i _areasToCompositeNonOverlappingTiled; // same list, but separated in smaller tiles

    // The list of areas that must be effectively redrawn in the Raw layer, and then redisplayed.
    Vec!box2i _areasToDisplay;
    Vec!box2i _areasToDisplayNonOverlapping; // same list, but reorganized to avoid overlap

    // The list of UIElement to draw.
    // Note: AlignedBuffer memory isn't scanned,
    //       but this doesn't matter since UIElement are the UI hierarchy anyway.
    Vec!UIElement _elemsToDraw;

    /// Amount of pixels dirty rectangles are extended with.
    int _updateMargin = 20;

    /// The composited buffer, before the Raw layer is applied.
    ubyte* _compositedBuffer = null;

    /// The final rendered framebuffer. 
    /// This is copied from `_renderedBuffer`, then Raw layer is drawn on top.
    ubyte* _renderedBuffer = null;

    version(BenchmarkCompositing)
    {
        StopWatch _compositingWatch;
        StopWatch _mipmapWatch;
        StopWatch _drawWatch;
    }

    void computeElementToRedraw()
    {
        // recompute draw list
        _elemsToDraw.clearContents();
        getDrawList(_elemsToDraw);

        // Sort by ascending z-order (high z-order gets drawn last)
        // This sort must be stable to avoid messing with tree natural order.
        int compareZOrder(in UIElement a, in UIElement b) nothrow @nogc
        {
            return a.zOrder() - b.zOrder();
        }
        grailSort!UIElement(_elemsToDraw[], &compareZOrder); // PERF: share this list with PBR and Raw layers
    }

    void doDraw(WindowPixelFormat pf) nothrow @nogc
    {
        // Composite GUI
        // Most of the cost of rendering is here
        // A. 1st PASS OF REDRAW
        // Some UIElements are redrawn at the PBR level
        version(BenchmarkCompositing)
            _drawWatch.start();
        redrawElementsPBR();
        version(BenchmarkCompositing)
        {
            _drawWatch.stop();
            _drawWatch.displayMean();
        }

        // B. MIPMAPPING
        version(BenchmarkCompositing)
            _mipmapWatch.start();
        // Split boxes to avoid overlapped work
        // Note: this is done separately for update areas and render areas
        regenerateMipmaps();
        version(BenchmarkCompositing)
        {
            _mipmapWatch.stop();
            _mipmapWatch.displayMean();
        }

        // C. COMPOSITING
        ImageRef!RGBA wfb;
        wfb.w = _askedWidth;
        wfb.h = _askedHeight;
        wfb.pitch = byteStride(_askedWidth);
        wfb.pixels = cast(RGBA*)_compositedBuffer;
        version(BenchmarkCompositing)
            _compositingWatch.start();        
        compositeGUI(wfb, pf); // Launch the possibly-expensive Compositor step, which implements PBR rendering
 
        version(BenchmarkCompositing)
        {
            _compositingWatch.stop();
            _compositingWatch.displayMean();
        }

        // D. COPY FROM "COMPOSITED" TO "RENDERED" BUFFER
        // PERF: optimize this copy, should only happen in _areasToCompositeNonOverlapping
        {
            size_t size = byteStride(_askedWidth) * _askedHeight;
            _renderedBuffer[0..size] = _compositedBuffer[0..size];
        }

        // E. 2nd PASS OF REDRAW
        // TODO: measure that
        redrawElementsRaw();

        // Only then is the list of rectangles to update cleared, 
        // before calling `doDraw` such work accumulates
        _areasToUpdateNonOverlappingPBR.clearContents();
        _areasToUpdateNonOverlappingRaw.clearContents();
    }

    void recomputeDirtyAreas() nothrow @nogc
    {
        // First we pull dirty rectangles from the UI, for the PBR and Raw layers
        // Note that there is indeed a race here (the same UIElement could have pushed rectangles in both
        // at around the same time), but that isn't a problem.
        context().dirtyListRaw.pullAllRectangles(_areasToUpdateNonOverlappingRaw);
        context().dirtyListPBR.pullAllRectangles(_areasToUpdateNonOverlappingPBR);


        // TECHNICAL DEBT HERE
        // The problem here is that if the window isn't shown there may be duplicates in
        // _areasToUpdateNonOverlappingRaw and _areasToUpdateNonOverlappingPBR
        // (`recomputeDirtyAreas`called multiple times without clearing those arrays), 
        //  so we have to maintain unicity again.
        //
        {
            // Make _areasToUpdateNonOverlappingRaw disjointed
            _areasTemp.clearContents();
            removeOverlappingAreas(_areasToUpdateNonOverlappingRaw, _areasTemp);
            _areasToUpdateNonOverlappingRaw.clearContents();
            _areasToUpdateNonOverlappingRaw.pushBack(_areasTemp);
            assert(haveNoOverlap(_areasToUpdateNonOverlappingRaw[]));

            // Make _areasToUpdateNonOverlappingPBR disjointed
            _areasTemp.clearContents();
            removeOverlappingAreas(_areasToUpdateNonOverlappingPBR, _areasTemp);
            _areasToUpdateNonOverlappingPBR.clearContents();
            _areasToUpdateNonOverlappingPBR.pushBack(_areasTemp);
            assert(haveNoOverlap(_areasToUpdateNonOverlappingPBR[]));
        }

        // Compute _areasToRender and _areasToDisplay, purely derived from the above.
        // Note that they are possibly overlapping collections
        // _areasToComposite <- margin(_areasToUpdatePBR)
        // _areasToDisplay <- union(_areasToComposite, _areasToUpdateRaw)        
        {
            _areasToComposite.clearContents();            
            foreach(rect; _areasToUpdateNonOverlappingPBR)
            {
                assert(rect.isSorted);
                assert(!rect.empty);
                _areasToComposite.pushBack( convertPBRLayerRectToRawLayerRect(rect, _askedWidth, _askedHeight) );
            }

            _areasToDisplay.clearContents();
            _areasToDisplay.pushBack(_areasToComposite);
            foreach(rect; _areasToUpdateNonOverlappingRaw)
            {
                assert(rect.isSorted);
                assert(!rect.empty);
                _areasToDisplay.pushBack( rect );
            }
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
        _compositedBuffer = cast(ubyte*) alignedRealloc(_renderedBuffer, sizeNeeded, 16);
        _renderedBuffer = cast(ubyte*) alignedRealloc(_renderedBuffer, sizeNeeded, 16);

        ImageRef!RGBA wfb;
        wfb.w = _askedWidth;
        wfb.h = _askedHeight;
        wfb.pitch = byteStride(_askedWidth);
        wfb.pixels = cast(RGBA*)(_renderedBuffer);
        return wfb;
    }

    /// Draw the Raw layer of `UIElement` widgets
    void redrawElementsRaw() nothrow @nogc
    {
        enum bool parallelDraw = true;

        ImageRef!RGBA compositeRef;
        compositeRef.w = _askedWidth;
        compositeRef.h = _askedHeight;
        compositeRef.pitch = byteStride(_askedWidth);
        compositeRef.pixels = cast(RGBA*)(_renderedBuffer);

        _areasToDisplayNonOverlapping.clearContents();
        removeOverlappingAreas(_areasToDisplay, _areasToDisplayNonOverlapping);
        
        static if (parallelDraw)
        {
            int drawn = 0;
            int maxParallelElements = 32; // PERF: why this limit of 32??
            int N = cast(int)_elemsToDraw.length;

            while(drawn < N)
            {
                int canBeDrawn = 1; // at least one can be drawn without collision

                // Search max number of parallelizable draws until the end of the list or a collision is found
                bool foundIntersection = false;
                for ( ; (canBeDrawn < maxParallelElements) && (drawn + canBeDrawn < N); ++canBeDrawn)
                {
                    box2i candidate = _elemsToDraw[drawn + canBeDrawn].position;

                    for (int j = 0; j < canBeDrawn; ++j)
                    {
                        if (_elemsToDraw[drawn + j].position.intersects(candidate))
                        {
                            foundIntersection = true;
                            break;
                        }
                    }
                    if (foundIntersection)
                        break;
                }

                assert(canBeDrawn >= 1 && canBeDrawn <= maxParallelElements);

                // Draw a number of UIElement in parallel
                void drawOneItem(int i) nothrow @nogc
                {
                    _elemsToDraw[drawn + i].renderRaw(compositeRef, _areasToDisplayNonOverlapping[]);
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
                elem.renderRaw(compositeRef, _areasToDisplayNonOverlapping[]);
        }
    }

    /// Draw the PBR layer of `UIElement` widgets
    void redrawElementsPBR() nothrow @nogc
    {
        enum bool parallelDraw = true;

        auto diffuseRef = _diffuseMap.levels[0].toRef();
        auto depthRef = _depthMap.levels[0].toRef();
        auto materialRef = _materialMap.levels[0].toRef();

        static if (parallelDraw)
        {
            int drawn = 0;
            int maxParallelElements = 32; // PERF: why this limit of 32??
            int N = cast(int)_elemsToDraw.length;

            while(drawn < N)
            {
                int canBeDrawn = 1; // at least one can be drawn without collision

                // Search max number of parallelizable draws until the end of the list or a collision is found
                bool foundIntersection = false;
                for ( ; (canBeDrawn < maxParallelElements) && (drawn + canBeDrawn < N); ++canBeDrawn)
                {
                    box2i candidate = _elemsToDraw[drawn + canBeDrawn].position;

                    for (int j = 0; j < canBeDrawn; ++j)
                    {
                        if (_elemsToDraw[drawn + j].position.intersects(candidate))
                        {
                            foundIntersection = true;
                            break;
                        }
                    }
                    if (foundIntersection)
                        break;
                }

                assert(canBeDrawn >= 1 && canBeDrawn <= maxParallelElements);
 
                // Draw a number of UIElement in parallel
                void drawOneItem(int i) nothrow @nogc
                {
                    _elemsToDraw[drawn + i].renderPBR(diffuseRef, depthRef, materialRef, _areasToUpdateNonOverlappingPBR[]);
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
                elem.renderPBR(diffuseRef, depthRef, materialRef, _areasToUpdateNonOverlappingPBR[]);
        }
    }

    /// Compose lighting effects from depth and diffuse into a result.
    /// takes output image and non-overlapping areas as input
    /// Useful multithreading code.
    void compositeGUI(ImageRef!RGBA wfb, WindowPixelFormat pf) nothrow @nogc
    {
        // Was tuned for performance, maybe the tradeoff has changed now that we use LDC.
        enum tileWidth = 64;
        enum tileHeight = 32;

        _areasToCompositeNonOverlapping.clearContents();
        removeOverlappingAreas(_areasToComposite, _areasToCompositeNonOverlapping);

        _areasToCompositeNonOverlappingTiled.clearContents();
        tileAreas(_areasToCompositeNonOverlapping[], tileWidth, tileHeight,_areasToCompositeNonOverlappingTiled);

        int numAreas = cast(int)_areasToCompositeNonOverlappingTiled.length;

        void compositeOneTile(int i) nothrow @nogc
        {
            compositor.compositeTile(wfb, pf, _areasToCompositeNonOverlappingTiled[i],
                                     _diffuseMap, _materialMap, _depthMap, context.skybox);
        }
        _threadPool.parallelFor(numAreas, &compositeOneTile);
    }

    /// Compose lighting effects from depth and diffuse into a result.
    /// takes output image and non-overlapping areas as input
    /// Useful multithreading code.
    void regenerateMipmaps() nothrow @nogc
    {
        int numAreas = cast(int)_areasToUpdateNonOverlappingPBR.length;

        // Fill update rect buffer with the content of _areasToUpdateNonOverlapping
        for (int i = 0; i < 2; ++i)
        {
            _updateRectScratch[i].clearContents();
            _updateRectScratch[i].pushBack(_areasToUpdateNonOverlappingPBR[]);
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
}


enum scanLineAlignment = 4; // could be anything

// given a width, how long in bytes should scanlines be
int byteStride(int width) pure nothrow @nogc
{
    int widthInBytes = width * 4;
    return (widthInBytes + (scanLineAlignment - 1)) & ~(scanLineAlignment-1);
}
