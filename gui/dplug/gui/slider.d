/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.slider;

import std.math;
import std.algorithm.comparison;

import dplug.core.math;
import dplug.gui.element;
import dplug.gui.drawex;
import dplug.client.params;


enum HandleStyle
{
    shapeW,
    shapeV,
    shapeA,
    shapeBlock
}

class UISlider : UIElement, IParameterListener
{
public:

    // Trail customization
    L16 trailDepth = L16(30000);
    RGBA unlitTrailDiffuse = RGBA(130, 90, 45, 5);
    RGBA litTrailDiffuse = RGBA(240, 165, 102, 130);
    float trailWidth = 0.2f;

    // Handle customization
    HandleStyle handleStyle = HandleStyle.shapeW;
    float handleHeightRatio = 0.25f;
    float handleWidthRatio = 0.7f;
    RGBA handleDiffuse = RGBA(248, 245, 233, 16);
    RGBA handleMaterial = RGBA(0, 255, 128, 255);

    this(UIContext context, FloatParameter param)
    {
        super(context);
        _param = param;
        _param.addListener(this);
        _sensivity = 1.0f;
         _pushedAnimation = 0;
        clearCrosspoints();
    }

    ~this()
    {
        debug ensureNotInGC("UISlider");
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
            setDirty();
        }
    }

    // Warning: does not respect dirtyRects!
    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        int width = _position.width;
        int height = _position.height;
        int handleHeight = cast(int)(0.5f + this.handleHeightRatio * height * (1 - 0.12f * _pushedAnimation));
        int handleWidth = cast(int)(0.5f + this.handleWidthRatio * width * (1 - 0.06f * _pushedAnimation));
        int trailWidth = cast(int)(0.5f + width * this.trailWidth);

        int handleHeightUnpushed = cast(int)(0.5f + this.handleHeightRatio * height);
        int trailMargin = cast(int)(0.5f + (handleHeightUnpushed - trailWidth) * 0.5f);
        if (trailMargin < 0) 
            trailMargin = 0;

        int trailX = cast(int)(0.5 + (width - trailWidth) * 0.5f);
        int trailHeight = height - 2 * trailMargin;

        // The switch is in a subrect

        box2i holeRect =  box2i(trailX, trailMargin, trailX + trailWidth, trailMargin + trailHeight);

        float value = _param.getNormalized();

        int posX = cast(int)(0.5f + (width - handleWidth) * 0.5f);
        int posY = cast(int)(0.5f + (1 - value) * (height - handleHeight));
        assert(posX >= 0);
        assert(posY >= 0);

        box2i handleRect = box2i(posX, posY, posX + handleWidth, posY + handleHeight);


        // Paint deeper hole
        {
            box2i holeBlack = box2i(holeRect.min.x, holeRect.min.y, holeRect.max.x, std.algorithm.max(holeRect.min.y, posY - 1));
            box2i holeLit = box2i(holeRect.min.x, std.algorithm.min(holeRect.max.y, posY + handleHeight), holeRect.max.x, holeRect.max.y);

            diffuseMap.cropImageRef(holeBlack).fill(unlitTrailDiffuse);

            // lit trail is 50% brighter when dragged
            RGBA litTrail = litTrailDiffuse;
            if (isDragged)
            {
                litTrail.a = cast(ubyte) std.algorithm.min(255, 3 * litTrail.a / 2);
            }

            diffuseMap.cropImageRef(holeLit).fill(litTrail);
            depthMap.cropImageRef(holeRect).fill(trailDepth);
        }

        // Paint handle of slider
        int emissive = handleDiffuse.a;
        if (isMouseOver && !isDragged)
            emissive += 50;
       // if (isDragged)
       //     emissive += 90;
        if (emissive > 255)
            emissive = 255;

        RGBA handleDiffuseLit = RGBA(handleDiffuse.r, handleDiffuse.g, handleDiffuse.b, cast(ubyte)emissive);        

        diffuseMap.cropImageRef(handleRect).fill(handleDiffuseLit);

        if (handleStyle == HandleStyle.shapeV)
        {
            auto c0 = L16(20000);
            auto c1 = L16(50000);

            int h0 = handleRect.min.y;
            int h1 = handleRect.center.y;
            int h2 = handleRect.max.y;

            verticalSlope(depthMap, box2i(handleRect.min.x, h0, handleRect.max.x, h1), c0, c1);
            verticalSlope(depthMap, box2i(handleRect.min.x, h1, handleRect.max.x, h2), c1, c0);
        }
        else if (handleStyle == HandleStyle.shapeA)
        {
            auto c0 = L16(50000);
            auto c1 = L16(20000);

            int h0 = handleRect.min.y;
            int h1 = handleRect.center.y;
            int h2 = handleRect.max.y;

            verticalSlope(depthMap, box2i(handleRect.min.x, h0, handleRect.max.x, h1), c0, c1);
            verticalSlope(depthMap, box2i(handleRect.min.x, h1, handleRect.max.x, h2), c1, c0);
        }
        else if (handleStyle == HandleStyle.shapeW)
        {
            auto c0 = L16(15000);
            auto c1 = L16(65535);
            auto c2 = L16(51400);

            int h0 = handleRect.min.y;
            int h1 = (handleRect.min.y * 3 + handleRect.max.y + 2) / 4;
            int h2 = handleRect.center.y;
            int h3 = (handleRect.min.y + handleRect.max.y * 3 + 2) / 4;
            int h4 = handleRect.max.y;

            verticalSlope(depthMap, box2i(handleRect.min.x, h0, handleRect.max.x, h1), c0, c1);
            verticalSlope(depthMap, box2i(handleRect.min.x, h1, handleRect.max.x, h2), c1, c2);
            verticalSlope(depthMap, box2i(handleRect.min.x, h2, handleRect.max.x, h3), c2, c1);
            verticalSlope(depthMap, box2i(handleRect.min.x, h3, handleRect.max.x, h4), c1, c0);
        }
        else if (handleStyle == HandleStyle.shapeBlock)
        {
            depthMap.cropImageRef(handleRect).fill(L16(50000));
        }

        materialMap.cropImageRef(handleRect).fill(handleMaterial);
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        // double-click => set to default
        if (isDoubleClick)
        {
            _param.setFromGUI(_param.defaultValue());
        }

        return true; // to initiate dragging
    }

    // Called when mouse drag this Element.
    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
        float displacementInHeight = cast(float)(dy) / _position.height; // TODO: replace by actual trail height instead of total height

        float modifier = 1.0f;
        if (mstate.shiftPressed || mstate.ctrlPressed)
            modifier *= 0.1f;

        double oldParamValue = _param.getNormalized();
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
            _param.setFromGUINormalized(newParamValue);
    }

    // For lazy updates
    override void onBeginDrag()
    {
        _param.beginParamEdit();
        setDirty();
    }

    override  void onStopDrag()
    {
        _param.endParamEdit();
        setDirty();
    }

    override void onMouseEnter()
    {
        setDirty();
    }

    override void onMouseExit()
    {
        setDirty();
    }

    override void onParameterChanged(Parameter sender) nothrow @nogc
    {
        setDirty();
    }

    override void onBeginParameterEdit(Parameter sender)
    {
    }

    override void onEndParameterEdit(Parameter sender)
    {
    }

protected:

    /// The parameter this switch is linked with.
    FloatParameter _param;

    /// Sensivity: given a mouse movement in 100th of the height of the knob,
    /// how much should the normalized parameter change.
    float _sensivity;

    float  _pushedAnimation;

    float _mousePosOnLast0Cross;
    float _mousePosOnLast1Cross;

    void clearCrosspoints()
    {
        _mousePosOnLast0Cross = float.infinity;
        _mousePosOnLast1Cross = -float.infinity;
    }
}
