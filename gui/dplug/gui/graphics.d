module dplug.gui.graphics;

import std.math;

import ae.utils.graphics;
import dplug.plugin.client;
import dplug.plugin.graphics;

import dplug.gui.window;
import dplug.gui.mipmap;
import dplug.gui.boxlist;
import dplug.gui.toolkit.context;
import dplug.gui.toolkit.element;

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
        override bool onMouseClick(int x, int y, MouseButton mb, bool isDoubleClick)
        {
            return this.outer.mouseClick(x, y, mb, isDoubleClick);
        }

        override bool onMouseRelease(int x, int y, MouseButton mb)
        {
            this.outer.mouseRelease(x, y, mb);
            return true;
        }

        override bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY)
        {
            return this.outer.mouseWheel(x, y, wheelDeltaX, wheelDeltaY);
        }

        override void onMouseMove(int x, int y, int dx, int dy)
        {
            this.outer.mouseMove(x, y, dx, dy);
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

        override box2i getDirtyRectangle()
        {
            // TODO: cache for areas to update to share with onDraw?

            // Get sorted draw list
            UIElement[] elemsToDraw = getDrawList();

            // Get areas to update
            _areasToUpdate.length = 0;
            foreach(elem; elemsToDraw)
                _areasToUpdate ~= elem.dirtyRect();

            return _areasToUpdate.boundingBox();
        }

        override void onResized(int width, int height)
        {
            _askedWidth = width;
            _askedHeight = height;

            reflow(box2i(0, 0, _askedWidth, _askedHeight));

            _diffuseMap.size(4, width, height);
            _depthMap.size(4, width, height);
        }

        override box2i extendsDirtyRect(box2i rect, int width, int height)
        {
            // shadow casting => 15 pixels influence on bottom left
            // color-bleed => 7 pixels influence in every direction
            int xmin = rect.min.x - 15;
            int ymin = rect.min.y - 7;
            int xmax = rect.max.x + 7;
            int ymax = rect.max.y + 15;
            if (xmin < 0) xmin = 0;
            if (ymin < 0) ymin = 0;
            if (xmax > width) xmax = width;
            if (ymax > height) ymax = height;
            return box2i(xmin, ymin, xmax, ymax);
        }

        override box2i[] onDraw(ImageRef!RGBA wfb)
        {
            // TODO: cache for areas to update to share with getDirtyRectangle?

            // Get sorted draw list
            UIElement[] elemsToDraw = getDrawList();

            // Get areas to update
            _areasToUpdate.length = 0;
            _areasToRender.length = 0;
            foreach(elem; elemsToDraw)
            {
                _areasToUpdate ~= elem.dirtyRect();

                // TODO: Not sure if this is needed anymore to have separate render areas now that the dirtied part is extended
                _areasToRender ~= extendsDirtyRect(elem.dirtyRect, wfb.w, wfb.h); 
            }

            // Split boxes to avoid overdraw
            // Note: this is done separately for update areas and render areas
            _areasToUpdate.boxes = _areasToUpdate.removeOverlappingAreas();
            _areasToRender.boxes = _areasToRender.removeOverlappingAreas();

            // Render required areas in diffuse and depth maps, base level
            foreach(elem; elemsToDraw)
                elem.render(_diffuseMap.levels[0].toRef(), _depthMap.levels[0].toRef());

            // Recompute mipmaps in updated areas
            foreach(area; _areasToUpdate.boxes)
            {
                _diffuseMap.generateMipmaps(area);
                _depthMap.generateMipmaps(area);
            }

            // Clear dirty state in the whole GUI since after this draw everything 
            // will be up-to-date.
            clearDirty();

            // Composite GUI
            compositeGUI(wfb, _areasToRender.boxes);

            // Return non-overlapping areas to update on screen
            return _areasToRender.boxes;
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

    // The list of areas whose diffuse/depth data have been changed 
    BoxList _areasToUpdate;

    // The list of areas that must be effectively updated (slithly larger than _areasToUpdate)
    BoxList _areasToRender;

    int _askedWidth = 0;
    int _askedHeight = 0;

    Mipmap _diffuseMap;
    Mipmap _depthMap;

    // compose lighting effects
    // takes output image and non-overlapping areas as input
    void compositeGUI(ImageRef!RGBA wfb, box2i[] areas)
    {
        Mipmap* skybox = &context.skybox;

        int w = _diffuseMap.levels[0].w;
        int h = _diffuseMap.levels[0].h;

        float div255 = 1 / 255.0f;


        foreach(area; areas)
        {
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

                    enum float sz = 16.0f * 9.0f;

                    vec3f normal = vec3f(sx, sy, sz).normalized;

                    RGBA imaterialDiffuse = _diffuseMap.levels[0][i, j];  
                    vec3f materialDiffuse = vec3f(imaterialDiffuse.r * div255, imaterialDiffuse.g * div255, imaterialDiffuse.b * div255);

                    vec3f color = vec3f(0.0f);
                    vec3f toEye = vec3f(cast(float)i / cast(float)w - 0.5f,
                                        cast(float)j / cast(float)h - 0.5f,
                                        1.0f).normalized;

                    float shininess = depth_scan[2].ptr[i].g / 255.0f;

                    // cast shadows, ie. enlight what isn't in shadows
                    {
                        int depthHere = depthPatch[2][2];

                        // sample at position + (1, -1)
                        float depth1 = _depthMap.linearSample(0, i + 1.5f, j - 0.5f).r;
                        float diff1 = depthHere + 1 - depth1;
                        float lighted1 = linearStep!(-10.0f, 3.0f)(diff1);

                        // sample at position + (3, -3)
                        float depth2 = _depthMap.linearSample(1, i + 3.5f, j - 2.5f).r;
                        float diff2 = depthHere + 3 - depth2;
                        float lighted2 = linearStep!(-20.0f, 7.2f)(diff2);

                        // sample at position + (7, -7)
                        float depth3 = _depthMap.linearSample(2, i + 7.5f, j -6.5f).r;
                        float diff3 = depthHere + 7 - depth3;
                        float lighted3 = linearStep!(-40.0f, 15.0f)(diff3);

                        // sample at position + (15, -15)
                        float depth4 = _depthMap.linearSample(3, i + 15.5f, j -14.5f).r;
                        float diff4 = depthHere + 15 - depth3;
                        float lighted4 = linearStep!(-80.0f, 30.0f)(diff4);

                        float lightPassed = lighted1 * lighted2 * lighted3 * lighted4;

                        color += materialDiffuse * light1Color * lightPassed;
                    }

                    // secundary light
                    {
                        
                        float diffuseFactor = dot(normal, light2Dir);

                        if (diffuseFactor > 0)
                            color += materialDiffuse * light2Color * diffuseFactor;
                    }

                    // specular reflection
                    {
                        vec3f lightReflect = reflect(light2Dir, normal);
                        float specularFactor = dot(toEye, lightReflect);
                        if (specularFactor > 0)
                        {
                            specularFactor = specularFactor * specularFactor;
                            specularFactor = specularFactor * specularFactor;
                            color += materialDiffuse * light2Color * specularFactor * 2 * shininess;
                        }
                    }

                    // skybox reflection (use the same shininess as specular)
                    {
                        vec3f pureReflection = reflect(toEye, normal);

                        float skyx = 0.5f + ((0.5f + pureReflection.x *0.5f) * (skybox.width - 1));
                        float skyy = 0.5f + ((0.5f + pureReflection.y *0.5f) * (skybox.height - 1));

                        float depthDX =  (depthPatch[3][2] - depthPatch[1][2]) * 0.5f;
                        float depthDY =  (depthPatch[2][3] - depthPatch[2][1]) * 0.5f;
                        float depthDerivSqr = depthDX * depthDX + depthDY * depthDY;
                        float indexDeriv = depthDerivSqr * skybox.width;

                        // cooking here
                        // log2 scaling + threshold
                        float mipLevel = 0.5f * log2(1.0f + indexDeriv * 0.5f); //TODO tune this

                        vec3f skyColor = skybox.linearMipmapSample(mipLevel, skyx, skyy) * div255;
                        color += shininess * 0.3f * skyColor;
                    }


                    // Add ambient component                    
                    
                    // Combined color bleed and ambient occlusion!
                    float avgDepthHere = _depthMap.linearSample(2, i + 0.5f, j + 0.5f).r * 0.33f
                                       + _depthMap.linearSample(3, i + 0.5f, j + 0.5f).r * 0.33f
                                       + _depthMap.linearSample(4, i + 0.5f, j + 0.5f).r * 0.33f;

                    float occluded = linearStep!(-90.0f, 90.0f)(depthPatch[2][2] - avgDepthHere);

                    //vec3f colorBleed = avgDepthHere.r * _diffuseMap.linearSample(3, i + 0.5f, j + 0.5f) * div255;
                    color += vec3f(occluded * ambientLight);

                    // Show normals
                    //color = vec3f(0.5f) + normal * 0.5f;

                    // Show depth
                    {
                        //float depthColor = depthPatch[2][2] / 255.0f;
                        //color = vec3f(depthColor);
                    }

                    // Show diffuse
                    //color = materialDiffuse;

                    // Show AO
                    // color = vec3f(occluded, occluded, occluded);

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
}

private:

// cause smoothStep wasn't needed
float linearStep(float a, float b)(float t) pure nothrow @nogc 
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