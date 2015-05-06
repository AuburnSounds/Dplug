module dplug.gui.graphics;

import ae.utils.graphics;
import dplug.plugin.client;
import dplug.plugin.graphics;

import dplug.gui.window;
import dplug.gui.boxlist;
import dplug.gui.toolkit.context;
import dplug.gui.toolkit.element;

// A GUIGraphics is the interface between a plugin client and a IWindow.
// It is also an UIElement and the root element of the plugin UI hierarchy.
// You have to derive it to have a GUI.
// It dispatches window events to the GUI hierarchy.
class GUIGraphics : UIElement, IGraphics
{
    this(int initialWidth, int initialHeight)
    {
        _uiContext = new UIContext();
        super(_uiContext);

        _windowListener = new WindowListener();

        _window = null;
        _askedWidth = initialWidth;
        _askedHeight = initialHeight;       
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

            _diffuseMap.size(width, height);
            _depthMap.size(width, height);
        }

        // an image you have to draw to, or return that nothing has changed
        override box2i[] onDraw(ImageRef!RGBA wfb)
        {
            // TODO: cache for areas to update to share with getDirtyRectangle?

            // Get sorted draw list
            UIElement[] elemsToDraw = getDrawList();

            // Get areas to update
            _areasToUpdate.length = 0;
            foreach(elem; elemsToDraw)
                _areasToUpdate ~= elem.dirtyRect();

            // Split boxes to avoid overdraw
            _areasToUpdate.boxes = _areasToUpdate.removeOverlappingAreas();

            // Render required areas in diffuse and depth maps
            foreach(elem; elemsToDraw)
                elem.render(_diffuseMap.toRef(), _depthMap.toRef());

            // Clear dirty state in the whole GUI since after this draw everything 
            // will be up-to-date.
            clearDirty();

            // Composite GUI
            compositeGUI(wfb, _areasToUpdate.boxes[]);

            // Return non-overlapping areas to update
            return _areasToUpdate.boxes[];
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

    BoxList _areasToUpdate;

    int _askedWidth = 0;
    int _askedHeight = 0;

    Image!RGBA _diffuseMap;
    Image!S16 _depthMap;

    // compose lighting effects
    // takes output image and non-overlapping areas as input
    void compositeGUI(ImageRef!RGBA wfb, box2i[] areas)
    {
        ImageRef!RGBA skybox = context().skybox.toRef();

        alias diffuse = _diffuseMap;
        alias depth = _depthMap;
        int w = diffuse.w;
        int h = diffuse.h;

        float clampedDepth(int i, int j)
        {
            i = clamp(i, 0, w - 1);
            j = clamp(j, 0, h - 1);
            return depth[i, j].l;
        }

        float filteredDepth(int i, int j)
        {
            float N = clampedDepth(i, j);
            float A = clampedDepth(i-1, j);
            float B = clampedDepth(i+1, j);
            float C = clampedDepth(i, j+1);
            float D = clampedDepth(i, j-1);
            float E = clampedDepth(i-1, j-1);
            float F = clampedDepth(i+1, j-1);
            float G = clampedDepth(i-1, j+1);
            float H = clampedDepth(i+1, j+1);
            return (N + A + B + C + D + E + F + G + H) / 9.0f;
        }

        foreach(area; areas)
        {
            for (int j = area.min.y; area.max.y; ++j)
            {
                for (int i = area.min.x; area.max.x; ++i)
                {
                    vec3f getNormal(int i, int j)
                    {
                        float sx = filteredDepth(i + 1, j) - filteredDepth(i - 1, j);
                        float sy = filteredDepth(i, j + 1) - filteredDepth(i, j - 1);
                        return vec3f(-sx, sy, 64 * 64).normalized;
                    }

                    vec3f normal = getNormal(i, j);

                    RGBA imaterialDiffuse = diffuse[i, j];  
                    vec3f materialDiffuse = vec3f(imaterialDiffuse.r / 255.0f, imaterialDiffuse.g / 255.0f, imaterialDiffuse.b / 255.0f);



                    vec3f color = vec3f(0.0f);

                    // Combined color bleed and ambient occlusion!
                    // TODO: accelerate this with mipmaps
                    int bleedWidth = 7;
                    vec3f colorBleed = 0;
                    float totalWeight = 0;
                    for (int k = -bleedWidth; k <= bleedWidth; ++k)
                        for (int l = -bleedWidth; l <= bleedWidth; ++l)
                        {
                            int x = clamp(i + l, 0, w - 1);
                            int y = clamp(j + k, 0, h - 1);
                            float weight = 1.0f;// / (std.math.abs(k) + std.math.abs(l) + 1);

                            RGBA diffuseRGBA = diffuse[x, y];  
                            vec3f diffuseC = vec3f(diffuseRGBA.r / 255.0f, diffuseRGBA.g / 255.0f, diffuseRGBA.b / 255.0f);

                            colorBleed += (weight * depth[x, y].l /  32767.0f) * diffuseC;
                            totalWeight += weight;
                        }

                    colorBleed = colorBleed / totalWeight;

                    // cast shadows

                    int samples = 10;
                    float lightPassed = 0.0f;
                    totalWeight = 0.0f;
                    float weight = 1.0f;
                    for (int l = 1; l <= samples; ++l)
                    {
                        int x = clamp(i + l, 0, w - 1);
                        int y = clamp(j - l, 0, h - 1);
                        float z = depth[i, j].l / 128.0f + l;

                        float diff = z - depth[x, y].l / 128.0f;

                        lightPassed += smoothStep!float(-40.0f, 20.0f, diff) * weight;
                        totalWeight += weight;
                        weight *= 0.78f;
                    }
                    lightPassed /= totalWeight;
                    vec3f keylightColor = vec3f(0.54f, 0.50f, 0.46f)* 0.7f;
                    color += materialDiffuse * keylightColor * lightPassed;


                    // secundary light
                    vec3f light2Color = vec3f(0.54f, 0.5f, 0.46f) * 0.7;
                    vec3f light2Dir = vec3f(0.0f, 1.0f, 0.1f).normalized;
                    vec3f eyeDir = vec3f(0.0f, 0f, 1.0f).normalized;
                    float diffuseFactor = dot(normal, light2Dir);

                    if (diffuseFactor > 0)
                        color += materialDiffuse * light2Color * diffuseFactor;

                    // specular
                    vec3f toEye = vec3f(0, 0, 1.0f);
                    vec3f lightReflect = (reflect(light2Dir, normal).normalized);
                    float specularFactor = dot(toEye, lightReflect);
                    if (specularFactor > 0)
                    {
                        specularFactor = specularFactor ^^ 4.0f;
                        color += materialDiffuse * light2Color * specularFactor * 2;
                    }

                    // skybox reflection
                    vec3f pureReflection = (reflect(toEye, normal).normalized);

                    int skyx = cast(int)(0.5 + ((0.5 + pureReflection.x *0.5) * (skybox.w - 1)));
                    int skyy = cast(int)(0.5 + ((0.5 + pureReflection.y *0.5) * (skybox.h - 1)));

                    RGBA skyC = skybox[skyx, skyy];  
                    vec3f skyColor = vec3f(skyC.r / 255.0f, skyC.g / 255.0f, skyC.b / 255.0f);

                    color += 0.15f * skyColor;


                    // Add ambient component
                    vec3f ambientLight = vec3f(0.3f, 0.3f, 0.3f);
                    vec3f materialAmbient = materialDiffuse;
                    //color = vec3f(0.0f);
                    color += colorBleed * ambientLight;

                    // Show normals
                    //color = vec3f(0.5f) + normal * 0.5f;

                    // Show AO
                    // color = vec3f(occluded, occluded, occluded);

                    color.x = clamp(color.x, 0.0f, 1.0f);
                    color.y = clamp(color.y, 0.0f, 1.0f);
                    color.z = clamp(color.z, 0.0f, 1.0f);


                    int r = cast(int)(0.5 + color.x * 255);
                    int g = cast(int)(0.5 + color.y * 255);
                    int b = cast(int)(0.5 + color.z * 255);

                    RGBA finalColor = RGBA(cast(ubyte)r, cast(ubyte)g, cast(ubyte)b, 255);
                    wfb[i, j] = finalColor;

                }
            }
        }
    }
}
