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

import std.conv : to;
import std.string : format;

import dplug.graphics.view;

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
