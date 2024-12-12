/**
* A GUIGraphics is the interface between a plugin client and a IWindow.
*
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.graphics;

import core.atomic;
import core.stdc.stdio;

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
import dplug.gui.profiler;

/// In the whole package:
/// The diffuse maps contains:
///   RGBA = red/green/blue/emissiveness
/// The depth maps contains depth (0 being lowest, 65535 highest)
/// The material map contains:
///   RGBA = roughness / metalness / specular / unused

alias RMSP = RGBA; // reminder

// Uncomment to enter the marvellous world of dirty rectangles.
//debug = resizing;

// A GUIGraphics is the interface between a plugin client and a IWindow.
// It is also an UIElement and the root element of the plugin UI hierarchy.
// You have to derive it to have a GUI.
// It dispatches window events to the GUI hierarchy.
class GUIGraphics : UIElement, IGraphics
{
nothrow:
@nogc:

    // Max size of tiles when doing the expensive PBR compositing step.
    // Difficult trade-off in general: not launching threads (one tile) might be better on low-powered devices and 
    // in case of a large number of opened UI.
    // But: having too large tiles also makes a visible delay when operating a single UI, even with only two threads.
    enum PBR_TILE_MAX_WIDTH = 64;
    enum PBR_TILE_MAX_HEIGHT = 64;

    this(SizeConstraints sizeConstraints, UIFlags flags)
    {
        _sizeConstraints = sizeConstraints;

        _uiContext = mallocNew!UIContext(this);
        super(_uiContext, flags);

        _windowListener = mallocNew!WindowListener(this);

        _window = null;

        // Find what size the UI should at first opening.
        _sizeConstraints.suggestDefaultSize(&_currentUserWidth, &_currentUserHeight);
        _currentLogicalWidth  = _currentUserWidth;
        _currentLogicalHeight = _currentUserHeight;
        _desiredLogicalWidth  = _currentUserWidth;
        _desiredLogicalHeight = _currentUserHeight;

        int numThreads = 0; // auto

        // Was lowered to 2 in October 2018 to save CPU usage.
        // Now in Jan 2023, increased to 3 to have a bit smoother PBR.
        // FUTURE: could make that 4 eventually, see Issue #752. This has minimal memory and CPU 
        // costs, but is worse on slower plugins.
        int maxThreads = 3;
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
        _sortScratchBuf = makeVec!UIElement;

        _diffuseMap = mallocNew!(Mipmap!RGBA)();
        _materialMap = mallocNew!(Mipmap!RGBA)();
        _depthMap = mallocNew!(Mipmap!L16)();

        _compositedBuffer = mallocNew!(OwnedImage!RGBA)();
        _renderedBuffer = mallocNew!(OwnedImage!RGBA)();
    }

    // Don't like the default rendering? Override this function and make another compositor.
    ICompositor buildCompositor(CompositorCreationContext* context)
    {
        return mallocNew!PBRCompositor(context);
    }

    /// Want a screenshot? Want to generate a mesh or a voxel out of your render?
    /// Override this function and call `IUIContext.requestUIScreenshot()`
    ///
    /// Params: pf Pixel format. pixelFormat == 0 if pixel format is RGBA8
    ///                          pixelFormat == 1 if pixel format is BGRA8
    ///                          pixelFormat == 2 if pixel format is ARGB8
    ///                          You must support all three, sorry.
    /// All maps have the same dimension, which is the logical pixel size. 
    /// Warning: nothing to do with the Screencap key, it doesn't get triggered like that.
    void onScreenshot(ImageRef!RGBA finalRender,    // the output, as show to the plugin user
                      WindowPixelFormat pixelFormat,// pixel format of `finalRender`, see above
                      ImageRef!RGBA diffuseMap,     // the PBR diffuse map
                      ImageRef!L16 depthMap,        // the PBR depth map
                      ImageRef!RGBA materialMap)    // the PBR material map
    {
        // override this to take programmatic screenshots
        // eg: generate a .vox, .png, etc.
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

        destroyFree(_compositedBuffer);
        destroyFree(_renderedBuffer);

        alignedFree(_resizedBuffer, 16);
    }

    // <IGraphics implementation>

    override void* openUI(void* parentInfo,
                          void* controlInfo,
                          IClient client,
                          GraphicsBackend backend)
    {
        _client = client;

        WindowBackend wbackend = void;
        final switch(backend)
        {
            case GraphicsBackend.autodetect: wbackend = WindowBackend.autodetect; break;
            case GraphicsBackend.win32: wbackend = WindowBackend.win32; break;
            case GraphicsBackend.cocoa: wbackend = WindowBackend.cocoa; break;
            case GraphicsBackend.x11: wbackend = WindowBackend.x11; break;
        }

        position = box2i(0, 0, _currentUserWidth, _currentUserHeight);

        // Sets the whole UI dirty.
        // This needs to be done _before_ window creation, else there could be a race
        // displaying partial updates to the UI.
        setDirtyWhole(UILayer.allLayers);

        // We create this window each time.
        _window = createWindow(WindowUsage.plugin, parentInfo, controlInfo, _windowListener, wbackend, _currentLogicalWidth, _currentLogicalHeight);

        version(Dplug_ProfileUI) profiler.category("ui").instant("Open UI");

        return _window.systemHandle();
    }

    override void closeUI()
    {
        // Destroy window.
        if (_window !is null)
        {
            version(Dplug_ProfileUI)
            {
                profiler.category("ui").instant("Close UI");
            }

            _window.destroyFree();
            _window = null;
        }
        _client = null;
    }

    override void getGUISize(int* widthLogicalPixels, int* heightLogicalPixels)
    {
        *widthLogicalPixels  = _currentLogicalWidth;
        *heightLogicalPixels = _currentLogicalHeight;
    }

    override void getDesiredGUISize(int* widthLogicalPixels, int* heightLogicalPixels)
    {
        *widthLogicalPixels  = _desiredLogicalWidth;
        *heightLogicalPixels = _desiredLogicalHeight;
    }

    override bool isResizeable()
    {
        return isUIResizable();
    }

    override bool isAspectRatioPreserved()
    {
        if (!isUIResizable()) return false;
        return _sizeConstraints.preserveAspectRatio();
    }

    override int[2] getPreservedAspectRatio()
    {
        return _sizeConstraints.aspectRatio();
    }

    override bool isResizeableHorizontally()
    {
        return _sizeConstraints.canResizeHorizontally();
    }

    override bool isResizeableVertically()
    {
        return _sizeConstraints.canResizeVertically();
    }

    override void getMaxSmallerValidSize(int* inoutWidth, int* inoutHeight)
    {
        _sizeConstraints.getMaxSmallerValidSize(inoutWidth, inoutHeight);
    }

    override void getNearestValidSize(int* inoutWidth, int* inoutHeight)
    {
        _sizeConstraints.getNearestValidSize(inoutWidth, inoutHeight);
    }

    override bool nativeWindowResize(int newWidthLogicalPixels, int newHeightLogicalPixels)
    {
        // If it's already the same logical size, nothing to do.
        if ( (newWidthLogicalPixels == _currentLogicalWidth)
             &&  (newHeightLogicalPixels == _currentLogicalHeight) )
            return true;

        // Issue #669.
        // Can't resize a non-existing window, return failure.
        // Hosts where this is needed: VST3PluginTestHost
        // It calls onSize way too soon.
        if (_window is null)
            return false;

        // Here we request the native window to resize.
        // The actual resize will be received by the window listener, later.
        return _window.requestResize(newWidthLogicalPixels, newHeightLogicalPixels, false);
    }

    // </IGraphics implementation>

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

            // Sends the event to the currently dragged element, if any exists.
            UIElement dragged = outer._uiContext.dragged;
            if (dragged !is null)
            {
                box2i pos = dragged._position;
                if (dragged.onMouseWheel(x - pos.min.x, y - pos.min.y, wheelDeltaX, wheelDeltaY, mstate))
                    return true;
            }

            return outer.mouseWheel(x, y, wheelDeltaX, wheelDeltaY, mstate);
        }

        override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
        {
            x -= outer._userArea.min.x;
            y -= outer._userArea.min.y;
            bool hitSomething = outer.mouseMove(x, y, dx, dy, mstate, false);
            version(legacyMouseDrag)
            {
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
            box2i r = outer._rectsToResize[].boundingBox();

            // If _userArea changed recently, mark the whole area as in need of redisplay.
            if (outer._reportBlackBordersAndResizedAreaAsDirty)
                r = r.expand( box2i(0, 0, outer._currentLogicalWidth, outer._currentLogicalHeight) );

            debug(resizing)
            {
                if (!r.empty)
                {
                    debugLogf("getDirtyRectangle returned rectangle(%d, %d, %d, %d)\n", r.min.x, r.min.y, r.width, r.height);
                }
            }

            return r;
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

        override void onMouseExitedWindow()
        {
            // Stop an eventual isMouseOver
            version(legacyMouseDrag)
            {
                outer._uiContext.setMouseOver(null);
            }
            else
            {
                if (outer._uiContext.dragged is null)
                    outer._uiContext.setMouseOver(null);
            }
        }

        override void onAnimate(double dt, double time)
        {
            version(Dplug_ProfileUI) outer.profiler.category("ui").begin("animate");
            outer.animate(dt, time);
            version(Dplug_ProfileUI) outer.profiler.end();
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
    /// IMPORTANT: This should be called only inside your main reflow() or at UI creation time.
    void setUpdateMargin(int margin = 20) nothrow @nogc
    {
        _updateMargin = margin; // theoretically it should dirty every PBR rectangle... hence restricting to reflow().
    }

package:

    // <resizing support>

    final float getUIScale()
    {
        // There is currently no support for this in Dplug, so it is always 1.0f for now.
        // The OS _might_ upscale the UI without our knowledge though.
        return 1.0f;
    }

    final float getUserScale()
    {
        // There is currently no _userArea resize in Dplug, so it is always 1.0f for now.
        return 1.0f;
    }

    final vec2i getDefaultUISizeInPixels()
    {
        int w = 0, h = 0;
        _sizeConstraints.suggestDefaultSize(&w, &h);
        return vec2i(w, h);
    }

    final vec2i getUISizeInPixelsUser()
    {
        return vec2i(_currentUserWidth, _currentUserHeight);
    }

    final vec2i getUISizeInPixelsLogical()
    {
        return vec2i(_currentLogicalWidth, _currentLogicalHeight);
    }

    final vec2i getUISizeInPixelsPhysical()
    {
        return getUISizeInPixelsLogical(); // no support yet
    }

    final void requestUIScreenshot()
    {
        atomicStore(_screenShotRequested, true);
    }

    final bool requestUIResize(int widthLogicalPixels,
                               int heightLogicalPixels)
    {
        _desiredLogicalWidth  = widthLogicalPixels;
        _desiredLogicalHeight = heightLogicalPixels;

        // If it's already the same logical size, nothing to do.
        if ( (widthLogicalPixels == _currentLogicalWidth)
            &&  (heightLogicalPixels == _currentLogicalHeight) )
            return true;

        // Note: the client might ask back the plugin size inside this call!
        // Hence why we have the concept of "desired" size.
        bool parentWasResized = _client.requestResize(widthLogicalPixels, heightLogicalPixels);

        // We do not "desire" something else than the current situation, at this point this is in our hands.
        _desiredLogicalWidth  = _currentLogicalWidth;
        _desiredLogicalHeight = _currentLogicalHeight;

        // We are be able to early-exit here in VST3.
        // This is because once a VST3 host has resized the parent window, it calls a callback
        // and that leads to `nativeWindowResize` to be called.
        if (parentWasResized && (_client.getPluginFormat() == PluginFormat.vst3))
            return true;

        // Cubase + VST2 + Windows need special treatment to resize parent and grandparent windows manually (Issue #595).
        bool needResizeParentWindow = false;
        version(Windows)
        {
            if (_client.getPluginFormat() == PluginFormat.vst2 && _client.getDAW() == DAW.Cubase)
                needResizeParentWindow = true;
        }

        // In VST2, very few hosts also resize the plugin window. We get to do it manually.

        // Here we request the native window to resize.
        // The actual resize will be received by the window listener, later.
        bool success = _window.requestResize(widthLogicalPixels, heightLogicalPixels, needResizeParentWindow);

        // FL Studio format is different, the host needs to be notified _after_ a manual resize.
        if (success && _client.getPluginFormat() == PluginFormat.flp)
        {
            success = _client.notifyResized;
        }
        return success;
    }

    final void getUINearestValidSize(int* widthLogicalPixels, int* heightLogicalPixels)
    {
        // Convert this size to a user width and height
        int userWidth = cast(int)(0.5f + *widthLogicalPixels * getUserScale());
        int userHeight = cast(int)(0.5f + *heightLogicalPixels * getUserScale());

        _sizeConstraints.getNearestValidSize(&userWidth, &userHeight);

        // Convert back to logical pixels
        // Note that because of rounding, there might be small problems yet unsolved.
        *widthLogicalPixels = cast(int)(0.5f + userWidth / getUserScale());
        *heightLogicalPixels = cast(int)(0.5f + userHeight / getUserScale());
    }

    final bool isUIResizable()
    {
        // TODO: allow logic resize if internally user area is resampled
        return _sizeConstraints.isResizable();
    }
    // </resizing support>

protected:

    // The link to act on the client through the interface.
    // Eventually it may supersedes direct usage of the client, or its IHostCommand in UIElements.
    // Only valid in a openUI/closeUI pair.
    IClient _client;

    ICompositor _compositor;

    UIContext _uiContext;

    WindowListener _windowListener;

    // An interface to the underlying window
    IWindow _window;

    // Task pool for multi-threaded image work
    package ThreadPool _threadPool;

    // Size constraints of this UI.
    // Currently can only be a fixed size.
    SizeConstraints _sizeConstraints;

    // The _external_ size in pixels of the plugin interface.
    // This is the size seen by the host/window.
    int _currentLogicalWidth = 0;
    int _currentLogicalHeight = 0;

    // The _desired_ size in pixels of the plugin interface.
    // It is only different from _currentLogicalWidth / _currentLogicalHeight 
    // during a resize (since the host could query the desired size there).
    // Not currently well separated unfortunately, it is seldom used.
    int _desiredLogicalWidth = 0;
    int _desiredLogicalHeight = 0;

    // The _internal_ size in pixels of our UI.
    // This is not the same as the size seen by the window ("logical").
    int _currentUserWidth = 0;
    int _currentUserHeight = 0;

    /// the area in logical area where the user area is drawn.
    box2i _userArea;

    // Force userArea refresh on first resize.
    bool _firstResize = true;

    // if true, it means the whole resize buffer and accompanying black
    // borders should be redrawn at the next onDraw
    bool _redrawBlackBordersAndResizedArea;

    // if true, it means the whole resize buffer and accompanying black
    // borders should be reported as dirty at the next recomputeDirtyAreas, and until
    // it is drawn.
    bool _reportBlackBordersAndResizedAreaAsDirty;

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

    // The areas that must be effectively redisplayed, in logical space (like _userArea).
    Vec!box2i _rectsToResize;
    Vec!box2i _rectsToResizeDisjointed;

    /// The list of UIElement to potentially call `onDrawPBR` on.
    Vec!UIElement _elemsToDrawRaw;

    /// The list of UIElement to potentially call `onDrawPBR` on.
    Vec!UIElement _elemsToDrawPBR;

    /// The scratch buffer used to sort the two above list.
    Vec!UIElement _sortScratchBuf;

    /// Amount of pixels dirty rectangles are extended with.
    int _updateMargin = 20;

    /// The composited buffer, before the Raw layer is applied.
    OwnedImage!RGBA _compositedBuffer = null;

    /// The rendered framebuffer.
    /// This is copied from `_compositedBuffer`, then Raw layer is drawn on top.
    /// Components are reordered there.
    /// It must be possible to use a Canvas on it.
    OwnedImage!RGBA _renderedBuffer = null;

    /// The final framebuffer.
    /// It is the only buffer to have a size in logical pixels.
    /// Internally the UI has an "user" size.
    /// FUTURE: resize from user size to logical size using a resizer,
    /// to allow better looking DPI without the OS blurry resizing.
    /// Or to allow higher internal pixel count.
    ubyte* _resizedBuffer = null;

    /// If a screenshot was requested by user widget.
    shared(bool) _screenShotRequested = false;

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
        timSort!UIElement(_elemsToDrawRaw[], _sortScratchBuf, &compareZOrder);
        timSort!UIElement(_elemsToDrawPBR[], _sortScratchBuf, &compareZOrder);
    }

    // Useful to convert 16-byte aligned buffer into an ImageRef!RGBA
    // This was probably still needed because of Issue #693. This was secretly a 
    // workaround. FUTURE: replace by regular toRef
    final ImageRef!RGBA toImageRef(ubyte* alignedBuffer, int width, int height)
    {
        ImageRef!RGBA ir = void;
        ir.w = width;
        ir.h = height;
        ir.pitch = byteStride(width);
        ir.pixels = cast(RGBA*)alignedBuffer;
        return ir;
    }

    IProfiler profiler()
    {
        return _uiContext.profiler();
    }

    void doDraw(WindowPixelFormat pf) nothrow @nogc
    {
        version(Dplug_ProfileUI) profiler.category("ui").begin("doDraw");

        debug(resizing) debugLogf(">doDraw\n");

        debug(resizing)
        {
            foreach(r; _rectsToUpdateDisjointedPBR[])
            {
                debugLogf("  * this will redraw PBR rectangle(%d, %d, %d, %d)\n", r.min.x, r.min.y, r.width, r.height);
            }
            foreach(r; _rectsToUpdateDisjointedRaw[])
            {
                debugLogf("  * this will redraw RAW rectangle(%d, %d, %d, %d)\n", r.min.x, r.min.y, r.width, r.height);
            }
        }

        // A. Recompute draw lists
        // These are the `UIElement`s that _may_ have their onDrawXXX callbacks called.

        version(Dplug_ProfileUI) profiler.begin("Recompute Draw Lists");
        recomputeDrawLists();
        version(Dplug_ProfileUI) profiler.end();

        // Composite GUI
        // Most of the cost of rendering is here
        // B. 1st PASS OF REDRAW
        // Some UIElements are redrawn at the PBR level
        version(Dplug_ProfileUI) profiler.begin("Draw Elements PBR");
        redrawElementsPBR();
        version(Dplug_ProfileUI) profiler.end();

        // C. MIPMAPPING
        version(Dplug_ProfileUI) profiler.begin("Regenerate Mipmaps");
        regenerateMipmaps();
        version(Dplug_ProfileUI) profiler.end();

        // D. COMPOSITING
        auto compositedRef = _compositedBuffer.toRef();

        version(Dplug_ProfileUI) profiler.begin("Composite GUI");
        compositeGUI(compositedRef); // Launch the possibly-expensive Compositor step, which implements PBR rendering
        version(Dplug_ProfileUI) profiler.end();

        // E. COPY FROM "COMPOSITED" TO "RENDERED" BUFFER
        // Copy _compositedBuffer onto _renderedBuffer for every rect that will be changed on display
        auto renderedRef = _renderedBuffer.toRef();
        version(Dplug_ProfileUI) profiler.begin("Copy to renderbuffer");
        foreach(rect; _rectsToDisplayDisjointed[])
        {
            auto croppedComposite = compositedRef.cropImageRef(rect);
            auto croppedRendered = renderedRef.cropImageRef(rect);
            croppedComposite.blitTo(croppedRendered); // failure to optimize this: 1
        }
        version(Dplug_ProfileUI) profiler.end();
        
        // F. 2nd PASS OF REDRAW
        version(Dplug_ProfileUI) profiler.begin("Draw Elements Raw");
        redrawElementsRaw();
        version(Dplug_ProfileUI) profiler.end();

        // G. Reorder components to the right pixel format
        version(Dplug_ProfileUI) profiler.begin("Component Reorder");
        reorderComponents(pf);
        version(Dplug_ProfileUI) profiler.end();

        // G.bis
        // We have a render.
        // Eventually make a screenshot here, if one was requested asynchronously.
        if (cas(&_screenShotRequested, true, false))
        {
            onScreenshot(_renderedBuffer.toRef(), 
                         pf, 
                         _diffuseMap.levels[0].toRef,
                         _depthMap.levels[0].toRef,
                         _materialMap.levels[0].toRef);
        }

        // H. Copy updated content to the final buffer. (hint: not actually resizing)
        version(Dplug_ProfileUI) profiler.begin("Copy content");
        resizeContent(pf);
        version(Dplug_ProfileUI) profiler.end();

        // Only then is the list of rectangles to update cleared,
        // before calling `doDraw` such work accumulates
        _rectsToUpdateDisjointedPBR.clearContents();
        _rectsToUpdateDisjointedRaw.clearContents();

        version(Dplug_ProfileUI) profiler.end();
        debug(resizing) debugLogf("<doDraw\n");
    }

    void recomputeDirtyAreas() nothrow @nogc
    {
        // First we pull dirty rectangles from the UI, for the PBR and Raw layers
        // Note that there is indeed a race here (the same UIElement could have pushed rectangles in both
        // at around the same time), but that isn't a problem.
        context().dirtyListRaw.pullAllRectangles(_rectsToUpdateDisjointedRaw);
        context().dirtyListPBR.pullAllRectangles(_rectsToUpdateDisjointedPBR);

        recomputePurelyDerivedRectangles();
    }

    void recomputePurelyDerivedRectangles()
    {
        // If a resize has been made recently, we need to clip rectangles
        // in the pending lists to the new size.
        // All other rectangles are purely derived from those.
        // PERF: this check is necessary because of #597.
        //       Solveing this is a long-term quest in itself.
        box2i validUserArea = rectangle(0, 0, _currentUserWidth, _currentUserHeight);
        foreach (ref r; _rectsToUpdateDisjointedRaw[])
        {
            r = r.intersection(validUserArea);
        }
        foreach (ref r; _rectsToUpdateDisjointedPBR[])
        {
            r = r.intersection(validUserArea);
        }

        // The problem here is that if the window isn't shown there may be duplicates in
        // _rectsToUpdateDisjointedRaw and _rectsToUpdateDisjointedPBR
        // (`recomputeDirtyAreas`called multiple times without clearing those arrays),
        //  so we have to maintain unicity again.
        // Also duplicate can accumulate in case of two successive onResize (to test: Studio One with continuous resizing plugin)
        //
        // PERF: when the window is shown, we could overwrite content of _rectsToUpdateDisjointedRaw/_rectsToUpdateDisjointedPBR?
        //       instead of doing that.
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

            if (_reportBlackBordersAndResizedAreaAsDirty)
            {
                // Redraw whole resized zone and black borders on next draw, as this will
                // be reported to the OS as being repainted.
                _redrawBlackBordersAndResizedArea = true;
            }
            _rectsToResizeDisjointed.clearContents();
            removeOverlappingAreas(_rectsToResize, _rectsToResizeDisjointed);

            // All those rectangles should be strictly in _userArea
            foreach(r; _rectsToResizeDisjointed)
                assert(_userArea.contains(r));
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
        version(Dplug_ProfileUI) profiler.category("ui").begin("doResize");
        debug(resizing) debugLogf(">doResize(%d, %d)\n", widthLogicalPixels, heightLogicalPixels);

        /// We do receive a new size in logical pixels.
        /// This is coming from getting the window client area. The reason
        /// for this resize doesn't matter, we must find a mapping that fits
        /// between this given logical size and user size.

        // 1.a Based upon the _sizeConstraints, select a user size in pixels.
        //     Keep in mind if the _userArea has just moved (just moving the contents elsewhere)
        //     or if its size has changed (user size), which require a redraw.

        // Has the logical available size changed?
        bool logicalSizeChanged = false;
        if (_currentLogicalWidth != widthLogicalPixels)
        {
            _currentLogicalWidth = widthLogicalPixels;
            logicalSizeChanged = true;
        }
        if (_currentLogicalHeight != heightLogicalPixels)
        {
            _currentLogicalHeight = heightLogicalPixels;
            logicalSizeChanged = true;
        }

        int newUserWidth = widthLogicalPixels;
        int newUserHeight = heightLogicalPixels;
        _sizeConstraints.getMaxSmallerValidSize(&newUserWidth, &newUserHeight);

        bool userSizeChanged = false;
        if (_currentUserWidth != newUserWidth)
        {
            _currentUserWidth = newUserWidth;
            userSizeChanged = true;
        }
        if (_currentUserHeight != newUserHeight)
        {
            _currentUserHeight = newUserHeight;
            userSizeChanged = true;
        }

        // On first onResize, assume both sizes changed
        if (_firstResize)
        {
            logicalSizeChanged = true;
            userSizeChanged = true;
            _firstResize = false;
        }

        if (userSizeChanged) { assert(logicalSizeChanged); }

        // 1.b Update user area rect. We find a suitable space in logical area
        //     to draw the whole UI.
        if (logicalSizeChanged)
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

            debug(resizing)
            {
                debugLogf("new _userArea is rectangle(%d, %d, %d, %d)\n", x, y, w, h);
            }

            _reportBlackBordersAndResizedAreaAsDirty = true;

            // Note: out of range rectangles will still be in the dirtyListRaw/dirtyListPBR
            // and also _rectsToUpdateDisjointedPBR/_rectsToUpdateDisjointedRaw
            // This is the dreaded Issue #597
            // Unicity and boundness is maintained inside recomputePurelyDerivedRectangles().

            // The user size has changed. Force an immediate full redraw, so that no ancient data is used.
            // Not that this is on top of previous resizes or pulled rectangles in 
            // _rectsToUpdateDisjointedPBR / _rectsToUpdateDisjointedRaw.
            if (userSizeChanged)
            {
                debug(resizing) debugLogf("  * provoke full redraw\n");
                _rectsToUpdateDisjointedPBR.pushBack( rectangle(0, 0, _userArea.width, _userArea.height) );
            }

            // This avoids an onDraw with wrong rectangles
            recomputePurelyDerivedRectangles();
        }

        // 2. Invalidate UI region if user size change.
        //    Note: _resizedBuffer invalidation is managed with flags instead of this.
        position = box2i(0, 0, _currentUserWidth, _currentUserHeight);

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

        int border_0 = 0;
        int rowAlign_16 = 16;
        int trailingSamples_0 = 0;
        int trailingSamples_3 = 3;
        _compositedBuffer.size(_currentUserWidth, _currentUserHeight, border_0, rowAlign_16, xMultiplicity_1, trailingSamples_0);
        _renderedBuffer.size(_currentUserWidth, _currentUserHeight, border_0, rowAlign_16, xMultiplicity_1, trailingSamples_3);

        // Extends final buffer with logical size
        //
        // Why one line more with the +1? This is to fixIssue #741 and all other related macOS bugs.
        // This workarounds an Apple bug that made a lot of crashed between Nov2022 and Jan2024.
        size_t sizeNeeded = byteStride(_currentLogicalWidth) * (_currentLogicalHeight + 1);


        _resizedBuffer = cast(ubyte*) alignedRealloc(_resizedBuffer, sizeNeeded, 16);

        debug(resizing) debugLogf("<doResize(%d, %d)\n", widthLogicalPixels, heightLogicalPixels);

        version(Dplug_ProfileUI) profiler.end();

        return toImageRef(_resizedBuffer, _currentLogicalWidth, _currentLogicalHeight);
    }

    /// Draw the Raw layer of `UIElement` widgets
    void redrawElementsRaw() nothrow @nogc
    {
        enum bool parallelDraw = true;

        ImageRef!RGBA renderedRef = _renderedBuffer.toRef();

        // No need to launch threads only to have them realize there isn't anything to do
        if (_rectsToDisplayDisjointed.length == 0)
            return;

        static if (parallelDraw)
        {
            int drawn = 0;
            int N = cast(int)_elemsToDrawRaw.length;

            while(drawn < N)
            {
                // See: redrawElementsPBR below for a remark on performance there.

                int canBeDrawn = 1; // at least one can be drawn without collision

                // Does this first widget in the FIFO wants to be draw alone?
                if (! _elemsToDrawRaw[drawn].isDrawAloneRaw())
                {
                    // Search max number of parallelizable draws until the end of the list or a collision is found
                    bool foundIntersection = false;
                    for ( ; (drawn + canBeDrawn < N); ++canBeDrawn)
                    {
                        // Should we include this element to the assembled set of widgets to draw?
                        UIElement candidateWidget = _elemsToDrawRaw[drawn + canBeDrawn];

                        if (candidateWidget.isDrawAloneRaw())
                            break; // wants to be drawn alone

                        box2i candidatePos = candidateWidget.position;

                        for (int j = 0; j < canBeDrawn; ++j) // PERF: aaaand this is nicely quadratic
                        {
                            if (_elemsToDrawRaw[drawn + j].position.intersects(candidatePos))
                            {
                                foundIntersection = true;
                                break;
                            }
                        }
                        if (foundIntersection)
                            break;
                    }
                }

                assert(canBeDrawn >= 1);

                // Draw a number of UIElement in parallel
                void drawOneItem(int i, int threadIndex) nothrow @nogc
                {
                    version(Dplug_ProfileUI) 
                    {
                        char[maxUIElementIDLength + 16] idstr;
                        snprintf(idstr.ptr, 128, 
                                 "draw Raw element %s".ptr, _elemsToDrawRaw[drawn + i].getId().ptr);
                        profiler.category("draw").begin(idstr);
                    }

                    _elemsToDrawRaw[drawn + i].renderRaw(renderedRef, _rectsToDisplayDisjointed[]);

                    version(Dplug_ProfileUI) profiler.end();
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

        assert(_diffuseMap.levels[0] !is null);
        assert(_depthMap.levels[0] !is null);
        assert(_materialMap.levels[0] !is null);
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
                // <Scheduling remark>
                // PERF: scheduling here is not entirely optimal: consecutive overalapping widgets 
                // would block further parallel draw if the next widget doesn't overlap the other two.
                //
                //  ________          _____
                //  |      |          |   |
                //  |  B   |______    | C |      <---- Will not draw A and C in parallel if
                //  |______|     |    |___|            Z(A) < Z(B) < Z(C)
                //      |    A   |
                //      |________|
                //
                // PERF: to go further, could use the disjointed rects to draw even more in parallel. 
                // Real updated graphics is intersection(position, union(_rectsToUpdateDisjointedPBR)),
                // not simply the widget position.
                // </Scheduling remark>

                int canBeDrawn = 1; // at least one can be drawn without collision

                // Does this first widget in the FIFO wants to be draw alone?
                if (! _elemsToDrawPBR[drawn].isDrawAlonePBR())
                {
                    // Search max number of parallelizable draws until the end of the list or a collision is found
                    bool foundIntersection = false;
                    for ( ; (drawn + canBeDrawn < N); ++canBeDrawn)
                    {
                        // Should we include this element to the assembled set of widgets to draw?
                        UIElement candidateWidget = _elemsToDrawPBR[drawn + canBeDrawn];

                        if (candidateWidget.isDrawAlonePBR())
                            break; // wants to be drawn alone

                        box2i candidatePos = _elemsToDrawPBR[drawn + canBeDrawn].position;

                        for (int j = 0; j < canBeDrawn; ++j) // check with each former selected widget, PERF quadratic
                        {
                            if (_elemsToDrawPBR[drawn + j].position.intersects(candidatePos))
                            {
                                foundIntersection = true;
                                break;
                            }
                        }
                        if (foundIntersection)
                            break;
                    }
                }

                assert(canBeDrawn >= 1);

                // Draw a number of UIElement in parallel
                void drawOneItem(int i, int threadIndex) nothrow @nogc
                {
                    version(Dplug_ProfileUI) 
                    {
                        char[maxUIElementIDLength + 16] idstr;
                        snprintf(idstr.ptr, 128, 
                                 "draw PBR element %s", _elemsToDrawPBR[drawn + i].getId().ptr);
                        profiler.category("draw").begin(idstr);
                    }

                    _elemsToDrawPBR[drawn + i].renderPBR(diffuseRef, depthRef, materialRef, _rectsToUpdateDisjointedPBR[]);

                    version(Dplug_ProfileUI) profiler.end();
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
                                  _depthMap,
                                  profiler());
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

        version(Dplug_ProfileUI) profiler.category("mipmap").begin("diffuse mipmap");

        // Generate diffuse mipmap, useful for dealing with emissive
        {
            // diffuse
            Mipmap!RGBA mipmap = _diffuseMap;
            foreach(level; 1 .. mipmap.numLevels())
            {
                Mipmap!RGBA.Quality quality;
                if (level == 1)
                    quality = Mipmap!RGBA.Quality.boxAlphaCovIntoPremul;
                else
                    quality = Mipmap!RGBA.Quality.cubic;
                foreach(ref area; _updateRectScratch[0])
                {
                    // Note: the rects might be disjointed, but each leveling up makes them
                    // Possibly overlapping. It is assumed the cost is minor.
                    // Some pixels in higher mipmap levels might be computed several times.
                    area = mipmap.generateNextLevel(quality, area, level);
                }
            }
        }

        version(Dplug_ProfileUI) profiler.end;

        version(Dplug_ProfileUI) profiler.begin("depth mipmap");

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

        version(Dplug_ProfileUI) profiler.end;
    }

    void reorderComponents(WindowPixelFormat pf)
    {
        auto renderedRef = _renderedBuffer.toRef();

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

        auto renderedRef = _renderedBuffer.toRef();
        auto resizedRef = toImageRef(_resizedBuffer, _currentLogicalWidth, _currentLogicalHeight);

        box2i[] rectsToCopy = _rectsToResizeDisjointed[];

        // If invalidated, the whole buffer needs to be redrawn
        // (because of borders, or changing offsets of the user area).
        if (_redrawBlackBordersAndResizedArea)
        {
            debug(resizing) debugLogf("  * redrawing black borders, and copy item\n");
            RGBA black;
            final switch(pf)
            {
                case WindowPixelFormat.RGBA8:
                case WindowPixelFormat.BGRA8: black = RGBA(0, 0, 0, 255); break;
                case WindowPixelFormat.ARGB8: black = RGBA(255, 0, 0, 0); break;
            }
            resizedRef.fillAll(black); // PERF: Only do this in the location of the black border.

            // No need to report that everything is dirty anymore.
            _reportBlackBordersAndResizedAreaAsDirty = false;

            // and no need to draw everything in onDraw anymore.
            _redrawBlackBordersAndResizedArea = false;

            rectsToCopy = (&_userArea)[0..1];
        }

        foreach(rect; rectsToCopy[])
        {
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


// given a width, how long in bytes should scanlines be for the final output buffer.
// Note: it seems win32 needs this exact stride for returned buffer. It mimics BMP.
//       On the other hands, is seems other platforms don't have the same constraints with row pitch.
int byteStride(int width) pure nothrow @nogc
{
    // See https://github.com/AuburnSounds/Dplug/issues/563, there
    // is currently a coupling with dplug:window and this can't be changed.
    enum scanLineAlignment = 4;
    int widthInBytes = width * 4;
    return (widthInBytes + (scanLineAlignment - 1)) & ~(scanLineAlignment-1);
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
