/**
 * Drawing functions.
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

module dplug.graphics.draw;

import std.algorithm : sort, min;
import std.traits;
import std.math;

import dplug.graphics.view;

version(unittest) import dplug.graphics.image;

// Constraints could be simpler if this was fixed:
// https://d.puremagic.com/issues/show_bug.cgi?id=12386

/// Get the pixel color at the specified coordinates,
/// or fall back to the specified default value if
/// the coordinates are out of bounds.
COLOR safeGet(V, COLOR)(auto ref V v, int x, int y, COLOR def)
	if (isView!V && is(COLOR : ViewColor!V))
{
	if (x>=0 && y>=0 && x<v.w && y<v.h)
		return v[x, y];
	else
		return def;
}

unittest
{
	auto v = onePixel(7);
	assert(v.safeGet(0, 0, 0) == 7);
	assert(v.safeGet(0, 1, 0) == 0);
}

/// Set the pixel color at the specified coordinates
/// if the coordinates are not out of bounds.
void safePut(V, COLOR)(auto ref V v, int x, int y, COLOR value)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	if (x>=0 && y>=0 && x<v.w && y<v.h)
		v[x, y] = value;
}


/// Forwards to safePut or opIndex, depending on the
/// CHECKED parameter. Allows propagation of a
/// CHECKED parameter from other callers.
void putPixel(bool CHECKED, V, COLOR)(auto ref V v, int x, int y, COLOR value)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	static if (CHECKED)
		v.safePut(x, y, value);
	else
		v[x, y] = value;
}


/// Gets a pixel's address from a direct view.
ViewColor!V* pixelPtr(V)(auto ref V v, int x, int y)
	if (isDirectView!V)
{
	return &v.scanline(y)[x];
}



/// Fills a writable view with a solid color.
void fill(V, COLOR)(auto ref V v, COLOR c)
	if (isWritableView!V
	 && is(COLOR : ViewColor!V))
{
	foreach (y; 0..v.h)
	{
		static if (isDirectView!V)
			v.scanline(y)[] = c;
		else
			foreach (x; 0..v.w)
				v[x, y] = c;
	}
}

// ***************************************************************************

enum CheckHLine =
q{
	static if (CHECKED)
	{
		if (x1 >= v.w || x2 <= 0 || y < 0 || y >= v.h || x1 >= x2) return;
		if (x1 <    0) x1 =   0;
		if (x2 >= v.w) x2 = v.w;
	}
	assert(x1 <= x2);
};

enum CheckVLine =
q{
	static if (CHECKED)
	{
		if (x < 0 || x >= v.w || y1 >= v.h || y2 <= 0 || y1 >= y2) return;
		if (y1 <    0) y1 =   0;
		if (y2 >= v.h) y2 = v.h;
	}
	assert(y1 <= y2);
};

void hline(bool CHECKED=true, V, COLOR)(auto ref V v, int x1, int x2, int y, COLOR c)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	mixin(CheckHLine);
	v.scanline(y)[x1..x2] = c;
}

void vline(bool CHECKED=true, V, COLOR)(auto ref V v, int x, int y1, int y2, COLOR c)
{
	mixin(CheckVLine);
	foreach (y; y1..y2) // TODO: optimize
		v[x, y] = c;
}

/+
void line(bool CHECKED=true, V, COLOR)(auto ref V v, int x1, int y1, int x2, int y2, COLOR c)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	mixin FixMath;

	enum DrawLine = q{
		// Axis-independent part. Mixin context:
		// a0 .. a1  - longer side
		// b0 .. b1  - shorter side
		// DrawPixel - mixin to draw a pixel at coordinates (a, b)

		if (a0 == a1)
			return;

		if (a0 > a1)
		{
			 swap(a0, a1);
			 swap(b0, b1);
		}

		// Use fixed-point for b position and offset per 1 pixel along "a" axis
		assert(b0 < (1L<<coordinateBits) && b1 < (1L<<coordinateBits));
		SignedBitsType!(coordinateBits*2) bPos = b0 << coordinateBits;
		SignedBitsType!(coordinateBits*2) bOff = ((b1-b0) << coordinateBits) / (a1-a0);

		foreach (a; a0..a1+1)
		{
			int b = (bPos += bOff) >> coordinateBits;
			mixin(DrawPixel);
		}
	};

	if (abs(x2-x1) > abs(y2-y1))
	{
		alias x1 a0;
		alias x2 a1;
		alias y1 b0;
		alias y2 b1;
		enum DrawPixel = q{ v.putPixel!CHECKED(a, b, c); };
		mixin(DrawLine);
	}
	else
	{
		alias y1 a0;
		alias y2 a1;
		alias x1 b0;
		alias x2 b1;
		enum DrawPixel = q{ v.putPixel!CHECKED(b, a, c); };
		mixin(DrawLine);
	}
}
+/

/// Draws a rectangle with a solid line.
/// The coordinates represent bounds (open on the right) for the outside of the rectangle.
void rect(bool CHECKED=true, V, COLOR)(auto ref V v, int x1, int y1, int x2, int y2, COLOR c)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	sort2(x1, x2);
	sort2(y1, y2);
	v.hline!CHECKED(x1, x2, y1  , c);
	v.hline!CHECKED(x1, x2, y2-1, c);
	v.vline!CHECKED(x1  , y1, y2, c);
	v.vline!CHECKED(x2-1, y1, y2, c);
}

void fillRect(bool CHECKED=true, V, COLOR)(auto ref V v, int x1, int y1, int x2, int y2, COLOR b) // [)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	sort2(x1, x2);
	sort2(y1, y2);
	static if (CHECKED)
	{
		if (x1 >= v.w || y1 >= v.h || x2 <= 0 || y2 <= 0 || x1==x2 || y1==y2) return;
		if (x1 <    0) x1 =   0;
		if (y1 <    0) y1 =   0;
		if (x2 >= v.w) x2 = v.w;
		if (y2 >= v.h) y2 = v.h;
	}
	foreach (y; y1..y2)
		v.scanline(y)[x1..x2] = b;
}

void fillRect(bool CHECKED=true, V, COLOR)(auto ref V v, int x1, int y1, int x2, int y2, COLOR c, COLOR b) // [)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	v.rect!CHECKED(x1, y1, x2, y2, c);
	if (x2-x1>2 && y2-y1>2)
		v.fillRect!CHECKED(x1+1, y1+1, x2-1, y2-1, b);
}

/// Unchecked! Make sure area is bounded.
void uncheckedFloodFill(V, COLOR)(auto ref V v, int x, int y, COLOR c)
	if (isDirectView!V && is(COLOR : ViewColor!V))
{
	v.floodFillPtr(&v[x, y], c, v[x, y]);
}

private void floodFillPtr(V, COLOR)(auto ref V v, COLOR* pp, COLOR c, COLOR f)
	if (isDirectView!V && is(COLOR : ViewColor!V))
{
	COLOR* p0 = pp; while (*p0==f) p0--; p0++;
	COLOR* p1 = pp; while (*p1==f) p1++; p1--;
	auto stride = v.scanline(1).ptr-v.scanline(0).ptr;
	for (auto p=p0; p<=p1; p++)
		*p = c;
	p0 -= stride; p1 -= stride;
	for (auto p=p0; p<=p1; p++)
		if (*p == f)
			v.floodFillPtr(p, c, f);
	p0 += stride*2; p1 += stride*2;
	for (auto p=p0; p<=p1; p++)
		if (*p == f)
			v.floodFillPtr(p, c, f);
}

void fillCircle(V, COLOR)(auto ref V v, int x, int y, int r, COLOR c)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	int x0 = x>r?x-r:0;
	int y0 = y>r?y-r:0;
	int x1 = min(x+r, v.w-1);
	int y1 = min(y+r, v.h-1);
	int rs = sqr(r);
	// TODO: optimize
	foreach (py; y0..y1+1)
		foreach (px; x0..x1+1)
			if (sqr(x-px) + sqr(y-py) < rs)
				v[px, py] = c;
}

void fillSector(V, COLOR)(auto ref V v, int x, int y, int r0, int r1, real a0, real a1, COLOR c)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	int x0 = x>r1?x-r1:0;
	int y0 = y>r1?y-r1:0;
	int x1 = min(x+r1, v.w-1);
	int y1 = min(y+r1, v.h-1);
	int r0s = sqr(r0);
	int r1s = sqr(r1);
	if (a0 > a1)
		a1 += (2 * PI);
	foreach (py; y0..y1+1)
		foreach (px; x0..x1+1)
		{
			int dx = px-x;
			int dy = py-y;
			int rs = sqr(dx) + sqr(dy);
			if (r0s <= rs && rs < r1s)
			{
				real a = atan2(cast(real)dy, cast(real)dx);
				if ((a0 <= a && a <= a1) ||
				    (a += (2 * PI),
				    (a0 <= a && a <= a1)))
					v[px, py] = c;
			}
		}
}

struct Coord { int x, y; string toString() { import std.string; return format("%s", [this.tupleof]); } }


/+
void fillPoly(V, COLOR)(auto ref V v, Coord[] coords, COLOR f)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	int minY, maxY;
	minY = maxY = coords[0].y;
	foreach (c; coords[1..$])
		minY = min(minY, c.y),
		maxY = max(maxY, c.y);

	foreach (y; minY..maxY+1)
	{
		int[] intersections;
		for (uint i=0; i<coords.length; i++)
		{
			auto c0=coords[i], c1=coords[i==$-1?0:i+1];
			if (y==c0.y)
			{
				assert(y == coords[i%$].y);
				int pi = i-1; int py;
				while ((py=coords[(pi+$)%$].y)==y)
					pi--;
				int ni = i+1; int ny;
				while ((ny=coords[ni%$].y)==y)
					ni++;
				if (ni > coords.length)
					continue;
				if ((py>y) == (y>ny))
					intersections ~= coords[i%$].x;
				i = ni-1;
			}
			else
			if (c0.y<y && y<c1.y)
				intersections ~= itpl(c0.x, c1.x, y, c0.y, c1.y);
			else
			if (c1.y<y && y<c0.y)
				intersections ~= itpl(c1.x, c0.x, y, c1.y, c0.y);
		}

		assert(intersections.length % 2==0);
		intersections.sort();
		for (uint i=0; i<intersections.length; i+=2)
			v.hline!true(intersections[i], intersections[i+1], y, f);
	}
}
+/

// No caps
void thickLine(V, COLOR)(auto ref V v, int x1, int y1, int x2, int y2, int r, COLOR c)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	int dx = x2-x1;
	int dy = y2-y1;
	int d  = cast(int)sqrt(cast(float)(sqr(dx)+sqr(dy)));
	if (d==0) return;

	int nx = dx*r/d;
	int ny = dy*r/d;

	fillPoly([
		Coord(x1-ny, y1+nx),
		Coord(x1+ny, y1-nx),
		Coord(x2+ny, y2-nx),
		Coord(x2-ny, y2+nx),
	], c);
}

// No caps
void thickLinePoly(V, COLOR)(auto ref V v, Coord[] coords, int r, COLOR c)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	foreach (i; 0..coords.length)
		thickLine(coords[i].tupleof, coords[(i+1)%$].tupleof, r, c);
}

// ************************************************************************************************************************************

mixin template FixMath(ubyte coordinateBitsParam = 16)
{
	enum coordinateBits = coordinateBitsParam;

	static assert(COLOR.homogenous, "Asymmetric color types not supported, fix me!");
	/// Fixed-point type, big enough to hold a coordinate, with fractionary precision corresponding to channel precision.
	alias fix  = SignedBitsType!(COLOR.channelBits   + coordinateBits);
	/// Type to hold temporary values for multiplication and division
	alias fix2 = SignedBitsType!(COLOR.channelBits*2 + coordinateBits);

	static assert(COLOR.channelBits < 32, "Shift operators are broken for shifts over 32 bits, fix me!");
	fix tofix(T:int  )(T x) { return cast(fix) (x<<COLOR.channelBits); }
	fix tofix(T:float)(T x) { return cast(fix) (x*(1<<COLOR.channelBits)); }
	T fixto(T:int)(fix x) { return cast(T)(x>>COLOR.channelBits); }

	fix fixsqr(fix x)        { return cast(fix)((cast(fix2)x*x) >> COLOR.channelBits); }
	fix fixmul(fix x, fix y) { return cast(fix)((cast(fix2)x*y) >> COLOR.channelBits); }
	fix fixdiv(fix x, fix y) { return cast(fix)((cast(fix2)x << COLOR.channelBits)/y); }

	static assert(COLOR.ChannelType.sizeof*8 == COLOR.channelBits, "COLORs with ChannelType not corresponding to native type not currently supported, fix me!");
	/// Type only large enough to hold a fractionary part of a "fix" (i.e. color channel precision). Used for alpha values, etc.
	alias COLOR.ChannelType frac;
	/// Type to hold temporary values for multiplication and division
	alias UnsignedBitsType!(COLOR.channelBits*2) frac2;

	frac tofrac(T:float)(T x) { return cast(frac) (x*(1<<COLOR.channelBits)); }
	frac fixfpart(fix x) { return cast(frac)x; }
	frac fracsqr(frac x        ) { return cast(frac)((cast(frac2)x*x) >> COLOR.channelBits); }
	frac fracmul(frac x, frac y) { return cast(frac)((cast(frac2)x*y) >> COLOR.channelBits); }

	frac tofracBounded(T:float)(T x) { return cast(frac) bound(tofix(x), 0, frac.max); }
}

// ************************************************************************************************************************************

void whiteNoise(V)(V v)
	if (isWritableView!V)
{
	import std.random;
	alias COLOR = ViewColor!V;

	for (int y=0;y<v.h/2;y++)
		for (int x=0;x<v.w/2;x++)
			v[x*2, y*2] = COLOR.monochrome(uniform!(COLOR.ChannelType)());

	// interpolate
	enum AVERAGE = q{(a+b)/2};

	for (int y=0;y<v.h/2;y++)
		for (int x=0;x<v.w/2-1;x++)
			v[x*2+1, y*2  ] = COLOR.op!AVERAGE(v[x*2  , y*2], v[x*2+2, y*2  ]);
	for (int y=0;y<v.h/2-1;y++)
		for (int x=0;x<v.w/2;x++)
			v[x*2  , y*2+1] = COLOR.op!AVERAGE(v[x*2  , y*2], v[x*2  , y*2+2]);
	for (int y=0;y<v.h/2-1;y++)
		for (int x=0;x<v.w/2-1;x++)
			v[x*2+1, y*2+1] = COLOR.op!AVERAGE(v[x*2+1, y*2], v[x*2+2, y*2+2]);
}

private template softRoundShape(bool RING)
{
	void softRoundShape(T, V, COLOR)(auto ref V v, T x, T y, T r0, T r1, T r2, COLOR color)
		if (isWritableView!V && isNumeric!T && is(COLOR : ViewColor!V))
	{
		mixin FixMath;

		assert(r0 <= r1);
		assert(r1 <= r2);
		assert(r2 < 256); // precision constraint - see SqrType
		//int ix = cast(int)x;
		//int iy = cast(int)y;
		//int ir1 = cast(int)sqr(r1-1);
		//int ir2 = cast(int)sqr(r2+1);
		int x1 = cast(int)(x-r2-1); if (x1<0) x1=0;
		int y1 = cast(int)(y-r2-1); if (y1<0) y1=0;
		int x2 = cast(int)(x+r2+1); if (x2>v.w) x2 = v.w;
		int y2 = cast(int)(y+r2+1); if (y2>v.h) y2 = v.h;

		static if (RING)
		auto r0s = r0*r0;
		auto r1s = r1*r1;
		auto r2s = r2*r2;
		//float rds = r2s - r1s;

		fix fx = tofix(x);
		fix fy = tofix(y);

		static if (RING)
		fix fr0s = tofix(r0s);
		fix fr1s = tofix(r1s);
		fix fr2s = tofix(r2s);

		static if (RING)
		fix fr10 = fr1s - fr0s;
		fix fr21 = fr2s - fr1s;

		for (int cy=y1;cy<y2;cy++)
		{
			auto row = v.scanline(cy);
			for (int cx=x1;cx<x2;cx++)
			{
				alias SignedBitsType!(2*(8 + COLOR.channelBits)) SqrType; // fit the square of radius expressed as fixed-point
				fix frs = cast(fix)((sqr(cast(SqrType)fx-tofix(cx)) + sqr(cast(SqrType)fy-tofix(cy))) >> COLOR.channelBits); // shift-right only once instead of once-per-sqr

				//static frac alphafunc(frac x) { return fracsqr(x); }
				static frac alphafunc(frac x) { return x; }

				static if (RING)
				{
					if (frs<fr0s)
						{}
					else
					if (frs<fr2s)
					{
						frac alpha;
						if (frs<fr1s)
							alpha =  alphafunc(cast(frac)fixdiv(frs-fr0s, fr10));
						else
							alpha = ~alphafunc(cast(frac)fixdiv(frs-fr1s, fr21));
						row[cx] = COLOR.op!q{.blend(a, b, c)}(color, row[cx], alpha);
					}
				}
				else
				{
					if (frs<fr1s)
						row[cx] = color;
					else
					if (frs<fr2s)
					{
						frac alpha = ~alphafunc(cast(frac)fixdiv(frs-fr1s, fr21));
						row[cx] = COLOR.op!q{.blend(a, b, c)}(color, row[cx], alpha);
					}
				}
			}
		}
	}
}

void softRing(T, V, COLOR)(auto ref V v, T x, T y, T r0, T r1, T r2, COLOR color)
	if (isWritableView!V && isNumeric!T && is(COLOR : ViewColor!V))
{
	v.softRoundShape!true(x, y, r0, r1, r2, color);
}

void softCircle(T, V, COLOR)(auto ref V v, T x, T y, T r1, T r2, COLOR color)
	if (isWritableView!V && isNumeric!T && is(COLOR : ViewColor!V))
{
	v.softRoundShape!false(x, y, cast(T)0, r1, r2, color);
}

template aaPutPixel(bool CHECKED=true, bool USE_ALPHA=true)
{
	void aaPutPixel(F:float, V, COLOR, frac)(auto ref V v, F x, F y, COLOR color, frac alpha)
		if (isWritableView!V && is(COLOR : ViewColor!V))
	{
		mixin FixMath;

		void plot(bool CHECKED2)(int x, int y, frac f)
		{
			static if (CHECKED2)
				if (x<0 || x>=v.w || y<0 || y>=v.h)
					return;

			COLOR* p = v.pixelPtr(x, y);
			static if (USE_ALPHA) f = fracmul(f, cast(frac)alpha);
			*p = COLOR.op!q{.blend(a, b, c)}(color, *p, f);
		}

		fix fx = tofix(x);
		fix fy = tofix(y);
		int ix = fixto!int(fx);
		int iy = fixto!int(fy);
		static if (CHECKED)
			if (ix>=0 && iy>=0 && ix+1<v.w && iy+1<v.h)
			{
				plot!false(ix  , iy  , fracmul(~fixfpart(fx), ~fixfpart(fy)));
				plot!false(ix  , iy+1, fracmul(~fixfpart(fx),  fixfpart(fy)));
				plot!false(ix+1, iy  , fracmul( fixfpart(fx), ~fixfpart(fy)));
				plot!false(ix+1, iy+1, fracmul( fixfpart(fx),  fixfpart(fy)));
				return;
			}
		plot!CHECKED(ix  , iy  , fracmul(~fixfpart(fx), ~fixfpart(fy)));
		plot!CHECKED(ix  , iy+1, fracmul(~fixfpart(fx),  fixfpart(fy)));
		plot!CHECKED(ix+1, iy  , fracmul( fixfpart(fx), ~fixfpart(fy)));
		plot!CHECKED(ix+1, iy+1, fracmul( fixfpart(fx),  fixfpart(fy)));
	}
}

void aaPutPixel(bool CHECKED=true, F:float, V, COLOR)(auto ref V v, F x, F y, COLOR color)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	//aaPutPixel!(false, F)(x, y, color, 0); // doesn't work, wtf
	alias aaPutPixel!(CHECKED, false) f;
	f(v, x, y, color, 0);
}

void hline(bool CHECKED=true, V, COLOR, frac)(auto ref V v, int x1, int x2, int y, COLOR color, frac alpha)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	mixin(CheckHLine);

	if (alpha==0)
		return;
	else
	if (alpha==frac.max)
		v.scanline(y)[x1..x2] = color;
	else
		foreach (ref p; v.scanline(y)[x1..x2])
			p = COLOR.op!q{.blend(a, b, c)}(color, p, alpha);
}

void vline(bool CHECKED=true, V, COLOR, frac)(auto ref V v, int x, int y1, int y2, COLOR color, frac alpha)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	mixin(CheckVLine);

	if (alpha==0)
		return;
	else
	if (alpha==frac.max)
		foreach (y; y1..y2)
			v[x, y] = color;
	else
		foreach (y; y1..y2)
		{
			auto p = v.pixelPtr(x, y);
			*p = COLOR.op!q{.blend(a, b, c)}(color, *p, alpha);
		}
}

void aaFillRect(bool CHECKED=true, F:float, V, COLOR)(auto ref V v, F x1, F y1, F x2, F y2, COLOR color)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	mixin FixMath;

	sort2(x1, x2);
	sort2(y1, y2);
	fix x1f = tofix(x1); int x1i = fixto!int(x1f);
	fix y1f = tofix(y1); int y1i = fixto!int(y1f);
	fix x2f = tofix(x2); int x2i = fixto!int(x2f);
	fix y2f = tofix(y2); int y2i = fixto!int(y2f);

	v.vline!CHECKED(x1i, y1i+1, y2i, color, ~fixfpart(x1f));
	v.vline!CHECKED(x2i, y1i+1, y2i, color,  fixfpart(x2f));
	v.hline!CHECKED(x1i+1, x2i, y1i, color, ~fixfpart(y1f));
	v.hline!CHECKED(x1i+1, x2i, y2i, color,  fixfpart(y2f));
	v.aaPutPixel!CHECKED(x1i, y1i, color, fracmul(~fixfpart(x1f), ~fixfpart(y1f)));
	v.aaPutPixel!CHECKED(x1i, y2i, color, fracmul(~fixfpart(x1f),  fixfpart(y2f)));
	v.aaPutPixel!CHECKED(x2i, y1i, color, fracmul( fixfpart(x2f), ~fixfpart(y1f)));
	v.aaPutPixel!CHECKED(x2i, y2i, color, fracmul( fixfpart(x2f),  fixfpart(y2f)));

	v.fillRect!CHECKED(x1i+1, y1i+1, x2i, y2i, color);
}

void aaLine(bool CHECKED=true, V, COLOR)(auto ref V v, float x1, float y1, float x2, float y2, COLOR color)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	// Simplistic straight-forward implementation. TODO: optimize
	if (abs(x1-x2) > abs(y1-y2))
		for (auto x=x1; sign(x1-x2)!=sign(x2-x); x += sign(x2-x1))
			v.aaPutPixel!CHECKED(x, itpl(y1, y2, x, x1, x2), color);
	else
		for (auto y=y1; sign(y1-y2)!=sign(y2-y); y += sign(y2-y1))
			v.aaPutPixel!CHECKED(itpl(x1, x2, y, y1, y2), y, color);
}

void aaLine(bool CHECKED=true, V, COLOR, frac)(auto ref V v, float x1, float y1, float x2, float y2, COLOR color, frac alpha)
	if (isWritableView!V && is(COLOR : ViewColor!V))
{
	// ditto
	if (abs(x1-x2) > abs(y1-y2))
		for (auto x=x1; sign(x1-x2)!=sign(x2-x); x += sign(x2-x1))
			v.aaPutPixel!CHECKED(x, itpl(y1, y2, x, x1, x2), color, alpha);
	else
		for (auto y=y1; sign(y1-y2)!=sign(y2-y); y += sign(y2-y1))
			v.aaPutPixel!CHECKED(itpl(x1, x2, y, y1, y2), y, color, alpha);
}

unittest
{
	// Test instantiation
	import dplug.graphics.color;
    ImageRef!RGB i;
    i.w = 100;
    i.h = 100;
    i.pitch = 100;
    i.pixels = (new RGB[100 * 100]).ptr;
	
	auto c = RGB(1, 2, 3);
	i.whiteNoise();
	i.aaLine(10, 10, 20, 20, c);
	i.aaLine(10f, 10f, 20f, 20f, c, 100);
	i.rect(10, 10, 20, 20, c);
	i.fillRect(10, 10, 20, 20, c);
	i.aaFillRect(10, 10, 20, 20, c);
	i.vline(10, 10, 20, c);
	i.vline(10, 10, 20, c);
//	i.line(10, 10, 20, 20, c);
	i.fillCircle(10, 10, 10, c);
	i.fillSector(10, 10, 10, 10, 0.0, (2 * PI), c);
	i.softRing(50, 50, 10, 15, 20, c);
	i.softCircle(50, 50, 10, 15, c);
//	i.fillPoly([Coord(10, 10), Coord(10, 20), Coord(20, 20)], c);
	i.uncheckedFloodFill(15, 15, RGB(4, 5, 6));
}

