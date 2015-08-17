/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.graphics;

import std.math;
import std.range;
import std.parallelism;
import std.algorithm;

import ae.utils.graphics;

import dplug.core.funcs;

import dplug.plugin.client;
import dplug.plugin.graphics;
import dplug.plugin.daw;

import dplug.window.window;

import dplug.gui.mipmap;
import dplug.gui.boxlist;
import dplug.gui.context;
import dplug.gui.element;
import dplug.gui.dirtylist;
import dplug.gui.materials;

/// In the whole package:
/// The diffuse maps contains:
///   RGBA = red/green/blue/emissiveness
/// The depth maps contains depth.
/// The material map contains:
///   RGBA = roughness / metalness / specular / physical (allows to bypass PBR)

// A GUIGraphics is the interface between a plugin client and a IWindow.
// It is also an UIElement and the root element of the plugin UI hierarchy.
// You have to derive it to have a GUI.
// It dispatches window events to the GUI hierarchy.
class GUIGraphics : UIElement, IGraphics
{
    // light 1 used for key lighting and shadows
    // always coming from top-right
    vec3f light1Color;


    // light 2 used for things using the normal
    vec3f light2Dir;
    vec3f light2Color;

    float ambientLight;



    this(int initialWidth, int initialHeight)
    {
        _uiContext = new UIContext();
        super(_uiContext);

        _windowListener = new WindowListener();

        _window = null;
        _askedWidth = initialWidth;
        _askedHeight = initialHeight;

        // defaults
        light1Color = vec3f(0.54f, 0.50f, 0.46f) * 0.4f;

        light2Dir = vec3f(0.0f, 1.0f, 0.1f).normalized;
        light2Color = vec3f(0.378f, 0.35f, 0.322f);
        ambientLight = 0.15f;

        _taskPool = new TaskPool();

        _areasToUpdate = new AlignedBuffer!box2i;

        _updateRectScratch[0] = new AlignedBuffer!box2i;
        _updateRectScratch[1] = new AlignedBuffer!box2i;

        _areasToRender = new AlignedBuffer!box2i;
        _areasToRenderNonOverlapping = new AlignedBuffer!box2i;
        _areasToRenderNonOverlappingTiled = new AlignedBuffer!box2i;

        _elemsToDraw = new AlignedBuffer!UIElement;

        _compositingWatch = new StopWatch("Compositing = ");
    }

    ~this()
    {
        close();
    }

    override void close()
    {
        // TODO make sure this is actually called
        super.close();
        _uiContext.close();

        _areasToUpdate.close();
        _updateRectScratch[0].close();
        _updateRectScratch[1].close();
        _areasToRender.close();
        _areasToRenderNonOverlapping.close();
        _areasToRenderNonOverlappingTiled.close();
        _elemsToDraw.close();
    }

    // Graphics implementation

    override void openUI(void* parentInfo, DAW daw)
    {
        // We create this window each time.
        _window = createWindow(parentInfo, _windowListener, _askedWidth, _askedHeight);

        _uiContext.debugOutput = &_window.debugOutput;

        reflow(box2i(0, 0, _askedWidth, _askedHeight));

        // Sets the whole UI dirty
        setDirty();
    }

    override void closeUI()
    {
        // Destroy window.
        _window.terminate();
    }

    override int getGUIWidth()
    {
        return _askedWidth;
    }

    override int getGUIHeight()
    {
        return _askedHeight;
    }

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
            //string msg = _title ~ to!string(timeDiff) ~ " ms";
            //_window.debugOutput(msg);
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


    // This nested class is only here to avoid name conflicts between
    // UIElement and IWindowListener methods :|
    class WindowListener : IWindowListener
    {
        override bool onMouseClick(int x, int y, MouseButton mb, bool isDoubleClick, MouseState mstate)
        {
            return this.outer.mouseClick(x, y, mb, isDoubleClick, mstate);
        }

        override bool onMouseRelease(int x, int y, MouseButton mb, MouseState mstate)
        {
            this.outer.mouseRelease(x, y, mb, mstate);
            return true;
        }

        override bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate)
        {
            return this.outer.mouseWheel(x, y, wheelDeltaX, wheelDeltaY, mstate);
        }

        override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
        {
            this.outer.mouseMove(x, y, dx, dy, mstate);
        }

        override void recomputeDirtyAreas()
        {
            return this.outer.recomputeDirtyAreas();
        }

        override bool isUIDirty()
        {
            return this.outer.isUIDirty();
        }

