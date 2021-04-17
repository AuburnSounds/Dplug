/**
 * X11 window implementation.
 *
 * Copyright: Copyright (C) 2017 Richard Andrew Cattermole
 *            Copyright (C) 2017 Ethan Reker
 *            Copyright (C) 2017 Lukasz Pelszynski
 *            Copyright (C) 2019-2020 Guillaume Piolat 
 *
 * Bugs:
 *     - X11 does not support double clicks, it is sometimes emulated https://github.com/glfw/glfw/issues/462
 *
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Richard (Rikki) Andrew Cattermole
 */
module dplug.window.x11window;

version(linux): // because of static linking with the X11 library

import core.atomic;
import core.stdc.string;
import core.sys.posix.unistd;
import core.sys.posix.time;

import dplug.math.box;

import derelict.x11.X;
import derelict.x11.Xlib;
import derelict.x11.keysym;
import derelict.x11.keysymdef;
import derelict.x11.Xutil;

import dplug.core.runtime;
import dplug.core.nogc;
import dplug.core.thread;
import dplug.core.sync;
import dplug.core.map;

import dplug.graphics.image;
import dplug.graphics.view;
import dplug.window.window;

nothrow:
@nogc:

//debug = logX11Window;

debug(logX11Window)
{
    import core.stdc.stdio;
}


// This is an extension to X11, almost always should exist on modern systems
// If it becomes a problem, version out its usage, it'll work just won't be as nice event wise
extern(C) bool XkbSetDetectableAutoRepeat(Display*, bool, bool*);

final class X11Window : IWindow
{
nothrow:
@nogc:
public:

    this(WindowUsage usage, void* parentWindow, IWindowListener listener, int width, int height)
    {
        debug(logX11Window) printf(">X11Window.this()\n");        

        _eventMutex = makeMutex();
        _dirtyAreaMutex = makeMutex();
        _isHostWindow = (usage == WindowUsage.host);

        assert(listener !is null);
        _listener = listener;

        bool isChildWindow = parentWindow !is null;
        acquireX11(isChildWindow);

        lockX11();

        //_parentID = cast(Window)parentWindow;
        _screen = DefaultScreen(_display);
        _visual = XDefaultVisual(_display, _screen);

        XkbSetDetectableAutoRepeat(_display, true, null);

        version(VST3) 
            _useXEmbed = true;
        else
            _useXEmbed = false;

        createX11Window(parentWindow, width, height);
        createHiddenCursor();

        _timeAtCreationInUs = getTimeUs();
        _lastMeasturedTimeInUs = _timeAtCreationInUs;
        _lastClickTimeUs = _timeAtCreationInUs;

        _timerLoop = makeThread(&timerLoopFunc);
        _timerLoop.start();
        _eventLoop = makeThread(&eventLoopFunc);
        _eventLoop.start();

        unlockX11();
        debug(logX11Window) printf("<X11Window.this()\n");
    }

    ~this()
    {     
        debug(logX11Window) printf(">X11Window.~this()\n");
        atomicStore(_terminateThreads, true);

        // Terminate event loop thread
        _eventLoop.join();

        // Terminate time thread
        _timerLoop.join();

        releaseX11Window();

        _eventMutex.destroy();

        releaseX11();
        debug(logX11Window) printf("<X11Window.~this()\n");
    }

    // <Implements IWindow>
    override void waitEventAndDispatch()
    {
        XEvent event;
        lockX11();
        XWindowEvent(_display, _windowID, windowEventMask(), &event);
        unlockX11();
        processEvent(&event);
    }

    override bool terminated()
    {
        return atomicLoad(_userRequestedTermination);
    }

    override uint getTimeMs()
    {
        static uint perform() 
        {
            import core.sys.posix.sys.time;
            timeval tv;
            gettimeofday(&tv, null);
            return cast(uint)((tv.tv_sec) * 1000 + (tv.tv_usec) / 1000 ) ;
        }
        return assumeNothrowNoGC(&perform)();
    }

    // For more precise animation
    ulong getTimeUs()
    {
        static ulong perform() 
        {
            import core.sys.posix.sys.time;
            timeval tv;
            gettimeofday(&tv, null);
            return cast(ulong)(tv.tv_sec) * 1_000_000 + tv.tv_usec;
        }
        return assumeNothrowNoGC(&perform)();
    }

