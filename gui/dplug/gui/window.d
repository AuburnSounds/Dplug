module dplug.gui.window;

import ae.utils.graphics;

enum Key
{
    space,
    upArrow,
    downArrow,
    leftArrow,
    rightArrow,
    digit0,
    digit1,
    digit2,
    digit3,
    digit4,
    digit5,
    digit6,
    digit7,
    digit8,
    digit9,
    enter
};

enum MouseButton
{
    left,
    right,
    middle,
    x1,
    x2
}

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
    // Called on mouse click
    void onMouseClick(int x, int y, MouseButton mb, bool isDoubleClick);

    // Called on mouse button release
    void onMouseRelease(int x, int y, MouseButton mb);

    // Called on mouse wheel movement
    void onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY);

    // Called on mouse movement (might not be within the window)
    void onMouseMove(int x, int y, int dx, int dy);

    // Called on keyboard press
    void onKeyDown(int x, int y, Key key);

    // Called on keyboard release
    void onKeyUp(int x, int y, Key up);

    // An image you have to draw to, or return that nothing has changed
    void onDraw(ImageRef!RGBA wfb, out bool needRedraw); // TODO: return just a region to save uploading bits
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