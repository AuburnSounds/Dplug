/**
 * Image maps.
 *
 * License:
 *   This Source Code Form is subject to the terms of
 *   the Mozilla Public License, v. 2.0. If a copy of
 *   the MPL was not distributed with this file, You
 *   can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * Authors:
 *   Vladimir Panteleev <vladimir@thecybershadow.net>
 *   Guillaume Piolat <contact@auburnsounds.com>
 */

module dplug.graphics.view;

import std.functional;
import std.typetuple;
import std.algorithm: swap;
import std.math;

import dplug.core.math;

public import dplug.graphics.color;

/// A view is any type which provides a width, height,
/// and can be indexed to get the color at a specific
/// coordinate.
enum isView(T) =
	is(typeof(T.init.w) : size_t) && // width
	is(typeof(T.init.h) : size_t) && // height
	is(typeof(T.init[0, 0])     );   // color information

/// Returns the color type of the specified view.
/// By convention, colors are structs with numeric
/// fields named after the channel they indicate.
alias ViewColor(T) = typeof(T.init[0, 0]);

/// Views can be read-only or writable.
enum isWritableView(T) =
	isView!T &&
	is(typeof(T.init[0, 0] = ViewColor!T.init));

/// Optionally, a view can also provide direct pixel
/// access. We call these "direct views".
enum isDirectView(T) =
	isView!T &&
	is(typeof(T.init.scanline(0)) : ViewColor!T[]);

/// Mixin which implements view primitives on top of
/// existing direct view primitives.
mixin template DirectView()
{
	alias COLOR = typeof(scanline(0)[0]);

	/// Implements the view[x, y] operator.
	ref COLOR opIndex(int x, int y)
	{
		return scanline(y)[x];
	}

	/// Implements the view[x, y] = c operator.
	COLOR opIndexAssign(COLOR value, int x, int y)
	{
		return scanline(y)[x] = value;
	}
}

// ***************************************************************************

/// Returns a view which calculates pixels
/// on-demand using the specified formula.
template procedural(alias formula)
{
	alias fun = binaryFun!(formula, "x", "y");
	alias COLOR = typeof(fun(0, 0));

	auto procedural(int w, int h)
	{
		struct Procedural
		{
			int w, h;

			auto ref COLOR opIndex(int x, int y)
			{
				assert(x >= 0 && y >= 0 && x < w && y < h);
				return fun(x, y);
			}
		}
		return Procedural(w, h);
	}
}

/// Returns a view of the specified dimensions
/// and same solid color.
auto solid(COLOR)(COLOR c, int w, int h)
{
	return procedural!((x, y) => c)(w, h);
}

/// Return a 1x1 view of the specified color.
/// Useful for testing.
auto onePixel(COLOR)(COLOR c)
{
	return solid(c, 1, 1);
}

unittest
{
	assert(onePixel(42)[0, 0] == 42);
}

// ***************************************************************************

/// Blits a view onto another.
/// The views must have the same size.
void blitTo(SRC, DST)(auto ref SRC src, auto ref DST dst)
	if (isView!SRC && isWritableView!DST)
{
	assert(src.w == dst.w && src.h == dst.h, "View size mismatch");
	foreach (y; 0..src.h)
	{
		static if (isDirectView!SRC && isDirectView!DST)
			dst.scanline(y)[] = src.scanline(y)[];
		else
		{
			foreach (x; 0..src.w)
				dst[x, y] = src[x, y];
		}
	}
}

/// Helper function to blit an image onto another at a specified location.
void blitTo(SRC, DST)(auto ref SRC src, auto ref DST dst, int x, int y)
{
	src.blitTo(dst.crop(x, y, x+src.w, y+src.h));
}

/// Default implementation for the .size method.
/// Asserts that the view has the desired size.
void size(V)(auto ref V src, int w, int h)
	if (isView!V)
{
	assert(src.w == w && src.h == h, "Wrong size for " ~ V.stringof);
}

// ***************************************************************************

/// Mixin which implements view primitives on top of
/// another view, using a coordinate transform function.
mixin template Warp(V)
	if (isView!V)
{
	V src;

	auto ref ViewColor!V opIndex(int x, int y)
	{
		warp(x, y);
		return src[x, y];
	}

	static if (isWritableView!V)
	ViewColor!V opIndexAssign(ViewColor!V value, int x, int y)
	{
		warp(x, y);
		return src[x, y] = value;
	}
}

