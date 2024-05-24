/**
Drawing functions. Port of ae.utils.graphics.
In many many cases, you should use dplug:canvas instead.

License:
    This Source Code Form is subject to the terms of
    the Mozilla Public License, v. 2.0. If a copy of
    the MPL was not distributed with this file, You
    can obtain one at http://mozilla.org/MPL/2.0/.
 
 Copyright: Vladimir Panteleev <vladimir@thecybershadow.net>
 Copyright: Guillaume Piolat <contact@auburnsounds.com>
 */

module dplug.graphics.draw;

import core.stdc.math: floorf, ceilf;

import std.math;

import dplug.math.box;

import dplug.core.nogc;
import dplug.core.vec;
import dplug.graphics.image;


nothrow:
@nogc:

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

void fillAll(V, COLOR)(auto ref V v, COLOR c)
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
    foreach (y; y1..y2) // FUTURE: optimize
        v[x, y] = c;
}

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
    int x0 = x > r ? x-r : 0;
    int y0 = y > r ? y-r : 0;
    int x1 = x+r;
    if (x1 > v.w-1)
        x1 = v.w-1;
    int y1 = y+r;
    if (y1 > v.h-1)
        y1 = v.h-1;
    int rs = sqr(r);
    // FUTURE: optimize
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
    int x1 = x+r1;
    if (x1 > v.w-1)
        x1 = v.w-1;
    int y1 = y+r1;
    if (y1 > v.h-1)
        y1 = v.h-1;


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
                if (a0 <= a && a <= a1)
                    v[px, py] = c;
                else
                {
                    a += 2 * PI;
                    if (a0 <= a && a <= a1)
                        v[px, py] = c;
                }
            }
        }
}

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

private template softRoundShape(bool RING)
{
    void softRoundShape(V, COLOR)(auto ref V v, float x, float y, float r0, float r1, float r2, COLOR color)
        if (isWritableView!V && is(COLOR : ViewColor!V))
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
                            alpha = cast(ubyte)(~cast(int)alphafunc(cast(frac)fixdiv(frs-fr1s, fr21)));
                        row[cx] = blendColor(color, row[cx], alpha);
                    }
                }
                else
                {
                    if (frs<fr1s)
                        row[cx] = color;
                    else
                    if (frs<fr2s)
                    {
                        frac alpha = cast(ubyte)(~cast(int)alphafunc(cast(frac)fixdiv(frs-fr1s, fr21)));
                        row[cx] = blendColor(color, row[cx], alpha);
                    }
                }
            }
        }
    }
}

void softRing(V, COLOR)(auto ref V v, float x, float y, float r0, float r1, float r2, COLOR color)
    if (isWritableView!V && is(COLOR : ViewColor!V))
{
    v.softRoundShape!true(x, y, r0, r1, r2, color);
}

void softCircle(V, COLOR)(auto ref V v, float x, float y, float r1, float r2, COLOR color)
    if (isWritableView!V && is(COLOR : ViewColor!V))
{
    v.softRoundShape!false(x, y, 0, r1, r2, color);
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
            *p = blendColor(color, *p, f);
        }

        fix fx = tofix(x);
        fix fy = tofix(y);
        int ix = fixto!int(fx);
        int iy = fixto!int(fy);
        static if (CHECKED)
            if (ix>=0 && iy>=0 && ix+1<v.w && iy+1<v.h)
            {
                plot!false(ix  , iy  , fracmul(cast(ubyte)(~cast(int)fixfpart(fx)), cast(ubyte)(~cast(int)fixfpart(fy))));
                plot!false(ix  , iy+1, fracmul(cast(ubyte)(~cast(int)fixfpart(fx)),  fixfpart(fy)));
                plot!false(ix+1, iy  , fracmul( fixfpart(fx), cast(ubyte)(~cast(int)fixfpart(fy))));
                plot!false(ix+1, iy+1, fracmul( fixfpart(fx),  fixfpart(fy)));
                return;
            }
        plot!CHECKED(ix  , iy  , fracmul(cast(ubyte)(~cast(int)fixfpart(fx)), cast(ubyte)(~cast(int)fixfpart(fy))));
        plot!CHECKED(ix  , iy+1, fracmul(cast(ubyte)(~cast(int)fixfpart(fx)),  fixfpart(fy)));
        plot!CHECKED(ix+1, iy  , fracmul( fixfpart(fx), cast(ubyte)(~cast(int)fixfpart(fy))));
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
            p = blendColor(color, p, alpha);
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
            *p = blendColor(color, *p, alpha);
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

    v.vline!CHECKED(x1i, y1i+1, y2i, color, cast(ubyte)(~cast(int)fixfpart(x1f)));
    v.vline!CHECKED(x2i, y1i+1, y2i, color,  fixfpart(x2f));
    v.hline!CHECKED(x1i+1, x2i, y1i, color, cast(ubyte)(~cast(int)fixfpart(y1f)));
    v.hline!CHECKED(x1i+1, x2i, y2i, color,  fixfpart(y2f));
    v.aaPutPixel!CHECKED(x1i, y1i, color, fracmul(cast(ubyte)(~cast(int)fixfpart(x1f)) ,
                                                  cast(ubyte)(~cast(int)fixfpart(y1f))) );
    v.aaPutPixel!CHECKED(x1i, y2i, color, fracmul(cast(ubyte)(~cast(int)fixfpart(x1f)) ,  fixfpart(y2f)));
    v.aaPutPixel!CHECKED(x2i, y1i, color, fracmul( fixfpart(x2f), cast(ubyte)(~cast(int)fixfpart(y1f))) );
    v.aaPutPixel!CHECKED(x2i, y2i, color, fracmul( fixfpart(x2f),  fixfpart(y2f)));

    v.fillRect!CHECKED(x1i+1, y1i+1, x2i, y2i, color);
}

