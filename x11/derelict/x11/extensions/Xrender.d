module derelict.x11.extensions.Xrender;

version(linux):
/*
 *
 * Copyright © 2000 SuSE, Inc.
 *
 * Permission to use, copy, modify, distribute, and sell this software and its
 * documentation for any purpose is hereby granted without fee, provided that
 * the above copyright notice appear in all copies and that both that
 * copyright notice and this permission notice appear in supporting
 * documentation, and that the name of SuSE not be used in advertising or
 * publicity pertaining to distribution of the software without specific,
 * written prior permission.  SuSE makes no representations about the
 * suitability of this software for any purpose.  It is provided "as is"
 * without express or implied warranty.
 *
 * SuSE DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE, INCLUDING ALL
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS, IN NO EVENT SHALL SuSE
 * BE LIABLE FOR ANY SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
 * OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
 * CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 * Author:  Keith Packard, SuSE, Inc.
 */

import derelict.x11.X;
import derelict.x11.Xlib;
import derelict.x11.Xutil;

import derelict.x11.extensions.render;

extern (C) nothrow @nogc:

struct XRenderDirectFormat{
	short   red;
	short   redMask;
	short   green;
	short   greenMask;
	short   blue;
	short   blueMask;
	short   alpha;
	short   alphaMask;
}

struct XRenderPictFormat{
	PictFormat		id;
	int			type;
	int			depth;
	XRenderDirectFormat	direct;
	Colormap		colormap;
}

enum PictFormatID        = (1 << 0);
enum PictFormatType      = (1 << 1);
enum PictFormatDepth     = (1 << 2);
enum PictFormatRed       = (1 << 3);
enum PictFormatRedMask   = (1 << 4);
enum PictFormatGreen     = (1 << 5);
enum PictFormatGreenMask = (1 << 6);
enum PictFormatBlue      = (1 << 7);
enum PictFormatBlueMask  = (1 << 8);
enum PictFormatAlpha     = (1 << 9);
enum PictFormatAlphaMask = (1 << 10);
enum PictFormatColormap  = (1 << 11);

struct XRenderPictureAttributes {
	int 		repeat;
	Picture		alpha_map;
	int			alpha_x_origin;
	int			alpha_y_origin;
	int			clip_x_origin;
	int			clip_y_origin;
	Pixmap		clip_mask;
	Bool		graphics_exposures;
	int			subwindow_mode;
	int			poly_edge;
	int			poly_mode;
	Atom		dither;
	Bool		component_alpha;
}

struct XRenderColor{
	ushort   red;
	ushort   green;
	ushort   blue;
	ushort   alpha;
}

struct XGlyphInfo {
	ushort  width;
	ushort  height;
	short	    x;
	short	    y;
	short	    xOff;
	short	    yOff;
}

struct XGlyphElt8 {
	GlyphSet		    glyphset;
	const char	    *chars;
	int			    nchars;
	int			    xOff;
	int			    yOff;
}

struct XGlyphElt16 {
	GlyphSet        glyphset;
	const ushort*   chars;
	int			    nchars;
	int			    xOff;
	int			    yOff;
}

struct XGlyphElt32 {
	GlyphSet		glyphset;
	const uint*     chars;
	int			    nchars;
	int			    xOff;
	int			    yOff;
}

alias double	XDouble;

struct XPointDouble {
	XDouble  x, y;
}

XFixed XDoubleToFixed(T)(T f) {
	return (cast(XFixed)(f * 65536));
}

XDouble XFixedToDouble(T)(T f) {
	return (cast(XDouble)(f * 65536));
}

alias int XFixed;

struct XPointFixed {
	XFixed  x, y;
}

struct XLineFixed {
	XPointFixed	p1, p2;
}

struct XTriangle {
	XPointFixed	p1, p2, p3;
}

struct XCircle {
	XFixed x;
	XFixed y;
	XFixed radius;
}

struct XTrapezoid {
	XFixed  top, bottom;
	XLineFixed	left, right;
}

struct XTransform {
	XFixed[3][3]  matrix;
}

struct XFilters {
	int	    nfilter;
	char    **filter;
	int	    nalias;
	short   *alias_;
}

struct XIndexValue {
	ulong    pixel;
	ushort   red, green, blue, alpha;
}

struct XAnimCursor {
	Cursor	    cursor;
	ulong   delay;
}

struct XSpanFix {
	XFixed	    left, right, y;
}