        override bool onKeyDown(Key key)
        {
            // Sends the event to the last clicked element first
            if (_uiContext.focused !is null)
                if (_uiContext.focused.onKeyDown(key))
                    return true;

            // else to all Elements
            return keyDown(key);
        }

        override bool onKeyUp(Key key)
        {
            // Sends the event to the last clicked element first
            if (_uiContext.focused !is null)
                if (_uiContext.focused.onKeyUp(key))
                    return true;
            // else to all Elements
            return keyUp(key);
        }

        /// Returns areas affected by updates.
        override box2i getDirtyRectangle() nothrow @nogc
        {
            return _areasToRender[].boundingBox();
        }

        override void onResized(int width, int height)
        {
            _askedWidth = width;
            _askedHeight = height;

            reflow(box2i(0, 0, _askedWidth, _askedHeight));

            _diffuseMap.size(5, width, height);
            _depthMap.size(4, width, height);
            _materialMap.size(0, width, height);
        }

        // Redraw dirtied controls in depth and diffuse maps.
        // Update composited cache.
        override void onDraw(ImageRef!RGBA wfb, WindowPixelFormat pf)
        {
            renderElements();

            // Split boxes to avoid overlapped work
            // Note: this is done separately for update areas and render areas
            _areasToRenderNonOverlapping.clearContents();
            removeOverlappingAreas(_areasToRender[], _areasToRenderNonOverlapping);

            regenerateMipmaps();

            // Composite GUI
            // Most of the cost of rendering is here
            _compositingWatch.start();
            compositeGUI(wfb, pf);
            _compositingWatch.stop();
            //_compositingWatch.displayMean();

            // only then is the list of rectangles to update cleared
            _areasToUpdate.clearContents();
        }

        override void onMouseCaptureCancelled()
        {
            // Stop an eventual drag operation
            _uiContext.stopDragging();
        }

        override void onAnimate(double dt, double time)
        {
            this.outer.animate(dt, time);
        }
    }

