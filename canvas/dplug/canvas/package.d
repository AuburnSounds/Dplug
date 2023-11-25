/**
  2D software renderer.
  See an example of a Canvas-enabled UIElement in:
      `dplug.flatwidgets.windowresizer.UIWindowResizer`

  This is a DPlug-specific rework of dg2d by Cerjones.
  https://github.com/cerjones/dg2d
  - removal of truetype functionnality (since covered by dplug:graphics)
  - nothrow @nogc
  - rework of the Canvas itself, to resemble more the HTML5 Canvas API
  - Blitter delegate made explicit with a userData pointer
  - added html color parsing
  - no alignment requirements
  - clipping is done with the ImageRef input
  However a failure of this fork is that for transforms and stroke() support
  you do need path abstraction in the end.

  dplug:canvas is pretty fast and writes 4 pixels at once.

  Bug: you can't use it on a widget that is full-size in your plugin.
  
  Copyright: Copyright Chris Jones 2020.
  Copyright: Copyright Guillaume Piolat 2020.
  License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.canvas;

import std.math: cos, sin, tan, PI;

import dplug.core.vec;
import dplug.core.nogc;
import dplug.core.math;

import dplug.graphics.color;
import dplug.graphics.image;

import dplug.canvas.htmlcolors;
import dplug.canvas.gradient;
import dplug.canvas.colorblit;
import dplug.canvas.linearblit;
import dplug.canvas.ellipticalblit;
import dplug.canvas.rasterizer;


// dplug:canvas whole public API should live here.

public import dplug.math.vector;
public import dplug.math.box;

/// `dplug:canvas` operates on RGBA 8-bit buffers.
alias ImageDest = ImageRef!RGBA;

enum FillRule
{
    /// Fill pixels whose scanline intersects a non-zero number of edges.
    nonZero,

    /// Fill pixels whose scanline intersects an odd number of edges.
    evenOdd
}

/// A 2D Canvas able to render complex pathes into an `ImageRef!RGBA` buffer.
/// `Canvas` tries to follow loosely the HTML 5 Canvas API.
///
/// See_also: https://developer.mozilla.org/en-US/docs/Web/API/HTMLCanvasElement
///
/// Important:
///     * Only works on RGBA output.
///     * There need at least 12 extra bytes between lines (`trailingSamples = 3` in `OwnedImage`).
///       You can use OwnedImage to have that guarantee. See https://github.com/AuburnSounds/Dplug/issues/563
///       For now, avoid full-UI controls that use a Canvas.
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

        int xmaxRounded4Up = (imageDest.w + 3) & 0xfffffffc;
        assert((xmaxRounded4Up & 3) == 0);

        // This is a limitation of dplug:canvas
        // Because this rasterizer writes to 4 pixels at once at all times,
        // there need up to 3 extra samples (12 bytes) between lines.
        // You can use OwnedImage to have that guarantee.
        // Or you can avoid full-UI controls that use a Canvas.
        assert(xmaxRounded4Up*4 <= imageDest.pitch);

        _stateStack.resize(1);
        _stateStack[0].transform = Transform2D.identity();
        _stateStack[0].fillRule = FillRule.nonZero;
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

    /// Set the fill style. The fill style can be a plain color fill, a `CanvasGradient`,
    /// or an HTML-compatible text string.
    void fillStyle(RGBA color)
    {
        uint color_as_uint = *cast(uint*)&color;
        _plainColorBlit.init(cast(ubyte*)_imageDest.pixels, 
                             _imageDest.pitch, 
                             _imageDest.h, 
                             color_as_uint);
        _currentBlitter.userData = &_plainColorBlit;
        _blitType = BlitType.color;
    }
    ///ditto
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
    ///ditto
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
                _blitType = BlitType.linear;
                break;

            case CanvasGradient.Type.elliptical:
                _ellipticalGradientBlit.init(cast(ubyte*)_imageDest.pixels,
                                             _imageDest.pitch, 
                                             _imageDest.h, 
                                             gradient._gradient,
                                             gradient.x0, gradient.y0, 
                                             gradient.x1, gradient.y1, gradient.r2);
                _currentBlitter.userData = &_ellipticalGradientBlit;
                _blitType = BlitType.elliptical;
                break;

            case CanvasGradient.Type.radial:
            case CanvasGradient.Type.angular:
                assert(false); // not implemented yet
        }
    }

    /// Set the current fill rule.
    void fillRule(FillRule rule)
    {
        _stateStack[$-1].fillRule = rule;
    }
    /// Get current fill rule.
    FillRule fillRule()
    {
        return _stateStack[$-1].fillRule;
    }

    // <PATH> functions

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
        vec2f pt = transformPoint(x, y);
        _rasterizer.moveTo(pt.x, pt.y);
    }
    ///ditto
    void moveTo(vec2f point)
    {
        moveTo(point.x, point.y);
    }

    /// Connects the last point in the current sub-path to the specified (x, y) coordinates with a straight line.
    /// If several points are provided, it is equivalent to consecutive single-point `lineTo` calls.
    void lineTo(float x, float y)
    {
        vec2f pt = transformPoint(x, y);
        _rasterizer.lineTo(pt.x, pt.y);
    }
    ///ditto
    void lineTo(vec2f point)
    {
        lineTo(point.x, point.y);
    }
    ///ditto
    void lineTo(vec2f[] points...) // an helper for chaining lineTo calls.
    {
        Transform2D M = currentTransform();
        foreach(pt; points)
        {
            float fx = pt.x * M.a + pt.y * M.b + M.c;
            float fy = pt.x * M.d + pt.y * M.e + M.f;
            _rasterizer.lineTo(fx, fy);
        }
    }

    /// Adds a cubic Bézier curve to the current path.
    void bezierCurveTo(float cp1x, float cp1y, float cp2x, float cp2y, float x, float y)
    {
        vec2f cp1 = transformPoint(cp1x, cp1y);
        vec2f cp2 = transformPoint(cp2x, cp2y);
        vec2f pt = transformPoint(x, y);
        _rasterizer.cubicTo(cp1.x, cp1.y, cp2.x, cp2.y, pt.x, pt.y);
    }
    ///ditto
    void bezierCurveTo(vec2f controlPoint1, vec2f controlPoint2, vec2f dest)
    {
        bezierCurveTo(controlPoint1.x, controlPoint1.y, controlPoint2.x, controlPoint2.y, dest.x, dest.y);
    }

    /// Adds a quadratic Bézier curve to the current path.
    void quadraticCurveTo(float cpx, float cpy, float x, float y)
    {
        vec2f cp = transformPoint(cpx, cpy);
        vec2f pt = transformPoint(x, y);
        _rasterizer.quadTo(cp.x, cp.y, pt.x, pt.y);
    }
    ///ditto
    void quadraticCurveTo(vec2f controlPoint, vec2f dest)
    {
        quadraticCurveTo(controlPoint.x, controlPoint.y, dest.x, dest.y);
    }

    /// Add a rect to the current path.
    void rect(float x, float y, float width, float height)
    {
        moveTo(x, y);
        lineTo(x + width, y);
        lineTo(x + width, y + height);
        lineTo(x, y + height);
        lineTo(x, y);
    }
    ///ditto
    void rect(vec2f topLeftPoint, vec2f dimension)
    {
        rect(topLeftPoint.x, topLeftPoint.y, dimension.x, dimension.y);
    }
    ///ditto
    void rect(box2f rectangle)
    {
        rect(rectangle.min.x, rectangle.min.y, rectangle.width, rectangle.height);
    }
    ///ditto
    void rect(box2i rectangle)
    {
        rect(rectangle.min.x, rectangle.min.y, rectangle.width, rectangle.height);
    }

    /// Adds an arc to the current path (used to create circles, or parts of circles).
    void arc(float x, float y, float radius, float startAngle, float endAngle, bool anticlockwise = false)
    {
        assert(radius >= 0);

        // See https://github.com/AuburnSounds/Dplug/issues/468
        // for the complexities of startAngle, endAngle, and clockwise things

        // "If anticlockwise is false and endAngle-startAngle is equal to or 
        //  greater than 2π, or, if anticlockwise is true and startAngle-endAngle 
        //  is equal to or greater than 2π, then the arc is the whole circumference 
        //  of this ellipse, and the point at startAngle along this circle's
        //  circumference, measured in radians clockwise from the ellipse's semi-major
        //  axis, acts as both the start point and the end point."

        // "Otherwise, the points at startAngle and endAngle along this circle's
        //  circumference, measured in radians clockwise from the ellipse's 
        //  semi-major axis, are the start and end points respectively, and 
        //  the arc is the path along the circumference of this ellipse from 
        //  the start point to the end point, going anti-clockwise if 
        //  anticlockwise is true, and clockwise otherwise. Since the points 
        //  are on the ellipse, as opposed to being simply angles from zero, 
        //  the arc can never cover an angle greater than 2π radians.
        if (!anticlockwise)
        {
            float endMinusStart = endAngle - startAngle;
            if (endMinusStart >= 2 * PI)
                endMinusStart = 2 * PI;
            else
            {
                endMinusStart = normalizePhase(endMinusStart);
                if (endMinusStart < 0) endMinusStart += 2 * PI;
            }

            // Modify endAngle so that startAngle <= endAngle <= startAngle + 2 * PI
            endAngle = startAngle + endMinusStart;
            assert(endAngle >= startAngle);
        }
        else
        {
            float endMinusStart = endAngle - startAngle;
            if (endMinusStart <= -2 * PI)
                endMinusStart = -2 * PI;
            else
            {
                endMinusStart = normalizePhase(endMinusStart);
                if (endMinusStart > 0) endMinusStart -= 2 * PI;
            }

            // Modify endAngle so that startAngle >= endAngle >= startAngle - 2 * PI
            endAngle = startAngle + endMinusStart;
            assert(endAngle <= startAngle);
        }

        // find tangential start point xt,yt
        float xt = x + fast_cos(startAngle) * radius;
        float yt = y + fast_sin(startAngle) * radius;

        // Make a line to there
        lineTo(xt, yt);
        if (radius < 1e-4f) // Below 4e-5f => stack overflow in bezier split. This is invisible anyway.
            return;

        enum float MAX_ANGLE_FOR_SINGLE_BEZIER_CURVE = PI / 2.0;

        // From https://stackoverflow.com/questions/1734745/how-to-create-circle-with-b%C3%A9zier-curves
        // The optimal distance to the control points, in the sense that the 
        // middle of the curve lies on the circle itself, is (4/3)*tan(pi/(2n)).

        float angleDiff = endAngle - startAngle;
        if (startAngle == endAngle || angleDiff == 0)
            return;
        
        // How many bezier curves will we draw?
        // The angle will be evenly split between those parts.
        // The 1e-2 offset is to avoid a circle made with 5 curves.
        int numCurves = cast(int)(fast_ceil( (fast_fabs(angleDiff) - 1e-2f) / MAX_ANGLE_FOR_SINGLE_BEZIER_CURVE));
        assert(numCurves >= 0);
        if (numCurves == 0)
            numCurves = 1;

        float currentAngle = startAngle;
        float angleIncr = angleDiff / cast(float)numCurves;

        // Compute where control points should be placed
        // How many segments does this correspond to for a full 2*pi circle?
        float numCurvesIfThisWereACircle = (2.0f * PI * numCurves) / angleDiff;

        // Then compute optimal distance of the control points
        float xx = cast(float)PI / (2.0f * numCurvesIfThisWereACircle);
        float optimalDistance = (4.0f / 3.0f) * tan(xx);
        optimalDistance *= radius;

        float angle0 = startAngle;
        float cos0 = fast_cos(angle0);
        float sin0 = fast_sin(angle0);

        // Using complex rotation here to save some cos/sin operations.
        float phasorX = fast_cos(angleIncr); 
        float phasorY = fast_sin(angleIncr);

        foreach(curve; 0..numCurves) 
        {
            float cos1 = cos0 * phasorX - sin0 * phasorY;
            float sin1 = cos0 * phasorY + sin0 * phasorX;

            // compute end points of the curve
            float x0 = x + cos0 * radius;
            float y0 = y + sin0 * radius;
            float x1 = x + cos1 * radius;
            float y1 = y + sin1 * radius;

            // compute control points
            float cp0x = x0 - sin0 * optimalDistance;
            float cp0y = y0 + cos0 * optimalDistance;
            float cp1x = x1 + sin1 * optimalDistance;
            float cp1y = y1 - cos1 * optimalDistance;
            bezierCurveTo(cp0x, cp0y, cp1x, cp1y, x1, y1);

            cos0 = cos1;
            sin0 = sin1;
        }
    }
    ///ditto
    void arc(vec2f center, float radius, float startAngle, float endAngle, bool anticlockwise = false)
    {
        arc(center.x, center.y, radius, startAngle, endAngle, anticlockwise);
    }

    /// Fills all subpaths of the current path using the current `fillStyle`.
    /// Open subpaths are implicitly closed when being filled.
    void fill()
    {
        closePath();

        // Select a particular blitter function here, depending on current state.
        _currentBlitter.doBlit = getBlitFunction();

        _rasterizer.rasterize(_currentBlitter);
    }

    /// Fill a rectangle using the current `fillStyle`.
    /// Note: affects the current path.
    void fillRect(float x, float y, float width, float height)
    {
        beginPath();
        rect(x, y, width, height);
        fill();
    }
    ///ditto
    void fillRect(vec2f topLeft, vec2f dimension)
    {
        fillRect(topLeft.x, topLeft.y, dimension.x, dimension.y);
    }
    ///ditto
    void fillRect(box2f rect)
    {
        fillRect(rect.min.x, rect.min.y, rect.width, rect.height);
    }
    ///ditto
    void fillRect(box2i rect)
    {
        fillRect(rect.min.x, rect.min.y, rect.width, rect.height);
    }

    /// Fill a disc using the current `fillStyle`.
    /// Note: affects the current path.
    void fillCircle(float x, float y, float radius)
    {
        beginPath();
        moveTo(x + radius, y);
        arc(x, y, radius, 0, 2 * PI);
        fill();
    }
    ///ditto
    void fillCircle(vec2f center, float radius)
    {
        fillCircle(center.x, center.y, radius);
    }

    // </PATH> functions


    // <GRADIENT> functions

    /// Creates a linear gradient along the line given by the coordinates 
    /// represented by the parameters.
    CanvasGradient createLinearGradient(float x0, float y0, float x1, float y1)
    {
        // TODO: delay this transform upon point of use with CTM
        vec2f pt0 = transformPoint(x0, y0);
        vec2f pt1 = transformPoint(x1, y1);

        CanvasGradient result = newOrReuseGradient();
        result.type = CanvasGradient.Type.linear;
        result.x0 = pt0.x;
        result.y0 = pt0.y;
        result.x1 = pt1.x;
        result.y1 = pt1.y;
        return result;
    }
    ///ditto
    CanvasGradient createLinearGradient(vec2f pt0, vec2f pt1)
    {
        return createLinearGradient(pt0.x, pt0.y, pt1.x, pt1.y);
    }


    /// Creates a circular gradient, centered in (x, y) and going from 0 to endRadius.
    CanvasGradient createCircularGradient(float centerX, float centerY, float endRadius)
    {
        float x1 = centerX + endRadius;
        float y1 = centerY;
        float r2 = endRadius;
        return createEllipticalGradient(centerX, centerY, x1, y1, r2);
    }
    ///ditto
    CanvasGradient createCircularGradient(vec2f center, float endRadius)
    {
        return createCircularGradient(center.x, center.y, endRadius);
    }

    /// Creates an elliptical gradient.
    /// First radius is given by (x1, y1), second radius with a radius at 90° with the first one).
    CanvasGradient createEllipticalGradient(float x0, float y0, float x1, float y1, float r2)
    { 
        // TODO: delay this transform upon point of use with CTM
        vec2f pt0 = transformPoint(x0, y0);
        vec2f pt1 = transformPoint(x1, y1);

        // Transform r2 radius
        vec2f diff = vec2f(x1 - x0, y1 - y0).normalized; // TODO: this could crash with radius zero
        vec2f pt2 = vec2f(x0 - diff.y * r2, y0 + diff.x * r2);
        pt2 = transformPoint(pt2);
        float tr2 = pt2.distanceTo(pt0);

        CanvasGradient result = newOrReuseGradient();
        result.type = CanvasGradient.Type.elliptical;
        result.x0 = pt0.x;
        result.y0 = pt0.y;
        result.x1 = pt1.x;
        result.y1 = pt1.y;
        result.r2 = tr2;
        return result;
    }
    ///ditto
    CanvasGradient createEllipticalGradient(vec2f pt0, vec2f pt1, float r2)
    {
        return createEllipticalGradient(pt0.x, pt0.y, pt1.x, pt1.y, r2);
    }

    // </GRADIENT> functions


    // <STATE> functions

    /// Save:
    ///   - current transform
    void save()
    {
        _stateStack ~= _stateStack[$-1]; // just duplicate current state
    }

    /// Restores state corresponding to `save()`.
    void restore()
    {
        _stateStack.popBack();
        if (_stateStack.length == 0)
            assert(false); // too many restore() without corresponding save()
    }

    /// Retrieves the current transformation matrix.
    Transform2D currentTransform()
    {
        return _stateStack[$-1].transform;
    }
    alias getTransform = currentTransform; ///ditto

    /// Adds a rotation to the transformation matrix. The angle argument represents 
    /// a clockwise rotation angle and is expressed in radians.
    void rotate(float angle)
    {
        float cosa = cos(angle);
        float sina = sin(angle);
        curMatrix() = curMatrix().scaleMulRot(cosa, sina);
    }

    /// Adds a scaling transformation to the canvas units by x horizontally and by y vertically.
    void scale(float x, float y)
    {
        curMatrix() = curMatrix().scaleMulOpt(x, y);
    }
    ///ditto
    void scale(vec2f xy)
    {
        scale(xy.x, xy.y);
    }
    ///ditto
    void scale(float xy)
    {
        scale(xy, xy);
    }

    /// Adds a translation transformation by moving the canvas and its origin `x`
    /// horizontally and `y` vertically on the grid.
    void translate(float x, float y)
    {
        curMatrix() = curMatrix().translateMulOpt(x, y);
    }
    ///ditto
    void translate(vec2f position)
    {
        translate(position.x, position.y);
    }

    /// Multiplies the current transformation matrix with the matrix described by its arguments.
    void transform(float a, float b, float c,
                   float d, float e, float f)
    {
        curMatrix() *= Transform2D(a, c, e, 
                                   b, d, f);
    }

    void setTransform(float a, float b, float c,
                      float d, float e, float f)
    {
        curMatrix() = Transform2D(a, c, e, 
                                  b, d, f);
    }

    ///ditto
    void setTransform(Transform2D transform)
    {
        curMatrix() = transform;
    }

    /// Changes the current transformation matrix to the identity matrix.
    void resetTransform()
    {
        curMatrix() = Transform2D.identity();
    }

    // </STATE>

private:

    ImageRef!RGBA _imageDest;

    enum BrushStyle
    {
        plainColor
    }

    enum BlitType
    {
        color, // Blit is a ColorBlit
        linear,
        elliptical
    }

    Rasterizer   _rasterizer;

    Blitter _currentBlitter;
    BlitType _blitType;

    // depends upon current fill rule and blit type.
    auto getBlitFunction() pure
    {
        FillRule rule = _stateStack[$-1].fillRule;
        bool nonZero = (rule == FillRule.nonZero);
        final switch(_blitType)
        {
            case BlitType.color:
                return nonZero
                          ? &doBlit_ColorBlit_NonZero
                          : &doBlit_ColorBlit_EvenOdd;
            case BlitType.linear:
                return nonZero
                        ? &doBlit_LinearBlit_NonZero
                        : &doBlit_LinearBlit_EvenOdd;
            case BlitType.elliptical:
                return nonZero
                        ? &doBlit_EllipticalBlit_NonZero
                        : &doBlit_EllipticalBlit_EvenOdd;
        }

    }


    // Blitters (only one used at once)
    union
    {
        ColorBlit _plainColorBlit;
        LinearBlit _linearGradientBlit;
        EllipticalBlit _ellipticalGradientBlit;
    }

    // Gradient cache
    // You're expected to recreate gradient in draw code.
    int _gradientUsed; // number of gradients in _gradients in active use
    Vec!CanvasGradient _gradients; // all gradients here are created on demand, 
                                   // and possibly reusable after `initialize`

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

    // State stack.
    // Current state is the last element.
    Vec!State _stateStack;

    // What is saved by `save`.
    struct State
    {
        Transform2D transform;
        FillRule fillRule;
    }

    ref Transform2D curMatrix()
    {
        return _stateStack[$-1].transform;
    }

    vec2f transformPoint(float x, float y)
    {
        Transform2D M = currentTransform();
        float fx = x * M.a + y * M.b + M.c;
        float fy = x * M.d + y * M.e + M.f;
        return vec2f(fx, fy);
    }

    vec2f transformPoint(vec2f pt)
    {
        return transformPoint(pt.x, pt.y);
    }
}

/// Holds both gradient data/table and positioning information.
///
/// You can create a gradient with `createLinearGradient`, `createCircularGradient`, or `createEllipticalGradient`,
/// every frame.
/// Then use `addColorStop` to set the color information.
///
/// The gradient data is managed  by the `Canvas` object itself. All gradients are invalidated once
/// `initialize` has been called.
class CanvasGradient
{
public:
nothrow:
@nogc:

    this()
    {
        _gradient = mallocNew!Gradient();
    }

    /// Adds a new color stop, defined by an offset and a color, to a given canvas gradient.
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
        elliptical,
        angular,
    }

    Type type;

    void reset()
    {
        _gradient.reset();
    }

    float x0, y0, x1, y1, r2;
    Gradient _gradient;
}

/// The transform type used by dplug:canvas. It's a 3x3 float matrix
/// with the form:
/// (a b c)
/// (d e f)
/// (0 0 1)
struct Transform2D
{
pure nothrow @nogc:
    float a = 1, b = 0, c = 0, 
          d = 0, e = 1, f = 0;

    static Transform2D identity()
    {
        return Transform2D.init;
    }

    void opOpAssign(string op)(Transform2D o) if (op == "*")
    {
        //          a  b  c
        //          d  e  f
        //          0  0  1
        // a  b  c  A  B  C
        // d  e  f  D  E  F
        // 0  0  1  0  0  1
        
        float A = a * o.a + b * o.d;
        float B = a * o.b + b * o.e;
        float C = a * o.c + b * o.f + c;
        float D = d * o.a + e * o.d;
        float E = d * o.b + e * o.e;
        float F = d * o.c + e * o.f + f;
        this = Transform2D(A, B, C, D, E, F);
    }

    /// Return this * Transform2D(1, 0, x,
    ///                           0, 1, y);
    Transform2D translateMulOpt(float x, float y)
    {
        //           1  0  x
        //           0  1  y
        //           0  0  1
        //           -------
        // a  b  c | a  b  C
        // d  e  f | d  e  F
        // 0  0  1 | 0  0  1
        float C = a * x + b * y + c;
        float F = d * x + e * y + f;
        return Transform2D(a, b, C, d, e, F);
    }

    /// Return this * Transform2D(x, 0, 0,
    ///                           0, y, 0);
    Transform2D scaleMulOpt(float x, float y)
    {
        //           x  0  0
        //           0  y  0
        //           0  0  1
        //           -------
        // a  b  c | A  B  c
        // d  e  f | D  E  f
        // 0  0  1 | 0  0  1
        float A = x * a;
        float B = y * b;
        float D = x * d;
        float E = y * e;
        return Transform2D(A, B, c, D, E, f);
    }


    /// Return this * Transform2D(cosa, -sina, 0,
    ///                           sina, cosa, 0)
    Transform2D scaleMulRot(float cosa, float sina)
    {
        //           g -h  0
        //           h  g  0
        //           0  0  1
        //           -------
        // a  b  c | A  B  c
        // d  e  f | D  E  f
        // 0  0  1 | 0  0  1
        float A = cosa * a + sina * b;
        float B = cosa * b - sina * a;
        float D = cosa * d + sina * e;
        float E = cosa * e - sina * d;
        return Transform2D(A, B, c, 
                           D, E, f);
    }
}