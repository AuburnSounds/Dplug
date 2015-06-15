/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.graphics;

import std.math;
import std.range;
import std.parallelism;

import ae.utils.graphics;
import dplug.plugin.client;
import dplug.plugin.graphics;

import dplug.gui.window;
import dplug.gui.mipmap;
import dplug.gui.boxlist;
import dplug.gui.toolkit.context;
import dplug.gui.toolkit.element;

/// In the whole package:
/// The diffuse maps contains:
///   RGBA = red/green/blue/emissiveness
/// The depth maps contains:
///   RGBA = depth / shininess

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
        ambientLight = 0.3f;

        _taskPool = new TaskPool();
    }

    // Graphics implementation

    override void openUI(void* parentInfo)
    {
        // We create this window each time.
        _window = createWindow(parentInfo, _windowListener, _askedWidth, _askedHeight);
        reflow(box2i(0, 0, _askedWidth, _askedHeight));
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

        override void markRectangleDirty(box2i dirtyRect)
        {
            setDirty(dirtyRect);
        }

        /// Returns areas affected by updates.
        override box2i getDirtyRectangle()
        {
            return _areasToRender.boundingBox();
        }

        override void onResized(int width, int height)
        {
            _askedWidth = width;
            _askedHeight = height;

            reflow(box2i(0, 0, _askedWidth, _askedHeight));

            _diffuseMap.size(4, width, height);
            _depthMap.size(4, width, height);
        }

        // Redraw dirtied controls in depth and diffuse maps.
        // Update composited cache.
        override void onDraw(ImageRef!RGBA wfb)
        {
            // Render required areas in diffuse and depth maps, base level
            foreach(elem; _elemsToDraw)
                elem.render(_diffuseMap.levels[0].toRef(), _depthMap.levels[0].toRef());


            // Split boxes to avoid overlapped work
            // Note: this is done separately for update areas and render areas
            _areasToUpdateNonOverlapping.length = 0;
            _areasToRenderNonOverlapping.length = 0;
            removeOverlappingAreas(_areasToUpdate, _areasToUpdateNonOverlapping);
            removeOverlappingAreas(_areasToRender, _areasToRenderNonOverlapping);
            _areasToUpdateNonOverlapping.keepAtLeastThatSize();
            _areasToRenderNonOverlapping.keepAtLeastThatSize();

            regenerateMipmaps();

            // Clear dirty state in the whole GUI since after this draw everything 
            // will be up-to-date.
            clearDirty();

            // Composite GUI
            compositeGUI(wfb);
        }

        override void onMouseCaptureCancelled()
        {
            // Stop an eventual drag operation
            _uiContext.stopDragging();
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

    Mipmap _diffuseMap;
    Mipmap _depthMap;


    box2i[] _areasToUpdate;                    // The list of areas whose diffuse/depth data have been changed.
    box2i[] _areasToUpdateNonOverlapping;      // same list, but reorganized to avoid overlap
    box2i[][2] _updateRectScratch;             // Same, but temporary variable for mipmap generation

    box2i[] _areasToRender;                    // The list of areas that must be effectively updated in the composite buffer (sligthly larger than _areasToUpdate).
    box2i[] _areasToRenderNonOverlapping;      // same list, but reorganized to avoid overlap
    box2i[] _areasToRenderNonOverlappingTiled; // same list, but separated in smaller tiles
    
    // The list of UIElement to draw
    UIElement[] _elemsToDraw;


    // Fills _areasToUpdate and _areasToRender
    void recomputeDirtyAreas()
    {
        int widthOfWindow = _askedWidth;
        int heightOfWindow = _askedHeight;

        // recompute draw list
        _elemsToDraw.length = 0;
        getDrawList(_elemsToDraw);
        _elemsToDraw.keepAtLeastThatSize();

        // Get areas to update
        _areasToUpdate.length = 0;
        _areasToRender.length = 0;
        foreach(elem; _elemsToDraw)
        {
            box2i dirty = elem.getDirtyRect();
            if (!dirty.empty)
            {
                _areasToUpdate ~= dirty;
                _areasToRender ~= extendsDirtyRect(dirty, widthOfWindow, heightOfWindow); 
            }
        }
        _areasToUpdate.keepAtLeastThatSize();
        _areasToRender.keepAtLeastThatSize();

    }

    box2i extendsDirtyRect(box2i rect, int width, int height)
    {
        // shadow casting => 15 pixels influence on bottom left
        // color-bleed => 7 pixels influence in every direction
        int xmin = rect.min.x - 15;
        int ymin = rect.min.y - 10;
        int xmax = rect.max.x + 10;
        int ymax = rect.max.y + 15;
        if (xmin < 0) xmin = 0;
        if (ymin < 0) ymin = 0;
        if (xmax > width) xmax = width;
        if (ymax > height) ymax = height;
        return box2i(xmin, ymin, xmax, ymax);
    }

    /// Compose lighting effects from depth and diffuse into a result.
    /// takes output image and non-overlapping areas as input
    /// Useful multithreading code.
    void compositeGUI(ImageRef!RGBA wfb)
    {
        // Quick subjective testing indicates than somewhere between 16x16 and 32x32 have best performance
        enum tileWidth = 32;
        enum tileHeight = 32;

        _areasToRenderNonOverlappingTiled.length = 0;
        tileAreas(_areasToRenderNonOverlapping, tileWidth, tileHeight,_areasToRenderNonOverlappingTiled);

        int numAreas = cast(int)_areasToRenderNonOverlappingTiled.length;
        _areasToRenderNonOverlappingTiled.keepAtLeastThatSize();

        foreach(i; _taskPool.parallel(numAreas.iota))
        {
            compositeTile(wfb, _areasToRenderNonOverlappingTiled[i]);
        }
    }

    /// Compose lighting effects from depth and diffuse into a result.
    /// takes output image and non-overlapping areas as input
    /// Useful multithreading code.
    void regenerateMipmaps()
    {
        int numAreas = cast(int)_areasToUpdateNonOverlapping.length;

        // Fill update rect buffer with the content of _areasToUpdateNonOverlapping
        for (int i = 0; i < 2; ++i)
        {
            _updateRectScratch[i].length = numAreas;
            _updateRectScratch[i][] = _areasToUpdateNonOverlapping[];
            _updateRectScratch[i].keepAtLeastThatSize();
        }

        // We can't use tiled parallelism here because there is overdraw beyond level 0
        // So instead what we do is using up to 2 threads.
        foreach(i; _taskPool.parallel(2.iota))
        {
            Mipmap* mipmap = i == 0 ? &_diffuseMap : &_depthMap;
            if (i == 0)
            {
                // diffuse
                foreach(level; 1 .. mipmap.numLevels())
                {
                    // TODO: a cubicAlphaCov mipmap mode
                    auto quality = Mipmap.Quality.boxAlphaCov;
                    foreach(ref area; _updateRectScratch[i])
                    {                        
                        area = mipmap.generateNextLevel(quality, area, level);
                    }
                }
            }
            else
            {
                // depth

                foreach(level; 1 .. mipmap.numLevels())
                {
                    auto quality = level >= 3 ? Mipmap.Quality.cubic : Mipmap.Quality.box;
                    foreach(ref area; _updateRectScratch[i])
                    {
                        area = mipmap.generateNextLevel(quality, area, level);
                    }
                }
            }
        }
    }

    /// Don't like this rendering? Feel free to override this method.
    void compositeTile(ImageRef!RGBA wfb, box2i area)
    {
        Mipmap* skybox = &context.skybox;
        int w = _diffuseMap.levels[0].w;
        int h = _diffuseMap.levels[0].h;
        float div255 = 1 / 255.0f;

        for (int j = area.min.y; j < area.max.y; ++j)
        {
            RGBA[] wfb_scan = wfb.scanline(j);

            // clamp to existing lines
            int[5] line_index = void;
            for (int l = 0; l < 5; ++l)
                line_index[l] = clamp(j - 2 + l, 0, h - 1);

            RGBA[][5] depth_scan = void;
            for (int l = 0; l < 5; ++l)
                depth_scan[l] = _depthMap.levels[0].scanline(line_index[l]);


            for (int i = area.min.x; i < area.max.x; ++i)
            {
                // clamp to existing columns
                int[5] col_index = void;
                for (int k = 0; k < 5; ++k)
                    col_index[k] = clamp(i - 2 + k, 0, w - 1);

                // Get depth for a 5x5 patch
                ubyte[5][5] depthPatch = void;
                for (int l = 0; l < 5; ++l)
                {
                    for (int k = 0; k < 5; ++k)
                    {
                        ubyte depthSample = depth_scan.ptr[l].ptr[col_index[k]].r;
                        depthPatch.ptr[l].ptr[k] = depthSample;
                    }
                }

                // compute normal
                float sx = depthPatch[1][0] + depthPatch[1][1] + depthPatch[2][0] + depthPatch[2][1] + depthPatch[3][0] + depthPatch[3][1]
                    - ( depthPatch[1][3] + depthPatch[1][4] + depthPatch[2][3] + depthPatch[2][4] + depthPatch[3][3] + depthPatch[3][4] );

                float sy = depthPatch[3][1] + depthPatch[4][1] + depthPatch[3][2] + depthPatch[4][2] + depthPatch[3][3] + depthPatch[4][3]
                    - ( depthPatch[0][1] + depthPatch[1][1] + depthPatch[0][2] + depthPatch[1][2] + depthPatch[0][3] + depthPatch[1][3] );

                enum float sz = 130.0f; // this factor basically tweak normals to make the UI flatter or not

                vec3f normal = vec3f(sx, sy, sz).normalized;

                RGBA ibaseColor = _diffuseMap.levels[0][i, j];  
                vec3f baseColor = vec3f(ibaseColor.r * div255, ibaseColor.g * div255, ibaseColor.b * div255);

                vec3f color = vec3f(0.0f);
                vec3f toEye = vec3f(cast(float)i / cast(float)w - 0.5f,
                                    cast(float)j / cast(float)h - 0.5f,
                                    1.0f).normalized;

                float shininess = depth_scan[2].ptr[i].g / 255.0f;

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
                        int diff = z - _depthMap.levels[0][x, y].r;
                        lightPassed += ctLinearStep!(-60.0f, 0.0f)(diff) * weights[sample];
                    }
                    color += baseColor * light1Color * (lightPassed * invTotalWeights);
                }

                // secundary light
                {

                    float diffuseFactor = dot(normal, light2Dir);

                    if (diffuseFactor > 0)
                        color += baseColor * light2Color * diffuseFactor;
                }

                // specular reflection
                if (shininess != 0)
                {
                    vec3f lightReflect = reflect(light2Dir, normal);
                    float specularFactor = dot(toEye, lightReflect);
                    if (specularFactor > 0)
                    {
                        specularFactor = specularFactor * specularFactor;
                        specularFactor = specularFactor * specularFactor;
                        color += baseColor * light2Color * specularFactor * 2 * shininess;
                    }
                }

                // skybox reflection (use the same shininess as specular)
                if (shininess != 0)
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

                    float depthDerivSqr = depthDX * depthDX + depthDY * depthDY;
                    float indexDeriv = depthDerivSqr * skybox.width * skybox.height;

                    // cooking here
                    // log2 scaling + threshold
                    float mipLevel = 0.5f * log2(1.0f + indexDeriv * 0.00001f);

                    vec4f skyColor = skybox.linearMipmapSample(mipLevel, skyx, skyy) * div255;
                    color += shininess * 0.3f * skyColor.rgb;
                }


                // Add ambient component

                {
                    float avgDepthHere = _depthMap.linearSample(2, i + 0.5f, j + 0.5f).r * 0.33f
                        + _depthMap.linearSample(3, i + 0.5f, j + 0.5f).r * 0.33f
                        + _depthMap.linearSample(4, i + 0.5f, j + 0.5f).r * 0.33f;

                    float occluded = ctLinearStep!(-90.0f, 90.0f)(depthPatch[2][2] - avgDepthHere);

                    color += vec3f(occluded * ambientLight) * baseColor;
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
                    vec4f colorLevel5 = _diffuseMap.linearSample!true(4, ic, jc);

                    vec3f emitted = colorLevel1.rgb * 0.2f;
                    emitted += colorLevel2.rgb * 0.3f;
                    emitted += colorLevel3.rgb * 0.25f;
                    emitted += colorLevel4.rgb * 0.15f;

                    emitted *= (div255 * 1.7f);

                    color += emitted;
                }


                // Show normals
                //color = vec3f(0.5f) + normal * 0.5f;

                // Show depth
                {
                    //float depthColor = depthPatch[2][2] / 255.0f;
                    //color = vec3f(depthColor);
                }

                // Show diffuse
                //color = baseColor;

                color.x = clamp(color.x, 0.0f, 1.0f);
                color.y = clamp(color.y, 0.0f, 1.0f);
                color.z = clamp(color.z, 0.0f, 1.0f);


                int r = cast(int)(0.5 + color.x * 255);
                int g = cast(int)(0.5 + color.y * 255);
                int b = cast(int)(0.5 + color.z * 255);

                // write composited color
                RGBA finalColor = RGBA(cast(ubyte)r, cast(ubyte)g, cast(ubyte)b, 255);

                wfb_scan.ptr[i] = finalColor;
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
        enum float divider = 1.0f / (b - a);
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

void keepAtLeastThatSize(T)(ref T[] slice)
{
    auto capacity = slice.capacity;
    auto length = slice.length;
    if (capacity < length)
        slice.reserve(length); // should not reallocate
}