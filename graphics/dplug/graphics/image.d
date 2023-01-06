/**
In-memory images.

License:
    This Source Code Form is subject to the terms of
    the Mozilla Public License, v. 2.0. If a copy of
    the MPL was not distributed with this file, You
    can obtain one at http://mozilla.org/MPL/2.0/.
 
 Copyright: Vladimir Panteleev <vladimir@thecybershadow.net>
 Copyright: Guillaume Piolat <contact@auburnsounds.com>
 */

module dplug.graphics.image;


import std.conv : to;
import std.string : format;
import std.functional;
import std.typetuple;
import std.algorithm.mutation: swap;
import std.math;
import dplug.core.math;
import dplug.core.vec;
import dplug.core.nogc;
import dplug.math.box;
public import dplug.graphics.color;
import gamut;

nothrow @nogc:

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
		assert(y >= 0 && y < h);
		assert(pitch);

        // perf: this cast help in 64-bit, since it avoids a MOVSXD to extend a signed 32-bit into a 64-bit pointer offset
        uint unsignedY = cast(uint)y;

		auto row = cast(COLOR*)(cast(ubyte*)pixels + unsignedY * pitch);
		return row[0..w];
	}

	mixin DirectView;

    /// Returns a cropped view of the same `ImageRef`.
    ImageRef!COLOR cropBorder(int borderPixels)
    {
        assert(w >= 2*borderPixels);
        assert(h >= 2*borderPixels);

        ImageRef cropped;
        cropped.w = w - 2*borderPixels;
        cropped.h = h - 2*borderPixels;
        cropped.pitch = pitch;
        cropped.pixels = cast(COLOR*)(cast(ubyte*)pixels + borderPixels*pitch + borderPixels*COLOR.sizeof);
        return cropped;
    }
}

unittest
{
    static assert(isDirectView!(ImageRef!ubyte));
}

/// Convert an `OwnedImage` to an `ImageRef`.
ImageRef!L8 toRef(OwnedImage!L8 src) pure
{
    return ImageRef!L8(src.w, src.h, src.pitchInBytes(), src.scanlinePtr(0));
}

///ditto
ImageRef!L16 toRef(OwnedImage!L16 src) pure
{
    return ImageRef!L16(src.w, src.h, src.pitchInBytes(), src.scanlinePtr(0));
}

///ditto
ImageRef!RGBA toRef(OwnedImage!RGBA src) pure
{
    return ImageRef!RGBA(src.w, src.h, src.pitchInBytes(), src.scanlinePtr(0));
}

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


/// Crop an ImageRef and get an ImageRef instead of a Voldemort type.
/// This also avoid adding offset to coordinates.
ImageRef!COLOR cropImageRef(COLOR)(ImageRef!COLOR src, box2i rect)
{
    assert(rect.max.x <= src.w);
    assert(rect.max.y <= src.h);
    ImageRef!COLOR result;
    result.w = rect.width;
    result.h = rect.height;
    result.pitch = src.pitch;
    COLOR[] scan = src.scanline(rect.min.y);
    result.pixels = &scan[rect.min.x];
    return result;
}
///ditto
ImageRef!COLOR cropImageRef(COLOR)(ImageRef!COLOR src, int xmin, int ymin, int xmax, int ymax)
{
    return src.cropImageRef(box2i(xmin, ymin, xmax, ymax));
}

/// Manually managed image.
final class OwnedImage(COLOR)
{
public:
nothrow:
@nogc:

    /// Width of the meaningful area. Public in order to be an `Image`.
    int w;

    /// Height of the meaningful area. Public in order to be an `Image`.
    int h;

    /// Create empty and with no size.
    this() nothrow @nogc
    {
    }

