module derelict.x11.extensions.Xge;

version(linux):

/* XGE Client interfaces */

import derelict.x11.Xlib;

extern (C) nothrow @nogc:

/**
 * Generic Event mask.
 * To be used whenever a list of masks per extension has to be provided.
 *
 * But, don't actually use the CARD{8,16,32} types.  We can't get them them
 * defined here without polluting the namespace.
 */
struct XGenericEventMask{
    ubyte       extension;
    ubyte       pad0;
    ushort      pad1;
    uint        evmask;
}

Bool XGEQueryExtension(Display* dpy, int *event_basep, int *err_basep);
Bool XGEQueryVersion(Display* dpy, int *major, int* minor);
