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