    override void* systemHandle()
    {
        return cast(void*)_windowID;
    }

    override bool requestResize(int widthLogicalPixels, int heightLogicalPixels, bool alsoResizeParentWindow)
    {
        // TODO implement
        assert(false);
    }

    // </Implements IWindow>

private:

    enum int BIT_DEPTH = 24;
    enum int XEMBED_VERSION = 0;
    enum int XEMBED_MAPPED = (1 << 0);

    /// Usage of this window (host or plugin)
    bool _isHostWindow;

    /// window listener.
    IWindowListener _listener = null;  

    /// Current width of window.
    int _width = -1;

    /// Current height of window.
    int _height = -1;

    /// Framebuffer reference
    ImageRef!RGBA _wfb;

    // For debug purpose.
    bool _recomputeDirtyAreasWasCalled;

    /// Flag to tell threads to terminate. Used in thread finalization only.
    shared(bool) _terminateThreads = false; 

    /// Did the user closed the window? (when used as host window).
    shared(bool) _userRequestedTermination = false;
    
    // Time when creating this window, in microseconds.
    ulong _timeAtCreationInUs;

    /// Last time in microseconds.
    ulong  _lastMeasturedTimeInUs;

    /// Last click time (for double click emulation).
    ulong _lastClickTimeUs;

    /// This thread pump event.
    Thread _eventLoop;

    /// This thread acts like a timer.
    Thread _timerLoop;

    /// Are we using XEmbed?
    bool _useXEmbed;

    /// Last mouse position.
    bool _firstMouseMoveAfterEntering = true;
    int _lastMouseX;
    int _lastMouseY;

    /// Prevent onAnimate and all other events from going on at the same time,
    /// notably including onDraw.
    /// That way, `onAnimate`, `onDraw` and input callbacks are not concurrent,
    /// like in Windows and macOS.
    UncheckedMutex _eventMutex;   

    /// Prevent recomputeDirtyAreas() and onDraw() to be called simulatneously.
    /// This is masking a race in dplug:gui.
    /// Other window systems (Windows and Mac) prevent this race by having the 
    /// timer messages inside the same event queue, and don't run into this problem.
    /// But X11Window has to prevent this race with this mutex.
    /// Strong case of coupling!
    UncheckedMutex _dirtyAreaMutex;

    //
    // <X11 resources>
    //

    /// X11 ID of this window.
    Window _windowID;

    /// The default X11 screen of _display.
    int _screen;

    /// The default Visual of _display.
    Visual* _visual;

    /// Colormap associated with this window.
    Colormap _cmap;

    // XEmbed stuff
    Atom _XEMBED;
    Atom _XEMBED_INFO;

    Atom _closeAtom;

    /// X11 Graphics Context
    derelict.x11.Xlib.GC _graphicGC;
    XImage* _graphicImage;

    // Last MouseCursor used. This is to avoid updating the cursor
    // more often than necessary
    // Default value of pointer
    MouseCursor _lastMouseCursor = MouseCursor.pointer;

    // empty pixmap for creating an invisible cursor
    Pixmap _bitmapNoData;

    // custom defined cursor that has empty data to appear invisible
    Cursor _hiddenCursor;

    //
    // </X11 resources>
    //

    void eventLoopFunc() nothrow @nogc
    {
        // Pump events until told to terminate.
        uint pauseTimeUs = 0;

        while (true)
        {
            if (atomicLoad(_terminateThreads))
                break;

            XEvent event;
            lockX11();
            Bool found = XCheckWindowEvent(_display, _windowID, windowEventMask(), &event);
            unlockX11();
            if (found == False)
            {
                pauseTimeUs = pauseTimeUs * 2 + 1000; // exponential pause
                if (pauseTimeUs > 100_000)
                    pauseTimeUs = 100_000; // max 100ms of pause            }
                usleep(pauseTimeUs);
            }
            else
            {
                processEvent(&event);
                pauseTimeUs = 0;
            }
        }
    }

    void timerLoopFunc() nothrow @nogc
    {
        // Send repaints until told to terminate.
        while(true)
        {
            if (atomicLoad(_terminateThreads))
                break;

            doAnimation();
            sendRepaintIfUIDirty();
            setCursor();

            if (atomicLoad(_terminateThreads))
                break;

            // Sleep 1 / 60th of a second
            enum long durationInNanosecs = 1_000_000_000 / 60;
            timespec time;
            timespec rem;
            time.tv_nsec = durationInNanosecs;
            time.tv_sec  = 0;
            nanosleep(&time, &rem);
        }
    }

