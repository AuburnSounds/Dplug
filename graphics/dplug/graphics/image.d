/**
 * In-memory images and various image formats.
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

module dplug.graphics.image;

import std.algorithm.comparison;
import std.conv : to;
import std.exception;
import std.range;
import std.traits;
import std.string : format;

public import dplug.graphics.view;

/// Represents a reference to COLOR data
/// already existing elsewhere in memory.
/// Assumes that pixels are stored row-by-row,
/// with a known distance between each row.
struct ImageRef(COLOR)
{
	int w, h;
	size_t pitch; /// In bytes, not COLORs
	COLOR* pixels;

	/// Returns an array for the pixels at row y.
	COLOR[] scanline(int y)
	{
		assert(y>=0 && y<h);
		assert(pitch);
		auto row = cast(COLOR*)(cast(ubyte*)pixels + y*pitch);
		return row[0..w];
	}

	mixin DirectView;
}

unittest
{
	static assert(isDirectView!(ImageRef!ubyte));
}

/// Convert a direct view to an ImageRef.
/// Assumes that the rows are evenly spaced.
ImageRef!(ViewColor!SRC) toRef(SRC)(auto ref SRC src)
	if (isDirectView!SRC)
{
	return ImageRef!(ViewColor!SRC)(src.w, src.h,
		src.h > 1 ? cast(ubyte*)src.scanline(1) - cast(ubyte*)src.scanline(0) : src.w,
		src.scanline(0).ptr);
}

unittest
{
	auto i = Image!ubyte(1, 1);
	auto r = i.toRef();
	assert(r.scanline(0).ptr is i.scanline(0).ptr);
}

// ***************************************************************************

/// An in-memory image.
/// Pixels are stored in a flat array.
struct Image(COLOR)
{
	int w, h;
	COLOR[] pixels;

	/// Returns an array for the pixels at row y.
	COLOR[] scanline(int y)
	{
		assert(y>=0 && y<h);
		auto start = w*y;
		return pixels[start..start+w];
	}

	mixin DirectView;

	this(int w, int h)
	{
		size(w, h);
	}

	/// Does not scale image
	void size(int w, int h)
	{
		this.w = w;
		this.h = h;
		if (pixels.length < w*h)
			pixels.length = w*h;
	}
}

unittest
{
	static assert(isDirectView!(Image!ubyte));
}

// ***************************************************************************

// Functions which need a target image to operate on are currenty declared
// as two overloads. The code might be simplified if some of these get fixed:
// https://d.puremagic.com/issues/show_bug.cgi?id=8074
// https://d.puremagic.com/issues/show_bug.cgi?id=12386
// https://d.puremagic.com/issues/show_bug.cgi?id=12425
// https://d.puremagic.com/issues/show_bug.cgi?id=12426
// https://d.puremagic.com/issues/show_bug.cgi?id=12433

alias ViewImage(V) = Image!(ViewColor!V);

/// Copy the given view into the specified target.
auto copy(SRC, TARGET)(auto ref SRC src, auto ref TARGET target)
	if (isView!SRC && isWritableView!TARGET)
{
	target.size(src.w, src.h);
	src.blitTo(target);
	return target;
}

/// Copy the given view into a newly-allocated image.
auto copy(SRC)(auto ref SRC src)
	if (isView!SRC)
{
	ViewImage!SRC target;
	return src.copy(target);
}

unittest
{
	auto v = onePixel(0);
	auto i = v.copy();
	v.copy(i);

	auto c = i.crop(0, 0, 1, 1);
	v.copy(c);
}

alias ElementViewImage(R) = ViewImage!(ElementType!R);

/// Splice multiple images horizontally.
auto hjoin(R, TARGET)(R images, auto ref TARGET target)
	if (isInputRange!R && isView!(ElementType!R) && isWritableView!TARGET)
{
	int w, h;
	foreach (ref image; images)
		w += image.w,
		h = max(h, image.h);
	target.size(w, h);
	int x;
	foreach (ref image; images)
		image.blitTo(target, x, 0),
		x += image.w;
	return target;
}
/// ditto
auto hjoin(R)(R images)
	if (isInputRange!R && isView!(ElementType!R))
{
	ElementViewImage!R target;
	return images.hjoin(target);
}

/// Splice multiple images vertically.
auto vjoin(R, TARGET)(R images, auto ref TARGET target)
	if (isInputRange!R && isView!(ElementType!R) && isWritableView!TARGET)
{
	int w, h;
	foreach (ref image; images)
		w = max(w, image.w),
		h += image.h;
	target.size(w, h);
	int y;
	foreach (ref image; images)
		image.blitTo(target, 0, y),
		y += image.h;
	return target;
}
/// ditto
auto vjoin(R)(R images)
	if (isInputRange!R && isView!(ElementType!R))
{
	ElementViewImage!R target;
	return images.vjoin(target);
}

unittest
{
	auto h = 10
		.iota
		.retro
		.map!onePixel
		.retro
		.hjoin();

	foreach (i; 0..10)
		assert(h[i, 0] == i);

	auto v = 10.iota.map!onePixel.vjoin();
	foreach (i; 0..10)
		assert(v[0, i] == i);
}

// ***************************************************************************

/// Performs linear downscale by a constant factor
template downscale(int HRX, int HRY=HRX)
{
	auto downscale(SRC, TARGET)(auto ref SRC src, auto ref TARGET target)
		if (isDirectView!SRC && isWritableView!TARGET)
	{
		alias lr = target;
		alias hr = src;

		assert(hr.w % HRX == 0 && hr.h % HRY == 0, "Size mismatch");

		lr.size(hr.w / HRX, hr.h / HRY);

		foreach (y; 0..lr.h)
			foreach (x; 0..lr.w)
			{
				static if (HRX*HRY <= 0x100)
					enum EXPAND_BYTES = 1;
				else
				static if (HRX*HRY <= 0x10000)
					enum EXPAND_BYTES = 2;
				else
					static assert(0);
				static if (is(typeof(COLOR.init.a))) // downscale with alpha
				{
					ExpandType!(COLOR, EXPAND_BYTES+COLOR.init.a.sizeof) sum;
					ExpandType!(typeof(COLOR.init.a), EXPAND_BYTES) alphaSum;
					auto start = y*HRY*hr.stride + x*HRX;
					foreach (j; 0..HRY)
					{
						foreach (p; hr.pixels[start..start+HRX])
						{
							foreach (i, f; p.tupleof)
								static if (p.tupleof[i].stringof != "p.a")
								{
									enum FIELD = p.tupleof[i].stringof[2..$];
									mixin("sum."~FIELD~" += cast(typeof(sum."~FIELD~"))p."~FIELD~" * p.a;");
								}
							alphaSum += p.a;
						}
						start += hr.stride;
					}
					if (alphaSum)
					{
						auto result = cast(COLOR)(sum / alphaSum);
						result.a = cast(typeof(result.a))(alphaSum / (HRX*HRY));
						lr[x, y] = result;
					}
					else
					{
						static assert(COLOR.init.a == 0);
						lr[x, y] = COLOR.init;
					}
				}
				else
				{
					ExpandChannelType!(ViewColor!SRC, EXPAND_BYTES) sum;
					auto x0 = x*HRX;
					auto x1 = x0+HRX;
					foreach (j; y*HRY..(y+1)*HRY)
						foreach (p; hr.scanline(j)[x0..x1])
							sum += p;
					lr[x, y] = cast(ViewColor!SRC)(sum / (HRX*HRY));
				}
			}

		return target;
	}

	auto downscale(SRC)(auto ref SRC src)
		if (isView!SRC)
	{
		ViewImage!SRC target;
		return src.downscale(target);
	}
}

unittest
{
	onePixel(RGB.init).nearestNeighbor(4, 4).copy.downscale!(2, 2)();
}

// ***************************************************************************

/// Copy the indicated row of src to a COLOR buffer.
void copyScanline(SRC, COLOR)(auto ref SRC src, int y, COLOR[] dst)
	if (isView!SRC && is(COLOR == ViewColor!SRC))
{
	static if (isDirectView!SRC)
		dst[] = src.scanline(y)[];
	else
	{
		assert(src.w == dst.length);
		foreach (x; 0..src.w)
			dst[x] = src[x, y];
	}
}

/// Copy a view's pixels (top-to-bottom) to a COLOR buffer.
void copyPixels(SRC, COLOR)(auto ref SRC src, COLOR[] dst)
	if (isView!SRC && is(COLOR == ViewColor!SRC))
{
	assert(dst.length == src.w * src.h);
	foreach (y; 0..src.h)
		src.copyScanline(y, dst[y*src.w..(y+1)*src.w]);
}

// ***************************************************************************

// Workaround for https://d.puremagic.com/issues/show_bug.cgi?id=12433

struct InputColor {}
alias GetInputColor(COLOR, INPUT) = Select!(is(COLOR == InputColor), INPUT, COLOR);

struct TargetColor {}
enum isTargetColor(C, TARGET) = is(C == TargetColor) || is(C == ViewColor!TARGET);

// ***************************************************************************
