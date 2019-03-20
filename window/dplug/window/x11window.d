/**
 * X11 window implementation.
 *
 * Copyright: Copyright (C) 2017 Richard Andrew Cattermole
 *            Copyright (C) 2017 Ethan Reker
 *            Copyright (C) 2017 Lukasz Pelszynski
 *
 * Bugs:
 *     - X11 does not support double clicks, it is sometimes emulated https://github.com/glfw/glfw/issues/462
 *
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Richard (Rikki) Andrew Cattermole
 */
module dplug.window.x11window;

import gfm.math.box;

import core.sys.posix.unistd;
import core.stdc.string;
import core.atomic;

import dplug.window.window;

import dplug.core.runtime;
import dplug.core.nogc;
import dplug.core.thread;
import dplug.core.sync;

import dplug.graphics.image;
import dplug.graphics.view;

nothrow:
@nogc:

version(linux):

import dplug.core.map;

import derelict.x11.X;
import derelict.x11.Xlib;
import derelict.x11.keysym;
import derelict.x11.keysymdef;
import derelict.x11.Xutil;
import derelict.x11.extensions.Xrandr;
import derelict.x11.extensions.randr;
import core.stdc.stdio;

// debug = logX11Window;

// This is an extension to X11, almost always should exist on modern systems
// If it becomes a problem, version out its usage, it'll work just won't be as nice event wise
extern(C) bool XkbSetDetectableAutoRepeat(Display*, bool, bool*);

__gshared XLibInitialized = false;
__gshared Display* _display;
__gshared Visual* _visual;
__gshared size_t _white_pixel, _black_pixel;
__gshared int _screen;

enum XA_CARDINAL = 6;

final class X11Window : IWindow
{
nothrow:
@nogc:

private:
    // Xlib variables
    Window _windowId, _parentWindowId;
    Atom _closeAtom;
    derelict.x11.Xlib.GC _graphicGC;
    XImage* _graphicImage;
    int depth;
    // Threads
    Thread _eventLoop, _timerLoop;
    // UncheckedMutex drawMutex;
    //Other
    IWindowListener _listener;

    ImageRef!RGBA _wfb; // framebuffer reference
    ubyte[4][] _bufferData;
    
    uint _timeAtCreationInMs;
    uint _lastMeasturedTimeInMs;
    bool _dirtyAreasAreNotYetComputed;

    int _width;
    int _height;

    uint currentTime;
    int lastMouseX, lastMouseY;

    box2i prevMergedDirtyRect, mergedDirtyRect;

    shared(bool) _terminated = false;

    Atom _XEMBED;
    Atom _XEMBED_INFO;
    enum int XEMBED_VERSION = 0;
    enum int XEMBED_MAPPED = (1 << 0);

public:
    this(void* parentWindow, /* void* transientWindowId,*/ IWindowListener listener, int width, int height)
    {
        debug(logX11Window) printf("X11Window: constructor\n");
        initializeXLib();

        int x, y;
        _listener = listener;

        if (parentWindow is null)
        {
            _parentWindowId = RootWindow(_display, _screen);
        }
        else
        {
            _parentWindowId = cast(Window)parentWindow;
        }

        x = (DisplayWidth(_display, _screen) - width) / 2;
        y = (DisplayHeight(_display, _screen) - height) / 3;
        _width = width;
        _height = height;
        _wfb = _listener.onResized(_width, _height);
        depth = 24;

        _windowId = XCreateSimpleWindow(_display, _parentWindowId, x, y, _width, _height, 0, 0, _black_pixel);
        //XStoreName(_display, _windowId, cast(char*)transientWindowId);

        XSizeHints sizeHints;
        sizeHints.flags = PMinSize | PMaxSize;
        sizeHints.min_width = _width;
        sizeHints.max_width = _width;
        sizeHints.min_height = _height;
        sizeHints.max_height = _height;

        XSetWMNormalHints(_display, _windowId, &sizeHints);

        //Setup XEMBED atoms
        _XEMBED = XInternAtom(_display, "_XEMBED", false);
        _XEMBED_INFO = XInternAtom(_display, "_XEMBED_INFO", false);
        uint[2] data = [XEMBED_VERSION, XEMBED_MAPPED];
        XChangeProperty(_display, _windowId, _XEMBED_INFO,
                        XA_CARDINAL, 32, PropModeReplace,
                        cast(ubyte*) data, 2);

        _closeAtom = XInternAtom(_display, cast(char*)("WM_DELETE_WINDOW".ptr), cast(Bool)false);
        XSetWMProtocols(_display, _windowId, &_closeAtom, 1);

        if (parentWindow) {
            // Embed the window in parent (most VST hosts expose some area for embedding a VST client)
            XReparentWindow(_display, _windowId, _parentWindowId, 0, 0);
        }

        XMapWindow(_display, _windowId);
        XFlush(_display);

        XSelectInput(_display, _windowId, windowEventMask());
        _graphicGC = XCreateGC(_display, _windowId, 0, null);
        XSetBackground(_display, _graphicGC, _white_pixel);
        XSetForeground(_display, _graphicGC, _black_pixel);

        _lastMeasturedTimeInMs = _timeAtCreationInMs = getTimeMs();

        _dirtyAreasAreNotYetComputed = true;

        emptyMergedBoxes();

        _timerLoop = makeThread(&timerLoop);
        _timerLoop.start();

        _eventLoop = makeThread(&eventLoop);
        _eventLoop.start();
        
    }