/// Crop a view to the specified rectangle.
auto crop(V)(auto ref V src, int x0, int y0, int x1, int y1)
	if (isView!V)
{
	assert( 0 <=    x0 &&  0 <=    y0);
	assert(x0 <=    x1 && y0 <=    y1);
	assert(x1 <= src.w && y1 <= src.h);

	static struct Crop
	{
		mixin Warp!V;

		int x0, y0, x1, y1;

		@property int w() { return x1-x0; }
		@property int h() { return y1-y0; }

		void warp(ref int x, ref int y)
		{
			x += x0;
			y += y0;
		}

		static if (isDirectView!V)
		ViewColor!V[] scanline(int y)
		{
			return src.scanline(y0+y)[x0..x1];
		}
	}

	static assert(isDirectView!V == isDirectView!Crop);

	return Crop(src, x0, y0, x1, y1);
}

unittest
{
	auto g = procedural!((x, y) => y)(1, 256);
	auto c = g.crop(0, 10, 1, 20);
	assert(c[0, 0] == 10);
}

/// Tile another view.
auto tile(V)(auto ref V src, int w, int h)
	if (isView!V)
{
	static struct Tile
	{
		mixin Warp!V;

		int w, h;

		void warp(ref int x, ref int y)
		{
			assert(x >= 0 && y >= 0 && x < w && y < h);
			x = x % src.w;
			y = y % src.h;
		}
	}

	return Tile(src, w, h);
}

unittest
{
	auto i = onePixel(4);
	auto t = i.tile(100, 100);
	assert(t[12, 34] == 4);
}

/// Present a resized view using nearest-neighbor interpolation.
/// Use big=true for images over 32k width/height.
auto nearestNeighbor(V)(auto ref V src, int w, int h)
	if (isView!V)
{
	static struct NearestNeighbor
	{
		mixin Warp!V;

		int w, h;

		void warp(ref int x, ref int y)
		{
			x = cast(int)(cast(long)x * src.w / w);
			y = cast(int)(cast(long)y * src.h / h);
		}
	}

	return NearestNeighbor(src, w, h);
}

unittest
{
	auto g = procedural!((x, y) => x+10*y)(10, 10);
	auto n = g.nearestNeighbor(100, 100);
	assert(n[12, 34] == 31);
}

/// Swap the X and Y axes (flip the image diagonally).
auto flipXY(V)(auto ref V src)
{
	static struct FlipXY
	{
		mixin Warp!V;

		@property int w() { return src.h; }
		@property int h() { return src.w; }

		void warp(ref int x, ref int y)
		{
			import std.algorithm;
			swap(x, y);
		}
	}

	return FlipXY(src);
}

// ***************************************************************************

/// Return a view of src with the coordinates transformed
/// according to the given formulas
template warp(string xExpr, string yExpr)
{
	auto warp(V)(auto ref V src)
		if (isView!V)
	{
		static struct Warped
		{
			mixin Warp!V;

			@property int w() { return src.w; }
			@property int h() { return src.h; }

			void warp(ref int x, ref int y)
			{
				auto nx = mixin(xExpr);
				auto ny = mixin(yExpr);
				x = nx; y = ny;
			}

			private void testWarpY()()
			{
				int y;
				y = mixin(yExpr);
			}

			/// If the x coordinate is not affected and y does not
			/// depend on x, we can transform entire scanlines.
			static if (xExpr == "x" &&
				__traits(compiles, testWarpY()) &&
				isDirectView!V)
			ViewColor!V[] scanline(int y)
			{
				return src.scanline(mixin(yExpr));
			}
		}

		return Warped(src);
	}
}

/// ditto
template warp(alias pred)
{
	auto warp(V)(auto ref V src)
		if (isView!V)
	{
		struct Warped
		{
			mixin Warp!V;

			@property int w() { return src.w; }
			@property int h() { return src.h; }

			alias warp = binaryFun!(pred, "x", "y");
		}

		return Warped(src);
	}
}

/// Return a view of src with the x coordinate inverted.
alias hflip = warp!(q{w-x-1}, q{y});

/// Return a view of src with the y coordinate inverted.
alias vflip = warp!(q{x}, q{h-y-1});

/// Return a view of src with both coordinates inverted.
alias flip = warp!(q{w-x-1}, q{h-y-1});

unittest
{
	import dplug.graphics.image;
	auto vband = procedural!((x, y) => y)(1, 256).copy();
	auto flipped = vband.vflip();
	assert(flipped[0, 1] == 254);
	static assert(isDirectView!(typeof(flipped)));

	auto w = vband.warp!((ref x, ref y) { swap(x, y); });
}

/// Rotate a view 90 degrees clockwise.
auto rotateCW(V)(auto ref V src)
{
	return src.flipXY().hflip();
}

/// Rotate a view 90 degrees counter-clockwise.
auto rotateCCW(V)(auto ref V src)
{
	return src.flipXY().vflip();
}

