/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
import std.typecons;
import std.stdio;

import ae.utils.graphics;
import dplug.window;


// Stand-alone program to test windowing alone.

void main(string[] args)
{
    auto app = scoped!App();

    app.mainloop();
    
}


class App : IWindowListener
{
    IWindow window;
    int _width;
    int _height;

    this()
    {
        window = createWindow(null, this, 640, 480);
    }

    void mainloop()
    {
        while(!window.terminated)
        {
            window.waitEventAndDispatch();
        }
    }


    void onDraw(ImageRef!RGBA wfb, bool swapRB)
    {
        if (swapRB)
            wfb.fill(RGBA(0, 128, 255, 255));
        else
            wfb.fill(RGBA(255, 128, 0, 255));
    }

    void onResized(int width, int height)
    {
        _width = width;
        _height = height;
    }

    
    override void recomputeDirtyAreas()
    {
        // do nothing
    }

    
    override box2i getDirtyRectangle()
    {
        return box2i(0, 0, _width, _height);
    }

    bool isUIDirty()
    {
        return true; // UI is always dirty
    }

    override void onMouseCaptureCancelled()
    {
    }

    override void onAnimate(double dt, double time)
    {
    }

    override bool onMouseClick(int x, int y, MouseButton mb, bool isDoubleClick, MouseState mstate)
    {
        writefln("onMouseClick(%s, %s, %s, %s)", x, y, mb, isDoubleClick);
        return false;
    }

    override bool onMouseRelease(int x, int y, MouseButton mb, MouseState mstate)
    {
        writefln("onMouseRelease(%s, %s, %s)", x, y, mb);
        return false;
    }

    override bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate)
    {
        writefln("onMouseWheel(%s, %s, %s, %s)", x, y, wheelDeltaX, wheelDeltaY);
        return false;
    }

    override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
        writefln("onMouseMove(%s, %s, %s, %s)", x, y, dx, dy);
    }

    override bool onKeyDown(Key key)
    {
        writeln("onKeyDown");
        if (key == Key.escape)
        {
            window.terminate();
            return true;
        }
        return false;
    }

    override bool onKeyUp(Key up)
    {
        writeln("onKeyUp");
        return false;
    }
}
