/**
Font high-level interface.

Copyright: Guillaume Piolat 2015.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.graphics.font;

import core.stdc.math: floorf;
import core.stdc.stdlib;
import std.conv;
import std.math;
import std.algorithm.comparison;
import std.utf;

import dplug.math.vector;
import dplug.math.box;

import dplug.core.sync;
import dplug.core.nogc;
import dplug.core.map;

import dplug.graphics.image;
import dplug.graphics.stb_truetype;

final class Font
{
public:
nothrow:
@nogc:

    /// Loads a TTF file.
    /// fontData should be the content of that file.
    this(ubyte[] fontData)
    {
        _fontData = fontData;
        if (0 == stbtt_InitFont(&_font, _fontData.ptr, stbtt_GetFontOffsetForIndex(_fontData.ptr, 0)))
            assert(false, "Coudln't load font");

        stbtt_GetFontVMetrics(&_font, &_fontAscent, &_fontDescent, &_fontLineGap);

        _mutex = makeMutex();

        _glyphCache.initialize(&_font);
    }

    ~this()
    {
        stbtt_FreeFont(&_font);
    }

    /// Returns: font ascent in pixels (aka the size of "A").
    float getAscent(float fontSizePx)
    {
        float scale = stbtt_ScaleForPixelHeight(&_font, fontSizePx);
        return scale * _fontAscent;
    }

    /// Returns: font descent in pixels (aka the size of "A").
    /// `ascent - descent` gives the extent of characters.
    float getDescent(float fontSizePx)
    {
        float scale = stbtt_ScaleForPixelHeight(&_font, fontSizePx);
        return scale * _fontDescent;
    }

    /// Returns: size of little 'x' in pixels. Useful for vertical alignment.
    float getHeightOfx(float fontSizePx)
    {
        float scale = stbtt_ScaleForPixelHeight(&_font, fontSizePx);
        int xIndex = stbtt_FindGlyphIndex(&_font, 'x'); // TODO optimize this function
        if (xIndex == 0)
            return getAscent(fontSizePx); // No 'x', return a likely height

        int x0, y0, x1, y1;
        if (stbtt_GetGlyphBox(&_font, xIndex, &x0, &y0, &x1, &y1))
        {
            return scale * y1;
        }
        else
            return getAscent(fontSizePx); // No 'x', return a likely height        
    }


    /// Returns: Where a line of text will be drawn if starting at position (0, 0).
    /// Note: aligning vertically with this information is dangerous, since different characters
    ///       may affect vertical extent differently. Prefer the use of `getHeightOfx()`.
    box2i measureText(const(char)[] s, float fontSizePx, float letterSpacingPx) nothrow @nogc
    {
        box2i area;
        void extendArea(int numCh, dchar ch, box2i position, float scale, float xShift, float yShift) nothrow @nogc
        {
            if (numCh == 0)
                area = position;
            else
                area = area.expand(position.min).expand(position.max);
        }

        // Note: when measuring the size of the text, we do not account for sub-pixel shifts
        // this is because it would make the size of the text vary which does movement jitter
        // for moving text
        iterateCharacterPositions(s, fontSizePx, letterSpacingPx, 0, 0, &extendArea);
        return area;
    }

private:

    stbtt_fontinfo _font;
    const(ubyte)[] _fontData;
    int _fontAscent, _fontDescent, _fontLineGap;

    /// Iterates on character and call the delegate with their subpixel position
    /// Only support one line of text.
    /// Use kerning.
    /// No hinting.
    void iterateCharacterPositions(const(char)[] text, float fontSizePx, float letterSpacingPx, float fractionalPosX, float fractionalPosY,
        scope void delegate(int numCh, dchar ch, box2i position, float scale, float xShift, float yShift) nothrow @nogc doSomethingWithPosition) nothrow @nogc
    {
        assert(0 <= fractionalPosX && fractionalPosX <= 1.0f);
        assert(0 <= fractionalPosY && fractionalPosY <= 1.0f);
        float scale = stbtt_ScaleForPixelHeight(&_font, fontSizePx);
        float xpos = fractionalPosX;
        float ypos = fractionalPosY;

        float lastxpos = 0;
        dchar lastCh;
        int maxHeight = 0;
        box2i area;
        int numCh = 0;
        foreach(dchar ch; text.byDchar)
        {
            if (numCh > 0)
                xpos += scale * stbtt_GetCodepointKernAdvance(&_font, lastCh, ch);

            int advance,lsb,x0,y0,x1,y1;

            const float fxpos = floorf(xpos);
            const float fypos = floorf(ypos);

            int ixpos = cast(int) fxpos;
            int iypos = cast(int) fypos;

            float xShift = xpos - fxpos;
            float yShift = ypos - fypos;

            // Round position sub-pixel to 1/4th of pixels, to make more use of the glyph cache.
            // That means for a codepoint at a particular size, up to 16 different glyph can potentially
            // exist in the cache.
            float roundDivide = 8.0f;
            xShift = cast(int)(round(roundDivide * xShift)) / roundDivide;
            yShift = cast(int)(round(roundDivide * yShift)) / roundDivide;

            stbtt_GetCodepointHMetrics(&_font, ch, &advance, &lsb);
            stbtt_GetCodepointBitmapBoxSubpixel(&_font, ch, scale, scale, xShift, yShift, &x0, &y0, &x1, &y1);
            box2i position = box2i(x0 + ixpos, y0 + iypos, x1 + ixpos, y1 + iypos);
            doSomethingWithPosition(numCh, ch, position, scale, xShift, yShift);
            xpos += (advance * scale);

            // add a user-provided constant letter spacing
            xpos += (letterSpacingPx);

            lastCh = ch;
            numCh++;
        }
    }

    GlyphCache _glyphCache;

    UncheckedMutex _mutex;

    ImageRef!L8 getGlyphCoverage(dchar codepoint, float scale, int w, int h, float xShift, float yShift) nothrow @nogc
    {
        GlyphKey key = GlyphKey(codepoint, scale, xShift, yShift);

        return _glyphCache.requestGlyph(key, w, h);
    }
}


enum HorizontalAlignment
{
    left,    // positionX in surface corresponds to the leftmost point of the first character 
             //   (a bit incorrect, since some chars such as O could go lefter than that)
    center   // positionX in surface corresponds to the center of the horizontal extent of the text
}

enum VerticalAlignment
{
    baseline, // positionY in surface corresponds to baseline coordinate in surface
    center    // positionY in surface corresponds to the center of the vertical extent of the text
}

/// Draw text centered on a point on a DirectView.
void fillText(ImageRef!RGBA surface, Font font, const(char)[] s, float fontSizePx, float letterSpacingPx,
              RGBA textColor, float positionX, float positionY,
              HorizontalAlignment horzAlign = HorizontalAlignment.center,
              VerticalAlignment   vertAlign = VerticalAlignment.center) nothrow @nogc
{
    font._mutex.lock();
    scope(exit) font._mutex.unlock();

    // Decompose in fractional and integer position
    int ipositionx = cast(int)floorf(positionX);
    int ipositiony = cast(int)floorf(positionY);
    float fractionalPosX = positionX - ipositionx;
    float fractionalPosY = positionY - ipositiony;

    box2i area = font.measureText(s, fontSizePx, letterSpacingPx);

    // For clipping outside characters
    box2i surfaceArea = box2i(0, 0, surface.w, surface.h);

    vec2i offset = vec2i(ipositionx, ipositiony);
    
    if (horzAlign == HorizontalAlignment.center)
        offset.x -= area.center.x;

    if (vertAlign == VerticalAlignment.center)
        offset.y -= area.center.y;

    void drawCharacter(int numCh, dchar ch, box2i position, float scale, float xShift, float yShift) nothrow @nogc
    {
        vec2i offsetPos = position.min + offset;

        // make room in temp buffer
        int w = position.width;
        int h = position.height;

        ImageRef!L8 coverageBuffer = font.getGlyphCoverage(ch, scale, w, h, xShift, yShift);

        // follows the cropping limitations of crop()
        int cropX0 = clamp!int(offsetPos.x, 0, surface.w);
        int cropY0 = clamp!int(offsetPos.y, 0, surface.h);
        int cropX1 = clamp!int(offsetPos.x + w, 0, surface.w);
        int cropY1 = clamp!int(offsetPos.y + h, 0, surface.h);
        box2i where = box2i(cropX0, cropY0, cropX1, cropY1);
 
        // Note: it is possible for where to be empty here.

        // Early exit if out of scope
        // For example the whole charater might be out of surface
        if (!surfaceArea.intersects(where))
            return;

        // The area where the glyph (part of it at least) is drawn.
        auto outsurf = surface.cropImageRef(where);

        int croppedWidth = outsurf.w;

        RGBA fontColor = textColor;

        // Need to crop the coverage surface like the output surface.
        // Get the margins introduced.
        // This fixed garbled rendering (Issue #642).
        int covx = cropX0 - offsetPos.x;
        int covy = cropY0 - offsetPos.y;
        int covw = cropX1 - cropX0;
        int covh = cropY1 - cropY0;
        assert(covw > 0 && covh > 0); // else would have exited above

        coverageBuffer = coverageBuffer.cropImageRef(covx, covy, covx + covw, covy + covh);

        assert(outsurf.w == coverageBuffer.w);
        assert(outsurf.h == coverageBuffer.h);

        for (int y = 0; y < outsurf.h; ++y)
        {
            RGBA[] outscan = outsurf.scanline(y);

            L8[] inscan = coverageBuffer.scanline(y);
            for (int x = 0; x < croppedWidth; ++x)
            {
                blendFontPixel(outscan.ptr[x], fontColor, inscan.ptr[x].l);
            }
        }
    }
    font.iterateCharacterPositions(s, fontSizePx, letterSpacingPx, fractionalPosX, fractionalPosY, &drawCharacter);
}

// PERF: perhaps this can be replaced by blendColor, but beware of alpha
// this can be breaking
private void blendFontPixel(ref RGBA bg, RGBA fontColor, int alpha) nothrow @nogc
{

    int alpha2 = 255 - alpha;
    int red =   (bg.r * alpha2 + fontColor.r * alpha + 128) >> 8;
    int green = (bg.g * alpha2 + fontColor.g * alpha + 128) >> 8;
    int blue =  (bg.b * alpha2 + fontColor.b * alpha + 128) >> 8;

    bg = RGBA(cast(ubyte)red, cast(ubyte)green, cast(ubyte)blue, fontColor.a);
}


private struct GlyphKey
{
    dchar codepoint;
    float scale;
    float xShift;
    float yShift;

    // PERF: that sounds a bit expensive, could be replaced by a hash I guess
    int opCmp(const(GlyphKey) other) const nothrow @nogc
    {
        // Basically: group by scale then by yShift (likely yo be the same line)
        //            then codepoint then xShift
        if (scale < other.scale)
            return -1;
        else if (scale > other.scale)
            return 1;
        else
        {
            if (yShift < other.yShift)
                return -1;
            else if (yShift > other.yShift)
                return 1;
            else
            {
                if (codepoint < other.codepoint)
                    return -1;
                else if (codepoint > other.codepoint)
                    return 1;
                else
                {
                    if (xShift < other.xShift)
                        return -1;
                    else if (xShift > other.xShift)
                        return 1;
                    else
                        return 0;
                }
            }
        }
    }
}

static assert(GlyphKey.sizeof == 16);

private struct GlyphCache
{
public:
nothrow:
@nogc:
    void initialize(stbtt_fontinfo* font)
    {
        _font = font;
        _glyphs = makeMap!(GlyphKey, ubyte*); // TODO: Inspector says this map is leaking, investigate why
    }

    @disable this(this);

    ~this()
    {
        // Free all glyphs
        foreach(g; _glyphs.byValue)
        {
            free(g);
        }
    }

    ImageRef!L8 requestGlyph(GlyphKey key, int w, int h)
    {
        ubyte** p = key in _glyphs;

        if (p !is null)
        {
            // Found glyph in cache, return this glyph
            ImageRef!L8 result;
            result.w = w;
            result.h = h;
            result.pitch = w;
            result.pixels = cast(L8*)(*p);
            return result;
        }

        //  Not existing, creates the glyph and add them to the cache
        {
            int stride = w;
            ubyte* buf = cast(ubyte*) malloc(w * h);
            stbtt_MakeCodepointBitmapSubpixel(_font, buf, w, h, stride, key.scale, key.scale, key.xShift, key.yShift, key.codepoint);
            _glyphs[key] = buf;
            
            ImageRef!L8 result;
            result.w = w;
            result.h = h;
            result.pitch = w;
            result.pixels = cast(L8*)buf;
            return result;
        }
    }
private:
    Map!(GlyphKey, ubyte*) _glyphs;
    stbtt_fontinfo* _font;
}