    /// Create with given initial size.
    ///
    /// Params:
    ///   w               Width of meaningful area in pixels.
    ///   h               Height of meaningful area in pixels.
    ///   border          Number of border pixels around the meaningful area. For the right border, this could actually be more depending on other constraints.
    ///   rowAlignment    Alignment of the _first_ pixel of each row, in bytes (excluding border).
    ///   xMultiplicity   Starting with the first meaningful pixel of a line, force the number of adressable
    ///                   pixels to be a multiple of `xMultiplicity`.
    ///                   All these "padding" samples added at the right of each line if needed will be considered 
    ///                   part of the border and replicated if need be.
    ///                   This is eg. to process a whole line with only aligned loads.
    ///                   Implemented with additional right border.
    ///   trailingSamples When reading from a meaningful position, you can read 1 + `trailingSamples` neightbours
    ///                   Their value is NOT guaranteed in any way and is completely undefined. 
    ///                   They are guaranteed non-NaN if you've generated borders and did not write into borders.
    ///                   Because of row alignment padding, this is not implemented with a few samples at the end 
    ///                   of the buffer, but is instead again a right border extension.
    ///
    /// Note: default arguments leads to a gapless representation.
    this(int w, int h, int border = 0, int rowAlignment = 1, int xMultiplicity = 1, int trailingSamples = 0) nothrow @nogc
    {
        this();
        size(w, h, border, rowAlignment, xMultiplicity, trailingSamples);
    }

    /// Create from already loaded dense RGBA pixel data.
    /// `buffer` should be allocated with `alignedMalloc`/`alignedRealloc` with an alignment of 1.
    /// Ownership of `buffer` is given to the `OwnedImage`.
    this(int w, int h, ubyte* buffer)
    {
        this.w = w;
        this.h = h;
        _pixels = cast(COLOR*) buffer;
        _bytePitch = w * cast(int)(COLOR.sizeof);
        _buffer = buffer;
        _border = 0;
        _borderRight = 0;
    }

    ~this()
    {
        if (_buffer !is null)
        {
             // FUTURE: use intel-intrinsics _mm_malloc/_mm_free
            alignedFree(_buffer, 1); // Note: this allocation methods must be synced with the one in JPEG and PNL loading.
            _buffer = null;
        }
    }

    /// Returns: A pointer to the pixels at row y. Excluding border pixels.
    COLOR* scanlinePtr(int y) pure
    {
        assert(y >= 0 && y < h);

        // perf: this cast help in 64-bit, since it avoids a MOVSXD to extend a signed 32-bit into a 64-bit pointer offset
        uint offsetBytes = _bytePitch * cast(uint)y;

        return cast(COLOR*)( cast(ubyte*)_pixels + offsetBytes );
    }

    /// Returns: A slice of the pixels at row y. Excluding border pixels.
    COLOR[] scanline(int y) pure
    {
        return scanlinePtr(y)[0..w];
    }    

