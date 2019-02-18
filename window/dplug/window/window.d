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
    a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z,
    A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
    backspace,
    enter,
    escape,
    unsupported // special value, means "other"
};

public dchar getCharFromKey(Key key) nothrow @nogc
{
    switch(key)
    {
        case Key.backspace: return '\t';
        case Key.digit0: .. case Key.digit9: return cast(dchar)('0' + (key - Key.digit0));
        case Key.a: .. case Key.z: return cast(dchar)('a' + (key - Key.a));
        case Key.A: .. case Key.Z: return cast(dchar)('A' + (key - Key.A));
        case Key.space : return ' ';
        default: return '\0';
    }
}

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

/// Is this window intended as a plug-in window running inside a host,
/// or a host window itself possibly hosting a plug-in?
enum WindowUsage
{
    /// This window is intended to be for displaying a plugin UI.
    /// Event pumping is done by the host (except in the X11 case where it's
    /// done by an internal thread).
    plugin,

    /// This window is intended to be top-level, for hosting another OS window.
    /// Event pumping will be done by the caller manually through
    /// Important: This case is not the nominal case.
    ///            Some calls to the `IWindowListener` will make no sense.
    host
}

/// Giving commands to a window.
interface IWindow
{
nothrow:
@nogc:
    /// To put in your message loop.
    /// This call should only be used if the window was
    /// created with `WindowUsage.host`.
    /// Else, event pumping is managed by the host or internally (X11).
    void waitEventAndDispatch();

    /// If exit was requested.
    /// This call should only be used if the window was
    /// created with `WindowUsage.host`.
    /// In the case of a plug-in, the plugin client will request
    /// termination of the window through its destructor.
    bool terminated();

    /// Profile-purpose: get time in milliseconds.
    /// Use the results of this function for deltas only.
    uint getTimeMs();

    /// Gets the window's OS handle.
    void* systemHandle();
}

enum WindowPixelFormat
{
    BGRA8,
    ARGB8,
    RGBA8
}

/// Receiving commands from a window.
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

    /// Render the window in software in the buffer previously returned by `onResized`.
    /// At the end of this function, the whole buffer should be a valid, coherent UI.
    ///
    /// recomputeDirtyAreas() MUST have been called before this is called.
    /// The pixel format cannot change over the lifetime of the window.
    ///
    /// `onDraw` guarantees the pixels to be in the format requested by `pf`, and it also
    /// guarantees that the alpha channel will be filled with 255.
    void onDraw(WindowPixelFormat pf);

    /// The drawing area size has changed.
    /// Always called at least once before onDraw.
    /// Returns: the location of the full rendered framebuffer.
    ImageRef!RGBA onResized(int width, int height);

    /// Recompute internally what needs be done for the next onDraw.
    /// This function MUST have been called before calling `onDraw` and `getDirtyRectangle`.
    /// This method exists to allow the Window to recompute these draw lists less.
    /// And because cache invalidation was easier on user code than internally in the UI.
    /// Important: once you've called `recomputeDirtyAreas()` you COMMIT to redraw the
    /// corresponding area given by `getDirtyRectangle()`.
    /// IMPORTANT: Two calls to `recomputeDirtyAreas()` will not yield the same area.
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

/// Various backends for windowing.
enum WindowBackend
{
    autodetect,
    win32,
    carbon,
    cocoa,
    x11
}

/// Returns: `true` if that windowing backend is supported on this platform.
static isWindowBackendSupported(WindowBackend backend) nothrow @nogc
{
    version(Windows)
        return (backend == WindowBackend.win32);
    else version(OSX)
    {
        version(X86_64)
            return (backend == WindowBackend.cocoa);
        else version(X86)
            return (backend == WindowBackend.cocoa) || (backend == WindowBackend.carbon); // Cocoa supported in 32-bit also
        else
            static assert(false, "unsupported arch");
    }
    else version(linux)
        return (backend == WindowBackend.x11);
    else
        static assert(false, "Unsupported OS");
}



/// Factory function to create windows.
///
/// The window is allocated with `mallocNew` and should be destroyed with `destroyFree`.
///
/// Returns: null if this backend isn't available on this platform.
///
/// Params:
///   usage = Intended usage of the window.
///
///   parentInfo = OS handle of the parent window.
///                For `WindowBackend.win32` it's a HWND.
///                For `WindowBackend.carbon` it's a NSWindow.
///                For `WindowBackend.x11` it's _unused_.
///
///   controlInfo = only used in Carbon Audio Units, an additional parenting information.
///                 Can be `null` otherwise.
///
///   listener = A `IWindowListener` which listens to events by this window. Can be `null` for the moment.
///              Must outlive the created window.
///
///   backend = Which windowing sub-system is used. Only Mac has any choice in this.
///             Should be `WindowBackend.autodetect` in almost all cases
///
///   width = Initial width of the window.
///
///   height = Initial height of the window.
///
nothrow @nogc
IWindow createWindow(WindowUsage usage,
                     void* parentInfo,
                     void* controlInfo,
                     IWindowListener listener,
                     WindowBackend backend,
                     int width,
                     int height)
{
    //MAYDO  `null` listeners not accepted anymore.
    //assert(listener !is null);

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
            return mallocNew!CocoaWindow(usage, parentInfo, listener, width, height);
        }
        else if (backend == WindowBackend.carbon)
        {
            import dplug.window.carbonwindow;
            return mallocNew!CarbonWindow(usage, parentInfo, controlInfo, listener, width, height);
        }
        else
            return null;
    }
    else version(linux)
    {
        if (backend == WindowBackend.x11)
        {
            import dplug.window.x11window;
            return mallocNew!X11Window(parentInfo, listener, width, height);
        }
        else
            return null;
    }
    else
    {
        static assert(false, "Unsupported OS.");
    }
}
