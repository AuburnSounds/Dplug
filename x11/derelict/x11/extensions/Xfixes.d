module derelict.x11.extensions.Xfixes;

version(linux):


public import
	derelict.x11.X,
	derelict.x11.Xlib;

extern(C):

	/+
	#include <X11/extensions/xfixeswire.h>

	#include <X11/Xfuncproto.h>
	#include <X11/Xlib.h>

	#define XFIXES_REVISION	1
	#define XFIXES_VERSION	((XFIXES_MAJOR * 10000) + (XFIXES_MINOR * 100) + (XFIXES_REVISION))
	+/

	enum XFIXES_MAJOR = 5;

	struct XFixesSelectionNotifyEvent {
	    int type;			/* event base */
	    ulong serial;
	    Bool send_event;
	    Display *display;
	    Window window;
	    int subtype;
	    Window owner;
	    Atom selection;
	    Time timestamp;
	    Time selection_timestamp;
	}

	struct XFixesCursorNotifyEvent {
	    int type;			/* event base */
	    ulong serial;
	    Bool send_event;
	    Display *display;
	    Window window;
	    int subtype;
	    ulong cursor_serial;
	    Time timestamp;
	    Atom cursor_name;
	}

	struct XFixesCursorImage {
	    short	    x, y;
	    ushort  width, height;
	    ushort  xhot, yhot;
	    ulong   cursor_serial;
	    ulong   *pixels;
		static if(XFIXES_MAJOR >= 2){
		    Atom	    atom;		    /* Version >= 2 only */
		    const char	    *name;		    /* Version >= 2 only */
		}
	}

	static if(XFIXES_MAJOR >= 2){
		/* Version 2 types */

		alias XserverRegion = XID;

		struct XFixesCursorImageAndName {
		    short	    x, y;
		    ushort  width, height;
		    ushort  xhot, yhot;
		    ulong   cursor_serial;
		    ulong   *pixels;
		    Atom	    atom;
		    const char	    *name;
		}
	}

	Bool XFixesQueryExtension (Display *dpy,
				    int *event_base_return,
				    int *error_base_return);
	Status XFixesQueryVersion (Display *dpy,
				    int     *major_static,
				    int     *minor_static);

	int XFixesVersion();

	void
	XFixesChangeSaveSet (Display	*dpy,
			     Window	win,
			     int	mode,
			     int	target,
			     int	map);

	void
	XFixesSelectSelectionInput (Display	    *dpy,
				    Window	    win,
				    Atom	    selection, 
				    ulong   eventMask);

	void
	XFixesSelectCursorInput (Display	*dpy,
				 Window		win,
				 ulong	eventMask);

	XFixesCursorImage *
	XFixesGetCursorImage (Display *dpy);

	static if(XFIXES_MAJOR >= 2){
		/* Version 2 functions */

		XserverRegion
		XFixesCreateRegion (Display *dpy, XRectangle *rectangles, int nrectangles);

		XserverRegion
		XFixesCreateRegionFromBitmap (Display *dpy, Pixmap bitmap);

		XserverRegion
		XFixesCreateRegionFromWindow (Display *dpy, Window window, int kind);

		XserverRegion
		XFixesCreateRegionFromGC (Display *dpy, GC gc);

		XserverRegion
		XFixesCreateRegionFromPicture (Display *dpy, XID picture);

		void
		XFixesDestroyRegion (Display *dpy, XserverRegion region);

		void
		XFixesSetRegion (Display *dpy, XserverRegion region,
				 XRectangle *rectangles, int nrectangles);

		void
		XFixesCopyRegion (Display *dpy, XserverRegion dst, XserverRegion src);

		void
		XFixesUnionRegion (Display *dpy, XserverRegion dst,
				   XserverRegion src1, XserverRegion src2);

		void
		XFixesIntersectRegion (Display *dpy, XserverRegion dst,
				       XserverRegion src1, XserverRegion src2);

		void
		XFixesSubtractRegion (Display *dpy, XserverRegion dst,
				      XserverRegion src1, XserverRegion src2);

		void
		XFixesInvertRegion (Display *dpy, XserverRegion dst,
				    XRectangle *rect, XserverRegion src);

		void
		XFixesTranslateRegion (Display *dpy, XserverRegion region, int dx, int dy);

		void
		XFixesRegionExtents (Display *dpy, XserverRegion dst, XserverRegion src);

		XRectangle *
		XFixesFetchRegion (Display *dpy, XserverRegion region, int *nrectanglesRet);

		XRectangle *
		XFixesFetchRegionAndBounds (Display *dpy, XserverRegion region, 
					    int *nrectanglesRet,
					    XRectangle *bounds);

		void
		XFixesSetGCClipRegion (Display *dpy, GC gc, 
				       int clip_x_origin, int clip_y_origin,
				       XserverRegion region);

		void
		XFixesSetWindowShapeRegion (Display *dpy, Window win, int shape_kind,
					    int x_off, int y_off, XserverRegion region);

		void
		XFixesSetPictureClipRegion (Display *dpy, XID picture,
					    int clip_x_origin, int clip_y_origin,
					    XserverRegion region);

		void
		XFixesSetCursorName (Display *dpy, Cursor cursor, const(char)* name);

		const(char)*
		XFixesGetCursorName (Display *dpy, Cursor cursor, Atom *atom);

		void
		XFixesChangeCursor (Display *dpy, Cursor source, Cursor destination);

		void
		XFixesChangeCursorByName (Display *dpy, Cursor source, const(char)* name);

	}

	static if(XFIXES_MAJOR >= 3){

		void
		XFixesExpandRegion (Display *dpy, XserverRegion dst, XserverRegion src,
				    uint left, uint uright,
				    uint utop, uint ubottom);

	}

	static if(XFIXES_MAJOR >= 4){
		/* Version 4.0 externs */

		void
		XFixesHideCursor (Display *dpy, Window win);

		void
		XFixesShowCursor (Display *dpy, Window win);

	}

	static if(XFIXES_MAJOR >= 5){

		alias PointerBarrier = XID;

		PointerBarrier
		XFixesCreatePointerBarrier(Display *dpy, Window w, int x1, int y1,
					   int x2, int y2, int directions,
					   int num_devices, int *devices);

		void
		XFixesDestroyPointerBarrier(Display *dpy, PointerBarrier b);

	}