unittest
{
    // Test instantiation    
    ImageRef!RGB i;
    i.w = 100;
    i.h = 100;
    i.pitch = 100;
    RGB[] rgb;
    rgb.reallocBuffer(100*100);
    scope(exit) rgb.reallocBuffer(0);
    i.pixels = rgb.ptr;

    auto c = RGB(1, 2, 3);
    i.rect(10, 10, 20, 20, c);
    i.fillRect(10, 10, 20, 20, c);
    i.aaFillRect(10, 10, 20, 20, c);
    i.vline(10, 10, 20, c);
    i.vline(10, 10, 20, c);
    i.fillCircle(10, 10, 10, c);
    i.fillSector(10, 10, 10, 10, 0.0, (2 * PI), c);
    i.softRing(50, 50, 10, 15, 20, c);
    i.softCircle(50, 50, 10, 15, c);
    i.uncheckedFloodFill(15, 15, RGB(4, 5, 6));
}



/// Rough anti-aliased fillsector
void aaFillSector(V, COLOR)(auto ref V v, float x, float y, float r0, float r1, float a0, float a1, COLOR c)
    if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;

    if (a0 == a1)
        return;

    int x0 = cast(int)floorf(x - r1 - 1);
    int x1 = cast(int)ceilf(x + r1 + 1);

    int y0 = cast(int)floorf(y - r1 - 1);
    int y1 = cast(int)ceilf(y + r1 + 1);

    float r0s = r0-1;
    if (r0s < 0) r0s = 0;
    r0s = r0s * r0s;
    float r1s = (r1 + 1) * (r1 + 1);

    if (a0 > a1)
        a1 += 2 * PI;

    if (a0 < -PI || a1 < -PI)
    {
        // else atan2 will never produce angles below PI
        a0 += 2 * PI;
        a1 += 2 * PI;
    }

    int xmin = x0;
    int xmax = x1+1;
    int ymin = y0;
    int ymax = y1+1;

    // avoids to draw out of bounds
    if (xmin < 0)
        xmin = 0;
    if (ymin < 0)
        ymin = 0;
    if (xmax > v.w)
        xmax = v.w;
    if (ymax > v.h)
        ymax = v.h;

    foreach (py; ymin .. ymax)
    {
        foreach (px; xmin .. xmax)
        {
            float dx = px-x;
            float dy = py-y;
            float rsq = dx * dx + dy * dy;

            if(r0s <= rsq && rsq <= r1s)
            {
                float rs = sqrt(rsq);

                // How much angle is one pixel at this radius?
                // It's actually rule of 3.
                // 2*pi radians => 2*pi*radius pixels
                // ???          => 1 pixel
                float aTransition = 1.0f / rs;


                if (r0 <= rs && rs < r1)
                {
                    float alpha = 1.0f;
                    if (r0 + 1 > rs)
                        alpha = rs - r0;
                    if (rs + 1 > r1)
                        alpha = r1 - rs;

                    float a = atan2(dy, dx);
                    bool inSector = (a0 <= a && a <= a1);
                    if (inSector)
                    {
                        float alpha2 = alpha;
                        if (a0 + aTransition > a)
                            alpha2 *= (a-a0) / aTransition;
                        else if (a + aTransition > a1)
                            alpha2 *= (a1 - a)/aTransition;

                        auto p = v.pixelPtr(px, py);
                        *p = blendColor(c, *p, cast(ChannelType)(0.5f + alpha2 * ChannelType.max));
                    }
                    else
                    {
                        a += 2 * PI;
                        bool inSector2 = (a0 <= a && a <= a1);
                        if(inSector2 )
                        {
                            float alpha2 = alpha;
                            if (a0 + aTransition > a)
                                alpha2 *= (a-a0) / aTransition;
                            else if (a + aTransition > a1)
                                alpha2 *= (a1 - a)/aTransition;

                            auto p = v.pixelPtr(px, py);
                            *p = blendColor(c, *p, cast(ChannelType)(0.5f + alpha2 * ChannelType.max));
                        }
                    }
                }
            }
        }
    }
}

