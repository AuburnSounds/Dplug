/**
Film-strip knob for a flat UI.

Copyright: Guillaume Piolat 2015-2018.
Copyright: Ethan Reker 2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.flatwidgets.flatknob;

import std.math;
import std.algorithm.comparison;

import dplug.core.math;

import dplug.gui.element;

import dplug.client.params;

/**
* UIFilmstripKnob is a knob with a vertical RGBA image describing the knob graphics.
*/
class UIFilmstripKnob : UIElement, IParameterListener
{
public:
nothrow:
@nogc:

    // This will change to 1.0f at one point for consistency, so better express your knob
    // sensivity with that.
    enum defaultSensivity = 0.25f;

    this(UIContext context, Parameter param, OwnedImage!RGBA mipmap, int numFrames, float sensitivity = 0.25)
    {
        super(context, flagRaw);
        _param = param;
        _sensitivity = sensitivity;
        _filmstrip = mipmap;
        _numFrames = numFrames;
        _knobWidth = _filmstrip.w;
        _knobHeight = _filmstrip.h / _numFrames;
        _param.addListener(this);
        _disabled = false;
        _filmstripScaled = mallocNew!(OwnedImage!RGBA)();
        _frameNthResized.reallocBuffer(_numFrames);
    }

    ~this()
    {
        _param.removeListener(this);
        _filmstripScaled.destroyFree();
        _frameNthResized.reallocBuffer(0);
    }

    override void reflow()
    {
        int W = position.width;
        int H = position.height * _numFrames;
        if (_filmstripScaled.w != W || _filmstripScaled.h != H)
        {
            _filmstripScaled.size(position.width, position.height * _numFrames);
            _frameNthResized[] = false;
        }
    }

    /// Returns: sensivity.
    float sensivity()
    {
        return _sensitivity;
    }

    /// Sets sensivity.
    float sensivity(float sensitivity)
    {
        return _sensitivity = sensitivity;
    }

    void disable()
    {
        _disabled = true;
    }

    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        setCurrentImage();
        ImageRef!RGBA _currentImage = _filmstripScaled.toRef().cropImageRef(box2i(_imageX1, _imageY1, _imageX2, _imageY2));
        foreach(dirtyRect; dirtyRects)
        {
            ImageRef!RGBA croppedRawIn = _currentImage.toRef().cropImageRef(dirtyRect);
            ImageRef!RGBA croppedRawOut = rawMap.cropImageRef(dirtyRect);

            int w = dirtyRect.width;
            int h = dirtyRect.height;

            for(int j = 0; j < h; ++j)
            {
                RGBA[] input = croppedRawIn.scanline(j);
                RGBA[] output = croppedRawOut.scanline(j);

                for(int i = 0; i < w; ++i)
                {
                    ubyte alpha = input[i].a;

                    RGBA color = blendColor(input[i], output[i], alpha);
                    output[i] = color;
                }
            }

        }
    }

    float distance(float x1, float x2, float y1, float y2)
    {
        return sqrt((x2-x1)*(x2-x1) + (y2-y1)*(y2-y1));
    }

    void setCurrentImage()
    {
        float value = _param.getNormalized();
        currentFrame = cast(int)(round(value * (_numFrames - 1)));

        if(currentFrame < 0) currentFrame = 0;

        _imageX1 = 0;
        _imageY1 = (_filmstripScaled.h / _numFrames) * currentFrame;

        _imageX2 = _filmstripScaled.w;
        _imageY2 = _imageY1 + (_filmstripScaled.h / _numFrames);

        cacheImage(currentFrame);
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        if (!containsPoint(x, y))
            return false;

        // double-click => set to default
        if (isDoubleClick || mstate.altPressed)
        {
            _param.beginParamEdit();
            if (auto fp = cast(FloatParameter)_param)
                fp.setFromGUI(fp.defaultValue());
            else if (auto ip = cast(IntegerParameter)_param)
                ip.setFromGUI(ip.defaultValue());
            else
                assert(false);
            _param.endParamEdit();
        }

        return true; // to initiate dragging
    }

    // Called when mouse drag this Element.
    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
        if(!_disabled)
        {
            float displacementInHeight = cast(float)(dy) / _position.height;

            float modifier = 1.0f;
            if (mstate.shiftPressed || mstate.ctrlPressed)
                modifier *= 0.1f;

            double oldParamValue = _param.getNormalized();
            double newParamValue = oldParamValue - displacementInHeight * modifier * _sensitivity;
            if (mstate.altPressed)
                newParamValue = _param.getNormalizedDefault();

            if (y > _mousePosOnLast0Cross)
                return;
            if (y < _mousePosOnLast1Cross)
                return;

            if (newParamValue <= 0 && oldParamValue > 0)
                _mousePosOnLast0Cross = y;

            if (newParamValue >= 1 && oldParamValue < 1)
                _mousePosOnLast1Cross = y;

            if (newParamValue < 0)
                newParamValue = 0;
            if (newParamValue > 1)
                newParamValue = 1;

            if (newParamValue > 0)
                _mousePosOnLast0Cross = float.infinity;

            if (newParamValue < 1)
                _mousePosOnLast1Cross = -float.infinity;

            if (newParamValue != oldParamValue)
            {
                if (auto fp = cast(FloatParameter)_param)
                    fp.setFromGUINormalized(newParamValue);
                else if (auto ip = cast(IntegerParameter)_param)
                    ip.setFromGUINormalized(newParamValue);
                else
                    assert(false);
            }
            setDirtyWhole();
        }
    }

    // For lazy updates
    override void onBeginDrag()
    {
        _param.beginParamEdit();
        setDirtyWhole();
    }

    override void onStopDrag()
    {
        _param.endParamEdit();
        clearCrosspoints();
        setDirtyWhole();
    }

    override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {

    }

    override void onMouseExit()
    {
    }

    override void onParameterChanged(Parameter sender) nothrow @nogc
    {
        setDirtyWhole();
    }

    override void onBeginParameterEdit(Parameter sender)
    {
    }

    override void onEndParameterEdit(Parameter sender)
    {
    }

