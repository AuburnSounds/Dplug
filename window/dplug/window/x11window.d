/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.window.x11window;

import core.stdc.config;
import core.stdc.stdlib;

import std.algorithm;

import ae.utils.graphics;

import gfm.math;

import dplug.window.window;


private enum debugX11Window = true;   
static if (debugX11Window)
    import std.stdio;

version = SimpleWindow;    


version(linux)
{
    import x11.X;
    import x11.Xutil;
    import x11.Xlib;
    import x11.keysymdef;

    // Important reads: 
    // http://stackoverflow.com/questions/10492275/how-to-upload-32-bit-image-to-server-side-pixmap
    // http://stackoverflow.com/questions/3645632/how-to-create-a-window-with-a-bit-depth-of-32

    final class X11Window : IWindow
    {
    private:             

        enum scanLineAlignment = 4; // could be 1, 2 or 4

        bool _terminated = false;
        bool _initialized = false;
        
        IWindowListener _listener;
        
        int _width = 0;
        int _height = 0;
        ubyte* _buffer = null;

        bool _firstMotionEvent = true;
        int _lastMouseX;
        int _lastMouseY;

        Window _window;    
        Display* _display;
        Screen* _screen;  
        Visual* _visual;
        Pixmap _pixmap;

        int _windowDepth;
        int _screenNumber;
        GC _pixmapGC;
        GC _gc;
        XImage* _bufferImage;

        XEvent _event;        

    public:

        this(void* parentWindow, IWindowListener listener, int width, int height)
        {
            static if (debugX11Window)
                XSetErrorHandler(&x11ErrorHandler);

            _listener = listener;
            _display = XOpenDisplay(null);
            if (_display is null)
                throw new Exception("Cannot open display");

            _screen = DefaultScreenOfDisplay(_display);
            _screenNumber = DefaultScreen(_display);

            Window parent;
            int x, y;
            if (parentWindow is null)
            {
                x = (WidthOfScreen(_screen) - width) / 2;
                y = (HeightOfScreen(_screen) - height) / 2;                
                parent = RootWindow(_display, _screenNumber);
            }
            else
            {
                parent = cast(Window)(parentWindow);
                x = 0;
                y = 0;                
            }

            auto black = BlackPixel(_display, _screenNumber);
            auto white = WhitePixel(_display, _screenNumber);

            version(SimpleWindow)
            {
                _window = XCreateSimpleWindow(_display, parent, x, y, width, height, 1, black, white);
            }
            else
            {
                XSetWindowAttributes attribOrigin;
                attribOrigin.override_redirect = False;
                attribOrigin.background_pixmap = None;
                attribOrigin.border_pixel = black;
                attribOrigin.background_pixel = black;

                _window = XCreateWindow(_display, 
                                        parent, 
                                        x, y, width, height, 
                                        0, // border_width
                                        CopyFromParent,                       
                                        InputOutput,
                                        cast(Visual*)CopyFromParent,
                                        CWOverrideRedirect | CWBackPixel | CWBorderPixel | CWBackPixmap, // valuemask
                                        &attribOrigin);
            }

            // cache window depth and visual
            XWindowAttributes attrib;
            getWindowAttributes(&attrib);
            _visual = attrib.visual;
            _windowDepth = attrib.depth;

            static if (debugX11Window)
                writefln("Created a window with depth %s", _windowDepth);

            _pixmap = XCreatePixmap(_display, _window, width, height, 24);
            _gc = DefaultGC(_display, _screenNumber);

            XSetForeground(_display, _gc, white);
            XFillRectangle(_display, _pixmap, _gc, 0, 0, width, height);
            XSetForeground(_display, _gc, black);

            // Set non resizeable
            {
                XSizeHints hints;
                hints.min_width = width;
                hints.min_height = height;
                hints.max_width = width;
                hints.max_height = height;
                hints.flags = PMaxSize | PMinSize;
                XSetWMNormalHints(_display, _window, &hints);
            }

            c_long eventMask = 
                ExposureMask |
                KeyPressMask |
                KeyReleaseMask |
                PropertyChangeMask |
                FocusChangeMask |
                StructureNotifyMask |
                PointerMotionMask |
                ButtonPressMask |
                ButtonReleaseMask;
            XSelectInput(_display, _window, eventMask);
            XMapWindow(_display, _window);

            _width = 0;//width;
            _height = 0;//height;
            
        //    XFlush(_display); // Flush all pending requests to the X server.

            _initialized = true;

          //  static if (debugX11Window)
          //      XSynchronize(_display, true);
        }

        ~this()
        {
            close();
        }

        void close()
        {
            if (_initialized)
            {
                _initialized = false;
                XFreeGC(_display, _pixmapGC);
                XFreePixmap(_display, _pixmap);
                XDestroyImage(_bufferImage);                
                XDestroyWindow(_display, _window);
                XCloseDisplay(_display); 
            }
        }
        
        override void terminate()
        {
            close();
        }
        
        // Implements IWindow
        override void waitEventAndDispatch()
        {
            while (XPending(_display))
            {
                XNextEvent(_display, &_event);
                dispatchEvent(&_event);
            }
        }

        override bool terminated()
        {
            return _terminated;
        }

        override void debugOutput(string s)
        {
            import std.stdio;
            writeln(s); // TODO: something better
        }

        override uint getTimeMs()
        {            
            import core.sys.posix.time;
            timespec time;
            clock_gettime(CLOCK_REALTIME, &time);
            return cast(uint)(time.tv_sec * 1000 + time.tv_nsec / 1_000_000);
        }
    private:

        void dispatchEvent(XEvent* event)
        {
            if (event.xexpose.window == None)
                return;

            switch (event.type)
            {
                case Expose: 
                    handleXExposeEvent(&event.xexpose);
                    break;

                case KeyPress: 
                    handleXKeyEvent(&event.xkey, false);
                    break;

                case KeyRelease: 
                    handleXKeyEvent(&event.xkey, true);
                    break;

                case ButtonPress:
                    handleXButtonEvent(&event.xbutton, false);
                    break;

                case ButtonRelease:
                    handleXButtonEvent(&event.xbutton, true);
                    break;

                case ConfigureNotify:
                    handleXConfigureEvent(&event.xconfigure);
                    break;

                case MotionNotify:
                    handleXMotionEvent(&event.xmotion);
                    break;

                case DestroyNotify:
                    close();
                    break;

/+
    

    /// Called on mouse wheel movement
    /// Returns: true if the event was handled.
    bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate);

    
    +/

                default:
                  // ignore
            }
        }

        void handleXKeyEvent(XKeyEvent* event, bool release)
        {
            if (event.window != _window)
                return;

            if (release)
                _listener.onKeyUp(translateToKey(event));
            else   
                _listener.onKeyDown(translateToKey(event));          
        }      

        Key translateToKey(XKeyEvent* event)
        {
            char[32] buffer;
            KeySym keysym;
            XLookupString(event, buffer.ptr, cast(int)buffer.length, &keysym, null);

            switch(keysym)
            {
                case XK_space: return Key.space;
                case XK_Up: return Key.upArrow;
                case XK_Down: return Key.downArrow;
                case XK_Left: return Key.leftArrow;
                case XK_Right: return Key.rightArrow;
                case XK_KP_0: return Key.digit0;
                case XK_KP_1: return Key.digit1;
                case XK_KP_2: return Key.digit2;
                case XK_KP_3: return Key.digit3;
                case XK_KP_4: return Key.digit4;
                case XK_KP_5: return Key.digit5;
                case XK_KP_6: return Key.digit6;
                case XK_KP_7: return Key.digit7;
                case XK_KP_8: return Key.digit8;
                case XK_KP_9: return Key.digit9;
                case XK_Return: return Key.enter;
                case XK_Escape: return Key.escape;
                default:
                    return Key.unsupported;
            }
        }

        void handleXButtonEvent(XButtonEvent* event, bool release)
        {
            if (event.window != _window)
                return;

            if (event.button < 1 || event.button > 5)
                return; // unknown mouse button

            MouseButton mb = toMouseButton(event.button);
            MouseState mstate = toMouseState(event.state);

            if (release)
                _listener.onMouseRelease(event.x, event.y, mb, mstate);
            else
                _listener.onMouseClick(event.x, event.y, mb, false, mstate);
        }

        static MouseButton toMouseButton(uint xbutton)
        {
            switch(xbutton)
            { 
                case Button1: return MouseButton.left;
                case Button2: return MouseButton.right;
                case Button3: return MouseButton.middle;
                case Button4: return MouseButton.x1;
                case Button5: return MouseButton.x2;
                default:
                    return MouseButton.left;
            }
        }

        static MouseState toMouseState(uint state)
        {
            MouseState result;
            if (state & Button1Mask) result.leftButtonDown = true;
            if (state & Button2Mask) result.rightButtonDown = true;
            if (state & Button3Mask) result.middleButtonDown = true;
            if (state & Button4Mask) result.x1ButtonDown = true;
            if (state & Button5Mask) result.x2ButtonDown = true;

            // TODO alt, ctrl, shift

            return result;
        }

        void handleXMotionEvent(XMotionEvent* event)
        {
            if (event.window != _window)
                return;

            if (_firstMotionEvent)
            {
                _firstMotionEvent = false;
                _lastMouseX = event.x;
                _lastMouseY = event.y;
            }

            MouseState mstate = toMouseState(event.state);
            _listener.onMouseMove(event.x, event.y, event.x - _lastMouseX, event.y - _lastMouseY, mstate);     

            _lastMouseX = event.x;
            _lastMouseY = event.y;
        }

        void handleXConfigureEvent(XConfigureEvent* event)
        {            
            if (event.window != _window)
                return;

            int newWidth = event.width;
            int newHeight = event.height;

            updateSizeIfNeeded(newWidth, newHeight);
        }

        void handleXExposeEvent(XExposeEvent* event)
        {
            if (event.window != _window)
                return;

            ImageRef!RGBA wfb;
            wfb.w = _width;
            wfb.h = _height;
            wfb.pitch = byteStride(_width);
            wfb.pixels = cast(RGBA*)_buffer;

            bool swapRB = true;
            _listener.onDraw(wfb, swapRB);

            box2i areaToRedraw = box2i(event.x, event.y, event.width, event.height);
            swapBuffers(wfb, areaToRedraw);
        }

        // given a width, how long in bytes should scanlines be
        int byteStride(int width)
        {
            int widthInBytes = width * 4;
            return (widthInBytes + (scanLineAlignment - 1)) & ~(scanLineAlignment-1);
        }

        import std.stdio;

        /// Returns: true if window size changed.
        bool updateSizeIfNeeded(int newWidth, int newHeight)
        {
            // only do something if the client size has changed
            if (newWidth != _width || newHeight != _height)
            {
                // Extends buffer
                if (_buffer != null)
                {                    
                    XFreeGC(_display, _pixmapGC);
                    XFreePixmap(_display, _pixmap);
                    XDestroyImage(_bufferImage); // calls free on _buffer

                    _buffer = null;
                }

                size_t sizeNeeded = byteStride(newWidth) * newHeight;
                 _buffer = cast(ubyte*) malloc(sizeNeeded);

                // resize the internal pixmap
                _pixmap = XCreatePixmap(_display, _window, newWidth, newHeight, 24);            
              
                _bufferImage = XCreateImage(_display, 
                                            cast(Visual*) CopyFromParent,
                                            24, 
                                            ZPixmap, 
                                            0,  // offset
                                            cast(char*)_buffer, 
                                            newWidth, 
                                            newHeight, 
                                            scanLineAlignment * 8,
                                            byteStride(newWidth));

                _pixmapGC = XCreateGC(_display, _pixmap, 0, null); // create a Graphic Context for the pixmap specifically

                _width = newWidth;
                _height = newHeight;
                _listener.onResized(_width, _height);
                return true;
            }
            else
                return false;
        }

        void swapBuffers(ImageRef!RGBA wfb, box2i area)
        {   
            int x = area.min.x;
            int y = area.min.y;
            int w = area.width;
            int h = area.height;

            XPutImage(_display, _pixmap, _pixmapGC, _bufferImage, x, y, x, y, w, h);

            // copy pixmap to window
            XCopyArea(_display, _pixmap, _window,_gc, x, y, w, h, x, y);

            XSync(_display, False);           
        }

        void getWindowAttributes(XWindowAttributes* attrib)
        {
            Status status = XGetWindowAttributes(_display, _window, attrib);
            if (status == 0)
                throw new Exception("XGetWindowAttributes failed");
        }
    }

    private
    {

        extern(C) int x11ErrorHandler(Display* display, XErrorEvent* errorEvent) nothrow
        {
            try
            {
                import std.stdio;
                writefln("Received X11 Error:");
                writefln(" - error_code = %s", errorCodeString(errorEvent.error_code));
                writefln(" - request_code = %s", errorEvent.request_code);
                writefln(" - minor_code = %s", errorEvent.minor_code);
                writefln(" - serial = %s", errorEvent.serial);
            }
            catch(Exception e)
            {
                // Not supposed to happen
            }
            return 0;
        }

        string errorCodeString(ubyte error_code)
        {
            switch(error_code)
            {
                case XErrorCode.Success: return "Success";
                case XErrorCode.BadRequest: return "BadRequest";
                case XErrorCode.BadValue: return "BadValue";
                case XErrorCode.BadWindow: return "BadWindow";
                case XErrorCode.BadPixmap: return "BadPixmap";
                case XErrorCode.BadAtom: return "BadAtom";
                case XErrorCode.BadCursor: return "BadCursor";
                case XErrorCode.BadFont: return "BadFont";
                case XErrorCode.BadMatch: return "BadMatch";
                case XErrorCode.BadDrawable: return "BadDrawable";
                case XErrorCode.BadAccess: return "BadAccess";
                case XErrorCode.BadAlloc: return "BadAlloc";
                case XErrorCode.BadColor: return "BadColor";
                case XErrorCode.BadGC: return "BadGC";
                case XErrorCode.BadIDChoice: return "BadIDChoice";
                case XErrorCode.BadName: return "BadName";
                case XErrorCode.BadLength: return "BadLength";
                case XErrorCode.BadImplementation: return "BadImplementation";
                default:
                    return "Unknown error_code";
            }
        }
    }
}


/+

// Receiving commands from a window
interface IWindowListener
{



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
    void onAnimate(double dt, double time);
}
+/