struct XTrap {
	XSpanFix	    top, bottom;
}

struct XLinearGradient {
	XPointFixed p1;
	XPointFixed p2;
}

struct XRadialGradient {
	XCircle inner;
	XCircle outer;
}

struct XConicalGradient {
	XPointFixed center;
	XFixed angle; /* in degrees */
}


Bool XRenderQueryExtension (Display *dpy, int *event_basep, int *error_basep);

Status XRenderQueryVersion (Display *dpy,
		int     *major_versionp,
		int     *minor_versionp);

Status XRenderQueryFormats (Display *dpy);

int XRenderQuerySubpixelOrder (Display *dpy, int screen);

Bool XRenderSetSubpixelOrder (Display *dpy, int screen, int subpixel);

XRenderPictFormat *
	XRenderFindVisualFormat (Display *dpy, const Visual *visual);

XRenderPictFormat *
	XRenderFindFormat (Display			*dpy,
			ulong		mask,
			const XRenderPictFormat	*templ,
			int				count);

enum PictStandardARGB32 = 0;
enum PictStandardRGB24  = 1;
enum PictStandardA8	    = 2;
enum PictStandardA4	    = 3;
enum PictStandardA1	    = 4;
enum PictStandardNUM    = 5;

XRenderPictFormat *
	XRenderFindStandardFormat (Display		*dpy,
			int			format);

XIndexValue *
	XRenderQueryPictIndexValues(Display			*dpy,
			const XRenderPictFormat	*format,
			int				*num);

Picture
	XRenderCreatePicture (Display				*dpy,
			Drawable				drawable,
			const XRenderPictFormat		*format,
			ulong			valuemask,
			const XRenderPictureAttributes	*attributes);

void
	XRenderChangePicture (Display				*dpy,
			Picture				picture,
			ulong			valuemask,
			const XRenderPictureAttributes  *attributes);

void
	XRenderSetPictureClipRectangles (Display	    *dpy,
			Picture	    picture,
			int		    xOrigin,
			int		    yOrigin,
			const XRectangle *rects,
			int		    n);

void
	XRenderSetPictureClipRegion (Display	    *dpy,
			Picture	    picture,
			Region	    r);

void
	XRenderSetPictureTransform (Display	    *dpy,
			Picture	    picture,
			XTransform	    *transform);

void
	XRenderFreePicture (Display                   *dpy,
			Picture                   picture);

void
	XRenderComposite (Display   *dpy,
			int	    op,
			Picture   src,
			Picture   mask,
			Picture   dst,
			int	    src_x,
			int	    src_y,
			int	    mask_x,
			int	    mask_y,
			int	    dst_x,
			int	    dst_y,
			uint	width,
			uint	height);

GlyphSet
	XRenderCreateGlyphSet (Display *dpy, const XRenderPictFormat *format);

GlyphSet
	XRenderReferenceGlyphSet (Display *dpy, GlyphSet existing);

void
	XRenderFreeGlyphSet (Display *dpy, GlyphSet glyphset);

void
	XRenderAddGlyphs (Display		*dpy,
			GlyphSet		glyphset,
			const Glyph		*gids,
			const XGlyphInfo	*glyphs,
			int			nglyphs,
			const char		*images,
			int			nbyte_images);

void
	XRenderFreeGlyphs (Display	    *dpy,
			GlyphSet	    glyphset,
			const Glyph    *gids,
			int		    nglyphs);

void
	XRenderCompositeString8 (Display		    *dpy,
			int			    op,
			Picture		    src,
			Picture		    dst,
			const XRenderPictFormat  *maskFormat,
			GlyphSet		    glyphset,
			int			    xSrc,
			int			    ySrc,
			int			    xDst,
			int			    yDst,
			const char		    *string,
			int			    nchar);

void
	XRenderCompositeString16 (Display		    *dpy,
			int			    op,
			Picture		    src,
			Picture		    dst,
			const XRenderPictFormat *maskFormat,
			GlyphSet		    glyphset,
			int			    xSrc,
			int			    ySrc,
			int			    xDst,
			int			    yDst,
			const ushort    *string,
			int			    nchar);

void
	XRenderCompositeString32 (Display		    *dpy,
			int			    op,
			Picture		    src,
			Picture		    dst,
			const XRenderPictFormat *maskFormat,
			GlyphSet		    glyphset,
			int			    xSrc,
			int			    ySrc,
			int			    xDst,
			int			    yDst,
			const uint	    *string,
			int			    nchar);

