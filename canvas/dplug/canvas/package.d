/// This is a DPlug-specific rework of dg2d by Cerjones.
/// 
/// - removal of truetype functionnality (since covered by dplug:graphics)
/// - nothrow @nogc
/// - rework of the Canvas itself, to resemble more the HTML5 Canvas API
/// - Blitter delegate made explicit with a userData pointer
/// - add html color parsing
/// - no alignment requirements
/// - clipping is done with the ImageRef input
/// etc...
/**
* Copyright: Copyright Chris Jones 2020.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.canvas;

import dplug.graphics.color;
import dplug.graphics.image;
import dplug.canvas.htmlcolors;
public import dplug.canvas.rasterizer;


import dplug.canvas.colorblit;

alias ImageDest = ImageRef!RGBA;

/// 2D Canvas able to render complex pathes into a ImageRef!RGBA buffer.
/// `Canvas` tries to follow loosely the HTML 5 Canvas API, without stroking.
struct Canvas
{
public:
nothrow:
@nogc:

    /// Initialize the Canvas object with this target.
    void initialize(ImageRef!RGBA imageDest)
    {
        _imageDest = imageDest;
        fillStyle(RGBA(0, 0, 0, 255));
    }

    ~this()
    {
    }

    @disable this(this);

    void fillStyle(RGBA color)
    {
        _brushStyle = BrushStyle.plainColor;
        _fillStyleColor = color;

        uint color_as_uint = *cast(uint*)&_fillStyleColor;

        _plainColorBlitter.init(cast(ubyte*)_imageDest.pixels, 
                                _imageDest.pitch, 
                                _imageDest.h, 
                                color_as_uint);

        _currentBlitter.userData = &_plainColorBlitter;
        _currentBlitter.doBlit = &doBlit_ColorBlit;
    }

    void fillStyle(const(char)[] htmlColorString)
    {
        string error;
        RGBA rgba;
        if (parseHTMLColor(htmlColorString, rgba, error))
        {
            fillStyle(rgba);
        }
        else
            assert(false);
    }

    /// Starts a new path by emptying the list of sub-paths. Call this method when you want to create a new path.
    void beginPath()
    {
        int left = 0;
        int top = 0;
        int right = _imageDest.w;
        int bottom = _imageDest.h;
        _rasterizer.initialise(left, top, right, bottom);
    }

    /// Adds a straight line to the path, going to the start of the current sub-path.
    void closePath()
    {
        _rasterizer.closePath();
    }

    /// Moves the starting point of a new sub-path to the (x, y) coordinates.
    void moveTo(float x, float y)
    {
        _rasterizer.moveTo(x, y);
    }

    /// Connects the last point in the current sub-path to the specified (x, y) coordinates with a straight line.
    void lineTo(float x, float y)
    {
        _rasterizer.lineTo(x, y);
    }

    /// Adds a cubic Bézier curve to the current path.
    void bezierCurveTo(float cp1x, float cp1y, float cp2x, float cp2y, float x, float y)
    {
        _rasterizer.cubicTo(cp1x, cp1y, cp2x, cp2y, x, y);
    }

    /// Adds a quadratic Bézier curve to the current path.
    void quadraticCurveTo(float cpx, float cpy, float x, float y)
    {
        _rasterizer.quadTo(cpx, cpy, x, y);
    }

    void fill()
    {
        _rasterizer.rasterize(_currentBlitter);
    }

  /*  void roundRect(float x, float y, float w, float h, float r, uint color)
    {
        float lpc = r*0.44772;

        _rasterizer.initialise(m_clip.x0,m_clip.y0,m_clip.x1, m_clip.y1);

        _rasterizer.moveTo(x+r,y);
        _rasterizer.lineTo(x+w-r,y);
        _rasterizer.cubicTo(x+w-lpc,y,  x+w,y+lpc,  x+w,y+r);
        _rasterizer.lineTo(x+w,y+h-r);
        _rasterizer.cubicTo(x+w,y+h-lpc,  x+w-lpc,y+h,  x+w-r,y+h);
        _rasterizer.lineTo(x+r,y+h);
        _rasterizer.cubicTo(x+lpc,y+h,  x,y+h-lpc,  x,y+h-r);
        _rasterizer.lineTo(x,y+r);
        _rasterizer.cubicTo(x,y+lpc,  x+lpc,y,  x+r,y);

        ColorBlit cb;
        _plainColorBlitter.init(m_pixels,m_stride,m_height,color);
        _rasterizer.rasterize(cb.getBlitter(WindingRule.NonZero));
    }*/

private:

    ImageRef!RGBA _imageDest;

    enum BrushStyle
    {
        plainColor
    }

    BrushStyle _brushStyle = BrushStyle.plainColor;
    RGBA _fillStyleColor = RGBA(0, 0, 0, 255); // default to plain black

    Rasterizer   _rasterizer;

    Blitter _currentBlitter;

    // Blitters
    ColorBlit _plainColorBlitter;
}