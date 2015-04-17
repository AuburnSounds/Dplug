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

struct WindowFrameBuffer
{
    ubyte* pixels;  // RGBA data, height x scanlines with contiguous pixels
    int width;      // width of image
    int height;     // height of image
    int byteStride; // offset between scanlines, in bytes
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
    void onKeyDown(Key key);
    void onKeyUp(Key up);

    // an image you have to draw to, or return that nothing has changed
    void onDraw(WindowFrameBuffer wfb, out bool needRedraw); // TODO: return just a region!
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