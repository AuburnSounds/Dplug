/**
* Copyright: Copyright Auburn Sounds 2015 - 2017.
*            Copyright Richard Andrew Cattermole 2017.
*
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.window.window;

import gfm.math.box;

import dplug.core.nogc;
import dplug.graphics.image;
import dplug.graphics.view;

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
    enter,
    escape,
    unsupported // special value, means "other"
};

enum MouseButton
{
    left,
    right,
    middle,
    x1,
    x2
}

struct MouseState
{
    bool leftButtonDown;
    bool rightButtonDown;
    bool middleButtonDown;
    bool x1ButtonDown;
    bool x2ButtonDown;
    bool ctrlPressed;
    bool shiftPressed;
    bool altPressed;
}

// Giving commands to a window
interface IWindow
{
nothrow:
@nogc:
    // To put in your message loop
    void waitEventAndDispatch();

    // If exit was requested
    bool terminated();

    // Profile-purpose: get time in milliseconds.
    // Use the results of this function for deltas only.
    uint getTimeMs();

    // Get the OS window handle.
    void* systemHandle();
}

enum WindowPixelFormat
{
    BGRA8,
    ARGB8,
    RGBA8
}

// Receiving commands from a window
interface IWindowListener
{
nothrow @nogc:
    /// Called on mouse click.
    /// Returns: true if the event was handled.
    bool onMouseClick(int x, int y, MouseButton mb, bool isDoubleClick, MouseState mstate);

    /// Called on mouse button release
    /// Returns: true if the event was handled.
    bool onMouseRelease(int x, int y, MouseButton mb, MouseState mstate);

    /// Called on mouse wheel movement
    /// Returns: true if the event was handled.
    bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate);

    /// Called on mouse movement (might not be within the window)
    void onMouseMove(int x, int y, int dx, int dy, MouseState mstate);

    /// Called on keyboard press.
    /// Returns: true if the event was handled.
    bool onKeyDown(Key key);

    /// Called on keyboard release.
    /// Returns: true if the event was handled.
    bool onKeyUp(Key up);

    /// An image you have to draw to, or return that nothing has changed.
    /// The location of this image is given before-hand by onResized.
    /// recomputeDirtyAreas() MUST have been called before.
    /// The pixel format cannot change over the lifetime of the window.
    void onDraw(WindowPixelFormat pf);

	/// Called when a drag and drop operation completes
	void onDragDrop(scope string filename, int x, int y);

	/// Is drag and drop operations supported?
	bool supportsDragAndDrop();

    /// The drawing area size has changed.
    /// Always called at least once before onDraw.
    /// Returns: the location of the full rendered framebuffer.
    ImageRef!RGBA onResized(int width, int height);

    /// Recompute internally what needs be done for the next onDraw.
    /// This function MUST be called before calling `onDraw` and `getDirtyRectangle`.
    /// This method exists to allow the Window to recompute these draw lists less.
    /// And because cache invalidation was easier on user code than internally in the UI.
    void recomputeDirtyAreas();

    /// Returns: Minimal rectangle that contains dirty UIELement in UI + their graphical extent.
    ///          Empty box if nothing to update.
    /// recomputeDirtyAreas() MUST have been called before.
    box2i getDirtyRectangle();

    /// Called whenever mouse capture was canceled (ALT + TAB, SetForegroundWindow...)
    void onMouseCaptureCancelled();

    /// Must be called periodically (ideally 60 times per second but this is not mandatory).
    /// `time` must refer to the window creation time.
    /// `dt` and `time` are expressed in seconds (not milliseconds).
    void onAnimate(double dt, double time);
}


enum WindowBackend
{
    autodetect,
    win32,
    carbon,
    cocoa,
    x11
}


/// Factory function to create windows.
/// The window is allocated with `mallocNew` and should be destroyed with `destroyFree`.
/// Returns: null if this backend isn't available on this platform.
/// Note: controlInfo is only used by Carbon + AU, can be null otherwise
nothrow @nogc
IWindow createWindow(void* parentInfo, void* controlInfo, IWindowListener listener, WindowBackend backend, int width, int height)
{
    static WindowBackend autoDetectBackend() nothrow @nogc
    {
        version(Windows)
            return WindowBackend.win32;
        else version(OSX)
        {
            version(X86_64)
            {
                return WindowBackend.cocoa;
            }
            else
            {
                return WindowBackend.carbon;
            }
        }
        else version(linux)
        {
            return WindowBackend.x11;
        }
        else
            static assert(false, "Unsupported OS");
    }

    if (backend == WindowBackend.autodetect)
        backend = autoDetectBackend();

    version(Windows)
    {
        if (backend == WindowBackend.win32)
        {
            import core.sys.windows.windef;
            import dplug.window.win32window;
            HWND parent = cast(HWND)parentInfo;
            return mallocNew!Win32Window(parent, listener, width, height);
        }
        else
            return null;
    }
    else version(OSX)
    {
        if (backend == WindowBackend.cocoa)
        {
            import dplug.window.cocoawindow;
            return mallocNew!CocoaWindow(parentInfo, listener, width, height);
        }
        else if (backend == WindowBackend.carbon)
        {
            import dplug.window.carbonwindow;
            return mallocNew!CarbonWindow(parentInfo, controlInfo, listener, width, height);
        }
        else
            return null;
    }
    else version(linux)
    {
        if (backend == WindowBackend.x11)
        {
            import dplug.window.x11window;
            return mallocNew!X11Window(null, listener, width, height);
        }
        else
            return null;
    }
    else
    {
        static assert(false, "Unsupported OS.");
    }
}

