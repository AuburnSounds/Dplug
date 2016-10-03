/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.drawex;

// Extends ae.graphics.utils
// Additional graphics primitives, and image loading

import std.algorithm.comparison;
import std.math;
import std.traits;

import dplug.core.nogc;
import dplug.core.alignedbuffer;

import dplug.graphics.box;

import ae.utils.graphics;
import ae.utils.graphics.view;


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

    if (a0 == a1)
        return;

    int x0 = cast(int)floor(x - r1 - 1);
    int x1 = cast(int)ceil(x + r1 + 1);

    int y0 = cast(int)floor(y - r1 - 1);
    int y1 = cast(int)ceil(y + r1 + 1);

    float r0s = std.algorithm.max(0, r0 - 1) ^^ 2;
    float r1s = (r1 + 1) * (r1 + 1);


    if (a0 > a1)
        a1 += 2 * PI;

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
                if (r0 <= rs && rs < r1)
                {
                    float alpha = 1.0f;
                    if (r0 + 1 > rs)
                        alpha = rs - r0;
                    if (rs + 1 > r1)
                        alpha = r1 - rs;

                    float a = atan2(dy, dx);
                    bool inSector = (a0 <= a && a <= a1);
                    a += 2 * PI;
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
void horizontalSlope(float curvature = 1.0f, V, COLOR)(auto ref V v, box2i rect, COLOR c0, COLOR c1)
    if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;

    box2i inter = box2i(0, 0, v.w, v.h).intersection(rect);

    int x0 = rect.min.x;
    int x1 = rect.max.x;
    immutable float invX1mX0 = 1.0f / (x1 - x0);
    
    foreach (px; inter.min.x .. inter.max.x)
    {
        float fAlpha =  (px - x0) * invX1mX0;
        static if (curvature != 1.0f)
            fAlpha = fAlpha ^^ curvature;
        ChannelType alpha = cast(ChannelType)( 0.5f + ChannelType.max * fAlpha );  // Not being generic here
        COLOR c = COLOR.op!q{.blend(a, b, c)}(c1, c0, alpha); // warning .blend is confusing, c1 comes first
        vline(v, px, inter.min.y, inter.max.y, c);
    }
}

void verticalSlope(float curvature = 1.0f, V, COLOR)(auto ref V v, box2i rect, COLOR c0, COLOR c1)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;

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
        ChannelType alpha = cast(ChannelType)( 0.5f + ChannelType.max * fAlpha );  // Not being generic here
        COLOR c = COLOR.op!q{.blend(a, b, c)}(c1, c0, alpha); // warning .blend is confusing, c1 comes first
        hline(v, inter.min.x, inter.max.x, py, c);
    }
}


void aaSoftDisc(float curvature = 1.0f, T, V, COLOR)(auto ref V v, T x, T y, T r1, T r2, COLOR color, float globalAlpha = 1.0f)
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
                row[cx] = COLOR.op!q{.blend(a, b, c)}(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * globalAlpha));
            else
            {
                if (frs<fr2s)
                {
                    float alpha = (frs-fr1s) * invfr21;
                    static if (curvature != 1.0f)
                        alpha = alpha ^^ curvature;
                    row[cx] = COLOR.op!q{.blend(a, b, c)}(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * (1-alpha) * globalAlpha));
                }
            }
        }
    }
}

void aaSoftEllipse(float curvature = 1.0f, T, V, COLOR)(auto ref V v, T x, T y, T r1, T r2, T scaleX, T scaleY, COLOR color, float globalAlpha = 1.0f)
if (isWritableView!V && isNumeric!T && is(COLOR : ViewColor!V))
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
                row[cx] = COLOR.op!q{.blend(a, b, c)}(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * globalAlpha));
            else
            {
                if (frs<fr2s)
                {
                    float alpha = (frs-fr1s) * invfr21;
                    static if (curvature != 1.0f)
                        alpha = alpha ^^ curvature;
                    row[cx] = COLOR.op!q{.blend(a, b, c)}(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * (1-alpha) * globalAlpha));
                }
            }
        }
    }
}

/// Draw a circle gradually fading in between r1 and r2 and fading out between r2 and r3
void aaSoftCircle(float curvature = 1.0f, T, V, COLOR)(auto ref V v, T x, T y, T r1, T r2, T r3, COLOR color, float globalAlpha = 1.0f)
if (isWritableView!V && isNumeric!T && is(COLOR : ViewColor!V))
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
                    row[cx] = COLOR.op!q{.blend(a, b, c)}(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * (1-alpha) * globalAlpha));
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
    import ae.utils.math;
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
                scan[x] = COLOR.op!q{.blend(a, b, c)}(b, scan[x], alpha);
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
    *p = COLOR.op!q{.blend(a, b, c)}(color, *p, alpha);
}

/// Manually managed image which is also GC-proof.
class OwnedImage(COLOR)
{
public:
    int w, h;

