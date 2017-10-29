/**
 * A `View` is the base abstraction for images. Port of ae.utils.graphics.
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
import std.algorithm.mutation: swap;
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