protected:
    UIContext _uiContext;

    WindowListener _windowListener;

    // An interface to the underlying window
    IWindow _window;

    // Task pool for multi-threaded image work
    TaskPool _taskPool;

    int _askedWidth = 0;
    int _askedHeight = 0;

    // Diffuse color values for the whole UI.
    Mipmap!RGBA _diffuseMap;

    // Depth values for the whole UI.
    Mipmap!L16 _depthMap;

    // Depth values for the whole UI.
    Mipmap!RGBA _materialMap;

    // The list of areas whose diffuse/depth data have been changed.
    AlignedBuffer!box2i _areasToUpdate;

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


    StopWatch _compositingWatch;


    bool isUIDirty() nothrow @nogc
    {
        bool dirtyListEmpty = context().dirtyList.isEmpty();
        return !dirtyListEmpty;
    }

    // Fills _areasToUpdate and _areasToRender
    void recomputeDirtyAreas() nothrow @nogc
    {
        // Get areas to update
        _areasToRender.clearContents();

        context().dirtyList.pullAllRectangles(_areasToUpdate);

        foreach(dirtyRect; _areasToUpdate)
        {
            assert(dirtyRect.isSorted);
            assert(!dirtyRect.empty);
            _areasToRender.pushBack( extendsDirtyRect(dirtyRect, _askedWidth, _askedHeight) );
        }
    }

    box2i extendsDirtyRect(box2i rect, int width, int height) nothrow @nogc
    {
        // Tuned by hand on very shiny light sources.
        // Too high and processing becomes very expensive.
        // Too little and the ligth decay doesn't feel natural.

        int xmin = rect.min.x - 30;
        int ymin = rect.min.y - 30;
        int xmax = rect.max.x + 30;
        int ymax = rect.max.y + 30;

        if (xmin < 0) xmin = 0;
        if (ymin < 0) ymin = 0;
        if (xmax > width) xmax = width;
        if (ymax > height) ymax = height;
        return box2i(xmin, ymin, xmax, ymax);
    }

    /// Redraw UIElements
    void renderElements()
    {
        // recompute draw list
        _elemsToDraw.clearContents();
        getDrawList(_elemsToDraw);

        // Sort by ascending z-order (high z-order gets drawn last)
        // This sort must be stable to avoid messing with tree natural order.
        auto elemsToSort = _elemsToDraw[];
        sort!("a.zOrder() < b.zOrder()", SwapStrategy.stable)(elemsToSort);

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

                // Draw a number of UIElement in parallel, don't use other threads if only one element
                if (canBeDrawn == 1)
                    _elemsToDraw[drawn].render(diffuseRef, depthRef, materialRef, _areasToUpdate[]);
                else
                    foreach(i; _taskPool.parallel(canBeDrawn.iota))
                        _elemsToDraw[drawn + i].render(diffuseRef, depthRef, materialRef,  _areasToUpdate[]);

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
    void compositeGUI(ImageRef!RGBA wfb, WindowPixelFormat pf)
    {
        // Quick subjective testing indicates than somewhere between 16x16 and 32x32 have best performance
        enum tileWidth = 64;
        enum tileHeight = 32;

        _areasToRenderNonOverlappingTiled.clearContents();
        tileAreas(_areasToRenderNonOverlapping[], tileWidth, tileHeight,_areasToRenderNonOverlappingTiled);

        int numAreas = cast(int)_areasToRenderNonOverlappingTiled.length;

        bool parallelCompositing = true;

        if (parallelCompositing)
        {
            foreach(i; _taskPool.parallel(numAreas.iota))
                compositeTile(wfb, pf, _areasToRenderNonOverlappingTiled[i]);
        }
        else
        {
            foreach(i; 0..numAreas)
                compositeTile(wfb, pf, _areasToRenderNonOverlappingTiled[i]);
        }
    }

    /// Compose lighting effects from depth and diffuse into a result.
    /// takes output image and non-overlapping areas as input
    /// Useful multithreading code.
    void regenerateMipmaps()
    {
        int numAreas = cast(int)_areasToUpdate.length;

        // Fill update rect buffer with the content of _areasToUpdateNonOverlapping
        for (int i = 0; i < 2; ++i)
        {
            _updateRectScratch[i].clearContents();
            _updateRectScratch[i].pushBack(_areasToUpdate[]);
        }

        // We can't use tiled parallelism here because there is overdraw beyond level 0
        // So instead what we do is using up to 2 threads.
        foreach(i; _taskPool.parallel(2.iota))
        {
            if (i == 0)
            {
                // diffuse
                Mipmap!RGBA* mipmap = &_diffuseMap;
                foreach(level; 1 .. mipmap.numLevels())
                {
                    auto quality = level >= 2 ? Mipmap!RGBA.Quality.cubicAlphaCov : Mipmap!RGBA.Quality.boxAlphaCov;
                    foreach(ref area; _updateRectScratch[i])
                    {
                        area = mipmap.generateNextLevel(quality, area, level);
                    }
                }
            }
            else
            {
                // depth
                Mipmap!L16* mipmap = &_depthMap;
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
    }

    /// Don't like this rendering? Feel free to override this method.
    void compositeTile(ImageRef!RGBA wfb, WindowPixelFormat pf, box2i area)
    {
        int[5] line_index = void;
        ushort[5][5] depthPatch = void;
        int[5] col_index = void;
        L16*[5] depth_scan = void;

        Mipmap!RGBA* skybox = &context.skybox;
        int w = _diffuseMap.levels[0].w;
        int h = _diffuseMap.levels[0].h;
        float invW = 1.0f / w;
        float invH = 1.0f / h;
        float div255 = 1 / 255.0f;

        for (int j = area.min.y; j < area.max.y; ++j)
        {
            RGBA* wfb_scan = wfb.scanline(j).ptr;

            // clamp to existing lines

            for (int l = 0; l < 5; ++l)
                line_index[l] = gfm.math.clamp(j - 2 + l, 0, h - 1);


            for (int l = 0; l < 5; ++l)
                depth_scan[l] = _depthMap.levels[0].scanline(line_index[l]).ptr;

            RGBA* materialScan = _materialMap.levels[0].scanline(j).ptr;

            for (int i = area.min.x; i < area.max.x; ++i)
            {
                // clamp to existing columns

                for (int k = 0; k < 5; ++k)
                    col_index[k] = gfm.math.clamp(i - 2 + k, 0, w - 1);

                // Get depth for a 5x5 patch

                for (int l = 0; l < 5; ++l)
                {
                    for (int k = 0; k < 5; ++k)
                    {
                        ushort depthSample = depth_scan.ptr[l][col_index[k]].l;
                        depthPatch.ptr[l].ptr[k] = depthSample;
                    }
                }

                // compute normal
                float sx = depthPatch[1][0]     + depthPatch[1][1] * 2
                         + depthPatch[2][0] * 2 + depthPatch[2][1] * 4
                         + depthPatch[3][0]     + depthPatch[3][1] * 2
                       - ( depthPatch[1][3] * 2 + depthPatch[1][4]
                         + depthPatch[2][3] * 4 + depthPatch[2][4] * 2
                         + depthPatch[3][3] * 2 + depthPatch[3][4] );

                float sy = depthPatch[3][1] * 2 + depthPatch[3][2] * 4 + depthPatch[3][3] * 2
                         + depthPatch[4][1]     + depthPatch[4][2] * 2 + depthPatch[4][3]
                       - ( depthPatch[0][1]     + depthPatch[0][2] * 2 + depthPatch[0][3]
                         + depthPatch[1][1] * 2 + depthPatch[1][2] * 4 + depthPatch[1][3] * 2);

                enum float sz = 260.0f * 257.0f; // this factor basically tweak normals to make the UI flatter or not

                vec3f normal = vec3f(sx, sy, sz);
                normal.normalize();

                RGBA ibaseColor = _diffuseMap.levels[0][i, j];
                vec3f baseColor = vec3f(ibaseColor.r, ibaseColor.g, ibaseColor.b) * div255;

                vec3f color = vec3f(0.0f);
                vec3f toEye = vec3f(0.5f - i * invW, j * invH - 0.5f, 1.0f);
                toEye.normalize();


                RGBA materialHere = materialScan[i];

                float roughness = materialHere.r * div255;
                float metalness = materialHere.g * div255;
                float specular  = materialHere.b * div255;
                float physical  = materialHere.a * div255;

                float cavity;

                // Add ambient component
                {
                    float px = i + 0.5f;
                    float py = j + 0.5f;

                    float avgDepthHere =
                      ( _depthMap.linearSample(1, px, py)
                        + _depthMap.linearSample(2, px, py)
                        + _depthMap.linearSample(3, px, py)
                        + _depthMap.linearSample(4, px, py) ) * 0.25f;

                    cavity = ctLinearStep!(-90.0f * 256.0f, 0.0f)(depthPatch[2][2] - avgDepthHere);

                    color += baseColor * (cavity * ambientLight);
                }

                // cast shadows, ie. enlight what isn't in shadows
                {
                    enum float fallOff = 0.78f;

                    int samples = 11;

                    static immutable float[11] weights =
                    [
                        1.0f,
                        fallOff,
                        fallOff ^^ 2,
                        fallOff ^^ 3,
                        fallOff ^^ 4,
                        fallOff ^^ 5,
                        fallOff ^^ 6,
                        fallOff ^^ 7,
                        fallOff ^^ 8,
                        fallOff ^^ 9,
                        fallOff ^^ 10
                    ];

                    enum float totalWeights = (1.0f - (fallOff ^^ 11)) / (1.0f - fallOff) - 1;
                    enum float invTotalWeights = 1 / totalWeights;

                    float lightPassed = 0.0f;

                    int depthHere = depthPatch[2][2];
                    for (int sample = 1; sample < samples; ++sample)
                    {
                        int x = i + sample;
                        if (x >= w)
                            x = w - 1;
                        int y = j - sample;
                        if (y < 0)
                            y = 0;
                        int z = depthHere + sample;
                        int diff = z - _depthMap.levels[0][x, y].l;
                        lightPassed += ctLinearStep!(-60.0f * 256.0f, 0.0f)(diff) * weights.ptr[sample];
                    }
                    color += baseColor * light1Color * (lightPassed * invTotalWeights);
                }

                // secundary light
                {
                    float diffuseFactor = 0.5f + 0.5f * dot(normal, light2Dir);// + roughness;

                    diffuseFactor = /*cavity * */ linmap!float(diffuseFactor, 0.24f - roughness * 0.5f, 1, 0, 1.0f);

                    if (diffuseFactor > 0)
                        color += baseColor * light2Color * diffuseFactor;
                }

                // specular reflection
                if (specular != 0)
                {
                    vec3f lightReflect = reflect(-light2Dir, normal);
                    float specularFactor = dot(toEye, lightReflect);
                    if (specularFactor > 0)
                    {
                        float exponent = 0.8f * exp( (1-roughness) * 5.5f);
                        specularFactor = specularFactor ^^ exponent;
                        float roughFactor = 10 * (1.0f - roughness) * (1 - metalness * 0.5f);
                        specularFactor = /* cavity * */ specularFactor * roughFactor;
                        if (specularFactor != 0)
                            color += baseColor * light2Color * (specularFactor * specular);
                    }
                }

                // skybox reflection (use the same shininess as specular)
                if (metalness != 0)
                {
                    vec3f pureReflection = reflect(toEye, normal);

                    float skyx = 0.5f + ((0.5f + pureReflection.x *0.5f) * (skybox.width - 1));
                    float skyy = 0.5f + ((0.5f + pureReflection.y *0.5f) * (skybox.height - 1));

                    // 2nd order derivatives
                    float depthDX = depthPatch[3][1] + depthPatch[3][2] + depthPatch[3][3]
                        + depthPatch[1][1] + depthPatch[1][2] + depthPatch[1][3]
                        - 2 * (depthPatch[2][1] + depthPatch[2][2] + depthPatch[2][3]);

                    float depthDY = depthPatch[1][3] + depthPatch[2][3] + depthPatch[3][3]
                        + depthPatch[1][1] + depthPatch[2][1] + depthPatch[3][1]
                        - 2 * (depthPatch[1][2] + depthPatch[2][2] + depthPatch[3][2]);

                    depthDX *= (1 / 256.0f);
                    depthDY *= (1 / 256.0f);

                    float depthDerivSqr = depthDX * depthDX + depthDY * depthDY;
                    float indexDeriv = depthDerivSqr * skybox.width * skybox.height;

                    // cooking here
                    // log2 scaling + threshold
                    float mipLevel = 0.5f * fastlog2(1.0f + indexDeriv * 0.00001f) + 6 * roughness;

                    vec3f skyColor = skybox.linearMipmapSample(mipLevel, skyx, skyy).rgb * (div255 * metalness * 0.4f);
                    color += skyColor * baseColor;
                }

                // Add light emitted by neighbours
                {
                    float ic = i + 0.5f;
                    float jc = j + 0.5f;

                    // Get alpha-premultiplied, avoids some white highlights
                    // Maybe we could solve the white highlights by having the whole mipmap premultiplied
                    vec4f colorLevel1 = _diffuseMap.linearSample!true(1, ic, jc);
                    vec4f colorLevel2 = _diffuseMap.linearSample!true(2, ic, jc);
                    vec4f colorLevel3 = _diffuseMap.linearSample!true(3, ic, jc);
                    vec4f colorLevel4 = _diffuseMap.linearSample!true(4, ic, jc);
                    vec4f colorLevel5 = _diffuseMap.linearSample!true(5, ic, jc);

                    vec4f emitted = colorLevel1 * 0.2f;
                    emitted += colorLevel2 * 0.3f;
                    emitted += colorLevel3 * 0.25f;
                    emitted += colorLevel4 * 0.15f;
                    emitted += colorLevel5 * 0.10f;

                    emitted *= (div255 * 1.5f);

                    color += emitted.rgb;
                }

                // Show normals
               // color = normal;//vec3f(0.5f) + normal * 0.5f;

                // Show depth
                {
                //    float depthColor = depthPatch[2][2] / 65535.0f;
                //    color = vec3f(depthColor);
                }

                // Show diffuse
                //color = baseColor;

                //  color = toEye;
                //color = vec3f(cavity);

                color.x = gfm.math.clamp(color.x, 0.0f, 1.0f);
                color.y = gfm.math.clamp(color.y, 0.0f, 1.0f);
                color.z = gfm.math.clamp(color.z, 0.0f, 1.0f);

                int r = cast(int)(color.x * 255.99f);
                int g = cast(int)(color.y * 255.99f);
                int b = cast(int)(color.z * 255.99f);

                RGBA finalColor = void;

                final switch (pf) with (WindowPixelFormat)
                {
                    case ARGB8:
                        finalColor = RGBA(255, cast(ubyte)r, cast(ubyte)g, cast(ubyte)b);
                        break;
                    case BGRA8:
                        finalColor = RGBA(cast(ubyte)b, cast(ubyte)g, cast(ubyte)r, 255);
                        break;
                }

                // write composited color
                wfb_scan[i] = finalColor;
            }
        }
    }
}

private:

// cause smoothStep wasn't needed
float ctLinearStep(float a, float b)(float t) pure nothrow @nogc
{
    if (t <= a)
        return 0.0f;
    else if (t >= b)
        return 1.0f;
    else
    {
        static immutable divider = 1.0f / (b - a);
        return (t - a) * divider;
    }
}

// cause smoothStep wasn't needed
float linearStep(float a, float b, float t) pure nothrow @nogc
{
    if (t <= a)
        return 0.0f;
    else if (t >= b)
        return 1.0f;
    else
    {
        float divider = 1.0f / (b - a);
        return (t - a) * divider;
    }
}

// log2 approximation by Laurent de Soras
// http://www.flipcode.com/archives/Fast_log_Function.shtml
float fastlog2(float val)
{
    union fi_t
    {
        int i;
        float f;
    }

    fi_t fi;
    fi.f = val;
    int x = fi.i;
    int log_2 = ((x >> 23) & 255) - 128;
    x = x & ~(255 << 23);
    x += 127 << 23;
    fi.i = x;
    return fi.f + log_2;
}