unittest
{
	auto g = procedural!((x, y) => x+10*y)(10, 10);
	int[] corners(V)(V v) { return [v[0, 0], v[9, 0], v[0, 9], v[9, 9]]; }
	assert(corners(g          ) == [ 0,  9, 90, 99]);
	assert(corners(g.flipXY   ) == [ 0, 90,  9, 99]);
	assert(corners(g.rotateCW ) == [90,  0, 99,  9]);
	assert(corners(g.rotateCCW) == [ 9, 99,  0, 90]);
}

// ***************************************************************************

/// Return a view with the given views concatenated vertically.
/// Assumes all views have the same width.
/// Creates an index for fast row -> source view lookup.
auto vjoiner(V)(V[] views)
	if (isView!V)
{
	static struct VJoiner
	{
		struct Child { V view; int y; }
		Child[] children;
		size_t[] index;

		@property int w() { return children[0].view.w; }
		int h;

		this(V[] views)
		{
			children = new Child[views.length];
			int y = 0;
			foreach (i, ref v; views)
			{
				assert(v.w == views[0].w, "Inconsistent width");
				children[i] = Child(v, y);
				y += v.h;
			}

			h = y;

			index = new size_t[h];

			foreach (i, ref child; children)
				index[child.y .. child.y + child.view.h] = i;
		}

		auto ref ViewColor!V opIndex(int x, int y)
		{
			auto child = &children[index[y]];
			return child.view[x, y - child.y];
		}

		static if (isWritableView!V)
		ViewColor!V opIndexAssign(ViewColor!V value, int x, int y)
		{
			auto child = &children[index[y]];
			return child.view[x, y - child.y] = value;
		}

		static if (isDirectView!V)
		ViewColor!V[] scanline(int y)
		{
			auto child = &children[index[y]];
			return child.view.scanline(y - child.y);
		}
	}

	return VJoiner(views);
}

unittest
{
	import std.algorithm : map;
	import std.array : array;
	import std.range : iota;

	auto v = 10.iota.map!onePixel.array.vjoiner();
	foreach (i; 0..10)
		assert(v[0, i] == i);
}

// ***************************************************************************

/// Overlay the view fg over bg at a certain coordinate.
/// The resulting view inherits bg's size.
auto overlay(BG, FG)(auto ref BG bg, auto ref FG fg, int x, int y)
	if (isView!BG && isView!FG && is(ViewColor!BG == ViewColor!FG))
{
	alias COLOR = ViewColor!BG;

	static struct Overlay
	{
		BG bg;
		FG fg;

		int ox, oy;

		@property int w() { return bg.w; }
		@property int h() { return bg.h; }

		auto ref COLOR opIndex(int x, int y)
		{
			if (x >= ox && y >= oy && x < ox + fg.w && y < oy + fg.h)
				return fg[x - ox, y - oy];
			else
				return bg[x, y];
		}

		static if (isWritableView!BG && isWritableView!FG)
		COLOR opIndexAssign(COLOR value, int x, int y)
		{
			if (x >= ox && y >= oy && x < ox + fg.w && y < oy + fg.h)
				return fg[x - ox, y - oy] = value;
			else
				return bg[x, y] = value;
		}
	}

	return Overlay(bg, fg, x, y);
}

/// Add a solid-color border around an image.
/// The parameters indicate the border's thickness around each side
/// (left, top, right, bottom in order).
auto border(V, COLOR)(auto ref V src, int x0, int y0, int x1, int y1, COLOR color)
	if (isView!V && is(COLOR == ViewColor!V))
{
	return color
		.solid(
			x0 + src.w + x1,
			y0 + src.h + y1,
		)
		.overlay(src, x0, y0);
}

unittest
{
	auto g = procedural!((x, y) => x+10*y)(10, 10);
	auto b = g.border(5, 5, 5, 5, 42);
	assert(b.w == 20);
	assert(b.h == 20);
	assert(b[1, 2] == 42);
	assert(b[5, 5] == 0);
	assert(b[14, 14] == 99);
	assert(b[14, 15] == 42);
}

// ***************************************************************************

/// Alpha-blend a number of views.
/// The order is bottom-to-top.
auto blend(SRCS...)(SRCS sources)
	if (allSatisfy!(isView, SRCS)
	 && sources.length > 0)
{
	alias COLOR = ViewColor!(SRCS[0]);

	foreach (src; sources)
		assert(src.w == sources[0].w && src.h == sources[0].h,
			"Mismatching layer size");

	static struct Blend
	{
		SRCS sources;

		@property int w() { return sources[0].w; }
		@property int h() { return sources[0].h; }

		COLOR opIndex(int x, int y)
		{
			COLOR c = sources[0][x, y];
			foreach (ref src; sources[1..$])
				c = COLOR.blend(c, src[x, y]);
			return c;
		}
	}

	return Blend(sources);
}