    /// Resize the image, the content is lost and the new content is undefined.
    ///
    /// Params:
    ///   w               Width of meaningful area in pixels.
    ///   h               Height of meaningful area in pixels.
    ///   border          Number of border pixels around the meaningful area. For the right border, this could actually be more depending on other constraints.
    ///   rowAlignment    Alignment of the _first_ pixel of each row, in bytes (excluding border).
    ///   xMultiplicity   Starting with the first meaningful pixel of a line, force the number of adressable
    ///                   pixels to be a multiple of `xMultiplicity`.
    ///                   All these "padding" samples added at the right of each line if needed will be considered 
    ///                   part of the border and replicated if need be.
    ///                   This is eg. to process a whole line with only aligned loads.
    ///                   Implemented with additional right border.
    ///   trailingSamples When reading from a meaningful position, you can read 1 + `trailingSamples` neightbours
    ///                   Their value is NOT guaranteed in any way and is completely undefined. 
    ///                   They are guaranteed non-NaN if you've generated borders and did not write into borders.
    ///                   Because of row alignment padding, this is not implemented with a few samples at the end 
    ///                   of the buffer, but is instead again a right border extension.
    ///
    /// Note: Default arguments leads to a gapless representation.
    void size(int width, 
              int height, 
              int border = 0, 
              int rowAlignment = 1, 
              int xMultiplicity = 1, 
              int trailingSamples = 0)
    {
        assert(width >= 0); // Note sure if 0 is supported
        assert(height >= 0); // Note sure if 0 is supported
        assert(border >= 0);
        assert(rowAlignment >= 1); // Not yet implemented!
        assert(xMultiplicity >= 1); // Not yet implemented!

        // Compute size of right border.
        // How many "padding samples" do we need to extend the right border with to respect `xMultiplicity`?
        int rightPadding = computeRightPadding(w, border, xMultiplicity);
        int borderRight = border + rightPadding;
        if (borderRight < trailingSamples)
            borderRight = trailingSamples;

        int actualWidthInSamples  = border + width  + borderRight;
        int actualHeightInSamples = border + height + border;        

        // Compute byte pitch and align it on `rowAlignment`
        int bytePitch = cast(int)(COLOR.sizeof) * actualWidthInSamples;
        bytePitch = cast(int) nextMultipleOf(bytePitch, rowAlignment);

        this.w = width;
        this.h = height;
        this._border = border;
        this._borderRight = borderRight;
        this._bytePitch = bytePitch;

        // How many bytes do we need for all samples? A bit more for aligning the first valid pixel.
        size_t allocationSize = bytePitch * actualHeightInSamples;
        allocationSize += (rowAlignment - 1);

        // We don't need to preserve former data, nor to align the first border pixel
        this._buffer = alignedReallocDiscard(this._buffer, allocationSize, 1);

        // Set _pixels to the right place
        size_t offsetToFirstMeaningfulPixel = bytePitch * borderTop() + COLOR.sizeof * borderLeft();
        this._pixels = cast(COLOR*) nextAlignedPointer(&_buffer[offsetToFirstMeaningfulPixel], rowAlignment);

        // Test alignment of rows
        assert( isPointerAligned(_pixels, rowAlignment) );
        if (height > 0)
            assert( isPointerAligned(scanlinePtr(0), rowAlignment) );

        if (border == 0 && rowAlignment == 1 && xMultiplicity == 1 && trailingSamples == 0)
        {
            assert(isGapless());
        }
    }

    /// Returns: `true` if rows of pixels are immediately consecutive in memory.
    ///          Meaning that there is no border or lost pixels in the data.
    bool isGapless() pure
    {
        return w * COLOR.sizeof  == _bytePitch;
    }

    /// Returns: Number of bytes to add to a COLOR* pointer to get to the previous/next line.
    ///          This pitch is guaranteed to be positive (>= 0).
    int pitchInBytes() pure
    {
        return _bytePitch;
    }

    /// Returns: Number of border pixels in the left direction (small X).
    int borderLeft() pure
    {
        return _border;
    }

    /// Returns: Number of border pixels in the right direction (large X).
    int borderRight() pure
    {
        return _borderRight;
    }

    /// Returns: Number of border pixels in the left direction (small Y).
    int borderTop() pure
    {
        return _border;
    }

    /// Returns: Number of border pixels in the left direction (large Y).
    int borderBottom() pure
    {
        return _border;
    }

    // It is a `DirectView`.
    mixin DirectView;

    /// Fills the whole image, border included, with a single color value.
    void fillWith(COLOR fill)
    {
        for (int y = -borderTop(); y < h + borderBottom(); ++y)
        {
            int pixelsInRow = borderLeft() + w + borderRight();
            COLOR* scan = unsafeScanlinePtr(y) - borderLeft();
            scan[0..pixelsInRow] = fill;
        }
    }

    /// Fill the borders by taking the nearest existing pixel in the meaningful area.
    void replicateBorders()
    {
        replicateBordersTouching( box2i.rectangle(0, 0, this.w, this.h) );
    }

