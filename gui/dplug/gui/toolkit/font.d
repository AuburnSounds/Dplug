module dplug.gui.toolkit.font;

import std.conv;

import ae.utils.graphics;

import gfm.math;
import gfm.image.stb_truetype;


final class Font
{
public:
    this(string fontface, int pxSize)
    {
        _fontData = cast(ubyte[])(std.file.read(fontface));
        if (0 == stbtt_InitFont(&_font, _fontData.ptr, stbtt_GetFontOffsetForIndex(_fontData.ptr, 0)))
            throw new Exception("Coudln't load font " ~ fontface);

        stbtt_GetFontVMetrics(&_font, &_fontAscent, &_fontDescent, &_fontLineGap);
        _initialized = true;

        // defaults
        _currentColor = RGBA(255, 255, 255, 255);
        _currentFontSizePx = 16;
    }

    ~this()
    {
        close();
    }

    /// Returns: Current font-size, in pixels.
    float fontSize() pure const nothrow @nogc
    {
        return _currentFontSizePx;
    }

    /// Sets current font-size, in pixels.
    float fontSize(float fontSizePx) pure nothrow @nogc
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

    void close()
    {
        if (_initialized)
        {
            _initialized = false;
        }
    }


    /+

    Image!RGBA makeCharTexture(dchar ch)
    {
        // Generate glyph coverage
        int width, height;
        int xoff, yoff;
        ubyte* glyphBitmap = stbtt_GetCodepointBitmap(&_font, _scaleFactor, _scaleFactor, ch , &width, &height, &xoff, &yoff);

        // Copy to a SDL surface
        uint Rmask = 0x00ff0000;
        uint Gmask = 0x0000ff00;
        uint Bmask = 0x000000ff;
        uint Amask = 0xff000000;

        auto surface = Image!RGBA(_charWidth, _charHeight); // allocates
        
        {
            // fill with transparent white
            surface.fill(RGBA(255, 255, 255, 0));

            for (int i = 0; i < height; ++i)
            {
                RGBA[] scanline = surface.scanline(i);
                for (int j = 0; j < width; ++j)
                {
                    ubyte source = glyphBitmap[j + i * width];
                    int destX = j + xoff;
                    int destY = i + yoff + cast(int)(0.5 + _fontAscent * _scaleFactor);

                    if (destX >= 0 && destX < _charWidth)
                    {
                        if (destY >= 0 && destY < _charHeight)
                        {
                            scanline[j].a = source; // fully white, but eventually transparent
                        }
                    }
                }
            }
        }

        // Free glyph coverage
        stbtt_FreeBitmap(glyphBitmap);
        return surface;
    }
    +/


    /// Returns: Where a line of text will be drawn if starting at position (0, 0).
    box2i measureText(StringType)(StringType s)
    {
        box2i area;
        void extendArea(int numCh, dchar ch, box2i position, float scale, float xShift, float yShift)
        {
            if (numCh == 0)
                area = box2i(x0, y0, x1, y1);
            else 
                area = area.expand(position.min).expand(position.max);
        }
        iterateCharacterPositions(s, _currentFontSizePx, &extendArea);
        return area;
    }

    /// Draw text centered on a point.
    void fillText(StringType)(RefImage!RGBA surface, StringType s, int x, int y)
    {
        box2i area = measureText(s);
        vec2i offset = vec2i(x, y) - area.center; // TODO support other alignment modes

        void drawCharacter(int numCh, dchar ch, box2i position, float scale, float xShift, float yShift)
        {
            vec2i offsetPos = position.min + offset;

            // make room in temp buffer
            int w = position.width;
            int h = position.geight;
            int stride = w;
            _greyscaleBuffer.size(w, h);

            ubyte* targetPixels = &surface.pixels[offsetPos.x, offsetPos.y];
            stbtt_MakeCodepointBitmapSubpixel(_font, _greyscaleBuffer.pixels, w, h, stride, scale, scale, xShift, yShift, ch);

            auto outsurf = surface.crop(offsetPos.x, offsetPos.y, w, h);
            int croppedWidth = outsurf.w;

            for (int y = 0; y < outsurf.h; ++y)
            {
                RGBA[] scanline = surface.scanline(y);
                L8[] inscan = outsurf.scanline(y);
                for (int x = 0; x < croppedWidth; ++x)
                {
                    RGBA finalColor = _currentColor;
                    finalColor.a = ( (_currentColor.a * inscan[x] + 128) / 255 );
                    scanline[x] = RGBA.blend(scanline[x], finalColor);
                }
            }            
        }
        iterateCharacterPositions(s, _currentFontSizePx, &drawCharacter);
    }

private:

    RGBA _currentColor; /// Current selected color for draw operations.

    float _currentFontSizePx; /// Current selected font-size (expressed in pixels)

    stbtt_fontinfo _font;    
    ubyte[] _fontData;
    int _fontAscent, _fontDescent, _fontLineGap;

    bool _initialized;

    /// Iterates on character and call the deledate with their subpixel position
    /// Only support one line of text.
    /// Use kerning.
    /// No hinting.
    void iterateCharacterPositions(StringType)(StringType text, float fontSizePx, 
                                               scope void delegate(dchar ch, box2i position, float scale, float xShift, float yShift) doSomethingWithPosition)
    {
        float scale = stbtt_ScaleForPixelHeight(_font, fontSizePx);
        float xpos = 0.0f;

        float lastxpos = 0;
        dchar lastCh;
        int maxHeight = 0;
        box2i area;
        foreach(int numCh, dchar ch; text)
        {
            if (numCh > 0)
                xpos += scale * stbtt_GetCodepointKernAdvance(&font, lastCh, ch);

            int advance,lsb,x0,y0,x1,y1;
            int ixpos = cast(int) floor(xpos);
            float xShift = xpos - floor(xpos);
            float yShift = 0;

            stbtt_GetCodepointHMetrics(_font, ch, &advance, &lsb);
            stbtt_GetCodepointBitmapBoxSubpixel(&font, ch, scale, scale, xShift, yShift, &x0, &y0, &x1, &y1);
            box2i position = box2i(x0 + ixpos, y0, x1 + ixpos, y1);
            doSomethingWithPosition(ch, position, scale, xShift, yShift); 
            xpos += (advance * scale);
            lastCh = ch;
        }
    }

    // temp-buffer before blending somewhere else
    // TODO: make it a cache instead
    Image!L8 _greyscaleBuffer;
}

