module dplug.gui.toolkit.font;

import std.conv;
import std.math;

import ae.utils.graphics;

import gfm.math;
import gfm.image.stb_truetype;





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

        // defaults
        _currentColor = RGBA(255, 255, 255, 255);
        _currentFontSizePx = 16;
    }

    ~this()
    {
        // nothing to be done
    }

    /// Returns: Current font size, in pixels.
    float size() pure const nothrow @nogc
    {
        return _currentFontSizePx;
    }

    /// Sets current font size, in pixels.
    float size(float fontSizePx) pure nothrow @nogc
    {
        return _currentFontSizePx = fontSizePx;
    }

    /// Returns: current color.
    RGBA color() pure const nothrow @nogc
    {
        return _currentColor;
    }

    /// Sets the font-size. Fast and constant-time.
    RGBA color(RGBA c) pure nothrow @nogc
    {
        return _currentColor = c;
    }

    /// Returns: Where a line of text will be drawn if starting at position (fractionalPosX, fractionalPosY).
    box2i measureText(StringType)(StringType s)
    {
        box2i area;
        void extendArea(int numCh, dchar ch, box2i position, float scale, float xShift, float yShift)
        {
            if (numCh == 0)
                area = position;
            else 
                area = area.expand(position.min).expand(position.max);
        }

        // Note: when measuring the size of the text, we do not account for sub-pixel shifts
        // this is because it would make the size of the text vary which does movement jitter
        // for moving text
        iterateCharacterPositions!StringType(s, _currentFontSizePx, 0, 0, &extendArea);
        return area;
    }    

private:

    RGBA _currentColor; /// Current selected color for draw operations.

    float _currentFontSizePx; /// Current selected font-size (expressed in pixels)

    stbtt_fontinfo _font;    
    const(ubyte)[] _fontData;
    int _fontAscent, _fontDescent, _fontLineGap;

    /// Iterates on character and call the deledate with their subpixel position
    /// Only support one line of text.
    /// Use kerning.
    /// No hinting.
    void iterateCharacterPositions(StringType)(StringType text, float fontSizePx, float fractionalPosX, float fractionalPosY,
                                               scope void delegate(int numCh, dchar ch, box2i position, float scale, float xShift, float yShift) doSomethingWithPosition)
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
        foreach(int numCh, dchar ch; text)
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
            lastCh = ch;
        }
    }

    // Glyph cache
    Image!L8[GlyphKey] _glyphCache;

    Image!L8 getGlyphCoverage(dchar codepoint, float scale, int w, int h, float xShift, float yShift)
    {
        GlyphKey key = GlyphKey(codepoint, scale, xShift, yShift);

        Image!L8* found = key in _glyphCache;

        if (found)
            return *found;
        else
        {
            int stride = w;
            _glyphCache[key] = Image!L8(w, h);
            ubyte* buf = cast(ubyte*)(_glyphCache[key].pixels.ptr);
            stbtt_MakeCodepointBitmapSubpixel(&_font, buf, w, h, stride, scale, scale, xShift, yShift, codepoint);
            return _glyphCache[key];
        }
    }
}

struct GlyphKey
{
    dchar codepoint;
    float scale;
    float xShift;
    float yShift;
}


/// Draw text centered on a point on a DirectView.

void fillText(V, StringType)(auto ref V surface, Font font, StringType s, float positionx, float positiony)
    if (isDirectView!V && is(ViewColor!V == RGBA))
{
    // Decompose in fractional and integer position
    int ipositionx = cast(int)floor(positionx);
    int ipositiony = cast(int)floor(positiony);
    float fractionalPosX = positionx - ipositionx;
    float fractionalPosY = positiony - ipositiony;

    box2i area = font.measureText(s);
    vec2i offset = vec2i(ipositionx, ipositiony) - area.center; // TODO: support other alignment modes

    void drawCharacter(int numCh, dchar ch, box2i position, float scale, float xShift, float yShift)
    {
        vec2i offsetPos = position.min + offset;

        // make room in temp buffer
        int w = position.width;
        int h = position.height;

        Image!L8 coverageBuffer = font.getGlyphCoverage(ch, scale, w, h, xShift, yShift);

        // follows the cropping limitations of crop()
        int cropX0 = clamp!int(offsetPos.x, 0, surface.w);
        int cropY0 = clamp!int(offsetPos.y, 0, surface.h);
        int cropX1 = clamp!int(offsetPos.x + w, 0, surface.w);
        int cropY1 = clamp!int(offsetPos.y + h, 0, surface.h);
        auto outsurf = surface.crop(cropX0, cropY0, cropX1, cropY1);
        int croppedWidth = outsurf.w;

        for (int y = 0; y < outsurf.h; ++y)
        {
            RGBA[] scanline = outsurf.scanline(y);
            L8[] inscan = coverageBuffer.scanline(y);
            for (int x = 0; x < croppedWidth; ++x)
            {
                RGBA finalColor = font._currentColor;
                finalColor.a = ( (font._currentColor.a * inscan[x].l + 128) / 255 );
                scanline[x] = RGBA.blend(scanline[x], finalColor);
            }
        }            
    }
    font.iterateCharacterPositions!StringType(s, font._currentFontSizePx, fractionalPosX, fractionalPosY, &drawCharacter);
}