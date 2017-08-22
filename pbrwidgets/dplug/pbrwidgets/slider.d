/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.pbrwidgets.slider;

import std.math;
import std.algorithm.comparison;

import dplug.core.math;
import dplug.graphics.drawex;
import dplug.gui.bufferedelement;
import dplug.client.params;


enum HandleStyle
{
    shapeW,
    shapeV,
    shapeA,
    shapeBlock
}

class UISlider : UIBufferedElement, IParameterListener
{
public:
nothrow:
@nogc:

    // Trail customization
    L16 trailDepth = L16(30000);
    RGBA unlitTrailDiffuse = RGBA(130, 90, 45, 5);
    RGBA litTrailDiffuse = RGBA(240, 165, 102, 130);
    float trailWidth = 0.2f;

    RGBA litTrailDiffuseAlt = RGBA(240, 165, 102, 130);
    bool hasAlternateTrail = false;
    float trailBase = 0.0f; // trail is from trailBase to parameter value

    // Handle customization
    HandleStyle handleStyle = HandleStyle.shapeW;
    float handleHeightRatio = 0.25f;
    float handleWidthRatio = 0.7f;
    RGBA handleDiffuse = RGBA(248, 245, 233, 16);
    RGBA handleMaterial = RGBA(0, 255, 128, 255);

    this(UIContext context, Parameter param)
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

    override void onDrawBuffered(ImageRef!RGBA diffuseMap, 
                                 ImageRef!L16 depthMap, 
                                 ImageRef!RGBA materialMap,
                                 ImageRef!L8 diffuseOpacity,
                                 ImageRef!L8 depthOpacity,
                                 ImageRef!L8 materialOpacity) nothrow @nogc
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


        // Dig hole and paint trail deeper hole
        {


            depthMap.cropImageRef(holeRect).fillAll(trailDepth);

            // Fill opacity for hole
            diffuseOpacity.cropImageRef(holeRect).fillAll(opacityFullyOpaque);
            depthOpacity.cropImageRef(holeRect).fillAll(opacityFullyOpaque);

            int valueToTrail(float value) nothrow @nogc
            {
                return cast(int)(0.5f + (1 - value) * (height+4 - handleHeight) + handleHeight*0.5f - 2);
            }

            void paintTrail(float from, float to, RGBA diffuse) nothrow @nogc
            {
                int ymin = valueToTrail(from);
                int ymax = valueToTrail(to);
                if (ymin > ymax)
                {
                    int temp = ymin;
                    ymin = ymax;
                    ymax = temp;
                }
                box2i b = box2i(holeRect.min.x, ymin, holeRect.max.x, ymax);
                diffuseMap.cropImageRef(b).fillAll(diffuse);
            }

            
        
            RGBA litTrail = (value >= trailBase) ? litTrailDiffuse : litTrailDiffuseAlt;                  
            if (isDragged)
            {
                // lit trail is 50% brighter when dragged      
                litTrail.a = cast(ubyte) std.algorithm.min(255, 3 * litTrail.a / 2);
            }

            paintTrail(0, 1, unlitTrailDiffuse);
            paintTrail(trailBase, value, litTrail);
        }

        // Paint handle of slider
        int emissive = handleDiffuse.a;
        if (isMouseOver && !isDragged)
            emissive += 50;
        if (emissive > 255)
            emissive = 255;

        RGBA handleDiffuseLit = RGBA(handleDiffuse.r, handleDiffuse.g, handleDiffuse.b, cast(ubyte)emissive);        

        diffuseMap.cropImageRef(handleRect).fillAll(handleDiffuseLit);

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
            depthMap.cropImageRef(handleRect).fillAll(L16(50000));
        }

        materialMap.cropImageRef(handleRect).fillAll(handleMaterial);

        // Fill opacity for handle
        diffuseOpacity.cropImageRef(handleRect).fillAll(opacityFullyOpaque);
        depthOpacity.cropImageRef(handleRect).fillAll(opacityFullyOpaque);
        materialOpacity.cropImageRef(handleRect).fillAll(opacityFullyOpaque);
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        // double-click => set to default
        if (isDoubleClick)
        {
            if (auto p = cast(FloatParameter)_param)
            {
                p.beginParamEdit();
                p.setFromGUI(p.defaultValue());
                p.endParamEdit();
            }
            else if (auto p = cast(IntegerParameter)_param)
            {
                p.beginParamEdit();
                p.setFromGUI(p.defaultValue());
                p.endParamEdit();
            }
            else
                assert(false); // only integer and float parameters supported
        }

        return true; // to initiate dragging
    }

    // Called when mouse drag this Element.
    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
        // FUTURE: replace by actual trail height instead of total height
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
            else if (auto p = cast(IntegerParameter)_param)
            {
                p.setFromGUINormalized(newParamValue);
                _draggingDebt = newParamValue - p.getNormalized();
            }
            else
                assert(false); // only integer and float parameters supported
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
        setDirtyWhole();
    }

    override void onMouseExit()
    {
        setDirtyWhole();
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

protected:

    /// The parameter this switch is linked with.
    Parameter _param;

    /// Sensivity: given a mouse movement in 100th of the height of the knob,
    /// how much should the normalized parameter change.
    float _sensivity;

    float  _pushedAnimation;

    float _mousePosOnLast0Cross;
    float _mousePosOnLast1Cross;

    // Exists because small mouse drags for integer parameters may not 
    // lead to a parameter value change, hence a need to accumulate those drags.
    float _draggingDebt = 0.0f;

    void clearCrosspoints()
    {
        _mousePosOnLast0Cross = float.infinity;
        _mousePosOnLast1Cross = -float.infinity;
    }
}
