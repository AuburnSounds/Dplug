/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.knob;

import std.math;
import dplug.gui.element;
import dplug.gui.knob;
import dplug.gui.drawex;
import dplug.plugin.params;

enum KnobStyle
{
    thumb, // with a hole
    cylinder
}

class UIKnob : UIElement, IParameterListener
{
public:

    // Modify these to customize
    float knobRadius = 0.75f;
    RGBA knobDiffuse = RGBA(233, 235, 236, 0);
    RGBA knobMaterial = RGBA(0, 255, 128, 255);
    KnobStyle style = KnobStyle.thumb;

    int numLEDs = 7;
    float LEDRadiusMin = 0.127f;
    float LEDRadiusMax = 0.127f;
    RGBA LEDDiffuse = RGBA(255, 140, 220, 0);
    float LEDDistanceFromCenter = 0.8f;
    float LEDDistanceFromCenterDragged = 0.7f;

    RGBA litTrailDiffuse = RGBA(230, 80, 43, 192);
    RGBA unlitTrailDiffuse = RGBA(150, 40, 20, 8);
    float trailRadiusMin = 0.85f;
    float trailRadiusMax = 0.97f;
    float animationTimeConstant = 40.0f;

    this(UIContext context, FloatParameter param)
    {
        super(context);
        _param = param;
        _sensivity = 0.25f;
        _param.addListener(this);
        _initialized = true;
        _pushedAnimation = 0;
        clearCrosspoints();
    }

    ~this()
    {
        if (_initialized)
        {
            debug ensureNotInGC("UIKnob");
            _param.removeListener(this);
            _initialized = false;
        }
    }

    override void onAnimate(double dt, double time)
    {
        float target = isDragged() ? 1 : 0;

        float newAnimation = lerp(_pushedAnimation, target, 1.0 - exp(-dt * animationTimeConstant));

        if (abs(newAnimation - _pushedAnimation) > 0.001f)
        {
            _pushedAnimation = newAnimation;
            setDirty();
        }
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

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        float normalizedValue = _param.getNormalized();


        // We'll draw entireyl in the largest centered square in _position.
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
        float radius = subSquare.width * 0.5f;
        float centerx = (subSquare.min.x + subSquare.max.x - 1) * 0.5f;
        float centery = (subSquare.min.y + subSquare.max.y - 1) * 0.5f;

        float knobRadiusPx = radius * knobRadius;

        float a1 = PI * 3/4;
        float a2 = a1 + PI * 1.5f * normalizedValue;
        float a3 = a1 + PI * 1.5f;

        diffuseMap.aaFillSector(cast(int)centerx, cast(int)centery, radius * trailRadiusMin, radius * trailRadiusMax, a1, a2, litTrailDiffuse);
        diffuseMap.aaFillSector(cast(int)centerx, cast(int)centery, radius * trailRadiusMin, radius * trailRadiusMax, a2, a3, unlitTrailDiffuse);

        //
        // Draw knob
        //

        float angle = (normalizedValue - 0.5f) * 4.8f;
        float depthRadius = std.algorithm.max(knobRadiusPx * 3.0f / 5.0f, 0);
        float depthRadius2 = std.algorithm.max(knobRadiusPx * 3.0f / 5.0f, 0);

        float posEdgeX = centerx + sin(angle) * depthRadius2;
        float posEdgeY = centery - cos(angle) * depthRadius2;

        ubyte emissive = 8;
        if (isMouseOver)
            emissive = 30;
        if (isDragged)
            emissive = 60;

        if (style == KnobStyle.thumb)
        {
            depthMap.softCircleFloat(centerx, centery, depthRadius, knobRadiusPx, L16(65535));
            depthMap.softCircleFloat(centerx, centery, 0, depthRadius, L16(38400));
        }
        else if (style == KnobStyle.cylinder)
        {
            L16 depth = L16(cast(ushort)(0.5f + lerp(65535.0f, 45000.0f, _pushedAnimation)) );
            depthMap.softCircleFloat(centerx, centery, knobRadiusPx - 1, knobRadiusPx, depth);
        }
        RGBA knobDiffuseLit = knobDiffuse;
            knobDiffuseLit.a = emissive;
        diffuseMap.softCircleFloat(centerx, centery, knobRadiusPx - 1, knobRadiusPx, knobDiffuseLit);        

        materialMap.softCircleFloat(centerx, centery, depthRadius - 1, depthRadius,   knobMaterial);


        // LEDs
        for (int i = 0; i < numLEDs; ++i)
        {
            float disp = i * 2 * PI / numLEDs;
            float distance = lerp(LEDDistanceFromCenter, LEDDistanceFromCenterDragged, _pushedAnimation);
            float x = centerx + sin(angle + disp) * knobRadiusPx * distance;
            float y = centery - cos(angle + disp) * knobRadiusPx * distance;

            float t = -1 + 2 * abs(disp - PI) / PI;

            float LEDRadius = std.algorithm.max(0.0f, lerp(LEDRadiusMin, LEDRadiusMax, t));

            float smallRadius = knobRadiusPx * LEDRadius * 0.714f;
            float largerRadius = knobRadiusPx * LEDRadius;

            RGBA LEDDiffuseLit = LEDDiffuse;
            LEDDiffuseLit.a = cast(ubyte)(0.5 + 40 + 215 * _pushedAnimation);                

            depthMap.softCircleFloat(x, y, 0, largerRadius, L16(65000));
            diffuseMap.softCircleFloat(x, y, 0, largerRadius, LEDDiffuseLit);
            materialMap.softCircleFloat(x, y, smallRadius, largerRadius, RGBA(128, 128, 255, defaultPhysical));
        }
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
        float displacementInHeight = cast(float)(dy) / _position.height;

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
        clearCrosspoints();
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

    /// The parameter this knob is linked with.
    FloatParameter _param;

    float _pushedAnimation;

    /// Sensivity: given a mouse movement in 100th of the height of the knob,
    /// how much should the normalized parameter change.
    float _sensivity;

    bool _initialized; // destructor flag

    float _mousePosOnLast0Cross;
    float _mousePosOnLast1Cross;

    void clearCrosspoints()
    {
        _mousePosOnLast0Cross = float.infinity;
        _mousePosOnLast1Cross = -float.infinity;
    }
}
