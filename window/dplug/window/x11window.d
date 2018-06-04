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

// This is an extension to X11, almost always should exist on modern systems
// If it becomes a problem, version out its usage, it'll work just won't be as nice event wise
extern(C) bool XkbSetDetectableAutoRepeat(Display*, bool, bool*);

__gshared XLibInitialized = false;
__gshared Display* _display;
__gshared Visual* _visual;
__gshared size_t _white_pixel, _black_pixel;
__gshared int _screen;

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
    int width, height, depth;
    // Threads
    Thread _eventLoop, _timerLoop;
    UncheckedMutex drawMutex;
    //Other
    IWindowListener listener;

    ImageRef!RGBA _wfb; // framebuffer reference
    ubyte[4][] _bufferData;

    uint lastTimeGot, creationTime, currentTime;
    int lastMouseX, lastMouseY;

    box2i prevMergedDirtyRect, mergedDirtyRect;

    shared(bool) _terminated = false;

public:
    this(void* parentWindow, IWindowListener listener, int width, int height)
    {
        drawMutex = makeMutex();

        initializeXLib();

        int x, y;
        this.listener = listener;

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
        this.width = width;
        this.height = height;
        depth = 24;

        //

        _windowId = XCreateSimpleWindow(_display, _parentWindowId, x, y, width, height, 0, 0, _black_pixel);
        XStoreName(_display, _windowId, cast(char*)" ".ptr);

        XSizeHints sizeHints;
        sizeHints.flags = PMinSize | PMaxSize;
        sizeHints.min_width = width;
        sizeHints.max_width = width;
        sizeHints.min_height = height;
        sizeHints.max_height = height;

        XSetWMNormalHints(_display, _windowId, &sizeHints);

        //

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

        _wfb = listener.onResized(width, height);

        creationTime = getTimeMs();
        lastTimeGot = creationTime;

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

    void swapBuffers(ImageRef!RGBA wfb, box2i[] areasToRedraw)
    {
        if (_bufferData.length != wfb.w * wfb.h)
        {
            _bufferData = mallocSlice!(ubyte[4])(wfb.w * wfb.h);

            if (_graphicImage !is null)
            {
                // X11 deallocates _bufferData for us (ugh...)
                XDestroyImage(_graphicImage);
            }

            _graphicImage = XCreateImage(_display, _visual, depth, ZPixmap, 0, cast(char*)_bufferData.ptr, width, height, 32, 0);

            size_t i;
            foreach(y; 0 .. wfb.h)
            {
                RGBA[] scanLine = wfb.scanline(y);
                foreach(x, ref c; scanLine)
                {
                    _bufferData[i][0] = c.b;
                    _bufferData[i][1] = c.g;
                    _bufferData[i][2] = c.r;
                    _bufferData[i][3] = c.a;
                    i++;
                }
            }
        }
        else
        {
            foreach(box2i area; areasToRedraw)
            {
                foreach(y; area.min.y .. area.max.y)
                {
                    RGBA[] scanLine = wfb.scanline(y);

                    size_t i = y * wfb.w;
                    i += area.min.x;

                    foreach(x, ref c; scanLine[area.min.x .. area.max.x])
                    {
                        _bufferData[i][0] = c.b;
                        _bufferData[i][1] = c.g;
                        _bufferData[i][2] = c.r;
                        _bufferData[i][3] = c.a;
                        i++;
                    }
                }
            }
        }

        XPutImage(_display, _windowId, _graphicGC, _graphicImage, 0, 0, 0, 0, cast(uint)width, cast(uint)height);
    }

    // Implements IWindow
    override void waitEventAndDispatch() nothrow @nogc
    {
        XEvent event;
        // Wait for events for current window
        XWindowEvent(_display, _windowId, windowEventMask(), &event);
        handleEvents(event, this);
    }

    void eventLoop() nothrow @nogc
    {
        while (!terminated()) {
            waitEventAndDispatch();
        }
    }

    void emptyMergedBoxes() nothrow @nogc
    {
        prevMergedDirtyRect = box2i(0,0,0,0);
        mergedDirtyRect = box2i(0,0,0,0);
    }

    void sendRepaintIfUIDirty() nothrow @nogc
    {
        listener.recomputeDirtyAreas();
        box2i dirtyRect = listener.getDirtyRectangle();
        if (!dirtyRect.empty())
        {
            drawMutex.lock();

            prevMergedDirtyRect = mergedDirtyRect;
            mergedDirtyRect = mergedDirtyRect.expand(dirtyRect);
            // If everything has been drawn by Expose event handler, send Expose event.
            // Otherwise merge areas to be redrawn and postpone Expose event.
            if (prevMergedDirtyRect.empty() && !mergedDirtyRect.empty()) {
                int x = dirtyRect.min.x;
                int y = dirtyRect.min.y;
                int width = dirtyRect.max.x - x;
                int height = dirtyRect.max.y - y;

                XEvent evt;
                memset(&evt, 0, XEvent.sizeof);
                evt.type = Expose;
                evt.xexpose.window = _windowId;
                evt.xexpose.display = _display;
                evt.xexpose.x = 0;
                evt.xexpose.y = 0;
                evt.xexpose.width = 0;
                evt.xexpose.height = 0;

                XSendEvent(_display, _windowId, False, ExposureMask, &evt);
                XFlush(_display);
            }

            drawMutex.unlock();
        }
    }

    void timerLoop() nothrow @nogc
    {
        while(!terminated())
        {
            currentTime = getTimeMs();
            float diff = currentTime - lastTimeGot;
            double dt = (currentTime - lastTimeGot) * 0.001;
            double time = (currentTime - creationTime) * 0.001;
            listener.onAnimate(dt, time);
            sendRepaintIfUIDirty();
            lastTimeGot = currentTime;
            //Sleep for ~16.6 milliseconds (60 frames per second rendering)
            usleep(16666);
        }
    }

    override bool terminated()
    {
        return atomicLoad(_terminated);
    }

    override uint getTimeMs()
    {
        static uint perform() {
            import core.sys.posix.sys.time;
            timeval  tv;
            gettimeofday(&tv, null);
            return cast(uint)((tv.tv_sec) * 1000 + (tv.tv_usec) / 1000) ;

        }

        return assumeNothrowNoGC(&perform)();
    }

    override void* systemHandle()
    {
        return cast(void*)_windowId;
    }
}