    ~this()
    { 
        XDestroyWindow(_display, _windowId);
        XFlush(_display);
        _terminated = true;
        _timerLoop.join();
        _eventLoop.join();
    }

    void initializeXLib() {
        if (!XLibInitialized) {
            XInitThreads();

            _display = XOpenDisplay(null);
            if(_display == null)
                assert(false);

            _screen = DefaultScreen(_display);
            _visual = XDefaultVisual(_display, _screen);
            _white_pixel = WhitePixel(_display, _screen);
            _black_pixel = BlackPixel(_display, _screen);
            XkbSetDetectableAutoRepeat(_display, true, null);

            XLibInitialized = true;
        }
    }

    long windowEventMask() {
        return ExposureMask | StructureNotifyMask |
            KeyReleaseMask | KeyPressMask | ButtonReleaseMask | ButtonPressMask | PointerMotionMask;
    }

    // Implements IWindow
    override void waitEventAndDispatch() nothrow @nogc
    {
        debug(logX11Window) printf("< waitEventAndDispatch\n");
        XEvent event;
        // Wait for events for current window
        XWindowEvent(_display, _windowId, windowEventMask(), &event);
        handleEvents(event, this);
        debug(logX11Window) printf("> waitEventAndDispatch\n");
    }

    void eventLoop() nothrow @nogc
    {
        debug(logX11Window) printf("< eventLoop\n");
        while (!terminated()) {
            waitEventAndDispatch();
        }
        debug(logX11Window) printf("> eventLoop\n");
    }

    void emptyMergedBoxes() nothrow @nogc
    {
        debug(logX11Window) printf("< emptyMergedBoxes\n");
        prevMergedDirtyRect = box2i(0,0,0,0);
        mergedDirtyRect = box2i(0,0,0,0);
        debug(logX11Window) printf("> emptyMergedBoxes\n");
    }

    void sendRepaintIfUIDirty() nothrow @nogc
    {
        debug(logX11Window) printf("< sendRepaintIfUIDirty\n");
        _listener.recomputeDirtyAreas();
        box2i dirtyRect = _listener.getDirtyRectangle();
        if (!dirtyRect.empty())
        {
            XEvent evt;
            memset(&evt, 0, XEvent.sizeof);
            evt.type = Expose;
            evt.xexpose.window = _windowId;
            evt.xexpose.display = _display;
            evt.xexpose.x = dirtyRect.min.x;
            evt.xexpose.y = dirtyRect.min.y;
            evt.xexpose.width = dirtyRect.width;
            evt.xexpose.height = dirtyRect.height;

            XSendEvent(_display, _windowId, False, ExposureMask, &evt);
            XFlush(_display);
        }
        debug(logX11Window) printf("> sendRepaintIfUIDirty\n");
    }

    void doAnimation()
    {
        uint now = getTimeMs();
        double dt = (now - _lastMeasturedTimeInMs) * 0.001;
        double time = (now - _timeAtCreationInMs) * 0.001; // hopefully no plug-in will be open more than 49 days
        _lastMeasturedTimeInMs = now;
        _listener.onAnimate(dt, time);
    }

    void timerLoop() nothrow @nogc
    {
        debug(logX11Window) printf("< timerLoop\n");
        while(!terminated())
        {
            doAnimation();

            _listener.recomputeDirtyAreas();
            _dirtyAreasAreNotYetComputed = false;

            sendRepaintIfUIDirty();
            sleep(1 / 60);
        }
        debug(logX11Window) printf("> timerLoop\n");
    }

    override bool terminated()
    {
        return atomicLoad(_terminated);
    }

    override uint getTimeMs()
    {
        debug(logX11Window) printf("< getTimeMs\n");
        static uint perform() {
            debug(logX11Window) printf("< perform\n");
            import core.sys.posix.sys.time;
            timeval  tv;
            gettimeofday(&tv, null);
            debug(logX11Window) printf("> perform\n");
            return cast(uint)((tv.tv_sec) * 1000 + (tv.tv_usec) / 1000 ) ;
        }
        debug(logX11Window) printf("> getTimeMs\n");
        return assumeNothrowNoGC(&perform)();
    }