    /// Fill the borders _touching updatedRect_ by taking the nearest existing pixel in the meaningful area.
    void replicateBordersTouching(box2i updatedRect)
    {
        if (w < 1 || h < 1)
            return; // can't replicate borders of an empty image

        // BORDER REPLICATION.
        // If an area is touching left border, then the border needs replication.
        // If an area is touching left and top border, then the border needs replication and the corner pixel should be filled too.
        // Same for all four corners. Border only applies to level 0.
        //
        // OOOOOOOxxxxxxxxxxxxxxx
        // Ooooooo
        // Oo    o
        // Oo    o    <------ if the update area is made of 'o', then the area to replicate is 'O'
        // Ooooooo
        // x
        // x

        int W = this.w;
        int H = this.h;

        int minx = updatedRect.min.x;
        int maxx = updatedRect.max.x;
        int miny = updatedRect.min.y;
        int maxy = updatedRect.max.y;

        bool touchLeft   = (minx == 0);
        bool touchTop    = (miny == 0);
        bool touchRight  = (maxx == W);
        bool touchBottom = (maxy == H);

        int bTop   = borderTop();
        int bBott  = borderBottom();
        int bLeft  = borderLeft();
        int bRight = borderRight();

        if (touchTop)
        {
            if (touchLeft)
            {
                COLOR topLeft = this[0, 0];
                for (int y = -borderTop; y < 0; ++y)
                    for (int x = -borderLeft; x < 0; ++x)
                        unsafeScanlinePtr(y)[x] = topLeft;
            }

            for (int y = -borderTop; y < 0; ++y)
            {
                unsafeScanlinePtr(y)[minx..maxx] = scanline(0)[minx..maxx];
            }

            if (touchRight)
            {
                COLOR topRight = this[W-1, 0];
                for (int y = -borderTop; y < 0; ++y)
                    for (int x = 0; x < borderRight(); ++x)
                        unsafeScanlinePtr(y)[W + x] = topRight;
            }
        }

        if (touchLeft)
        {
            for (int y = miny; y < maxy; ++y)
            {
                COLOR edge = this[0, y];
                for (int x = -borderLeft(); x < 0; ++x)
                    unsafeScanlinePtr(y)[x] = edge;
            }
        }

        if (touchRight)
        {
            for (int y = miny; y < maxy; ++y)
            {
                COLOR edge = this[W-1, y];
                for (int x = 0; x < borderRight(); ++x)
                    unsafeScanlinePtr(y)[W + x] = edge;
            }
        }

        if (touchBottom)
        {
            if (touchLeft)
            {
                COLOR bottomLeft = this[0, H-1];
                for (int y = H; y < H + borderTop(); ++y)
                    for (int x = -borderLeft; x < 0; ++x)
                        unsafeScanlinePtr(y)[x] = bottomLeft;
            }

            for (int y = H; y < H + borderBottom(); ++y)
            {
                unsafeScanlinePtr(y)[minx..maxx] = scanline(H-1)[minx..maxx];
            }

            if (touchRight)
            {
                COLOR bottomRight = this[W-1, H-1];
                for (int y = H; y < H + borderTop(); ++y)
                    for (int x = 0; x < borderRight(); ++x)
                        unsafeScanlinePtr(y)[W + x] = bottomRight;
            }
        }
    }

private:

    /// Adress of the first meaningful pixel
    COLOR* _pixels;

    /// Samples difference between rows of pixels.
    int _bytePitch;

    /// Address of the allocation itself
    void* _buffer = null;

    /// Size of left, top and bottom borders, around the meaningful area.
    int _border;

    /// Size of border at thr right of the meaningful area (most positive X)
    int _borderRight;

    // Internal use: allows to get the scanlines of top and bottom borders too
    COLOR* unsafeScanlinePtr(int y) pure
    {
        assert(y >= -borderTop());      // negative Y allows to get top border scanlines
        assert(y < h + borderBottom()); // Y overflow allows to get bottom border scanlines
        int byteOffset = _bytePitch * y; // unlike the normal `scanlinePtr`, there will be a MOVSXD here
        return cast(COLOR*)(cast(ubyte*)(_pixels) + byteOffset);
    }