    void doAnimation()
    {
        ulong now = getTimeUs();
        double dt = (now - _lastMeasturedTimeInUs) * 0.001;
        double time = (now - _timeAtCreationInUs) * 0.001; // hopefully no plug-in will be open more than 49 days
        _lastMeasturedTimeInUs = now;

        _eventMutex.lock();
        _listener.onAnimate(dt, time);
        _eventMutex.unlock();
    }

    void setCursor()
    {
        version(legacyMouseCursor)
        {}
        else
        {
            MouseCursor cursor = _listener.getMouseCursor();

            if(cursor != _lastMouseCursor)
            {
                lockX11();
                immutable int x11CursorFont = convertCursorToX11CursorFont(cursor);
                auto c = cursor == MouseCursor.hidden ? _hiddenCursor : XCreateFontCursor(_display, x11CursorFont); 
                XDefineCursor(_display, _windowID, c);
                unlockX11();
            }
            _lastMouseCursor = cursor;
        }
    }

    void processEvent(XEvent* event)
    {
        switch(event.type)
        {
        case ConfigureNotify:
            notifySize(event.xconfigure.width, event.xconfigure.height);
            break;

        case EnterNotify:
            _firstMouseMoveAfterEntering = true;
            return; // nothing to do

        case Expose:
            assert(_recomputeDirtyAreasWasCalled);

            // Draw UI
            _eventMutex.lock();
            _dirtyAreaMutex.lock();
            _listener.onDraw(WindowPixelFormat.BGRA8);
            _dirtyAreaMutex.unlock();
            _eventMutex.unlock();

            XExposeEvent* xpose = cast(XExposeEvent*)event;

            // Find dirty rect from event
            int x = xpose.x;
            int y = xpose.y;
            int width = xpose.width;
            int height = xpose.height;

            lockX11();
            XPutImage(_display, 
                      _windowID,
                      _graphicGC, 
                      _graphicImage, 
                      x, y, // source position
                      x, y, // dest position
                      width,
                      height);
            unlockX11();
            break;

        case ReparentNotify:
            break; // do nothing

        case KeyPress:
            KeySym symbol;
            lockX11();
            XLookupString(&event.xkey, null, 0, &symbol, null);
            unlockX11();
            _eventMutex.lock();
            _listener.onKeyDown(convertKeyFromX11(symbol));
            _eventMutex.unlock();
            break;

        case KeyRelease:
            KeySym symbol;
            lockX11();
            XLookupString(&event.xkey, null, 0, &symbol, null);
            unlockX11();
            _eventMutex.lock();
            _listener.onKeyUp(convertKeyFromX11(symbol));
            _eventMutex.unlock();
            break;

        case MotionNotify:
            int newMouseX = event.xmotion.x;
            int newMouseY = event.xmotion.y;

            if (_firstMouseMoveAfterEntering)
            {
                _lastMouseX = newMouseX;
                _lastMouseY = newMouseY;
                _firstMouseMoveAfterEntering = false;                    
            }

            int dx = newMouseX - _lastMouseX;
            int dy = newMouseY - _lastMouseY;
            _eventMutex.lock();
            _listener.onMouseMove(newMouseX, newMouseY, dx, dy, mouseStateFromX11(event.xbutton.state));
            _eventMutex.unlock();
            _lastMouseX = newMouseX;
            _lastMouseY = newMouseY;
            break;

        case ButtonPress:
            int newMouseX = event.xbutton.x;
            int newMouseY = event.xbutton.y;
            MouseButton button;
            if (event.xbutton.button == Button1)
                button = MouseButton.left;
            else if (event.xbutton.button == Button3)
                button = MouseButton.right;
            else if (event.xbutton.button == Button2)
                button = MouseButton.middle;
            else if (event.xbutton.button == Button4)
                button = MouseButton.x1;
            else if (event.xbutton.button == Button5)
                button = MouseButton.x2;

            ulong now = getTimeUs();
            bool isDoubleClick = now - _lastClickTimeUs <= 500_000; // 500 ms
            _lastClickTimeUs = now;

            _lastMouseX = newMouseX;
            _lastMouseY = newMouseY;

            _eventMutex.lock();
            if (event.xbutton.button == Button4 || event.xbutton.button == Button5)
            {
                _listener.onMouseWheel(newMouseX, newMouseY, 0, event.xbutton.button == Button4 ? 1 : -1,
                    mouseStateFromX11(event.xbutton.state));
            }
            else
            {
                _listener.onMouseClick(newMouseX, newMouseY, button, isDoubleClick, mouseStateFromX11(event.xbutton.state));
            }
            _eventMutex.unlock();
            break;

        case ButtonRelease:
            int newMouseX = event.xbutton.x;
            int newMouseY = event.xbutton.y;

            MouseButton button;

            _lastMouseX = newMouseX;
            _lastMouseY = newMouseY;

            if (event.xbutton.button == Button1)
                button = MouseButton.left;
            else if (event.xbutton.button == Button3)
                button = MouseButton.right;
            else if (event.xbutton.button == Button2)
                button = MouseButton.middle;
            else if (event.xbutton.button == Button4 || event.xbutton.button == Button5)
                break;

            _eventMutex.lock();
            _listener.onMouseRelease(newMouseX, newMouseY, button, mouseStateFromX11(event.xbutton.state));
            _eventMutex.unlock();
            break;

        case DestroyNotify:
            atomicStore(_userRequestedTermination, true);
            break;

        default:
            string s = X11EventTypeString(event.type);           
            debug(logX11Window) printf("Unhandled event %d (%s)\n", event.type, s.ptr);
        }
    }

