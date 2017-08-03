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

int MAX(int a, int b) { return (a < b) ? b : a; }
int MIN(int a, int b) { return (a > b) ? b : a; }


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

/* Xutil.d contains the declaration:
 * typedef struct _XRegion *Region;
 */

/*  1 if two BOXs overlap.
 *  0 if two BOXs do not overlap.
 *  Remember, x2 and y2 are not in the region
 */
bool EXTENTCHECK(Box* r1, Box* r2){
    return  ( r1.x2 > r2.x1 )
        &&  ( r1.x1 < r2.x2 )
        &&  ( r1.y2 > r2.y1 )
        &&  ( r1.y1 < r2.y2 );
 }

/*
 *  update region extents
 */
void EXTENTS( Box* r, REGION* idRect ){
    if(r.x1 < idRect.extents.x1)
        idRect.extents.x1 = r.x1;
    if(r.y1 < idRect.extents.y1)
        idRect.extents.y1 = r.y1;
    if(r.x2 > idRect.extents.x2)
        idRect.extents.x2 = r.x2;
    if(r.y2 > idRect.extents.y2)
        idRect.extents.y2 = r.y2;
}

/*
 *   Check to see if there is enough memory in the present region.
 */
bool MEMCHECK(REGION* reg, Box* rect, Box* firstrect){
    bool result = false;
    if (reg.numRects >= (reg.size - 1)){
        firstrect = cast(BOX*) Xrealloc( cast(void*) firstrect, cast(uint)(2 * BOX.sizeof * reg.size ) );
        if (firstrect is null)
            result = false;
        else{
            reg.size *= 2;
            rect = &firstrect[reg.numRects];
            result = true;
        }
    }
    return result;
}

/*  this routine checks to see if the previous rectangle is the same
 *  or subsumes the new rectangle to add.
 */
bool CHECK_PREVIOUS(REGION* Reg, Box* R, short Rx1, short Ry1, short Rx2, short Ry2){
    return !( (Reg.numRects > 0) && ((R-1).y1 == Ry1) && ((R-1).y2 == Ry2) && ((R-1).x1 <= Rx1) && ((R-1).x2 >= Rx2) );
}

/*  add a rectangle to the given Region */
void ADDRECT(REGION* reg, Box* r, short rx1, short ry1, short rx2, short ry2){
    if ( (rx1 < rx2) && (ry1 < ry2) && CHECK_PREVIOUS(reg, r, rx1, ry1, rx2, ry2) ){
        r.x1 = rx1;
        r.y1 = ry1;
        r.x2 = rx2;
        r.y2 = ry2;
        EXTENTS( r, reg );
        reg.numRects++;
        r++;
    }
}



/*  add a rectangle to the given Region */
void ADDRECTNOX(REGION* reg, Box* r, short rx1, short ry1, short rx2, short ry2){
    if ( (rx1 < rx2) && (ry1 < ry2) && CHECK_PREVIOUS(reg, r, rx1, ry1, rx2, ry2) ){
        r.x1 = rx1;
        r.y1 = ry1;
        r.x2 = rx2;
        r.y2 = ry2;
        reg.numRects++;
        r++;
    }
}

void EMPTY_REGION(REGION* pReg){
    pReg.numRects = 0;
}

c_long REGION_NOT_EMPTY(REGION* pReg){
    return pReg.numRects;
}

bool INBOX(Box* r, short x, short y){
    return ( (r.x2 >  x) && (r.x1 <= x) && (r.y2 >  y) && (r.y1 <= y) );
}

/*
 * number of points to buffer before sending them off
 * to scanlines() :  Must be an even number
 */
const int NUMPTSTOBUFFER = 200;

/*
 * used to allocate buffers for points and link
 * the buffers together
 */
struct POINTBLOCK {
    XPoint[NUMPTSTOBUFFER]      pts;
    POINTBLOCK* next;
}
