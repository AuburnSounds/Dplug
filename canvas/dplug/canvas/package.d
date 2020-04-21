/// This is a DPlug-specific rework of dg2d by Cerjones.
/// 
/// - use of gfm:math types to avoid redefining vectors and stuff
/// - removal of truetype functionnality (since covered by dplug:graphics)
/// - nothrow @nogc
/// - rework of the Canvas itself.
/// - use of Vec instead of Array
/// - we can't use static dtor/ctor
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

alias ImageDest = ImageRef!RGBA;

/// 2D Canvas able to render complex pathes into a ImageRef!RGBA buffer.
/// `Canvas` tries to follow loosely the HTML 5 Canvas API, without stroking.
struct Canvas
{
public:
nothrow:
@nogc:

    /// Initilialize the Canvas object with this target.
    void initialize(ImageRef!RGBA imageDest)
    {
        _imageDest = imageDest;
    }

    ~this()
    {
    }

    @disable this(this);

    void fillStyle(RGBA color)
    {
        _brushStyle = BrushStyle.plainColor;
        _fillStyleColor = color;
    }

    void fillStyle(const(char)[] htmlColorString)
    {
        string error;
        RGBA rgba;
        if (parseHTMLColor(htmlColorString, rgba, error))
        {
            _brushStyle = BrushStyle.plainColor;
            _fillStyleColor = rgba;
        }
    }

private:

    ImageRef!RGBA _imageDest;

    enum BrushStyle
    {
        plainColor
    }

    BrushStyle _brushStyle = BrushStyle.plainColor;
    RGBA _fillStyleColor = RGBA(0, 0, 0, 255); // default to plain black

    Rasterizer   m_rasterizer;
}