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

import dplug.core.vec;
import dplug.core.nogc;

import dplug.graphics.color;
import dplug.graphics.image;

import dplug.canvas.htmlcolors;
import dplug.canvas.gradient;
import dplug.canvas.colorblit;
import dplug.canvas.linearblit;

import dplug.canvas.rasterizer;


// dplug:canvas whole public API should live here.

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
        _gradientUsed = 0;
        fillStyle(RGBA(0, 0, 0, 255));
    }

    ~this()
    {
        // delete all created gradients

        foreach(gradient; _gradients[])
        {
            destroyFree(gradient);
        }
    }

    @disable this(this);

    void fillStyle(RGBA color)
    {
        uint color_as_uint = *cast(uint*)&color;
        _plainColorBlit.init(cast(ubyte*)_imageDest.pixels, 
                             _imageDest.pitch, 
                             _imageDest.h, 
                             color_as_uint);
        _currentBlitter.userData = &_plainColorBlit;
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

    void fillStyle(CanvasGradient gradient)
    {
        final switch(gradient.type)
        {
            case CanvasGradient.Type.linear:
                _linearGradientBlit.init(cast(ubyte*)_imageDest.pixels,
                                         _imageDest.pitch, 
                                         _imageDest.h, 
                                         gradient._gradient,
                                         gradient.x0, gradient.y0, gradient.x1, gradient.y1);
                _currentBlitter.userData = &_linearGradientBlit;
                _currentBlitter.doBlit = &doBlit_LinearBlit;
                break;

            case CanvasGradient.Type.radial:
            case CanvasGradient.Type.angular:
                assert(false); // not implemented yet
        }
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

    /// Fills all subpaths of the current path.
    /// Open subpaths are implicitly closed when being filled.
    void fill()
    {
        closePath();
        _rasterizer.rasterize(_currentBlitter);
    }

    void fillRect(float x, float y, float width, float height)
    {
        assert(false); // it's more complicated than it seems
    }

    /// Creates a linear gradient along the line given by the coordinates 
    /// represented by the parameters.
    CanvasGradient createLinearGradient(float x0, float y0, float x1, float y1)
    {
        CanvasGradient result = newOrReuseGradient();
        result.type = CanvasGradient.Type.linear;
        result.x0 = x0;
        result.y0 = y0;
        result.x1 = x1;
        result.y1 = y1;
        return result;
    }

private:

    ImageRef!RGBA _imageDest;

    enum BrushStyle
    {
        plainColor
    }

    Rasterizer   _rasterizer;

    Blitter _currentBlitter;

    // Blitters
    ColorBlit _plainColorBlit;
    LinearBlit _linearGradientBlit;

    // Gradient cache
    // You're expected to recreate gradient in draw code.
    int _gradientUsed; // number of gradients in _gradients in active use
    Vec!CanvasGradient _gradients; // all gradients here are created on demand, 
                                   // and possibly reusable after `ìnitialize`

    CanvasGradient newOrReuseGradient()
    {
        if (_gradientUsed < _gradients.length)
        {
            _gradients[_gradientUsed].reset();
            return _gradients[_gradientUsed++];
        }
        else
        {
            CanvasGradient result = mallocNew!CanvasGradient();
            _gradients.pushBack(result);
            return result;
        }
    }
}

/// To conform with the HMLTL 5 API, this holds both the gradient data/table and 
/// positioning information.
class CanvasGradient
{
public:
nothrow:
@nogc:

    this()
    {
        _gradient = mallocNew!Gradient();
    }

    void addColorStop(float offset, RGBA color)
    {
        uint color_as_uint = *cast(uint*)(&color);
        _gradient.addStop(offset, color_as_uint);
    }

package:

    enum Type
    {
        linear,
        radial,
        angular,
    }

    Type type;

    void reset()
    {
        _gradient.reset();
    }

    float x0, y0, x1, y1;
    Gradient _gradient;
}