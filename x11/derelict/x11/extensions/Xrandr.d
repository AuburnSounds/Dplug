module derelict.x11.extensions.Xrandr;

version(linux):
/*
 * Copyright © 2000 Compaq Computer Corporation, Inc.
 * Copyright © 2002 Hewlett-Packard Company, Inc.
 * Copyright © 2006 Intel Corporation
 * Copyright © 2008 Red Hat, Inc.
 *
 * Permission to use, copy, modify, distribute, and sell this software and its
 * documentation for any purpose is hereby granted without fee, provided that
 * the above copyright notice appear in all copies and that both that copyright
 * notice and this permission notice appear in supporting documentation, and
 * that the name of the copyright holders not be used in advertising or
 * publicity pertaining to distribution of the software without specific,
 * written prior permission.  The copyright holders make no representations
 * about the suitability of this software for any purpose.  It is provided "as
 * is" without express or implied warranty.
 *
 * THE COPYRIGHT HOLDERS DISCLAIM ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
 * INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS, IN NO
 * EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY SPECIAL, INDIRECT OR
 * CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE,
 * DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
 * TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
 * OF THIS SOFTWARE.
 *
 * Author:  Jim Gettys, HP Labs, Hewlett-Packard, Inc.
 *	    Keith Packard, Intel Corporation
 */

import derelict.x11.X;
import derelict.x11.Xlib;
import derelict.x11.extensions.Xrender;
import derelict.x11.extensions.randr;
//import derelict.x11.Xfuncproto;

extern (C) nothrow @nogc:

alias XID RROutput;
alias XID RRCrtc;
alias XID RRMode;

struct XRRScreenSize {
	int width, height;
	int mwidth, mheight;
}

struct XRRScreenChangeNotifyEvent {
	int type;			/* event base */
	ulong serial;	/* # of last request processed by server */
	Bool send_event;		/* true if this came from a SendEvent request */
	Display *display;		/* Display the event was read from */
	Window window;		/* window which selected for this event */
	Window root;		/* Root window for changed screen */
	Time timestamp;		/* when the screen change occurred */
	Time config_timestamp;	/* when the last configuration change */
	SizeID size_index;
	SubpixelOrder subpixel_order;
	Rotation rotation;
	int width;
	int height;
	int mwidth;
	int mheight;
}

struct XRRNotifyEvent {
	int type;	/* event base */
	ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;	/* window which selected for this event */
	int subtype;	/* RRNotify_ subtype */
}

struct XRROutputChangeNotifyEvent {
	int type;	/* event base */
	ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;	/* window which selected for this event */
	int subtype;	/* RRNotify_OutputChange */
	RROutput output;	/* affected output */
	RRCrtc crtc;	/* current crtc (or None) */
	RRMode mode;	/* current mode (or None) */
	Rotation rotation;	/* current rotation of associated crtc */
	Connection connection;	/* current connection status */
	SubpixelOrder subpixel_order;
}

struct XRRCrtcChangeNotifyEvent {
	int type;	/* event base */
	ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;	/* window which selected for this event */
	int subtype;	/* RRNotify_CrtcChange */
	RRCrtc crtc; /* current crtc (or None) */
	RRMode mode;	/* current mode (or None) */
	Rotation rotation;	/* current rotation of associated crtc */
	int x, y;	/* position */
	uint width, height;	/* size */
}

struct XRROutputPropertyNotifyEvent {
	int type;	/* event base */
	ulong serial;	/* # of last request processed by server */
	Bool send_event;	/* true if this came from a SendEvent request */
	Display *display;	/* Display the event was read from */
	Window window;	/* window which selected for this event */
	int subtype;	/* RRNotify_OutputProperty */
	RROutput output;	/* related output */
	Atom property;	/* changed property */
	Time timestamp;	/* time of change */
	int state;	/* NewValue, Deleted */
}

struct _XRRScreenConfiguration;
alias _XRRScreenConfiguration XRRScreenConfiguration;

Bool XRRQueryExtension (Display *dpy,
						int *event_base_return,
						int *error_base_return);
Status XRRQueryVersion (Display *dpy,
						int *major_version_return,
						int *minor_version_return);

XRRScreenConfiguration *XRRGetScreenInfo (Display *dpy,
										  Window window);

