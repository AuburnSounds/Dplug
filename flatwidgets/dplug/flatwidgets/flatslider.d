/**
Film-strip slider.

Copyright: Guillaume Piolat 2015.
Copyright: Ethan Reker 2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/

module dplug.flatwidgets.flatslider;

import std.math;
import std.algorithm.comparison;

import dplug.core.math;
import dplug.graphics.drawex;
import dplug.gui.bufferedelement;
import dplug.client.params;

class UIFilmstripSlider : UIElement, IParameterListener
{
public:
nothrow:
@nogc:

    this(UIContext context, FloatParameter param, OwnedImage!RGBA mipmap, int numFrames, float sensitivity = 0.25)
    {
        super(context);
        _param = param;
        _sensivity = sensitivity;
        _filmstrip = mipmap;
        _numFrames = numFrames;
        _knobWidth = _filmstrip.w;
        _knobHeight = _filmstrip.h / _numFrames;
        _disabled = false;
    }

    ~this()
    {
        _param.removeListener(this);
    }

    /// Returns: sensivity.
    float sensivity()
    {
        return _sensivity;
    }

    /// Sets sensivity.
    float sensivity(float sensivity)
    {
        return _sensivity = sensivity;
    }

    override void onAnimate(double dt, double time) nothrow @nogc
    {
        float target = isDragged() ? 1 : 0;
        float newAnimation = lerp(_pushedAnimation, target, 1.0 - exp(-dt * 30));
        if (abs(newAnimation - _pushedAnimation) > 0.001f)
        {
            _pushedAnimation = newAnimation;
            setDirtyWhole();
        }
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        setCurrentImage();
        auto _currentImage = _filmstrip.crop(box2i(_imageX1, _imageY1, _imageX2, _imageY2));
        foreach(dirtyRect; dirtyRects){

            auto croppedDiffuseIn = _currentImage.crop(dirtyRect);
            auto croppedDiffuseOut = diffuseMap.crop(dirtyRect);

            int w = dirtyRect.width;
            int h = dirtyRect.height;

            for(int j = 0; j < h; ++j){

                RGBA[] input = croppedDiffuseIn.scanline(j);
                RGBA[] output = croppedDiffuseOut.scanline(j);


                for(int i = 0; i < w; ++i){
                    ubyte alpha = input[i].a;

                    RGBA color = RGBA.op!q{.blend(a, b, c)} (input[i], output[i], alpha);
                    output[i] = color;
                }
            }

        }
    }

    void setCurrentImage()
    {
        float value = _param.getNormalized();
        currentFrame = cast(int)(round(value * (_numFrames - 1)));

        if(currentFrame < 0) currentFrame = 0;
        if(currentFrame > 59) currentFrame = 59;

        _imageX1 = 0;
        _imageY1 = (_filmstrip.h / _numFrames) * currentFrame;

        _imageX2 = _filmstrip.w;
        _imageY2 = _imageY1 + (_filmstrip.h / _numFrames);

    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        // double-click => set to default
        if (isDoubleClick)
        {
            _param.beginParamEdit();
            if (auto p = cast(FloatParameter)_param)
                p.setFromGUI(p.defaultValue());
            else if (auto p = cast(IntegerParameter)_param)
                p.setFromGUI(p.defaultValue());
            else
                assert(false); // only integer and float parameters supported
            _param.endParamEdit();
        }

        return true; // to initiate dragging
    }

    // Called when mouse drag this Element.
    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
        // FUTURE: replace by actual trail height instead of total height
        if(!_disabled)
        {
            float displacementInHeight = cast(float)(dy) / _position.height; 

            float modifier = 1.0f;
            if (mstate.shiftPressed || mstate.ctrlPressed)
                modifier *= 0.1f;

            double oldParamValue = _param.getNormalized() + _draggingDebt;
            double newParamValue = oldParamValue - displacementInHeight * modifier * _sensivity;

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
                if (auto p = cast(FloatParameter)_param)
                {
                    p.setFromGUINormalized(newParamValue);
                }
                /*else if (auto p = cast(IntegerParameter)_param)
                {
                    p.setFromGUINormalized(newParamValue);
                    _draggingDebt = newParamValue - p.getNormalized();
                }*/
                else
                    assert(false); // only integer and float parameters supported
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
        setDirtyWhole();
        _draggingDebt = 0.0f;
    }

    override void onMouseEnter()
    {
    }

    override void onMouseExit()
    {
    }

    override void onParameterChanged(Parameter sender)
    {
        setDirtyWhole();
    }

    override void onBeginParameterEdit(Parameter sender)
    {
    }

    override void onEndParameterEdit(Parameter sender)
    {
    }

    void disable()
    {
        _disabled = true;
    }

protected:

    /// The parameter this switch is linked with.
    Parameter _param;

    OwnedImage!RGBA _filmstrip;
    int _numFrames;
    int _imageX1, _imageX2, _imageY1, _imageY2;
    int currentFrame;

    int _knobWidth;
    int _knobHeight;

    /// Sensivity: given a mouse movement in 100th of the height of the knob,
    /// how much should the normalized parameter change.
    float _sensivity;

    float  _pushedAnimation;

    float _mousePosOnLast0Cross;
    float _mousePosOnLast1Cross;

    // Exists because small mouse drags for integer parameters may not 
    // lead to a parameter value change, hence a need to accumulate those drags.
    float _draggingDebt = 0.0f;

    bool _disabled;

    void clearCrosspoints()
    {
        _mousePosOnLast0Cross = float.infinity;
        _mousePosOnLast1Cross = -float.infinity;
    }
}
