module derelict.x11.Xregion;

version(linux):
import core.stdc.config;

import derelict.x11.Xlibint;
import derelict.x11.Xlib : XPoint;

extern (C) nothrow @nogc:

struct Box{
    short x1, x2, y1, y2;
}
alias Box   BOX;
alias Box   BoxRec;
alias Box*  BoxPtr;

struct RECTANGLE{
    short x, y, width, height;
}
alias RECTANGLE     RectangleRec;
alias RECTANGLE*    RectanglePtr;

const int TRUE      = 1;
const int FALSE     = 0;
const int MAXSHORT  = 32767;
const int MINSHORT  = -MAXSHORT;

/*
 *   clip region
 */

struct _XRegion {
    c_long size;
    c_long numRects;
    BOX* rects;
    BOX  extents;
}
alias _XRegion REGION;