void XRRFreeScreenConfigInfo (XRRScreenConfiguration *config);

Status XRRSetScreenConfig (Display *dpy,
						   XRRScreenConfiguration *config,
						   Drawable draw,
						   int size_index,
						   Rotation rotation,
						   Time timestamp);

Status XRRSetScreenConfigAndRate (Display *dpy,
								  XRRScreenConfiguration *config,
								  Drawable draw,
								  int size_index,
								  Rotation rotation,
								  short rate,
								  Time timestamp);

Rotation XRRConfigRotations(XRRScreenConfiguration *config, Rotation *current_rotation);

Time XRRConfigTimes (XRRScreenConfiguration *config, Time *config_timestamp);

XRRScreenSize *XRRConfigSizes(XRRScreenConfiguration *config, int *nsizes);

short *XRRConfigRates (XRRScreenConfiguration *config, int sizeID, int *nrates);

SizeID XRRConfigCurrentConfiguration (XRRScreenConfiguration *config,
									  Rotation *rotation);

short XRRConfigCurrentRate (XRRScreenConfiguration *config);

int XRRRootToScreen(Display *dpy, Window root);

void XRRSelectInput(Display *dpy, Window window, int mask);

Rotation XRRRotations(Display *dpy, int screen, Rotation *current_rotation);
XRRScreenSize *XRRSizes(Display *dpy, int screen, int *nsizes);
short *XRRRates (Display *dpy, int screen, int sizeID, int *nrates);
Time XRRTimes (Display *dpy, int screen, Time *config_timestamp);

Status
	XRRGetScreenSizeRange (Display *dpy, Window window,
						   int *minWidth, int *minHeight,
						   int *maxWidth, int *maxHeight);

void
	XRRSetScreenSize (Display *dpy, Window window,
					  int width, int height,
					  int mmWidth, int mmHeight);

alias ulong XRRModeFlags;

struct _XRRModeInfo {
	RRMode	id;
	uint	width;
	uint	height;
	ulong	dotClock;
	uint	hSyncStart;
	uint	hSyncEnd;
	uint	hTotal;
	uint	hSkew;
	uint	vSyncStart;
	uint	vSyncEnd;
	uint	vTotal;
	char	*name;
	uint	nameLength;
	XRRModeFlags	modeFlags;
}
alias _XRRModeInfo XRRModeInfo;

struct _XRRScreenResources {
	Time	timestamp;
	Time	configTimestamp;
	int	ncrtc;
	RRCrtc	*crtcs;
	int	noutput;
	RROutput	*outputs;
	int	nmode;
	XRRModeInfo	*modes;
}
alias _XRRScreenResources XRRScreenResources;

XRRScreenResources *
	XRRGetScreenResources (Display *dpy, Window window);

void
	XRRFreeScreenResources (XRRScreenResources *resources);

struct _XRROutputInfo {
	Time	timestamp;
	RRCrtc	crtc;
	char	*name;
	int	nameLen;
	ulong mm_width;
	ulong mm_height;
	Connection	connection;
	SubpixelOrder subpixel_order;
	int	ncrtc;
	RRCrtc	*crtcs;
	int	nclone;
	RROutput	*clones;
	int	nmode;
	int	npreferred;
	RRMode	*modes;
}
alias _XRROutputInfo XRROutputInfo;

XRROutputInfo *
	XRRGetOutputInfo (Display *dpy, XRRScreenResources *resources, RROutput output);

void
	XRRFreeOutputInfo (XRROutputInfo *outputInfo);

Atom *
	XRRListOutputProperties (Display *dpy, RROutput output, int *nprop);

struct XRRPropertyInfo {
	Bool pending;
	Bool range;
	Bool immutable_; // cannot call this property immutable (D keyword). Prefixing with _.
	int	num_values;
	long *values;
}

XRRPropertyInfo *
	XRRQueryOutputProperty (Display *dpy, RROutput output, Atom property);

void
	XRRConfigureOutputProperty (Display *dpy, RROutput output, Atom property,
								Bool pending, Bool range, int num_values,
								long *values);

void
	XRRChangeOutputProperty (Display *dpy, RROutput output,
							 Atom property, Atom type,
							 int format, int mode,
							 const ubyte *data, int nelements);

