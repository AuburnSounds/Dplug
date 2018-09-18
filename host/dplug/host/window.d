/**
Host window creation.

Copyright: Auburn Sounds 2015-2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.host.window;

import gfm.math.box;
import dplug.window;
import dplug.graphics.image;
import dplug.graphics.color;
import dplug.host.host;

/// Creates a new native window suitable to host the plugin window.
/// This window may keep a reference to pluginHost
IWindow createHostWindow(IPluginHost pluginHost)
{    
    int[2] windowSize = pluginHost.getUISize();

    auto hostWindow = createWindow(WindowUsage.host, null, null,
                                   new NullWindowListener, WindowBackend.autodetect, windowSize[0], windowSize[1]);
    pluginHost.openUI(hostWindow.systemHandle());

    return hostWindow;
}

/// A listener to ignore window events, since we are not interested in host windows events.
class NullWindowListener : IWindowListener
{
nothrow:
@nogc:

    bool onMouseClick(int x, int y, MouseButton mb, bool isDoubleClick, MouseState mstate)
    {
        return false;
    }

    bool onMouseRelease(int x, int y, MouseButton mb, MouseState mstate)
    {
        return false;
    }

    bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate)
    {
        return false;
    }

    void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
    }

    bool onKeyDown(Key key)
    {
        return false;
    }

    bool onKeyUp(Key key)
    {
        return false;
    }

    void onDraw(WindowPixelFormat pf)
    {
    }

    ImageRef!RGBA onResized(int width, int height)
    {
        ImageRef!RGBA fake;
        fake.w = width;
        fake.h = height;
        fake.pixels = null;
        fake.pitch = width*RGBA.sizeof;
        return fake;
    }

    void recomputeDirtyAreas()
    {
    }

    box2i getDirtyRectangle()
    { 
        // return empty box since the host window itself is nothing interesting to draw
        return box2i(0, 0, 0, 0); 
    }

    void onMouseCaptureCancelled()
    {
    }

    void onAnimate(double dt, double time)
    {
    }
}