void handleEvents(ref XEvent event, X11Window theWindow) nothrow @nogc
{
    with(theWindow)
    {

        switch(event.type)
        {
            case KeyPress:
                KeySym symbol;
                XLookupString(&event.xkey, null, 0, &symbol, null);
                listener.onKeyDown(convertKeyFromX11(symbol));
                break;

            case KeyRelease:
                KeySym symbol;
                XLookupString(&event.xkey, null, 0, &symbol, null);
                listener.onKeyUp(convertKeyFromX11(symbol));
                break;

            case MapNotify:
            case Expose:
                // Resize should trigger Expose event, so we don't need to handle it here
                drawMutex.lock();

                box2i areaToRedraw = mergedDirtyRect;
                box2i eventAreaToRedraw = box2i(event.xexpose.x, event.xexpose.y, event.xexpose.x + event.xexpose.width, event.xexpose.y + event.xexpose.height);
                areaToRedraw = areaToRedraw.expand(eventAreaToRedraw);

                emptyMergedBoxes();

                drawMutex.unlock();

                if (!areaToRedraw.empty()) {
                    listener.onDraw(WindowPixelFormat.RGBA8);
                    box2i[] areasToRedraw = (&areaToRedraw)[0..1];
                    swapBuffers(_wfb, areasToRedraw);
                }
                break;

            case ConfigureNotify:
                if (event.xconfigure.width != width || event.xconfigure.height != height)
                {
                    // Handle resize event
                    width = event.xconfigure.width;
                    height = event.xconfigure.height;

                    _wfb = listener.onResized(width, height);
                    sendRepaintIfUIDirty();
                }
                break;

            case MotionNotify:
                int newMouseX = event.xmotion.x;
                int newMouseY = event.xmotion.y;
                int dx = newMouseX - lastMouseX;
                int dy = newMouseY - lastMouseY;

                listener.onMouseMove(newMouseX, newMouseY, dx, dy, mouseStateFromX11(event.xbutton.state));

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
                    listener.onMouseWheel(newMouseX, newMouseY, 0, event.xbutton.button == Button4 ? 1 : -1,
                        mouseStateFromX11(event.xbutton.state));
                }
                else
                {
                    listener.onMouseClick(newMouseX, newMouseY, button, isDoubleClick, mouseStateFromX11(event.xbutton.state));
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

                listener.onMouseRelease(newMouseX, newMouseY, button, mouseStateFromX11(event.xbutton.state));
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