unittest
{
	import dplug.graphics.color : LA;
	auto v0 = onePixel(LA(  0, 255));
	auto v1 = onePixel(LA(255, 100));
	auto vb = blend(v0, v1);
	assert(vb[0, 0] == LA(100, 255));
}

// ***************************************************************************

/// Similar to Warp, but allows warped coordinates to go out of bounds.
mixin template SafeWarp(V)
{
	V src;
	ViewColor!V defaultColor;

	auto ref ViewColor!V opIndex(int x, int y)
	{
		warp(x, y);
		if (x >= 0 && y >= 0 && x < w && y < h)
			return src[x, y];
		else
			return defaultColor;
	}

	static if (isWritableView!V)
	ViewColor!V opIndexAssign(ViewColor!V value, int x, int y)
	{
		warp(x, y);
		if (x >= 0 && y >= 0 && x < w && y < h)
			return src[x, y] = value;
		else
			return defaultColor;
	}
}

/// Rotate a view at an arbitrary angle (specified in radians),
/// around the specified point. Rotated points that fall outside of
/// the specified view resolve to defaultColor.
auto rotate(V, COLOR)(auto ref V src, double angle, COLOR defaultColor,
		double ox, double oy)
	if (isView!V && is(COLOR : ViewColor!V))
{
	static struct Rotate
	{
		mixin SafeWarp!V;
		double theta, ox, oy;

		@property int w() { return src.w; }
		@property int h() { return src.h; }

		void warp(ref int x, ref int y)
		{
			auto vx = x - ox;
			auto vy = y - oy;
			x = cast(int)round(ox + cos(theta) * vx - sin(theta) * vy);
			y = cast(int)round(oy + sin(theta) * vx + cos(theta) * vy);
		}
	}

	return Rotate(src, defaultColor, angle, ox, oy);
}

/// Rotate a view at an arbitrary angle (specified in radians) around
/// its center.
auto rotate(V, COLOR)(auto ref V src, double angle,
		COLOR defaultColor = ViewColor!V.init)
	if (isView!V && is(COLOR : ViewColor!V))
{
	return src.rotate(angle, defaultColor, src.w / 2.0 - 0.5, src.h / 2.0 - 0.5);
}

unittest
{
	import dplug.graphics.image;
	auto i = Image!int(3, 3);
	i[1, 0] = 1;
	auto r = i.rotate(cast(double)TAU/4, 0);
	assert(r[1, 0] == 0);
	assert(r[0, 1] == 1);
}

// ***************************************************************************

/// Return a view which applies a predicate over the
/// underlying view's pixel colors.
template colorMap(alias fun)
{
	auto colorMap(V)(auto ref V src)
		if (isView!V)
	{
		alias OLDCOLOR = ViewColor!V;
		alias NEWCOLOR = typeof(fun(OLDCOLOR.init));

		struct Map
		{
			V src;

			@property int w() { return src.w; }
			@property int h() { return src.h; }

			/*auto ref*/ NEWCOLOR opIndex(int x, int y)
			{
				return fun(src[x, y]);
			}
		}

		return Map(src);
	}
}

/// Returns a view which inverts all channels.
// TODO: skip alpha and padding
alias invert = colorMap!(c => ~c);

unittest
{
	import dplug.graphics.color;
	import dplug.graphics.image;

	auto i = onePixel(L8(1));
	assert(i.invert[0, 0].l == 254);
}

// ***************************************************************************

/// Returns the smallest window containing all
/// pixels that satisfy the given predicate.
template trim(alias fun)
{

	auto trim(V)(auto ref V src)
	{
		int x0 = 0, y0 = 0, x1 = src.w, y1 = src.h;
	topLoop:
		while (y0 < y1)
		{
			foreach (x; 0..src.w)
				if (fun(src[x, y0]))
					break topLoop;
			y0++;
		}
	bottomLoop:
		while (y1 > y0)
		{
			foreach (x; 0..src.w)
				if (fun(src[x, y1-1]))
					break bottomLoop;
			y1--;
		}

	leftLoop:
		while (x0 < x1)
		{
			foreach (y; y0..y1)
				if (fun(src[x0, y]))
					break leftLoop;
			x0++;
		}
	rightLoop:
		while (x1 > x0)
		{
			foreach (y; y0..y1)
				if (fun(src[x1-1, y]))
					break rightLoop;
			x1--;
		}

		return src.crop(x0, y0, x1, y1);
	}
}

alias trimAlpha = trim!(c => c.a);

