module dplug.gui.window;

import gfm.math;

import ae.utils.graphics;

import dplug.gui.types;

// Giving commands to a window
interface IWindow
{
    // To put in your message loop
    void waitEventAndDispatch();

    // If exit was requested
    bool terminated();

    // request exit
    void terminate();
}

// Receiving commands from a window
interface IWindowListener
{
    // Called on mouse click.
    // Returns: true if the event was handled.
    bool onMouseClick(int x, int y, MouseButton mb, bool isDoubleClick);

    // Called on mouse button release
    // Returns: true if the event was handled.
    bool onMouseRelease(int x, int y, MouseButton mb);

    // Called on mouse wheel movement
    // Returns: true if the event was handled.
    bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY);

    // Called on mouse movement (might not be within the window)
    void onMouseMove(int x, int y, int dx, int dy);

    // Called on keyboard press.
    // Returns: true if the event was handled.
    bool onKeyDown(Key key);

    // Called on keyboard release.
    // Returns: true if the event was handled.
    bool onKeyUp(Key up);

    /// An image you have to draw to, or return that nothing has changed
    /// Returns: the non-overlapping rectangles area that should be updated
    box2i[] onDraw(ImageRef!RGBA wfb);

    // Called whenever mouse capture was canceled (ALT + TAB, SetForegroundWindow...)
    void onMouseCaptureCancelled();
}



// Factory function
IWindow createWindow(void* parentInfo, IWindowListener listener, int width, int height)
{
    version(Windows)
    {
        import win32.windef;
        import dplug.gui.win32window;
        HWND parent = cast(HWND)parentInfo;
        return new Win32Window(parent, listener, width, height);
    }
    else
        return null;
}