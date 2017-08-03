module derelict.x11.extensions.Xdamage;

version(linux):

/*
 * Copyright © 2003 Keith Packard
 *
 * Permission to use, copy, modify, distribute, and sell this software and its
 * documentation for any purpose is hereby granted without fee, provided that
 * the above copyright notice appear in all copies and that both that
 * copyright notice and this permission notice appear in supporting
 * documentation, and that the name of Keith Packard not be used in
 * advertising or publicity pertaining to distribution of the software without
 * specific, written prior permission.  Keith Packard makes no
 * representations about the suitability of this software for any purpose.  It
 * is provided "as is" without express or implied warranty.
 *
 * KEITH PACKARD DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
 * INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS, IN NO
 * EVENT SHALL KEITH PACKARD BE LIABLE FOR ANY SPECIAL, INDIRECT OR
 * CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE,
 * DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
 * TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
 * PERFORMANCE OF THIS SOFTWARE.
 */

public import
    derelict.x11.extensions.damagewire,
    derelict.x11.extensions.Xfixes;

enum XDAMAGE_1_1_INTERFACE = true;

alias Damage = XID;

struct XDamageNotifyEvent {
    int type;			/* event base */
    ulong serial;
    Bool send_event;
    Display *display;
    Drawable drawable;
    Damage damage;
    int level;
    Bool more;			/* more events will be delivered immediately */
    Time timestamp;
    XRectangle area;
    XRectangle geometry;
}

extern(C) nothrow:

Bool XDamageQueryExtension (Display *dpy,
                            int *event_base_return,
                            int *error_base_return);

Status XDamageQueryVersion (Display *dpy,
			    int     *major_version_return,
			    int     *minor_version_return);

Damage
XDamageCreate (Display	*dpy, Drawable drawable, int level);

void
XDamageDestroy (Display *dpy, Damage damage);

void
XDamageSubtract (Display *dpy, Damage damage, 
		 XserverRegion repair, XserverRegion parts);

void
XDamageAdd (Display *dpy, Drawable drawable, XserverRegion region);

