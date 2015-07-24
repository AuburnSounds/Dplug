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


    void onDraw(ImageRef!RGB wfb, bool swapRB)
    {
        if (swapRB)
            wfb.fill(RGB(0, 0, 255));
        else
            wfb.fill(RGB(255, 0, 0));
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
        return false;
    }

    override bool onMouseRelease(int x, int y, MouseButton mb, MouseState mstate)
    {
        return false;
    }

    override bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate)
    {
        return false;
    }

    override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
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
