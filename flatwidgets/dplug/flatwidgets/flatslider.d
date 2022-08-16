/**
Film-strip slider.

Copyright: Guillaume Piolat 2015-2018.
Copyright: Ethan Reker 2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/

module dplug.flatwidgets.flatslider;

import std.math;
import std.algorithm.comparison;

import dplug.core.math;
import dplug.gui.bufferedelement;
import dplug.client.params;

class UIFilmstripSlider : UIElement, IParameterListener
{
public:
nothrow:
@nogc:

    enum Direction
    {
        vertical,
        horizontal
    }

    @ScriptProperty Direction direction = Direction.vertical;

    this(UIContext context, FloatParameter param, OwnedImage!RGBA sliderImage, int numFrames, float sensitivity = 0.25)
    {
        super(context, flagRaw);
        _param = param;
        _param.addListener(this);
        _sensivity = sensitivity;

        // Borrow original image.
        _filmstrip = sliderImage;
        _numFrames = numFrames;
        _frameHeightOrig = _filmstrip.h / _numFrames;

        _disabled = false;
        _filmstripResized = mallocNew!(OwnedImage!RGBA)();
    }

    ~this()
    {
        destroyFree(_filmstripResized);
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

    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        assert(position.width != 0);
        assert(position.height != 0); // does this hold though?

        // Get frame coordinate in _filmstripResized
        float value = _param.getNormalized();
        int frame = cast(int)(round(value * (_numFrames - 1)));
        if(frame >= _numFrames) 
            frame = _numFrames - 1;

        if(frame < 0) 
            frame = 0;

        assert(frame >= 0 && frame < _numFrames);
        assert(_filmstripResized.h == position.height * _numFrames);
        int frameHeightResized = _filmstripResized.h / _numFrames;

        int x1 = 0;
        int y1 = frameHeightResized * frame;
        
        assert(y1 + position.height <= _filmstripResized.h);

        box2i resizedRect = rectangle(x1, y1, position.width, position.height);
        ImageRef!RGBA frameImage = _filmstripResized.toRef.cropImageRef(resizedRect);

        foreach(dirtyRect; dirtyRects)
        {
            ImageRef!RGBA croppedImage = frameImage.cropImageRef(dirtyRect);
            ImageRef!RGBA croppedRaw = rawMap.cropImageRef(dirtyRect);

            int w = dirtyRect.width;
            int h = dirtyRect.height;

            for(int j = 0; j < h; ++j)
            {
                const(RGBA)* input = croppedImage.scanline(j).ptr;
                RGBA* output       = croppedRaw.scanline(j).ptr;

                for(int i = 0; i < w; ++i)
                {
                    ubyte alpha = input[i].a;
                    output[i] = blendColor(input[i], output[i], alpha);
                }
            }
        }
    }

    override void reflow()
    {
        // If target size is position.width x position.height, then
        // slider image must be resized to position.width x (position.height x _numFrames).

        int usefulInputPixelHeight = _numFrames * _frameHeightOrig;
        assert(usefulInputPixelHeight <= _filmstrip.h);

        box2i origRect = rectangle(0, 0, _filmstrip.w, usefulInputPixelHeight);        
        ImageRef!RGBA originalInput = _filmstrip.toRef().cropImageRef(origRect);

        _filmstripResized.size(position.width, position.height * _numFrames);

        // PERF: if we do like in flatknob.d, we can avoid resizing the whole image, and just resize just-in-time
        //       the one frame we need. Which is better for fast resize.
        context.globalImageResizer.resizeImage_sRGBWithAlpha(originalInput, _filmstripResized.toRef);
    }  

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        // double-click => set to default
        if (isDoubleClick || mstate.altPressed)
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
            float referenceCoord;
            float displacementInHeight;
            if (direction == Direction.vertical)
            {
                referenceCoord = y;
                displacementInHeight = cast(float)(dy) / _position.height;
            }
            else
            {
                referenceCoord = -x;
                displacementInHeight = cast(float)(-dx) / _position.width;
            }

            float modifier = 1.0f;
            if (mstate.shiftPressed || mstate.ctrlPressed)
                modifier *= 0.1f;

            double oldParamValue = _param.getNormalized() + _draggingDebt;
            double newParamValue = oldParamValue - displacementInHeight * modifier * _sensivity;
            if (mstate.altPressed)
                newParamValue = _param.getNormalizedDefault();

            if (referenceCoord > _mousePosOnLast0Cross)
                return;
            if (referenceCoord < _mousePosOnLast1Cross)
                return;

            if (newParamValue <= 0 && oldParamValue > 0)
                _mousePosOnLast0Cross = referenceCoord;

            if (newParamValue >= 1 && oldParamValue < 1)
                _mousePosOnLast1Cross = referenceCoord;

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

    /// Original slider image.
    OwnedImage!RGBA _filmstrip;

    /// Resized slider image, full.
    OwnedImage!RGBA _filmstripResized;

    /// The number of slider image frames contained in the _filmstrip image.
    int _numFrames;

    /// The pixel height of slider frames in _filmstrip image.
    /// _frameHeightOrig x _numFrames is the useful range of pixels, excess ones aren't used, if any.
    int _frameHeightOrig;

    /// Sensivity: given a mouse movement in 100th of the height of the knob,
    /// how much should the normalized parameter change.
    float _sensivity;


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
