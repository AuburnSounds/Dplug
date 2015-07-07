/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.drawex;

// Extends ae.graphics.utils
// Additional graphics primitives

import std.algorithm;
import std.math;
import std.traits;

import gfm.math;
import ae.utils.graphics;


/// Crop a view from a box2i
auto crop(V)(auto ref V src, box2i b) if (isView!V)
{
    return ae.utils.graphics.view.crop(src, b.min.x, b.min.y, b.max.x, b.max.y);
}

/// Crop an ImageRef and get an ImageRef instead of a Voldemort type.
/// This also avoid adding offset to coordinates.
ImageRef!COLOR cropImageRef(COLOR)(ImageRef!COLOR src, box2i rect)
{
    ImageRef!COLOR result;
    result.w = rect.width;
    result.h = rect.height;
    result.pitch = src.pitch;
    COLOR[] scan = src.scanline(rect.min.y);
    result.pixels = &scan[rect.min.x];
    return result;
}

/// Rough anti-aliased fillsector
void aaFillSector(V, COLOR)(auto ref V v, float x, float y, float r0, float r1, float a0, float a1, COLOR c)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;

    int x0 = cast(int)floor(x - r1 - 1);
    int x1 = cast(int)ceil(x + r1 + 1);

    int y0 = cast(int)floor(y - r1 - 1);
    int y1 = cast(int)ceil(y + r1 + 1);

    float r0s = std.algorithm.max(0, r0 - 1) ^^ 2;
    float r1s = (r1 + 1) * (r1 + 1);


    if (a0 > a1)
        a1 += TAU;

    foreach (py; y0..y1+1)
    {
        foreach (px; x0..x1+1)
        {
            float dx = px-x;
            float dy = py-y;
            float rsq = dx * dx + dy * dy;

            if(r0s <= rsq && rsq <= r1s)
            {
                float rs = sqrt(rsq);
                if (r0 <= rs && rs < r1)
                {
                    float alpha = 1.0f;
                    if (r0 + 1 > rs)
                        alpha = rs - r0;
                    if (rs + 1 > r1)
                        alpha = r1 - rs;                

                    float a = atan2(dy, dx);
                    bool inSector = (a0 <= a && a <= a1);
                    a += TAU;
                    bool inSector2 = (a0 <= a && a <= a1);
                    if( inSector || inSector2 )
                    {
                        auto p = v.pixelPtr(px, py);
                        *p = COLOR.op!q{.blend(a, b, c)}(c, *p, cast(ChannelType)(0.5f + alpha * ChannelType.max));
                    }
                }
            }
        }
    }
}

/// Fill rectangle while interpolating a color horiontally
void horizontalSlope(V, COLOR)(auto ref V v, box2i rect, COLOR c0, COLOR c1)
    if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;
    int x0 = rect.min.x;
    int y0 = rect.min.y;
    int x1 = rect.max.x;
    int y1 = rect.max.y;
    foreach (px; x0..x1)
    { 
        ubyte alpha = cast(ChannelType)( 0.5f + ChannelType.max * (px - x0) / cast(float)(x1 - x0) );  // Not being generic here
        COLOR c = COLOR.op!q{.blend(a, b, c)}(c1, c0, alpha); // warning .blend is confusing, c1 comes first
        vline(v, px, y0, y1, c);
    }
}

void verticalSlope(V, COLOR)(auto ref V v, box2i rect, COLOR c0, COLOR c1)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;
    int x0 = rect.min.x;
    int y0 = rect.min.y;
    int x1 = rect.max.x;
    int y1 = rect.max.y;
    foreach (py; y0..y1)
    { 
        ChannelType alpha = cast(ChannelType)( 0.5f + ChannelType.max * (py - y0) / cast(float)(y1 - y0) );  // Not being generic here
        COLOR c = COLOR.op!q{.blend(a, b, c)}(c1, c0, alpha); // warning .blend is confusing, c1 comes first
        hline(v, x0, x1, py, c);
    }
}

// Rewritten because of weird codegen bugs
void softCircleFloat(float curvature = 1.0f, T, V, COLOR)(auto ref V v, T x, T y, T r1, T r2, COLOR color)
if (isWritableView!V && isNumeric!T && is(COLOR : ViewColor!V))
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

    float fr1s = r1s;
    float fr2s = r2s;

    float fr21 = fr2s - fr1s;

    for (int cy=y1;cy<y2;cy++)
    {
        auto row = v.scanline(cy);
        for (int cx=x1;cx<x2;cx++)
        {
            float frs = (fx - cx)*(fx - cx) + (fy - cy)*(fy - cy);

            if (frs<fr1s)
                row[cx] = color;
            else
            {
                if (frs<fr2s)
                {
                    float alpha = (frs-fr1s) / fr21;
                    static if (curvature != 1.0f)
                        alpha = alpha ^^ curvature;
                    row[cx] = COLOR.op!q{.blend(a, b, c)}(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * (1-alpha)));
                }
            }
        }
    }
}

void aaFillRectFloat(bool CHECKED=true, V, COLOR)(auto ref V v, float x1, float y1, float x2, float y2, COLOR color) 
    if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;
    import ae.utils.math;
    sort2(x1, x2);
    sort2(y1, y2);

    int ix1 = cast(int)(floor(x1));
    int iy1 = cast(int)(floor(y1));
    int ix2 = cast(int)(floor(x2));
    int iy2 = cast(int)(floor(y2));
    float fx1 = x1 - ix1;
    float fy1 = y1 - iy1;
    float fx2 = x2 - ix2;
    float fy2 = y2 - iy2;

    static ChannelType toAlpha(float fraction) pure nothrow @nogc
    {
        return cast(ChannelType)(cast(int)(0.5f + ChannelType.max * fraction));
    }

    v.aaPutPixelFloat!CHECKED(ix1, iy1, color, toAlpha( (1-fx1) * (1-fy1) ));
    v.hline!CHECKED(ix1+1, ix2, iy1, color, toAlpha(1 - fy1));
    v.aaPutPixelFloat!CHECKED(ix2, iy1, color, toAlpha( fx2 * (1-fy1) ));

    v.vline!CHECKED(ix1, iy1+1, iy2, color, toAlpha(1 - fx1));
    v.vline!CHECKED(ix2, iy1+1, iy2, color, toAlpha(fx2));

    v.aaPutPixelFloat!CHECKED(ix1, iy2, color, toAlpha( (1-fx1) * fy2 ));
    v.hline!CHECKED(ix1+1, ix2, iy2, color,  toAlpha(fy2));
    v.aaPutPixelFloat!CHECKED(ix2, iy2, color, toAlpha( fx2 * fy2 ));

    v.fillRect!CHECKED(ix1+1, iy1+1, ix2, iy2, color);
}

/*template aaPutPixelFloat()
{*/
    void aaPutPixelFloat(bool CHECKED=true, V, COLOR, A)(auto ref V v, int x, int y, COLOR color, A alpha)
        if (is(COLOR.ChannelType == A))
    {
        static if (CHECKED)
            if (x<0 || x>=v.w || y<0 || y>=v.h)
                return;

        COLOR* p = v.pixelPtr(x, y);
        *p = COLOR.op!q{.blend(a, b, c)}(color, *p, alpha);
    }
//}