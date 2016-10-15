/**
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
        _uiContext = mallocEmplace!UIContext();
        super(_uiContext);

        // Don't like the default rendering? Make another compositor.
        compositor = mallocEmplace!PBRCompositor();

        _windowListener = mallocEmplace!WindowListener(this);

        _window = null;
        _askedWidth = initialWidth;
        _askedHeight = initialHeight;

        _threadPool = mallocEmplace!ThreadPool();

        _areasToUpdateNonOverlapping = makeAlignedBuffer!box2i;
        _areasToUpdateTemp = makeAlignedBuffer!box2i;

        _updateRectScratch[0] = makeAlignedBuffer!box2i;
        _updateRectScratch[1] = makeAlignedBuffer!box2i;

        _areasToRender = makeAlignedBuffer!box2i;
        _areasToRenderNonOverlapping = makeAlignedBuffer!box2i;
        _areasToRenderNonOverlappingTiled = makeAlignedBuffer!box2i;

        _elemsToDraw = makeAlignedBuffer!UIElement;
        _elemsToDrawScratch = makeAlignedBuffer!UIElement;

        version(BenchmarkCompositing)
        {
            _compositingWatch = new StopWatch("Compositing = ");
            _drawWatch = new StopWatch("Draw = ");
            _mipmapWatch = new StopWatch("Mipmap = ");
        }

        _diffuseMap = mallocEmplace!(Mipmap!RGBA)();
        _materialMap = mallocEmplace!(Mipmap!RGBA)();
        _depthMap = mallocEmplace!(Mipmap!L16)();
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
        }

        // We create this window each time.
        _window = createWindow(parentInfo, controlInfo, _windowListener, wbackend, _askedWidth, _askedHeight);

        reflow(box2i(0, 0, _askedWidth, _askedHeight));

        // Sets the whole UI dirty
        setDirty();

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
            return outer._areasToRender[].boundingBox();
        }

        override ImageRef!RGBA onResized(int width, int height)
        {
            return outer.doResize(width, height);          
        }

        // Redraw dirtied controls in depth and diffuse maps.
        // Update composited cache.
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
    /// Too high and processing becomes very expensive.
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

    // The list of areas whose diffuse/depth data have been changed.
    AlignedBuffer!box2i _areasToUpdateNonOverlapping;

    // Used to maintain the _areasToUpdate invariant of no overlap
    AlignedBuffer!box2i _areasToUpdateTemp;

    // Same, but temporary variable for mipmap generation
    AlignedBuffer!box2i[2] _updateRectScratch;

    // The list of areas that must be effectively updated in the composite buffer
    // (sligthly larger than _areasToUpdate).
    AlignedBuffer!box2i _areasToRender;

    // same list, but reorganized to avoid overlap
    AlignedBuffer!box2i _areasToRenderNonOverlapping;

    // same list, but separated in smaller tiles
    AlignedBuffer!box2i _areasToRenderNonOverlappingTiled;

    // The list of UIElement to draw
    // Note: AlignedBuffer memory isn't scanned,
    //       but this doesn't matter since UIElement are the UI hierarchy anyway.
    AlignedBuffer!UIElement _elemsToDraw;

    /// Temporary buffer for stable sorting of _elemsToDraw
    AlignedBuffer!UIElement _elemsToDrawScratch;

    /// Amount of pixels dirty rectangles are extended with.
    int _updateMargin = 20;

    // The fully rendered framebuffer.
    // This should point into comitted virtual memory for faster (maybe) upload to device
    ubyte* _renderedBuffer = null;

    version(BenchmarkCompositing)
    {
        StopWatch _compositingWatch;
        StopWatch _mipmapWatch;
        StopWatch _drawWatch;
    }

    void doDraw(WindowPixelFormat pf) nothrow @nogc
    {
        ImageRef!RGBA wfb;
        wfb.w = _askedWidth;
        wfb.h = _askedHeight;
        wfb.pitch = byteStride(_askedWidth);
        wfb.pixels = cast(RGBA*)_renderedBuffer;

        // Composite GUI
        // Most of the cost of rendering is here
        version(BenchmarkCompositing)
            _drawWatch.start();

        renderElements();

        version(BenchmarkCompositing)
        {
            _drawWatch.stop();
            _drawWatch.displayMean();
        }

        version(BenchmarkCompositing)
            _mipmapWatch.start();

        // Split boxes to avoid overlapped work
        // Note: this is done separately for update areas and render areas
        _areasToRenderNonOverlapping.clearContents();
        removeOverlappingAreas(_areasToRender, _areasToRenderNonOverlapping);

        regenerateMipmaps();

        version(BenchmarkCompositing)
        {
            _mipmapWatch.stop();
            _mipmapWatch.displayMean();
        }

        version(BenchmarkCompositing)
            _compositingWatch.start();

        compositeGUI(wfb, pf);

        // only then is the list of rectangles to update cleared
        _areasToUpdateNonOverlapping.clearContents();

        version(BenchmarkCompositing)
        {
            _compositingWatch.stop();
            _compositingWatch.displayMean();
        }
    }

    // Fills _areasToUpdate and _areasToRender
    void recomputeDirtyAreas() nothrow @nogc
    {
        // Get areas to update
        _areasToRender.clearContents();

        // First we pull dirty rectangles from the UI
        context().dirtyList.pullAllRectangles(_areasToUpdateNonOverlapping);

        // TECHNICAL DEBT HERE
        // The problem here is that if the window isn't shown there may be duplicates in
        // _areasToUpdate, so we have to maintain unicity again
        // The code with dirty rects is a big mess, it needs a severe rewrite.
        //
        // SOLUTION
        // The fundamental problem is that dirtyList should probably be merged with
        // _areasToUpdateNonOverlapping.
        // _areasToRender should also be purely derived from _areasToUpdateNonOverlapping
        // Finally the interface of IWindowListener is poorly defined, this ties the window
        // to the renderer in a bad way.
        {
            _areasToUpdateTemp.clearContents();
            removeOverlappingAreas(_areasToUpdateNonOverlapping, _areasToUpdateTemp);
            _areasToUpdateNonOverlapping.clearContents();
            _areasToUpdateNonOverlapping.pushBack(_areasToUpdateTemp);
        }
        assert(haveNoOverlap(_areasToUpdateNonOverlapping[]));

        foreach(dirtyRect; _areasToUpdateNonOverlapping)
        {
            assert(dirtyRect.isSorted);
            assert(!dirtyRect.empty);
            _areasToRender.pushBack( extendsDirtyRect(dirtyRect, _askedWidth, _askedHeight) );
        }
    }

    box2i extendsDirtyRect(box2i rect, int width, int height) nothrow @nogc
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

        // TODO: maybe not destroy the whole mipmap?
        _diffuseMap.size(5, width, height);
        _depthMap.size(4, width, height);
        _materialMap.size(0, width, height);

        // Extends buffer
        size_t sizeNeeded = byteStride(width) * height;
        _renderedBuffer = cast(ubyte*) alignedRealloc(_renderedBuffer, sizeNeeded, 16);

        ImageRef!RGBA wfb;
        wfb.w = _askedWidth;
        wfb.h = _askedHeight;
        wfb.pitch = byteStride(_askedWidth);
        wfb.pixels = cast(RGBA*)(_renderedBuffer);
        return wfb;
    }

    /// Redraw UIElements
    void renderElements() nothrow @nogc
    {
        // recompute draw list
        _elemsToDraw.clearContents();
        getDrawList(_elemsToDraw);

        // Sort by ascending z-order (high z-order gets drawn last)
        // This sort must be stable to avoid messing with tree natural order.
        _elemsToDrawScratch.resize(_elemsToDraw.length);
        int compareZOrder(in UIElement a, in UIElement b) nothrow @nogc
        {
            return a.zOrder() - b.zOrder();
        }
        mergeSort!UIElement(_elemsToDraw[], _elemsToDrawScratch[] , &compareZOrder);

        enum bool parallelDraw = true;

        auto diffuseRef = _diffuseMap.levels[0].toRef();
        auto depthRef = _depthMap.levels[0].toRef();
        auto materialRef = _materialMap.levels[0].toRef();

        static if (parallelDraw)
        {
            int drawn = 0;
            int maxParallelElements = 32;
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
                    _elemsToDraw[drawn + i].render(diffuseRef, depthRef, materialRef, _areasToUpdateNonOverlapping[]);
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
                elem.render(diffuseRef, depthRef, _areasToUpdate[]);
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

        _areasToRenderNonOverlappingTiled.clearContents();
        tileAreas(_areasToRenderNonOverlapping[], tileWidth, tileHeight,_areasToRenderNonOverlappingTiled);

        int numAreas = cast(int)_areasToRenderNonOverlappingTiled.length;

        void compositeOneTile(int i) nothrow @nogc
        {
            compositor.compositeTile(wfb, pf, _areasToRenderNonOverlappingTiled[i],
                                     _diffuseMap, _materialMap, _depthMap, context.skybox);
        }
        _threadPool.parallelFor(numAreas, &compositeOneTile);
    }

    /// Compose lighting effects from depth and diffuse into a result.
    /// takes output image and non-overlapping areas as input
    /// Useful multithreading code.
    void regenerateMipmaps() nothrow @nogc
    {
        int numAreas = cast(int)_areasToUpdateNonOverlapping.length;

        // Fill update rect buffer with the content of _areasToUpdateNonOverlapping
        for (int i = 0; i < 2; ++i)
        {
            _updateRectScratch[i].clearContents();
            _updateRectScratch[i].pushBack(_areasToUpdateNonOverlapping[]);
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
