module derelict.x11.Xlib_xcb;

version(linux):
// import deimos.XCB.xcb;
import derelict.x11.Xlib;
//import derelict.x11.Xfuncproto;

extern (C) nothrow @nogc:

// xcb_connection_t*	XGetXCBConnection(Display* dpy);

enum XEventQueueOwner
{
	XlibOwnsEventQueue = 0,
	XCBOwnsEventQueue
}

void	XSetEventQueueOwner(Display* dpy, XEventQueueOwner owner);