    /// Create empty.
    this() nothrow @nogc
    {
        w = 0;
        h = 0;
        _pixels = null;
    }

    /// Create with given initial size.
    this(int w, int h) nothrow @nogc
    {
        this();
        size(w, h);
    }

    ~this()
    {
        if (_pixels !is null)
        {
            debug ensureNotInGC("OwnedImage");
            alignedFree(_pixels);
            _pixels = null;
        }
    }

    /// Returns an array for the pixels at row y.
    COLOR[] scanline(int y) pure nothrow @nogc
    {
        assert(y>=0 && y<h);
        auto start = w*y;
        return _pixels[start..start+w];
    }

    mixin DirectView;

    /// Resize the image, the content is lost.  
    void size(int w, int h) nothrow @nogc
    {
        this.w = w;
        this.h = h;
        size_t sizeInBytes = w * h * COLOR.sizeof;
        _pixels = cast(COLOR*) alignedRealloc(_pixels, sizeInBytes, 128);
    }

    /// Returns: A slice of all pixels.
    COLOR[] pixels() nothrow @nogc
    {
        return _pixels[0..w*h];
    }

private:
    COLOR* _pixels;
}

unittest
{
    static assert(isDirectView!(OwnedImage!ubyte));
}

//
// Image loading
//

struct IFImage
{
    int w, h;
    ubyte[] pixels;
    int channels; // number of channels
}

IFImage readImageFromMem(const(ubyte[]) imageData, int channels)
{
    static immutable ubyte[8] pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    bool isPNG = imageData.length >= 8 && (imageData[0..8] == pngSignature);

    // PNG are decoded using stb_image to avoid GC overload using zlib
    if (isPNG)
    {
        import dplug.gui.pngload;

        int width, height, components;
        ubyte* decoded = stbi_load_png_from_memory(imageData, width, height, components, channels);
        scope(exit) stbi_image_free(decoded);

        IFImage result;
        result.w = width;
        result.h = height;
        result.channels = channels;
        int size = width * height * channels; 
        result.pixels = new ubyte[size];
        import core.stdc.string: memcpy;
        memcpy(result.pixels.ptr, decoded, size);
        return result;
    }
    else
    {
        bool isJPEG = (imageData.length >= 2) && (imageData[0] == 0xff) && (imageData[1] == 0xd8);

        if (isJPEG)
        {
            import dplug.gui.jpegload;

            IFImage result;
            int comp;
            ubyte[] pixels = decompress_jpeg_image_from_memory!false(imageData, result.w, result.h, comp, channels);
            result.channels = channels;
            result.pixels = pixels;

            return result;
        }
        else
            assert(false); // Only PNG and JPEG are supported
    }
}

/// The one function you probably want to use.
/// Loads an image from a static array.
/// Throws: $(D ImageIOException) on error.
OwnedImage!RGBA loadOwnedImage(in void[] imageData)
{
    IFImage ifImage = readImageFromMem(cast(const(ubyte[])) imageData, 4);
    int width = cast(int)ifImage.w;
    int height = cast(int)ifImage.h;

    OwnedImage!RGBA loaded = new OwnedImage!RGBA(width, height);
    loaded.pixels[] = (cast(RGBA[]) ifImage.pixels)[]; // pixel copy here
    return loaded;
}



/// Loads two different images:
/// - the 1st is the RGB channels
/// - the 2nd is interpreted as greyscale and fetch in the alpha channel of the result.
/// Throws: $(D ImageIOException) on error.
OwnedImage!RGBA loadImageSeparateAlpha(in void[] imageDataRGB, in void[] imageDataAlpha)
{
    IFImage ifImageRGB = readImageFromMem(cast(const(ubyte[])) imageDataRGB, 3);
    int widthRGB = cast(int)ifImageRGB.w;
    int heightRGB = cast(int)ifImageRGB.h;

    IFImage ifImageA = readImageFromMem(cast(const(ubyte[])) imageDataAlpha, 1);
    int widthA = cast(int)ifImageA.w;
    int heightA = cast(int)ifImageA.h;

    if ( (widthA != widthRGB) || (heightRGB != heightA) )
    {
        throw new Exception("Image size mismatch");
    }

    int width = widthA;
    int height = heightA;

    OwnedImage!RGBA loaded = new OwnedImage!RGBA(width, height);

    for (int j = 0; j < height; ++j)
    {
        RGB* rgbscan = cast(RGB*)(&ifImageRGB.pixels[3 * (j * width)]);
        ubyte* ascan = &ifImageA.pixels[j * width];
        RGBA[] outscan = loaded.scanline(j);
        for (int i = 0; i < width; ++i)
        {
            RGB rgb = rgbscan[i];
            outscan[i] = RGBA(rgb.r, rgb.g, rgb.b, ascan[i]);
        }
    }
    return loaded;
}