/**
    Fill rectangle while interpolating a `COLOR` (can be depth) horiontally.
    Params:
         v     The surface to write to. That be clipped by a dirtyRect.
         rect  The bounds of the slopped plane. The drawing itself will be 
               clipped to its limit, and the limits of the surface.
               Should NOT be clipped by the dirtyRect.
         c0    Color at left edge.
         c1    Color at right edge.
*/
void horizontalSlope(float curvature = 1.0f, V, COLOR)(auto ref V v, 
                                                       box2i rect, 
                                                       COLOR c0, 
                                                       COLOR c1)
    if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias Type = COLOR.ChannelType;

    box2i inter = box2i(0, 0, v.w, v.h).intersection(rect);

    int x0 = rect.min.x;
    int x1 = rect.max.x;
    immutable float invX1mX0 = 1.0f / (x1 - x0);

    foreach (px; inter.min.x .. inter.max.x)
    {
        float fAlpha =  (px - x0) * invX1mX0;
        static if (curvature != 1.0f)
            fAlpha = fAlpha ^^ curvature;
        Type alpha = cast(Type)( 0.5f + Type.max * fAlpha );
        COLOR c = blendColor(c1, c0, alpha);
        vline(v, px, inter.min.y, inter.max.y, c);
    }
}

/** 
    Fill rectangle while interpolating a `COLOR` (can be depth) vertically.

    Params:
         v     The surface to write to. That be clipped by a dirtyRect.
         rect  The bounds of the slopped plane. The drawing itself will be 
               clipped to its limit, and the limits of the surface.
               Should NOT be clipped by the dirtyRect.
         c0    Color at top edge.
         c1    Color at bottom edge.
*/
void verticalSlope(float curvature = 1.0f, V, COLOR)(auto ref V v, box2i rect, COLOR c0, COLOR c1)
    if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias Type = COLOR.ChannelType;

    box2i inter = box2i(0, 0, v.w, v.h).intersection(rect);

    int x0 = rect.min.x;
    int y0 = rect.min.y;
    int x1 = rect.max.x;
    int y1 = rect.max.y;

    immutable float invY1mY0 = 1.0f / (y1 - y0);

    foreach (py; inter.min.y .. inter.max.y)
    {
        float fAlpha =  (py - y0) * invY1mY0;
        static if (curvature != 1.0f)
            fAlpha = fAlpha ^^ curvature;
        Type alpha = cast(Type)( 0.5f + Type.max * fAlpha );
        COLOR c = blendColor(c1, c0, alpha);
        hline(v, inter.min.x, inter.max.x, py, c);
    }
}


void aaSoftDisc(float curvature = 1.0f, V, COLOR)(auto ref V v, float x, float y, float r1, float r2, COLOR color, float globalAlpha = 1.0f)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;
    assert(r1 <= r2);
    int x1 = cast(int)(x-r2-1); if (x1<0) x1=0;
    int y1 = cast(int)(y-r2-1); if (y1<0) y1=0;
    int x2 = cast(int)(x+r2+1); if (x2>v.w) x2 = v.w;
    int y2 = cast(int)(y+r2+1); if (y2>v.h) y2 = v.h;

    auto r1s = r1*r1;
    auto r2s = r2*r2;

    float fx = x;
    float fy = y;

    immutable float fr1s = r1s;
    immutable float fr2s = r2s;

    immutable float fr21 = fr2s - fr1s;
    immutable float invfr21 = 1 / fr21;

    for (int cy=y1;cy<y2;cy++)
    {
        auto row = v.scanline(cy);
        for (int cx=x1;cx<x2;cx++)
        {
            float dx =  (fx - cx);
            float dy =  (fy - cy);
            float frs = dx*dx + dy*dy;

            if (frs<fr1s)
                row[cx] = blendColor(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * globalAlpha));
            else
            {
                if (frs<fr2s)
                {
                    float alpha = (frs-fr1s) * invfr21;
                    static if (curvature != 1.0f)
                        alpha = alpha ^^ curvature;
                    row[cx] = blendColor(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * (1-alpha) * globalAlpha));
                }
            }
        }
    }
}