void
	XRenderCompositeText8 (Display			    *dpy,
			int			    op,
			Picture			    src,
			Picture			    dst,
			const XRenderPictFormat    *maskFormat,
			int			    xSrc,
			int			    ySrc,
			int			    xDst,
			int			    yDst,
			const XGlyphElt8	    *elts,
			int			    nelt);

void
	XRenderCompositeText16 (Display			    *dpy,
			int			    op,
			Picture			    src,
			Picture			    dst,
			const XRenderPictFormat   *maskFormat,
			int			    xSrc,
			int			    ySrc,
			int			    xDst,
			int			    yDst,
			const XGlyphElt16	    *elts,
			int			    nelt);

void
	XRenderCompositeText32 (Display			    *dpy,
			int			    op,
			Picture			    src,
			Picture			    dst,
			const XRenderPictFormat   *maskFormat,
			int			    xSrc,
			int			    ySrc,
			int			    xDst,
			int			    yDst,
			const XGlyphElt32	    *elts,
			int			    nelt);

void
	XRenderFillRectangle (Display		    *dpy,
			int		    op,
			Picture		    dst,
			const XRenderColor  *color,
			int		    x,
			int		    y,
			uint	    width,
			uint	    height);

void
	XRenderFillRectangles (Display		    *dpy,
			int		    op,
			Picture		    dst,
			const XRenderColor *color,
			const XRectangle   *rectangles,
			int		    n_rects);

void
	XRenderCompositeTrapezoids (Display		*dpy,
			int			op,
			Picture		src,
			Picture		dst,
			const XRenderPictFormat	*maskFormat,
			int			xSrc,
			int			ySrc,
			const XTrapezoid	*traps,
			int			ntrap);

void
	XRenderCompositeTriangles (Display		*dpy,
			int			op,
			Picture		src,
			Picture		dst,
			const XRenderPictFormat	*maskFormat,
			int			xSrc,
			int			ySrc,
			const XTriangle	*triangles,
			int			ntriangle);

void
	XRenderCompositeTriStrip (Display		*dpy,
			int			op,
			Picture		src,
			Picture		dst,
			const XRenderPictFormat	*maskFormat,
			int			xSrc,
			int			ySrc,
			const XPointFixed	*points,
			int			npoint);

void
	XRenderCompositeTriFan (Display			*dpy,
			int			op,
			Picture			src,
			Picture			dst,
			const XRenderPictFormat	*maskFormat,
			int			xSrc,
			int			ySrc,
			const XPointFixed	*points,
			int			npoint);

void
	XRenderCompositeDoublePoly (Display		    *dpy,
			int			    op,
			Picture		    src,
			Picture		    dst,
			const XRenderPictFormat	*maskFormat,
			int			    xSrc,
			int			    ySrc,
			int			    xDst,
			int			    yDst,
			const XPointDouble    *fpoints,
			int			    npoints,
			int			    winding);
Status
	XRenderParseColor(Display	*dpy,
			char		*spec,
			XRenderColor	*def);

Cursor
	XRenderCreateCursor (Display	    *dpy,
			Picture	    source,
			uint   x,
			uint   y);

XFilters *
	XRenderQueryFilters (Display *dpy, Drawable drawable);

void
	XRenderSetPictureFilter (Display    *dpy,
			Picture    picture,
			const char *filter,
			XFixed	    *params,
			int	    nparams);

Cursor
	XRenderCreateAnimCursor (Display	*dpy,
			int		ncursor,
			XAnimCursor	*cursors);


void
	XRenderAddTraps (Display	    *dpy,
			Picture	    picture,
			int		    xOff,
			int		    yOff,
			const XTrap	    *traps,
			int		    ntrap);

Picture XRenderCreateSolidFill (Display *dpy,
		const XRenderColor *color);

Picture XRenderCreateLinearGradient (Display *dpy,
		const XLinearGradient *gradient,
		const XFixed *stops,
		const XRenderColor *colors,
		int nstops);

Picture XRenderCreateRadialGradient (Display *dpy,
		const XRadialGradient *gradient,
		const XFixed *stops,
		const XRenderColor *colors,
		int nstops);

Picture XRenderCreateConicalGradient (Display *dpy,
		const XConicalGradient *gradient,
		const XFixed *stops,
		const XRenderColor *colors,
		int nstops);
