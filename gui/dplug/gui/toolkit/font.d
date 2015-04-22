module dplug.gui.toolkit.font;

import std.conv;

import ae.utils.graphics;

import dplug.gui.toolkit.stb_truetype;
import dplug.gui.toolkit.renderer;

// TODO: use color
final class Font
{
public:
    this(UIRenderer renderer, string fontface, int ptSize)
    {
        _renderer = renderer;  

        _fontData = cast(ubyte[])(std.file.read(fontface));
        if (0 == stbtt_InitFont(&_font, _fontData.ptr, stbtt_GetFontOffsetForIndex(_fontData.ptr, 0)))
            throw new Exception("Coudln't load font " ~ fontface);

        _scaleFactor = stbtt_ScaleForPixelHeight(&_font, ptSize);

        stbtt_GetFontVMetrics(&_font, &_fontAscent, &_fontDescent, &_fontLineGap);

        int ax;
        stbtt_GetCodepointHMetrics(&_font, 'A', &ax, null);
        _charWidth = cast(int)(0.5 + (ax * _scaleFactor));        
        _charHeight = cast(int)(0.5 + (_fontAscent - _fontDescent + _fontLineGap) * _scaleFactor);

        _initialized = true;

        _r = 255;
        _g = 255;
        _b = 255;
        _a = 255;
    }

    ~this()
    {
        close();
    }

    void close()
    {
        if (_initialized)
        {
            _initialized = false;
        }
    }

    Image!RGBA getCharTexture(dchar ch)
    {
        if (ch == 0)
            ch = 0xFFFD;
        
        if (! (ch in _glyphCache))
        {
            _glyphCache[ch] = makeCharTexture(ch);
        }

        return _glyphCache[ch];
    }

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

    int charWidth() pure const nothrow
    {
        return _charWidth;
    }

    int charHeight() pure const nothrow
    {
        return _charHeight;
    }

    void setColor(int r, int g, int b, int a = 255)
    {
        _r = r;
        _g = g;
        _b = b;
        _a = a;
    }

    void renderString(StringType)(StringType s, int x, int y)
    {
        foreach(dchar ch; s)
        {
            Image!RGBA tex = getCharTexture(ch);
            _renderer.copy(tex, x, y);
            x += tex.w;
        }
    }

    void renderChar(dchar ch, int x, int y)
    {
        Image!RGBA tex = getCharTexture(ch);
        _renderer.copy(tex, x, y);
    }


private:

    int _r, _g, _b, _a;

    UIRenderer _renderer;
    stbtt_fontinfo _font;    
    ubyte[] _fontData;
    int _fontAscent, _fontDescent, _fontLineGap;

    Image!RGBA[dchar] _glyphCache;
    int _charWidth;
    int _charHeight;
    float _scaleFactor;
    bool _initialized;
}
