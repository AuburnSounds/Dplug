module derelict.x11.Xprotostr;
version(linux):
import derelict.x11.Xmd;

/* Used by PolySegment */

struct _xSegment {
    INT16 x1, y1, x2, y2;
}
alias _xSegment xSegment;

/* POINT */

struct _xPoint {
    INT16       x, y;
}
alias _xPoint xPoint;

struct _xRectangle {
    INT16 x, y;
    CARD16  width, height;
}
alias _xRectangle xRectangle;

/*  ARC  */

struct _xArc {
    INT16 x, y;
    CARD16   width, height;
    INT16   angle1, angle2;
}
alias _xArc xArc;
