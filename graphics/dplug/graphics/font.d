/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.graphics.font;

import core.stdc.stdlib;
import std.conv;
import std.math;
import std.algorithm.comparison;
import std.utf;

import dplug.core.alignedbuffer;
import dplug.core.unchecked_sync;
import dplug.core.nogc;

import dplug.graphics.vector;
import dplug.graphics.box;
import dplug.graphics.image;
import dplug.graphics.stb_truetype;

final class Font
{
public:

    /// Loads a TTF file.
    /// fontData should be the content of that file.
    this(ubyte[] fontData)
    {
        _fontData = fontData;
        if (0 == stbtt_InitFont(&_font, _fontData.ptr, stbtt_GetFontOffsetForIndex(_fontData.ptr, 0)))
            throw new Exception("Coudln't load font");

        stbtt_GetFontVMetrics(&_font, &_fontAscent, &_fontDescent, &_fontLineGap);

        _mutex = makeMutex();

        _glyphCache.initialize(&_font);
    }

    ~this()
    {
        debug ensureNotInGC("Font");
    }

    /// Returns: Where a line of text will be drawn if starting at position (0, 0).
    box2i measureText(StringType)(StringType s, float fontSizePx, float letterSpacingPx) nothrow @nogc
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
        iterateCharacterPositions!StringType(s, fontSizePx, letterSpacingPx, 0, 0, &extendArea);
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
    void iterateCharacterPositions(StringType)(StringType text, float fontSizePx, float letterSpacingPx, float fractionalPosX, float fractionalPosY,
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

            int ixpos = cast(int) floor(xpos);
            int iypos = cast(int) floor(ypos);


            float xShift = xpos - floor(xpos);
            float yShift = ypos - floor(ypos);

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

/// Draw text centered on a point on a DirectView.

void fillText(V, StringType)(auto ref V surface, Font font, StringType s, float fontSizePx, float letterSpacingPx,
                             RGBA textColor, float positionx, float positiony) nothrow @nogc
    if (isWritableView!V && is(ViewColor!V == RGBA))
{
    font._mutex.lock();
    scope(exit) font._mutex.unlock();

    // Decompose in fractional and integer position
    int ipositionx = cast(int)floor(positionx);
    int ipositiony = cast(int)floor(positiony);
    float fractionalPosX = positionx - ipositionx;
    float fractionalPosY = positiony - ipositiony;

    box2i area = font.measureText(s, fontSizePx, letterSpacingPx);

    // Early exit if out of scope
    box2i surfaceArea = box2i(0, 0, surface.w, surface.h);
    if (!surfaceArea.intersects(area))
        return;

    vec2i offset = vec2i(ipositionx, ipositiony) - area.center; // TODO: support other alignment modes

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
        auto outsurf = surface.crop(cropX0, cropY0, cropX1, cropY1);

        int croppedWidth = outsurf.w;

        RGBA fontColor = textColor;

        for (int y = 0; y < outsurf.h; ++y)
        {
            static if (isDirectView!V)
                RGBA[] outscan = outsurf.scanline(y);

            L8[] inscan = coverageBuffer.scanline(y);
            for (int x = 0; x < croppedWidth; ++x)
            {
                static if (isDirectView!V)
                {
                    blendFontPixel(outscan.ptr[x], fontColor, inscan.ptr[x].l);
                }
                else
                {
                    blendFontPixel(outscan.ptr[x], fontColor, inscan.ptr[x].l);
                }
            }
        }
    }
    font.iterateCharacterPositions!StringType(s, fontSizePx, letterSpacingPx, fractionalPosX, fractionalPosY, &drawCharacter);
}


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
}

static assert(GlyphKey.sizeof == 16);

private struct GlyphCache
{
public:
    void initialize(stbtt_fontinfo* font)
    {
        _font = font;
        keys = makeAlignedBuffer!GlyphKey;
        glyphs = makeAlignedBuffer!(ubyte*);
    }

    @disable this(this);

    ~this()
    {
        // Free all glyphs
        foreach(g; glyphs)
        {
            free(g);
        }
    }

    ImageRef!L8 requestGlyph(GlyphKey key, int w, int h) nothrow @nogc
    {
        // TODO
        // Just a linear search for now. Obviously this
        // will be a problem for larger text
        assert(keys.length == glyphs.length);

        for(int i = 0; i < glyphs.length; ++i)
        {
            GlyphKey k = keys[i];
            if (k.codepoint == key.codepoint
                && k.scale == key.scale
                && k.xShift == key.xShift
                && k.yShift == key.yShift)
            {
                // Found, return this glyph
                ImageRef!L8 result;
                result.w = w;
                result.h = h;
                result.pitch = w;
                result.pixels = cast(L8*)(glyphs[i]);
                return result;
            }
        }

        //  Not existing, creates the glyph and add them to the cache
        {
            int stride = w;
            ubyte* buf = cast(ubyte*) malloc(w * h);
            keys.pushBack(key);
            glyphs.pushBack(buf);

            stbtt_MakeCodepointBitmapSubpixel(_font, buf, w, h, stride, key.scale, key.scale, key.xShift, key.yShift, key.codepoint);
            
            ImageRef!L8 result;
            result.w = w;
            result.h = h;
            result.pitch = w;
            result.pixels = cast(L8*)buf;
            return result;
        }
    }
private:
    AlignedBuffer!GlyphKey keys;
    AlignedBuffer!(ubyte*) glyphs;
    stbtt_fontinfo* _font;
}