    static int computeRightPadding(int width, int border, int xMultiplicity) pure
    {
        int nextMultiple = cast(int)(nextMultipleOf(width + border, xMultiplicity));
        return nextMultiple - (width + border);
    }

    static size_t nextMultipleOf(size_t base, size_t multiple) pure
    {
        assert(multiple > 0);
        size_t n = (base + multiple - 1) / multiple;
        return multiple * n;
    }

    /// Returns: next pointer aligned with alignment bytes.
    static void* nextAlignedPointer(void* start, size_t alignment) pure
    {
        return cast(void*)nextMultipleOf(cast(size_t)(start), alignment);
    }
}

unittest
{
    static assert(isDirectView!(OwnedImage!ubyte));
    assert(OwnedImage!RGBA.computeRightPadding(4, 0, 4) == 0);
    assert(OwnedImage!RGBA.computeRightPadding(1, 3, 5) == 1);
    assert(OwnedImage!L16.computeRightPadding(2, 0, 4) == 2);
    assert(OwnedImage!RGBA.computeRightPadding(2, 1, 4) == 1);
    assert(OwnedImage!RGBf.nextMultipleOf(0, 7) == 0);
    assert(OwnedImage!RGBAf.nextMultipleOf(1, 7) == 7);
    assert(OwnedImage!RGBA.nextMultipleOf(6, 7) == 7);
    assert(OwnedImage!RGBA.nextMultipleOf(7, 7) == 7);
    assert(OwnedImage!RGBA.nextMultipleOf(8, 7) == 14);

    {
        OwnedImage!RGBA img = mallocNew!(OwnedImage!RGBA);
        scope(exit) destroyFree(img);
        img.size(0, 0); // should be supported

        int border = 10;
        img.size(0, 0, border); // should also be supported (border with no data!)
        img.replicateBorders(); // should not crash

        border = 0;
        img.size(1, 1, border);
        img.replicateBorders(); // should not crash
    }
}

// Test border replication
unittest
{
    OwnedImage!L8 img = mallocNew!(OwnedImage!L8);
    scope(exit) destroyFree(img);
    int width = 2;
    int height = 2;
    int border = 2;
    int xMultiplicity = 1;
    int trailing = 3;
    img.size(width, height, border, xMultiplicity, trailing);
    assert(img.w == 2 && img.h == 2);
    assert(img.borderLeft() == 2 && img.borderRight() == 3);
    assert(img._bytePitch == 7);

    img.fillWith(L8(5));
    img.scanline(0)[0].l = 1;
    img.scanlinePtr(0)[1].l = 2;
    img[0, 1].l = 3;
    img[1, 1].l = 4;
    
    img.replicateBorders();
    ubyte[7][6] correct = 
    [
        [1, 1, 1, 2, 2, 2, 2],
        [1, 1, 1, 2, 2, 2, 2],
        [1, 1, 1, 2, 2, 2, 2],
        [3, 3, 3, 4, 4, 4, 4],
        [3, 3, 3, 4, 4, 4, 4],
        [3, 3, 3, 4, 4, 4, 4],
    ];

    for (int y = -2; y < 4; ++y)
    {
        for (int x = -2; x < 5; ++x)
        {            
            L8 read = img.unsafeScanlinePtr(y)[x];
            ubyte good = correct[y+2][x+2];
            assert(read.l == good);
        }
    }
}

// Test toRef
unittest
{
    OwnedImage!L8 img = mallocNew!(OwnedImage!L8);
    scope(exit) destroyFree(img);

    int border = 0;
    int rowAlignment = 1;
    int xMultiplicity = 1;
    int trailingSamples = 4;
    img.size(10, 10, border, rowAlignment, xMultiplicity, trailingSamples); // Ask for 4 trailing samples
    ImageRef!L8 r = img.toRef();
    assert(r.pitch >= 10 + 4); // per the API, OwnedImage could add more space than required
}