    void notifySize(int width, int height)
    {
        if (width != _width || height != _height)
        {
            _width = width;
            _height = height;

            _eventMutex.lock();
            _dirtyAreaMutex.lock();
            _wfb = _listener.onResized(width, height);
            _dirtyAreaMutex.unlock();
            _eventMutex.unlock();

            // reallocates backbuffer (if any)
            freeBackbuffer();

            // and recreates it at the right size
            assert(_visual);
            lockX11();
            _graphicImage = XCreateImage(_display, 
                            _visual, 
                            BIT_DEPTH, 
                            ZPixmap, 
                            0, 
                            cast(char*)_wfb.pixels, 
                            _width, 
                            _height, 
                            32, 
                            0);
            unlockX11();
        }
    }

    void sendRepaintIfUIDirty() nothrow @nogc
    {
        box2i dirtyRect;
        _dirtyAreaMutex.lock();
        {
            _listener.recomputeDirtyAreas();
            _recomputeDirtyAreasWasCalled = true;
            dirtyRect = _listener.getDirtyRectangle();
        }
        _dirtyAreaMutex.unlock();

        if (!dirtyRect.empty())
        {
            XEvent evt;
            memset(&evt, 0, XEvent.sizeof);
            evt.type = Expose;
            evt.xexpose.window = _windowID;
            evt.xexpose.display = _display;
            evt.xexpose.x = dirtyRect.min.x;
            evt.xexpose.y = dirtyRect.min.y;
            evt.xexpose.width = dirtyRect.width;
            evt.xexpose.height = dirtyRect.height;
            lockX11();
            XSendEvent(_display, _windowID, False, ExposureMask, &evt);
            XFlush(_display);
            unlockX11();
        }
    }