    override void* systemHandle()
    {
        return cast(void*)_windowId;
    }
}

void handleEvents(ref XEvent event, X11Window theWindow) nothrow @nogc
{
    debug(logX11Window) printf("< handleEvents\n");
    with(theWindow)
    {
        
        switch(event.type)
        {
            case KeyPress:
                KeySym symbol;
                XLookupString(&event.xkey, null, 0, &symbol, null);
                _listener.onKeyDown(convertKeyFromX11(symbol));
                break;

            case KeyRelease:
                KeySym symbol;
                XLookupString(&event.xkey, null, 0, &symbol, null);
                _listener.onKeyUp(convertKeyFromX11(symbol));
                break;

            case MapNotify:
            case Expose:
                if (_dirtyAreasAreNotYetComputed)
                {
                    _dirtyAreasAreNotYetComputed = false;
                    _listener.recomputeDirtyAreas();
                }
                
                if(_graphicImage is null)
                    _graphicImage = XCreateImage(_display, _visual, depth, ZPixmap, 0, cast(char*)_wfb.pixels, _width, _height, 32, 0);
                XLockDisplay(_display);
                _listener.onDraw(WindowPixelFormat.BGRA8);
                XPutImage(_display, _windowId, _graphicGC, _graphicImage, 0, 0, 0, 0, cast(uint)_width, cast(uint)_height);
                XUnlockDisplay(_display);
                break;

            case ConfigureNotify:
                if (event.xconfigure.width != _width || event.xconfigure.height != _height)
                {
                    // Handle resize event
                    _width = event.xconfigure.width;
                    _height = event.xconfigure.height;

                    _wfb = _listener.onResized(_width, _height);
                    sendRepaintIfUIDirty();
                }
                break;

            case MotionNotify:
                int newMouseX = event.xmotion.x;
                int newMouseY = event.xmotion.y;
                int dx = newMouseX - lastMouseX;
                int dy = newMouseY - lastMouseY;

                _listener.onMouseMove(newMouseX, newMouseY, dx, dy, mouseStateFromX11(event.xbutton.state));

                lastMouseX = newMouseX;
                lastMouseY = newMouseY;
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

                bool isDoubleClick;

                lastMouseX = newMouseX;
                lastMouseY = newMouseY;

                if (event.xbutton.button == Button4 || event.xbutton.button == Button5)
                {
                    _listener.onMouseWheel(newMouseX, newMouseY, 0, event.xbutton.button == Button4 ? 1 : -1,
                        mouseStateFromX11(event.xbutton.state));
                }
                else
                {
                    _listener.onMouseClick(newMouseX, newMouseY, button, isDoubleClick, mouseStateFromX11(event.xbutton.state));
                }
                break;

            case ButtonRelease:
                int newMouseX = event.xbutton.x;
                int newMouseY = event.xbutton.y;

                MouseButton button;

                lastMouseX = newMouseX;
                lastMouseY = newMouseY;

                if (event.xbutton.button == Button1)
                    button = MouseButton.left;
                else if (event.xbutton.button == Button3)
                    button = MouseButton.right;
                else if (event.xbutton.button == Button2)
                    button = MouseButton.middle;
                else if (event.xbutton.button == Button4 || event.xbutton.button == Button5)
                    break;

                _listener.onMouseRelease(newMouseX, newMouseY, button, mouseStateFromX11(event.xbutton.state));
                break;

            case DestroyNotify:
                XDestroyImage(_graphicImage);
                XFreeGC(_display, _graphicGC);
                atomicStore(_terminated, true);
                break;

            case ClientMessage:
                // TODO Possibly not used anymore
                if (event.xclient.data.l[0] == _closeAtom)
                {
                    atomicStore(_terminated, true);
                    XDestroyImage(_graphicImage);
                    XFreeGC(_display, _graphicGC);
                    XDestroyWindow(_display, _windowId);
                    XFlush(_display);
                }
                break;

            default:
                break;
        }
    }
    debug(logX11Window) printf("> handleEvents\n");
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

MouseState mouseStateFromX11(uint state) {
    return MouseState(
        (state & Button1Mask) == Button1Mask,
        (state & Button3Mask) == Button3Mask,
        (state & Button2Mask) == Button2Mask,
        false, false,
        (state & ControlMask) == ControlMask,
        (state & ShiftMask) == ShiftMask,
        (state & Mod1Mask) == Mod1Mask);
}