/// Loads an image from compressed data.
/// The returned `OwnedImage!RGBA` should be destroyed with `destroyFree`.
/// Throws: $(D ImageIOException) on error.
OwnedImage!RGBA loadOwnedImage(in void[] imageData)
{
    Image image;
    image.loadFromMemory(cast(const(ubyte[])) imageData, 
                         LOAD_RGB | LOAD_8BIT | LOAD_ALPHA | LAYOUT_VERT_STRAIGHT | LAYOUT_GAPLESS);
    if (image.errored)
    {
        assert(false, "Decoding failed");
    }

    return convertImageToOwnedImage_rgba8(image);
}


/// Loads two different images:
/// - the 1st is the RGB channels
/// - the 2nd is interpreted as greyscale and fetch in the alpha channel of the result.
/// The returned `OwnedImage!RGBA` should be destroyed with `destroyFree`.
/// Throws: $(D ImageIOException) on error.
OwnedImage!RGBA loadImageSeparateAlpha(in void[] imageDataRGB, in void[] imageDataAlpha)
{
    Image alpha;
    alpha.loadFromMemory(cast(const(ubyte[])) imageDataAlpha, 
                         LOAD_GREYSCALE | LOAD_8BIT | LOAD_NO_ALPHA | LAYOUT_VERT_STRAIGHT | LAYOUT_GAPLESS);
    if (alpha.errored)
    {
        assert(false, "Decoding failed");
    }

    Image rgb;
    rgb.loadFromMemory(cast(const(ubyte[])) imageDataRGB, 
                       LOAD_RGB | LOAD_8BIT | LOAD_ALPHA | LAYOUT_VERT_STRAIGHT | LAYOUT_GAPLESS);
    if (rgb.errored)
    {
        assert(false, "Decoding failed");
    }

    if ( (rgb.width != alpha.width) || (rgb.height != alpha.height) )
    {
        // If you fail here, typically size of your Diffuse map doesn't match the Emissive map.
        assert(false, "Image size mismatch");
    }

    int W = rgb.width;
    int H = rgb.height;

    for (int y = 0; y < H; ++y)
    {
        ubyte* scanA = cast(ubyte*) alpha.scanline(y);
        ubyte* scanRGBA = cast(ubyte*) rgb.scanline(y);
        for (int x = 0; x < W; ++x)
        {
            scanRGBA[4*x + 3] = scanA[x];
        }
    }

    return convertImageToOwnedImage_rgba8(rgb);
}


/// Loads an image to be a 16-bit one channel image (`OwnedImage!L16`).
/// The returned `OwnedImage!L16` should be destroyed with `destroyFree`.
/// Throws: $(D ImageIOException) on error.
OwnedImage!L16 loadOwnedImageDepth(in void[] imageData)
{
    Image image;
    image.loadFromMemory(cast(const(ubyte[])) imageData, LOAD_NO_ALPHA);
    if (image.errored)
    {
        assert(false, "Decoding failed");
    }
  
    if (image.type() == PixelType.rgb8)
    {
        // Legacy 8-bit to 16-bit depth conversion
        // This is the original legacy way to load depth.
        // Load as 8-bit RGBA, then mix the channels so as to support
        // legacy depth maps.
        Image image16;
        image16.setSize(image.width, image.height, PixelType.l16, LAYOUT_VERT_STRAIGHT | LAYOUT_GAPLESS);
        int width = image.width;
        int height = image.height;

        OwnedImage!L16 result = mallocNew!(OwnedImage!L16)(width, height);

        for (int j = 0; j < height; ++j)
        {
            ubyte* inDepth = cast(ubyte*) image.scanline(j);
            ushort* outDepth = cast(ushort*) image16.scanline(j);

            for (int i = 0; i < width; ++i)
            {
                // Using 257 to span the full range of depth: 257 * (255+255+255)/3 = 65535
                // If we do that inside stb_image, it will first reduce channels _then_ increase bitdepth.
                // Instead, this is used to gain 1.5 bit of accuracy for 8-bit depth maps. :)
                float d = 0.5f + 257 * (inDepth[3*i+0] + inDepth[3*i+1] + inDepth[3*i+2]) / 3; 
                outDepth[i] = cast(ushort)(d);
            }
        }
        return convertImageToOwnedImage_l16(image16);
    }
    else
    {
        // Ensure the format pixel is l16, and the layout is compatible with OwnedImage
        image.convertTo(PixelType.l16, LAYOUT_VERT_STRAIGHT | LAYOUT_GAPLESS);
        return convertImageToOwnedImage_l16(image);
    }
}

