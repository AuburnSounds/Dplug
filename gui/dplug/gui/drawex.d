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
    RGBA[] scan = src.scanline(rect.min.y);
    result.pixels = &scan[rect.min.x];
    return result;
}

/// Rough anti-aliased fillsector
void aaFillSector(V, COLOR)(auto ref V v, float x, float y, float r0, float r1, float a0, float a1, COLOR c)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
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
                        *p = COLOR.op!q{.blend(a, b, c)}(c, *p, cast(ubyte)(0.5f + alpha * 255.0f));
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
    int x0 = rect.min.x;
    int y0 = rect.min.y;
    int x1 = rect.max.x;
    int y1 = rect.max.y;
    foreach (px; x0..x1)
    { 
        ubyte alpha = cast(ubyte)( 0.5f + 255.0f * (px - x0) / cast(float)(x1 - x0) );  // Not being generic here
        COLOR c = COLOR.op!q{.blend(a, b, c)}(c1, c0, alpha); // warning .blend is confusing, c1 comes first
        vline(v, px, y0, y1, c);
    }
}

void verticalSlope(V, COLOR)(auto ref V v, box2i rect, COLOR c0, COLOR c1)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
    int x0 = rect.min.x;
    int y0 = rect.min.y;
    int x1 = rect.max.x;
    int y1 = rect.max.y;
    foreach (py; y0..y1)
    { 
        ubyte alpha = cast(ubyte)( 0.5f + 255.0f * (py - y0) / cast(float)(y1 - y0) );  // Not being generic here
        COLOR c = COLOR.op!q{.blend(a, b, c)}(c1, c0, alpha); // warning .blend is confusing, c1 comes first
        hline(v, x0, x1, py, c);
    }
}