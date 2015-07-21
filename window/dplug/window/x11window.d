/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.window.x11window;


import gfm.math;

import ae.utils.graphics;

import dplug.window.window;


version(linux)
{
    import x11.X;
    import x11.Xutil;
    import x11.Xlib;

    final class X11Window : IWindow
    {
    private:
        bool _terminated = false;
        Display* _display;
        Window _window;    
        int _screen;    

    public:

        this(void* parentWindow, IWindowListener listener, int width, int height)
        {
            _display = XOpenDisplay(null);
            if (_display is null)
                throw new Exception("Cannot open display");

            _screen = DefaultScreen(_display);
            _window = XCreateSimpleWindow(_display, RootWindow(_display, _screen), 10, 10, width, height, 1, 
                                          BlackPixel(_display, _screen), 
                                          WhitePixel(_display, _screen));
            XSelectInput(_display, _window, ExposureMask | KeyPressMask);
            XMapWindow(_display, _window);
        }

        ~this()
        {
            close();
        }

        void close()
        {
            XCloseDisplay(_display);
        }
        
        override void terminate()
        {
            close();
        }

        
        // Implements IWindow
        override void waitEventAndDispatch()
        {
            XEvent _xevent;
            XNextEvent(_display, &_xevent);
            if (_xevent.type == Expose) 
            {
                XFillRectangle(_display, _window, DefaultGC(_display, _screen), 20, 20, 10, 10);
                //XDrawString(_display, _window, DefaultGC(_display, _screen), 10, 50, msg, strlen(msg));
            }
            if (_xevent.type == KeyPress)
                _terminated = true;
        }

        override bool terminated()
        {
            return _terminated;
        }

        override void debugOutput(string s)
        {
            // TODO
        }

        override uint getTimeMs()
        {
            // TODO
            return 0;
        }
    }

    

}