/// Make a gamut `Image` view from a dplug:graphics `ImageRef`.
/// The original `OwnedImage` is still the owner of the pixel data.
void createViewFromImageRef(COLOR)(ref Image view, ImageRef!COLOR source)
{
    static if (is(COLOR == RGBA))
    {
        view.createViewFromData(source.pixels, source.w, source.h, PixelType.rgba8, cast(int)source.pitch);
    }
    else static if (is(COLOR == RGB))
    {
        view.createViewFromData(source.pixels, source.w, source.h, PixelType.rgb8, cast(int)source.pitch);
    }
    else static if (is(COLOR == L8))
    {
        view.createViewFromData(source.pixels, source.w, source.h, PixelType.l8, cast(int)source.pitch);
    }
    else static if (is(COLOR == L16))
    {
        view.createViewFromData(source.pixels, source.w, source.h, PixelType.l16, cast(int)source.pitch);
    }
    else
        static assert(false);
}

/// Convert and disown gamut Image to OwnedImage.
/// Result: ìmage` is disowned, result is owning the image data.
OwnedImage!RGBA convertImageToOwnedImage_rgba8(ref Image image)
{
    assert(image.type() == PixelType.rgba8);
    OwnedImage!RGBA r = mallocNew!(OwnedImage!RGBA);
    r.w = image.width;
    r.h = image.height;    
    r._pixels = cast(RGBA*) image.scanline(0);
    r._bytePitch = image.pitchInBytes();
    r._buffer = image.disownData();
    r._border = 0;      // TODO should keep it from input
    r._borderRight = 0; // TODO should keep it from input
    return r;
}

///ditto
OwnedImage!RGB convertImageToOwnedImage_rgb8(ref Image image)
{
    assert(image.type() == PixelType.rgb8);
    OwnedImage!RGB r = mallocNew!(OwnedImage!RGB);
    r.w = image.width;
    r.h = image.height;    
    r._pixels = cast(RGB*) image.scanline(0);
    r._bytePitch = image.pitchInBytes();
    r._buffer = image.disownData();
    r._border = 0;      // TODO should keep it from input
    r._borderRight = 0; // TODO should keep it from input
    return r;
}

///ditto
OwnedImage!L16 convertImageToOwnedImage_l16(ref Image image)
{
    assert(image.type() == PixelType.l16);
    OwnedImage!L16 r = mallocNew!(OwnedImage!L16);
    r.w = image.width;
    r.h = image.height;    
    r._pixels = cast(L16*) image.scanline(0);
    r._bytePitch = image.pitchInBytes();
    r._buffer = image.disownData();
    r._border = 0;      // TODO should keep it from input
    r._borderRight = 0; // TODO should keep it from input
    return r;
}

///ditto
OwnedImage!L8 convertImageToOwnedImage_l8(ref Image image)
{
    assert(image.type() == PixelType.l8);
    OwnedImage!L8 r = mallocNew!(OwnedImage!L8);
    r.w = image.width;
    r.h = image.height;    
    r._pixels = cast(L8*) image.scanline(0);
    r._bytePitch = image.pitchInBytes();
    r._buffer = image.disownData();
    r._border = 0;      // TODO should keep it from input
    r._borderRight = 0; // TODO should keep it from input
    return r;
}