/**
 * Copyright (C) 2017 Richard Andrew Cattermole
 * X11 support.
 * 
 * Bugs:
 *     - X11 does not support double clicks, it is sometimes emulated https://github.com/glfw/glfw/issues/462
 * 
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Richard (Rikki) Andrew Cattermole
 */
module dplug.window.x11window;

import gfm.math.box;

import dplug.window.window;

import dplug.core.runtime;
import dplug.core.nogc;

import dplug.graphics.image;
import dplug.graphics.view;

nothrow:
@nogc:

version(Posix)
{
    import x11.X;
    import x11.Xlib;
    import x11.keysym;
    import x11.keysymdef;
    import x11.Xutil;
    import x11.extensions.Xrandr;
    import x11.extensions.randr;

    Display* _display;
    size_t _white_pixel, _black_pixel;
    int _screen;
    DumbSlowNoGCMap!(Window, X11Window) x11WindowMapping;

    // This is an extension to X11, almost always should exist on modern systems
    // If it becomes a problem, version out its usage, it'll work just won't be as nice event wise
    extern(C) bool XkbSetDetectableAutoRepeat(Display*, bool, bool*);

    final class X11Window : IWindow
    {
    public:
    nothrow:
    @nogc:

        this(void* parentWindow, IWindowListener listener, int width, int height)
        {
            int x, y;
            this.listener = listener;

            //
            
            if (_display is null)
            {
                _display = assumeNoGC(&XOpenDisplay)(null);
                _screen = assumeNoGC(&DefaultScreen)(_display);
                _white_pixel = assumeNoGC(&WhitePixel)(_display, _screen);
                _black_pixel = assumeNoGC(&BlackPixel)(_display, _screen);
                assumeNoGC(&XkbSetDetectableAutoRepeat)(_display, true, null);
            }

            if (parentWindow is null)
            {
                _parentWindowId = assumeNoGC(&RootWindow)(_display, _screen);
            }
            else
            {
                _parentWindowId = cast(Window)parentWindow;
            }

            x = (assumeNoGC(&DisplayWidth)(_display, _screen) - width) / 2;
            y = (assumeNoGC(&DisplayHeight)(_display, _screen) - height) / 3;
            this.width = width;
            this.height = height;
            depth = 24;

            //

            _windowId = assumeNoGC(&XCreateSimpleWindow)(_display, _parentWindowId, x, y, width, height, 0, 0, _white_pixel);
            assumeNoGC(&XStoreName)(_display, _windowId, cast(char*)"Dplug window".ptr);
            x11WindowMapping[_windowId] = this;

            //

            XSizeHints sizeHints;
            sizeHints.flags = PMinSize | PMaxSize;
            sizeHints.min_width = width;
            sizeHints.max_width = width;
            sizeHints.min_height = height;
            sizeHints.max_height = height;

            assumeNoGC(&XSetWMNormalHints)(_display, _windowId, &sizeHints);

            //

            _closeAtom = assumeNoGC(&XInternAtom)(_display, cast(char*)("WM_DELETE_WINDOW".ptr), cast(Bool)false);
            assumeNoGC(&XSetWMProtocols)(_display, _windowId, &_closeAtom, 1);

            assumeNoGC(&XMapWindow)(_display, _windowId);
            assumeNoGC(&XFlush)(_display);

            assumeNoGC(&XSelectInput)(_display, _windowId, ExposureMask | KeyPressMask | StructureNotifyMask |
                KeyReleaseMask | KeyPressMask | ButtonReleaseMask | ButtonPressMask | PointerMotionMask);
            _graphicGC = assumeNoGC(&XCreateGC)(_display, _windowId, 0, null);
            assumeNoGC(&XSetBackground)(_display, _graphicGC, _white_pixel);
            assumeNoGC(&XSetForeground)(_display, _graphicGC, _black_pixel);

            _wfb = listener.onResized(width, height);
            listener.recomputeDirtyAreas();
            listener.onDraw(WindowPixelFormat.RGBA8);
            
            box2i areaToRedraw = listener.getDirtyRectangle();
            box2i[] areasToRedraw = (&areaToRedraw)[0..1];
            if (_wfb.pixels !is null)
            {
                swapBuffers(_wfb, areasToRedraw);
            }

            creationTime = getTimeMs();
            lastTimeGot = creationTime;
        }
        
        ~this()
        {
            x11WindowMapping.remove(_windowId);
            assumeNoGC(&XDestroyImage)(_graphicImage);
            assumeNoGC(&XFreeGC)(_display, _graphicGC);
            assumeNoGC(&XDestroyWindow)(_display, _windowId);
            assumeNoGC(&XFlush)(_display);
        }

        void swapBuffers(ImageRef!RGBA wfb, box2i[] areasToRedraw)
        {
            if (_bufferData.length != wfb.w * wfb.h)
            {
                _bufferData = mallocSlice!(ubyte[4])(wfb.w * wfb.h);

                if (_graphicImage !is null)
                {
                    // X11 deallocates _bufferData for us (ugh...)
                    assumeNoGC(&XDestroyImage)(_graphicImage);
                }

                _graphicImage = assumeNoGC(&XCreateImage)(_display, cast(Visual*)&_graphicGC, depth, ZPixmap, 0, cast(char*)_bufferData.ptr, width, height, 32, 0);

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

            assumeNoGC(&XPutImage)(_display, _windowId, _graphicGC, _graphicImage, 0, 0, 0, 0, cast(uint)width, cast(uint)height);
        }

        // Implements IWindow
        override void waitEventAndDispatch()
        {
            while(x11WindowMapping.haveAValue)
            {
                XEvent event;
                assumeNoGC(&XNextEvent)(_display, &event);

                X11Window theWindow = x11WindowMapping[event.xany.window];

                if (theWindow is null)
                {
                    // well hello, I didn't expect this.. goodbye
                    continue;
                }

                handleEvents(event, theWindow);
            }
        }

        override bool terminated()
        {
            return _terminated;
        }

        override uint getTimeMs()
        {
            static uint perform() {
                import std.datetime : Clock;
                return cast(uint)(Clock.currTime.stdTime / 100000);
            }

            return assumeNothrowNoGC(&perform)();
        }

        override void* systemHandle()
        {
            return cast(void*)_windowId;
        }

    private:

        IWindowListener listener;
        Window _windowId, _parentWindowId;
        bool _terminated = false;
        Atom _closeAtom;

        ImageRef!RGBA _wfb; // framebuffer reference

        GC _graphicGC;
        XImage* _graphicImage;
        ubyte[4][] _bufferData;
        int width, height, depth;

        uint lastTimeGot, creationTime;
        int lastMouseX, lastMouseY;
    }
}


void handleEvents(ref XEvent event, X11Window theWindow)
{
    enum OneSixteith = 100/60;

    with(theWindow)
    {
        uint currentTime = getTimeMs();
        uint diff = currentTime-lastTimeGot;
        if (diff >= OneSixteith)
        {
            lastTimeGot = currentTime;
            if (listener !is null)
            {
                listener.onAnimate(cast(double)diff, cast(double)creationTime);
                listener.recomputeDirtyAreas();
                listener.onDraw(WindowPixelFormat.RGBA8);

                box2i areaToRedraw = listener.getDirtyRectangle();
                box2i[] areasToRedraw = (&areaToRedraw)[0..1];
                if (_wfb.pixels !is null)
                {
                    swapBuffers(_wfb, areasToRedraw);
                }
            }
        }

        switch(event.type)
        {
            case MapNotify:
            case Expose:
                if (listener !is null)
                {
                    listener.recomputeDirtyAreas();
                    listener.onDraw(WindowPixelFormat.RGBA8);
                    
                    box2i areaToRedraw = listener.getDirtyRectangle();
                    box2i[] areasToRedraw = (&areaToRedraw)[0..1];
                    if (_wfb.pixels !is null)
                    {
                        swapBuffers(_wfb, areasToRedraw);
                    }
                }
                break;
                
            case ConfigureNotify:
                if (event.xconfigure.width != width || event.xconfigure.height != height)
                {
                    width = event.xconfigure.width;
                    height = event.xconfigure.height;
                    
                    if (listener !is null)
                    {
                        _wfb = listener.onResized(width, height);
                        
                        listener.recomputeDirtyAreas();
                        listener.onDraw(WindowPixelFormat.RGBA8);
                        
                        box2i areaToRedraw = listener.getDirtyRectangle();
                        box2i[] areasToRedraw = (&areaToRedraw)[0..1];
                        if (_wfb.pixels !is null)
                        {
                            swapBuffers(_wfb, areasToRedraw);
                        }
                    }
                }
                break;
                
            case ButtonPress:
                if (listener !is null)
                {
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

                    if (event.xbutton.button == Button4 || event.xbutton.button == Button5)
                    {
                        listener.onMouseWheel(newMouseX, newMouseY, 0, event.xbutton.button == Button4 ? 1 : -1,
                            mouseStateFromX11(event.xbutton.state));
                    }
                else
                {
                        listener.onMouseClick(newMouseX, newMouseY, button, isDoubleClick, mouseStateFromX11(event.xbutton.state));
                    }
                }
                break;
            case ButtonRelease:
                if (listener !is null)
                {
                    int newMouseX = event.xbutton.x;
                    int newMouseY = event.xbutton.y;
                    
                    MouseButton button;
                    
                    if (event.xbutton.button == Button1)
                        button = MouseButton.left;
                    else if (event.xbutton.button == Button3)
                        button = MouseButton.right;
                    else if (event.xbutton.button == Button2)
                        button = MouseButton.middle;
                    else if (event.xbutton.button == Button4 || event.xbutton.button == Button5)
                        break;
                    
                    listener.onMouseRelease(newMouseX, newMouseY, button, mouseStateFromX11(event.xbutton.state));
                }
                break;

            case MotionNotify:
                if (listener !is null)
                {
                    int newMouseX = event.xmotion.x;
                    int newMouseY = event.xmotion.y;
                    int dx = newMouseX - lastMouseX;
                    int dy = newMouseY - lastMouseY;

                    listener.onMouseMove(newMouseX, newMouseY, dx, dy, mouseStateFromX11(event.xmotion.state));

                    lastMouseX = newMouseX;
                    lastMouseY = newMouseY;
                }
                break;
                
            case KeyPress:
                KeySym symbol;
                assumeNoGC(&XLookupString)(&event.xkey, null, 0, &symbol, null);
                if (listener !is null)
                {
                    listener.onKeyDown(convertKeyFromX11(symbol));
                }
                break;
            case KeyRelease:
                KeySym symbol;
                assumeNoGC(&XLookupString)(&event.xkey, null, 0, &symbol, null);
                if (listener !is null)
                {
                    listener.onKeyUp(convertKeyFromX11(symbol));
                }
                break;
                
            case ClientMessage:
                if (event.xclient.data.l[0] == _closeAtom)
                {
                    _terminated = true;
                    x11WindowMapping.remove(_windowId);
                    assumeNoGC(&XDestroyImage)(_graphicImage);
                    assumeNoGC(&XFreeGC)(_display, _graphicGC);
                    assumeNoGC(&XDestroyWindow)(_display, _windowId);
                    assumeNoGC(&XFlush)(_display);
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

        case XK_Return:
        case XK_KP_Enter:
            return Key.enter;

        case XK_Escape:
            return Key.escape;

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

/**
 * A simple @nogc map, that also happens to be quite dumb.
 * 
 * It is used for X11 mapping of window id's to instances,
 * if you need something like this for anything more serious, replace!
 * Or look into EMSI's containers.
 *
 */

/// A dumb slow @nogc map implementation. You probably don't want to use this...
/// No seriously, its probably worse than O(n)!
struct DumbSlowNoGCMap(K, V)
{
    import dplug.core.nogc;
    import std.typecons : Nullable;

    private
    {
        Nullable!K[] keys_;
        V[] values_;
    }

@nogc:

    @disable
    this(this);

    ~this()
    {
        freeSlice(keys_);
        freeSlice(values_);
    }

    V opIndex(K key)
    {
        foreach(i, ref k; keys_)
        {
            if (!k.isNull && k == key)
                return values_[i];
        }

        return V.init;
    }

    void opIndexAssign(V value, K key)
    {
        if (keys_.length == 0)
        {
            keys_ = mallocSlice!(Nullable!K)(8);
            values_ = mallocSlice!V(8);
            keys_[0] = key;
            values_[0] = value;

            keys_[1 .. $] = Nullable!K.init;

            return;
        }
        else
        {
            foreach(i, ref k; keys_)
            {
                if (!k.isNull && k == key)
                {
                    values_[i] = value;
                    return;
                }
            }

            foreach(i, ref k; keys_)
            {
                if (k.isNull)
                {
                    k = key;
                    values_[i] = value;
                    return;
                }
            }
        }

        Nullable!K[] newKeys = mallocSlice!(Nullable!K)(keys_.length+8);
        V[] newValues = mallocSlice!V(values_.length+8);
        newKeys[0 .. $-8] = keys_;
        newValues[0 .. $-8] = values_;

        newKeys[$-7] = key;
        newKeys[$-6 .. $] = Nullable!K.init;
        newValues[$-7] = value;

        freeSlice(keys_);
        freeSlice(values_);

        keys_ = newKeys;
        values_ = newValues;
    }

    void remove(K key)
    {
        foreach(i, ref k; keys_)
        {
            if (!k.isNull && k == key)
            {
                k.nullify;
                values_[i] = V.init;
                return;
            }
        }
    }

    bool haveAValue() {
        foreach(i, ref k; keys_)
        {
            if (!k.isNull)
            {
                return true;
            }
        }

        return false;
    }
}