void aaSoftEllipse(float curvature = 1.0f, V, COLOR)(auto ref V v, float x, float y, float r1, float r2, float scaleX, float scaleY, COLOR color, float globalAlpha = 1.0f)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;
    assert(r1 <= r2);
    int x1 = cast(int)(x-r2*scaleX-1); if (x1<0) x1=0;
    int y1 = cast(int)(y-r2*scaleY-1); if (y1<0) y1=0;
    int x2 = cast(int)(x+r2*scaleX+1); if (x2>v.w) x2 = v.w;
    int y2 = cast(int)(y+r2*scaleY+1); if (y2>v.h) y2 = v.h;

    float invScaleX = 1 / scaleX;
    float invScaleY = 1 / scaleY;

    auto r1s = r1*r1;
    auto r2s = r2*r2;

    float fx = x;
    float fy = y;

    immutable float fr1s = r1s;
    immutable float fr2s = r2s;

    immutable float fr21 = fr2s - fr1s;
    immutable float invfr21 = 1 / fr21;

    for (int cy=y1;cy<y2;cy++)
    {
        auto row = v.scanline(cy);
        for (int cx=x1;cx<x2;cx++)
        {
            float dx =  (fx - cx) * invScaleX;
            float dy =  (fy - cy) * invScaleY;
            float frs = dx*dx + dy*dy;

            if (frs<fr1s)
                row[cx] = blendColor(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * globalAlpha));
            else
            {
                if (frs<fr2s)
                {
                    float alpha = (frs-fr1s) * invfr21;
                    static if (curvature != 1.0f)
                        alpha = alpha ^^ curvature;
                    row[cx] = blendColor(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * (1-alpha) * globalAlpha));
                }
            }
        }
    }
}

/// Draw a circle gradually fading in between r1 and r2 and fading out between r2 and r3
void aaSoftCircle(float curvature = 1.0f, V, COLOR)(auto ref V v, float x, float y, float r1, float r2, float r3, COLOR color, float globalAlpha = 1.0f)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;
    assert(r1 <= r2);
    assert(r2 <= r3);
    int x1 = cast(int)(x-r3-1); if (x1<0) x1=0;
    int y1 = cast(int)(y-r3-1); if (y1<0) y1=0;
    int x2 = cast(int)(x+r3+1); if (x2>v.w) x2 = v.w;
    int y2 = cast(int)(y+r3+1); if (y2>v.h) y2 = v.h;

    auto r1s = r1*r1;
    auto r2s = r2*r2;
    auto r3s = r3*r3;

    float fx = x;
    float fy = y;

    immutable float fr1s = r1s;
    immutable float fr2s = r2s;
    immutable float fr3s = r3s;

    immutable float fr21 = fr2s - fr1s;
    immutable float fr32 = fr3s - fr2s;
    immutable float invfr21 = 1 / fr21;
    immutable float invfr32 = 1 / fr32;

    for (int cy=y1;cy<y2;cy++)
    {
        auto row = v.scanline(cy);
        for (int cx=x1;cx<x2;cx++)
        {
            float frs = (fx - cx)*(fx - cx) + (fy - cy)*(fy - cy);

            if (frs >= fr1s)
            {
                if (frs < fr3s)
                {
                    float alpha = void;
                    if (frs >= fr2s)
                        alpha = (frs - fr2s) * invfr32;
                    else
                        alpha = 1 - (frs - fr1s) * invfr21;

                    static if (curvature != 1.0f)
                        alpha = alpha ^^ curvature;
                    row[cx] = blendColor(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * (1-alpha) * globalAlpha));
                }
            }
        }
    }
}