protected:

    /// The parameter this knob is linked with.
    Parameter _param;

    OwnedImage!RGBA _filmstrip;
    OwnedImage!RGBA _filmstripScaled;

    deprecated OwnedImage!RGBA _faderFilmstrip;
    deprecated OwnedImage!RGBA _knobGreenFilmstrip;
    ImageRef!RGBA _currentImage;

    int _numFrames;
    int _imageX1, _imageX2, _imageY1, _imageY2;
    int currentFrame;

    int _knobWidth;
    int _knobHeight;

    float _pushedAnimation;

    /// Sensivity: given a mouse movement in 100th of the height of the knob,
    /// how much should the normalized parameter change.
    float _sensitivity;

    float _mousePosOnLast0Cross;
    float _mousePosOnLast1Cross;

    bool _disabled;

    ImageResizer _resizer;
    bool[] _frameNthResized;

    void clearCrosspoints() nothrow @nogc
    {
        _mousePosOnLast0Cross = float.infinity;
        _mousePosOnLast1Cross = -float.infinity;
    }

    final bool containsPoint(int x, int y) nothrow @nogc
    {
        vec2f center = getCenter();
        return vec2f(x, y).distanceTo(center) < getRadius();
    }

    /// Returns: largest square centered in _position
    final box2i getSubsquare() pure const nothrow @nogc
    {
        // We'll draw entirely in the largest centered square in _position.
        box2i subSquare;
        if (_position.width > _position.height)
        {
            int offset = (_position.width - _position.height) / 2;
            int minX = offset;
            subSquare = box2i(minX, 0, minX + _position.height, _position.height);
        }
        else
        {
            int offset = (_position.height - _position.width) / 2;
            int minY = offset;
            subSquare = box2i(0, minY, _position.width, minY + _position.width);
        }
        return subSquare;
    }

    final float getRadius() pure const nothrow @nogc
    {
        return getSubsquare().width * 0.5f;
    }

    final vec2f getCenter() pure const nothrow @nogc
    {
        box2i subSquare = getSubsquare();
        float centerx = (subSquare.min.x + subSquare.max.x - 1) * 0.5f;
        float centery = (subSquare.min.y + subSquare.max.y - 1) * 0.5f;
        return vec2f(centerx, centery);
    }

    // Resize sub-image lazily. Instead of doing it in `reflow()` for all frames,
    // we do it in a case by case basis when needed in `onDrawRaw`.
    void cacheImage(int frame)
    {
        // Limitation: the source image should have identically sized sub-frames.
        assert(_filmstrip.h % _numFrames == 0);

        if (_frameNthResized[frame]) 
            return;

        int hsource = _filmstrip.h / _numFrames;
        int hdest   = _filmstripScaled.h / _numFrames;

        // Note: in order to avoid slight sample offsets, each subframe needs to be resized separately.
        ImageRef!RGBA source     = _filmstrip.toRef.cropImageRef(rectangle(0, hsource * frame, _filmstrip.w, hsource));
        ImageRef!RGBA dest = _filmstripScaled.toRef.cropImageRef(rectangle(0, hdest   * frame, _filmstripScaled.w, hdest  ));
        _resizer.resizeImage_sRGBNoAlpha(source, dest);

        _frameNthResized[frame] = true;
    }
}