    void createX11Window(void* parentWindow, int width, int height)
    {
        // Note: this is already locked by constructor

        // Find the parent Window ID if none provided
        Window parentWindowID;
        if (parentWindow is null)
            parentWindowID = RootWindow(_display, _screen);
        else
            parentWindowID = cast(Window)parentWindow;

        _cmap = XCreateColormap(_display, parentWindowID, _visual, AllocNone);

        XSetWindowAttributes attr;
        memset(&attr, 0, XSetWindowAttributes.sizeof);
        attr.border_pixel = BlackPixel(_display, _screen);
        attr.colormap     = _cmap;
        attr.event_mask   = windowEventMask();

        int left = 0;
        int top = 0;
        int border_width = 0;
        _windowID = XCreateWindow(_display, 
                                  parentWindowID, 
                                  left, top, 
                                  width, height, border_width, 
                                  BIT_DEPTH, 
                                  InputOutput, 
                                  _visual, 
                                  CWBorderPixel | CWColormap | CWEventMask,  // TODO we need all this?
                                  &attr);
        

        // in case ConfigureNotiy isn't sent
        // this create t
        notifySize(width, height);

        // MAYDO: Is it necessary? seems not.
        // XResizeWindow(_display, _windowID, width, height);

        _closeAtom = XInternAtom(_display, "WM_DELETE_WINDOW", False);
        XSetWMProtocols(_display, _windowID, &_closeAtom , 1);
        
        if(_useXEmbed)
        {
            //Setup XEMBED atoms
            _XEMBED = XInternAtom(_display, "_XEMBED", false);
            _XEMBED_INFO = XInternAtom(_display, "_XEMBED_INFO", false);
            uint[2] data = [XEMBED_VERSION, XEMBED_MAPPED];
            enum XA_CARDINAL = 6;
            XChangeProperty(_display, _windowID, _XEMBED_INFO,
                            XA_CARDINAL, 32, PropModeReplace,
                            cast(ubyte*) data, 2);

            if(parentWindow)
            {
                XReparentWindow(_display, _windowID, parentWindowID, 0, 0);
            }
        }

        // MAYDO possible could be XMapWindow I guess
        XMapRaised(_display, _windowID);
        XSelectInput(_display, _windowID, windowEventMask());

        _graphicGC = XCreateGC(_display, _windowID, 0, null);
    }

    void releaseX11Window()
    {
        // release all X11 resource allocated by createX11Window
        lockX11();
        XFreeCursor(_display, _hiddenCursor);
        XFreePixmap(_display, _bitmapNoData);
        XFreeColormap(_display, _cmap);
        XFreeGC(_display, _graphicGC);
        freeBackbuffer();
        XDestroyWindow(_display, _windowID);

        // We need to flush all window events from the queue that are related to this window.
        // Else another open instance may read message from this window and crash.
        XSync(_display, false);
        XEvent event;
        while(true)
        {
            Bool found = XCheckWindowEvent(_display, _windowID, windowEventMask(), &event);
            if (!found) break;
        }

        unlockX11();
    }

    // this frees _graphicImage
    void freeBackbuffer()
    {
        // For some reason freeing that buffer is crashing X11
     /+   if (_graphicImage)
        {
            lockX11();
            XDestroyImage(_graphicImage);
            unlockX11();
            _graphicImage = null;
        } +/
    }    

    // which X11 events we are interested in

    uint windowEventMask() 
    {
        return ExposureMask 
             | StructureNotifyMask
             | KeyReleaseMask
             | KeyPressMask
             | ButtonReleaseMask
             | ButtonPressMask
             | PointerMotionMask
             | EnterWindowMask;
    }

    void createHiddenCursor()
    {
        XColor black;
        static char[] noData = [0,0,0,0,0,0,0,0];
        black.red = black.green = black.blue = 0;

        _bitmapNoData = XCreateBitmapFromData(_display, _windowID, noData.ptr, 8, 8);
        _hiddenCursor = XCreatePixmapCursor(_display, _bitmapNoData, _bitmapNoData, &black, &black, 0, 0);
    }
}

private:

debug(logX11Window) 
{
    extern(C) int X11ErrorHandler(Display* display, XErrorEvent* event)
    {
        char[128] buf;
        lockX11();
        XGetErrorText(display, event.error_code, buf.ptr, 128); 
        unlockX11();
        printf("Error = %s\n", buf.ptr);
        assert(false);
    }
}

Key convertKeyFromX11(KeySym symbol)
{
    switch(symbol)
    {
        case XK_space:
            return Key.space;

        case XK_Up:
            return Key.upArrow;

        case XK_Down:
            return Key.downArrow;

        case XK_Left:
            return Key.leftArrow;

        case XK_Right:
            return Key.rightArrow;

        case XK_0: .. case XK_9:
            return cast(Key)(Key.digit0 + (symbol - XK_0));

        case XK_KP_0: .. case XK_KP_9:
            return cast(Key)(Key.digit0 + (symbol - XK_KP_0));

        case XK_A: .. case XK_Z:
            return cast(Key)(Key.A + (symbol - XK_A));

        case XK_a: .. case XK_z:
            return cast(Key)(Key.a + (symbol - XK_a));

        case XK_Return:
        case XK_KP_Enter:
            return Key.enter;

        case XK_Escape:
            return Key.escape;

        case XK_BackSpace:
            return Key.backspace;

        default:
            return Key.unsupported;
    }
}