void aaFillRectFloat(bool CHECKED=true, V, COLOR)(auto ref V v, float x1, float y1, float x2, float y2, COLOR color, float globalAlpha = 1.0f)
    if (isWritableView!V && is(COLOR : ViewColor!V))
{
    if (globalAlpha == 0)
        return;

    alias ChannelType = COLOR.ChannelType;

    sort2(x1, x2);
    sort2(y1, y2);

    int ix1 = cast(int)(floorf(x1));
    int iy1 = cast(int)(floorf(y1));
    int ix2 = cast(int)(floorf(x2));
    int iy2 = cast(int)(floorf(y2));
    float fx1 = x1 - ix1;
    float fy1 = y1 - iy1;
    float fx2 = x2 - ix2;
    float fy2 = y2 - iy2;

    static ChannelType toAlpha(float fraction) pure nothrow @nogc
    {
        return cast(ChannelType)(cast(int)(0.5f + ChannelType.max * fraction));
    }

    v.aaPutPixelFloat!CHECKED(ix1, iy1, color, toAlpha(globalAlpha * (1-fx1) * (1-fy1) ));
    v.hline!CHECKED(ix1+1, ix2, iy1, color, toAlpha(globalAlpha * (1 - fy1) ));
    v.aaPutPixelFloat!CHECKED(ix2, iy1, color, toAlpha(globalAlpha * fx2 * (1-fy1) ));

    v.vline!CHECKED(ix1, iy1+1, iy2, color, toAlpha(globalAlpha * (1 - fx1)));
    v.vline!CHECKED(ix2, iy1+1, iy2, color, toAlpha(globalAlpha * fx2));

    v.aaPutPixelFloat!CHECKED(ix1, iy2, color, toAlpha(globalAlpha * (1-fx1) * fy2 ));
    v.hline!CHECKED(ix1+1, ix2, iy2, color,  toAlpha(globalAlpha * fy2));
    v.aaPutPixelFloat!CHECKED(ix2, iy2, color, toAlpha(globalAlpha * fx2 * fy2 ));

    v.fillRectFloat!CHECKED(ix1+1, iy1+1, ix2, iy2, color, globalAlpha);
}

void fillRectFloat(bool CHECKED=true, V, COLOR)(auto ref V v, int x1, int y1, int x2, int y2, COLOR b, float globalAlpha = 1.0f) // [)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
    if (globalAlpha == 0)
        return;

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

    if (globalAlpha == 1)
    {
        foreach (y; y1..y2)
            v.scanline(y)[x1..x2] = b;
    }
    else
    {
        alias ChannelType = COLOR.ChannelType;
        static ChannelType toAlpha(float fraction) pure nothrow @nogc
        {
            return cast(ChannelType)(cast(int)(0.5f + ChannelType.max * fraction));
        }

        ChannelType alpha = toAlpha(globalAlpha);

        foreach (y; y1..y2)
        {
            COLOR[] scan = v.scanline(y);
            foreach (x; x1..x2)
            {
                scan[x] = blendColor(b, scan[x], alpha);
            }
        }
    }
}

void aaPutPixelFloat(bool CHECKED=true, V, COLOR, A)(auto ref V v, int x, int y, COLOR color, A alpha)
    if (is(COLOR.ChannelType == A))
{
    static if (CHECKED)
        if (x<0 || x>=v.w || y<0 || y>=v.h)
            return;

    COLOR* p = v.pixelPtr(x, y);
    *p = blendColor(color, *p, alpha);
}


/// Blits a view onto another.
/// The views must have the same size.
/// PERF: optimize that
void blendWithAlpha(SRC, DST)(auto ref SRC srcView, auto ref DST dstView, auto ref ImageRef!L8 alphaView)
{
    static assert(isDirectView!SRC);
    static assert(isDirectView!DST);
    static assert(isWritableView!DST);

    static ubyte blendByte(ubyte a, ubyte b, ubyte f) nothrow @nogc
    {
        int sum = ( f * a + b * (cast(ubyte)(~cast(int)f)) ) + 127;
        return cast(ubyte)(sum / 255 );// ((sum+1)*257) >> 16 ); // integer divide by 255
    }

    static ushort blendShort(ushort a, ushort b, ubyte f) nothrow @nogc
    {
        ushort ff = (f << 8) | f;
        int sum = ( ff * a + b * (cast(ushort)(~cast(int)ff)) ) + 32768;
        return cast(ushort)( sum >> 16 ); // MAYDO: this doesn't map to the full range
    }

    alias COLOR = ViewColor!DST;
    assert(srcView.w == dstView.w && srcView.h == dstView.h, "View size mismatch");

    foreach (y; 0..srcView.h)
    {
        COLOR* srcScan = srcView.scanline(y).ptr;
        COLOR* dstScan = dstView.scanline(y).ptr;
        L8* alphaScan = alphaView.scanline(y).ptr;

        foreach (x; 0..srcView.w)
        {
            ubyte alpha = alphaScan[x].l;
            if (alpha == 0)
                continue;
            static if (is(COLOR == RGBA))
            {
                dstScan[x] = blendColor(srcScan[x], dstScan[x], alpha);
            }
            else static if (is(COLOR == L16))
                dstScan[x].l = blendShort(srcScan[x].l, dstScan[x].l, alpha);
            else
                static assert(false);
        }
    }
}

