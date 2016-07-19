/**
 * Copyright: Copyright Auburn Sounds 2016
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.host.window;

import dplug.window;
import dplug.host.host;
import ae.utils.graphics;

/// Creates a new native window suitable to host the plugin window.
/// This window may keep a reference to pluginHost
IWindow createHostWindow(IPluginHost pluginHost)
{    
    int[2] windowSize = pluginHost.getUISize();

    auto hostListener = new HostWindowListener();

    auto hostWindow = createWindow(null, null, hostListener, WindowBackend.autodetect, windowSize[0], windowSize[1]);
    pluginHost.openUI(hostWindow.systemHandle());

    return hostWindow;
}


private class HostWindowListener : IWindowListener
{
public:
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

    bool onKeyUp(Key up)
    {
        return false;
    }

    void onDraw(ImageRef!RGBA wfb, WindowPixelFormat pf){}
    void onResized(int width, int height){}
    void recomputeDirtyAreas(){}
    box2i getDirtyRectangle()
    {
        return box2i(0, 0, 0, 0);
    }
    bool isUIDirty()
    {
        return false;
    }
    void onMouseCaptureCancelled(){}
    void onAnimate(double dt, double time){}
}