void
	XRRDeleteOutputProperty (Display *dpy, RROutput output, Atom property);

int
	XRRGetOutputProperty (Display *dpy, RROutput output,
						  Atom property, long offset, long length,
						  Bool _delete, Bool pending, Atom req_type,
						  Atom *actual_type, int *actual_format,
						  ulong *nitems, ulong *bytes_after,
						  ubyte **prop);

XRRModeInfo *
	XRRAllocModeInfo (char *name, int nameLength);

RRMode
	XRRCreateMode (Display *dpy, Window window, XRRModeInfo *modeInfo);

void
	XRRDestroyMode (Display *dpy, RRMode mode);

void
	XRRAddOutputMode (Display *dpy, RROutput output, RRMode mode);

void
	XRRDeleteOutputMode (Display *dpy, RROutput output, RRMode mode);

void
	XRRFreeModeInfo (XRRModeInfo *modeInfo);

struct _XRRCrtcInfo {
	Time	timestamp;
	int	x, y;
	uint width, height;
	RRMode	mode;
	Rotation	rotation;
	int	noutput;
	RROutput	*outputs;
	Rotation	rotations;
	int	npossible;
	RROutput	*possible;
}
alias _XRRCrtcInfo XRRCrtcInfo;

XRRCrtcInfo *
	XRRGetCrtcInfo (Display *dpy, XRRScreenResources *resources, RRCrtc crtc);

void
	XRRFreeCrtcInfo (XRRCrtcInfo *crtcInfo);

Status
	XRRSetCrtcConfig (Display *dpy,
					  XRRScreenResources *resources,
					  RRCrtc crtc,
					  Time timestamp,
					  int x, int y,
					  RRMode mode,
					  Rotation rotation,
					  RROutput *outputs,
					  int noutputs);

int
	XRRGetCrtcGammaSize (Display *dpy, RRCrtc crtc);

struct _XRRCrtcGamma {
	int	size;
	ushort *red;
	ushort *green;
	ushort *blue;
}
alias _XRRCrtcGamma XRRCrtcGamma;

XRRCrtcGamma *
	XRRGetCrtcGamma (Display *dpy, RRCrtc crtc);

XRRCrtcGamma *
	XRRAllocGamma (int size);

void
	XRRSetCrtcGamma (Display *dpy, RRCrtc crtc, XRRCrtcGamma *gamma);

void
	XRRFreeGamma (XRRCrtcGamma *gamma);

XRRScreenResources *
	XRRGetScreenResourcesCurrent (Display *dpy, Window window);

void
	XRRSetCrtcTransform (Display	*dpy,
						 RRCrtc	crtc,
						 XTransform	*transform,
						 char	*filter,
						 XFixed	*params,
						 int	nparams);

struct _XRRCrtcTransformAttributes {
	XTransform	pendingTransform;
	char	*pendingFilter;
	int	pendingNparams;
	XFixed	*pendingParams;
	XTransform	currentTransform;
	char	*currentFilter;
	int	currentNparams;
	XFixed	*currentParams;
}
alias _XRRCrtcTransformAttributes XRRCrtcTransformAttributes;

Status
	XRRGetCrtcTransform (Display	*dpy,
						 RRCrtc	crtc,
						 XRRCrtcTransformAttributes **attributes);

int XRRUpdateConfiguration(XEvent *event);

struct _XRRPanning {
	Time timestamp;
	uint left;
	uint top;
	uint width;
	uint height;
	uint track_left;
	uint track_top;
	uint track_width;
	uint track_height;
	int border_left;
	int border_top;
	int border_right;
	int border_bottom;
}
alias _XRRPanning XRRPanning;

XRRPanning *
	XRRGetPanning (Display *dpy, XRRScreenResources *resources, RRCrtc crtc);

void
	XRRFreePanning (XRRPanning *panning);

Status
	XRRSetPanning (Display *dpy,
				   XRRScreenResources *resources,
				   RRCrtc crtc,
				   XRRPanning *panning);

void
	XRRSetOutputPrimary(Display *dpy,
						Window window,
						RROutput output);

RROutput
	XRRGetOutputPrimary(Display *dpy,
						Window window);