MouseState mouseStateFromX11(uint state) 
{
    return MouseState(
        (state & Button1Mask) == Button1Mask,
        (state & Button3Mask) == Button3Mask,
        (state & Button2Mask) == Button2Mask,
        false, false,
        (state & ControlMask) == ControlMask,
        (state & ShiftMask) == ShiftMask,
        (state & Mod1Mask) == Mod1Mask);
}

// Check if the X11 operation has completed correctly
void checkX11Status(Status err)
{
    if (err == 0)
        assert(false); // There was an error
}


// <X11 initialization>

shared(int) _x11Counter = 0;
__gshared Display* _display;

/// Protects every X11 call. This is because as a plugin we cannot call XInitThreads() 
/// to ensure thread safety.
/// Note that like the connection, this is shared across plugin instances...
__gshared UncheckedMutex _x11Mutex;

void lockX11()
{
    _x11Mutex.lock();
}

void unlockX11()
{
    _x11Mutex.unlock();
}

void acquireX11(bool isAChildwindow)
{
    // Note: this is racey, if you open two plugins exactly at once, it might race
    if (atomicOp!"+="(_x11Counter, 1) == 1)
    {
        _x11Mutex = makeMutex();
        debug(logX11Window)
        {
            XSetErrorHandler(&X11ErrorHandler);
        }

        // "On a POSIX-conformant system, if the display_name is NULL, 
        // it defaults to the value of the DISPLAY environment variable."
        _display = XOpenDisplay(null);

        if(_display == null)
            assert(false);

        debug(logX11Window)
            XSynchronize(_display, False);
    }
    else
    {
        usleep(20); // Dumb protection against X11 initialization race.
    }
}

void releaseX11()
{
    if (atomicOp!"-="(_x11Counter, 1) == 0)
    {
        XCloseDisplay(_display);
        _x11Mutex.destroy();
    }
}


string X11EventTypeString(int type)
{
    string s = "Unknown event";
    if (type == 2) s = "KeyPress";
    if (type == 3) s = "KeyRelease";
    if (type == 4) s = "ButtonPress";
    if (type == 5) s = "ButtonRelease";
    if (type == 6) s = "MotionNotify";
    if (type == 7) s = "EnterNotify";
    if (type == 8) s = "LeaveNotify";
    if (type == 9) s = "FocusIn";
    if (type == 10) s = "FocusOut";
    if (type == 11) s = "KeymapNotify";
    if (type == 12) s = "Expose";
    if (type == 13) s = "GraphicsExpose";
    if (type == 14) s = "NoExpose";
    if (type == 15) s = "VisibilityNotify";
    if (type == 16) s = "CreateNotify";
    if (type == 17) s = "DestroyNotify";
    if (type == 18) s = "UnmapNotify";
    if (type == 19) s = "MapNotify";
    if (type == 20) s = "MapRequest";
    if (type == 21) s = "ReparentNotify";
    if (type == 22) s = "ConfigureNotify";
    if (type == 23) s = "ConfigureRequest";
    if (type == 24) s = "GravityNotify";
    if (type == 25) s = "ResizeRequest";
    if (type == 26) s = "CirculateNotify";
    if (type == 27) s = "CirculateRequest";
    if (type == 28) s = "PropertyNotify";
    if (type == 29) s = "SelectionClear";
    if (type == 30) s = "SelectionRequest";
    if (type == 31) s = "SelectionNotify";
    if (type == 32) s = "ColormapNotify";
    if (type == 33) s = "ClientMessage";
    if (type == 34) s = "MappingNotify";
    if (type == 35) s = "GenericEvent";
    if (type == 36) s = "LASTEvent";
    return s;
}

int convertCursorToX11CursorFont(MouseCursor cursor)
{
    switch(cursor)
    {

        case cursor.linkSelect:
            return 60;
        case cursor.drag:
            return 58;
        case cursor.move:
            return 34;
        case cursor.horizontalResize:
            return 116;
        case cursor.verticalResize:
            return 108;
        case cursor.diagonalResize:
            return 14;
        case cursor.pointer:
        default:
            return 2;
    }
}