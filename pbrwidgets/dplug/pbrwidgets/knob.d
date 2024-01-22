/**
Knob.

Copyright: Copyright Auburn Sounds 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Guillaume Piolat
*/
module dplug.pbrwidgets.knob;

import std.math: PI, exp, abs, sin, cos;

import dplug.core.math;

import dplug.gui.element;

import dplug.client.params;

enum KnobStyle
{
    thumb, // with a hole
    cylinder,
    cone,
    ball
}

class UIKnob : UIElement, IParameterListener
{
public:
nothrow:
@nogc:

    // This will change to 1.0f at one point for consistency, so better express your knob
    // sensivity with that.
    enum defaultSensivity = 0.25f;

    //
    // Modify these public members to customize knobs!
    //
    @ScriptProperty float knobRadius = 0.75f;
    @ScriptProperty RGBA knobDiffuse = RGBA(233, 235, 236, 0); // Last channel is ignored.
    @ScriptProperty RGBA knobMaterial = RGBA(0, 255, 128, 255);
    @ScriptProperty KnobStyle style = KnobStyle.thumb;
    @ScriptProperty ubyte emissive = 0;
    @ScriptProperty ubyte emissiveHovered = 30;
    @ScriptProperty ubyte emissiveDragged = 0;

    // LEDs
    @ScriptProperty int numLEDs = 7;
    @ScriptProperty float LEDRadiusMin = 0.127f;
    @ScriptProperty float LEDRadiusMax = 0.127f;
    @ScriptProperty RGBA LEDDiffuseLit = RGBA(255, 140, 220, 215);
    @ScriptProperty RGBA LEDDiffuseUnlit = RGBA(255, 140, 220, 40);
    @ScriptProperty RGBA LEDMaterial = RGBA(128, 128, 255, 255);
    @ScriptProperty float LEDDistanceFromCenter = 0.8f;
    @ScriptProperty float LEDDistanceFromCenterDragged = 0.7f;
    @ScriptProperty ushort LEDDepth = 65000;

    // trail
    @ScriptProperty bool hasTrail = true;
    @ScriptProperty RGBA litTrailDiffuse = RGBA(230, 80, 43, 192);
    @ScriptProperty RGBA unlitTrailDiffuse = RGBA(150, 40, 20, 8);
    @ScriptProperty float trailRadiusMin = 0.85f;
    @ScriptProperty float trailRadiusMax = 0.97f;
    @ScriptProperty float trailOffsetX = 0.0f; // in ratio of knob size
    @ScriptProperty float trailOffsetY = 0.0f; // in ratio of knob size

    @ScriptProperty float trailMinAngle = -PI * 0.75f;
    @ScriptProperty float trailBaseAngle = -PI * 0.75f;
    @ScriptProperty float trailMaxAngle = +PI * 0.75f;

    // alternate trail is for values below base angle
    // For example, knob trails can be blue for positive values,
    // and orange for negative.
    @ScriptProperty RGBA litTrailDiffuseAlt = RGBA(43, 80, 230, 192);
    @ScriptProperty bool hasAlternateTrail = false;


    @ScriptProperty float animationTimeConstant = 40.0f;

    this(UIContext context, Parameter param)
    {
        super(context, flagAnimated | flagPBR);
        _param = param;
        _sensivity = defaultSensivity;
        _param.addListener(this);
        _pushedAnimation = 0;
        clearCrosspoints();
        setCursorWhenDragged(MouseCursor.hidden);
        setCursorWhenMouseOver(MouseCursor.move);
    }

    ~this()
    {
        _param.removeListener(this);
    }

    override void onAnimate(double dt, double time) nothrow @nogc
    {
        float target = isDragged() ? 1 : 0;

        float newAnimation = lerp(_pushedAnimation, target, 1.0 - exp(-dt * animationTimeConstant));

        if (abs(newAnimation - _pushedAnimation) > 0.001f)
        {
            _pushedAnimation = newAnimation;
            setDirtyWhole();
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

    override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        if (hasTrail)
            drawTrail(diffuseMap, depthMap, materialMap, dirtyRects);
        drawKnob(diffuseMap, depthMap, materialMap, dirtyRects);
    }

    void drawTrail(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        float radius = getRadius();
        vec2f center = getCenter();

        float knobRadiusPx = radius * knobRadius;

        vec2f trailOffset = vec2f(knobRadiusPx * trailOffsetX, knobRadiusPx * trailOffsetY);

        // Eventually, use the alternative trail color
        RGBA litTrail = litTrailDiffuse;
        bool alternateTrail = false;
        if (getValueAngle < getBaseAngle)
        {
            alternateTrail = true;
            if (hasAlternateTrail)
            {
                litTrail = litTrailDiffuseAlt;
            }
        }

        // when dragged, trail is two times brighter
        if (isDragged)
        {
            int alpha = 2 * litTrail.a;
            if (alpha > 255) alpha = 255;
            litTrail.a = cast(ubyte) alpha;
        }

        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuse = diffuseMap.cropImageRef(dirtyRect);
            auto croppedDepth = depthMap.cropImageRef(dirtyRect);
            auto croppedMaterial = materialMap.cropImageRef(dirtyRect);

            int bx = dirtyRect.min.x;
            int by = dirtyRect.min.y;

            //
            // Draw trail
            //
            {
                float trailCenterX = center.x - bx + trailOffset.x;
                float trailCenterY = center.y - by + trailOffset.y;

                float valueAngle = getValueAngle();
                float minAngle = getMinAngle();
                float maxAngle = getMaxAngle();
                float baseAngle = getBaseAngle();

                // Order is minAngle <= valueAngle-when-alt <= baseAngle <= valueAngle-when-not-alt <= maxAngle

                float rmin = radius * trailRadiusMin;
                float rmax = radius * trailRadiusMax;

                // trail below baseAngle
                if (alternateTrail)
                {
                    croppedDiffuse.aaFillSector(trailCenterX, trailCenterY, rmin, rmax, minAngle, valueAngle, unlitTrailDiffuse);
                    croppedDiffuse.aaFillSector(trailCenterX, trailCenterY, rmin, rmax, valueAngle, baseAngle, litTrail);
                }
                else
                {
                    croppedDiffuse.aaFillSector(trailCenterX, trailCenterY, rmin, rmax, minAngle, baseAngle, unlitTrailDiffuse);
                }

                // trail above baseAngle
                if (alternateTrail)
                {
                    croppedDiffuse.aaFillSector(trailCenterX, trailCenterY, rmin, rmax, baseAngle, maxAngle, unlitTrailDiffuse);
                }
                else
                {
                    croppedDiffuse.aaFillSector(trailCenterX, trailCenterY, rmin, rmax, baseAngle, valueAngle, litTrail);
                    croppedDiffuse.aaFillSector(trailCenterX, trailCenterY, rmin, rmax, valueAngle, maxAngle, unlitTrailDiffuse);
                }
            }
        }
    }

    void drawKnob(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        float radius = getRadius();
        vec2f center = getCenter();

        float knobRadiusPx = radius * knobRadius;

        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuse = diffuseMap.cropImageRef(dirtyRect);
            auto croppedDepth = depthMap.cropImageRef(dirtyRect);
            auto croppedMaterial = materialMap.cropImageRef(dirtyRect);

            int bx = dirtyRect.min.x;
            int by = dirtyRect.min.y;

            //
            // Draw knob
            //
            float angle = getValueAngle + PI * 0.5f;
            float depthRadius = knobRadiusPx * 3.0f / 5.0f;
            if (depthRadius < 0) 
                depthRadius = 0;
            float depthRadius2 = knobRadiusPx * 3.0f / 5.0f;
            if (depthRadius2 < 0) 
                depthRadius2 = 0;

            float posEdgeX = center.x + sin(angle) * depthRadius2;
            float posEdgeY = center.y - cos(angle) * depthRadius2;

            ubyte emissiveComputed = emissive;
            if (_shouldBeHighlighted)
                emissiveComputed = emissiveHovered;
            if (isDragged)
                emissiveComputed = emissiveDragged;

            if (style == KnobStyle.thumb)
            {
                croppedDepth.aaSoftDisc(center.x - bx, center.y - by, depthRadius, knobRadiusPx, L16(65535));
                croppedDepth.aaSoftDisc(center.x - bx, center.y - by, 0, depthRadius, L16(38400));
            }
            else if (style == KnobStyle.cylinder)
            {
                L16 depth = L16(cast(ushort)(0.5f + lerp(65535.0f, 45000.0f, _pushedAnimation)) );
                croppedDepth.aaSoftDisc(center.x - bx, center.y - by, knobRadiusPx - 5, knobRadiusPx, depth);
            }
            else if (style == KnobStyle.cone)
            {
                L16 depth = L16(cast(ushort)(0.5f + lerp(65535.0f, 45000.0f, _pushedAnimation)) );
                croppedDepth.aaSoftDisc(center.x - bx, center.y - by, 0, knobRadiusPx, depth);
            }
            else if (style == KnobStyle.ball)
            {
                L16 depth = L16(cast(ushort)(0.5f + lerp(65535.0f, 45000.0f, _pushedAnimation)) );
                croppedDepth.aaSoftDisc!1.2f(center.x - bx, center.y - by, 2, knobRadiusPx, depth);
            }
            RGBA knobDiffuseLit = knobDiffuse;
            knobDiffuseLit.a = emissiveComputed;
            croppedDiffuse.aaSoftDisc(center.x - bx, center.y - by, knobRadiusPx - 1, knobRadiusPx, knobDiffuseLit);
            croppedMaterial.aaSoftDisc(center.x - bx, center.y - by, knobRadiusPx - 5, knobRadiusPx, knobMaterial);


            // LEDs
            for (int i = 0; i < numLEDs; ++i)
            {
                float disp = i * 2 * PI / numLEDs;
                float distance = lerp(LEDDistanceFromCenter, LEDDistanceFromCenterDragged, _pushedAnimation);
                float x = center.x + sin(angle + disp) * knobRadiusPx * distance;
                float y = center.y - cos(angle + disp) * knobRadiusPx * distance;

                float t = -1 + 2 * abs(disp - PI) / PI;

                float LEDRadius = lerp(LEDRadiusMin, LEDRadiusMax, t);
                if (LEDRadius < 0)
                    LEDRadius = 0;

                float smallRadius = knobRadiusPx * LEDRadius * 0.714f;
                float largerRadius = knobRadiusPx * LEDRadius;

                RGBA LEDDiffuse;
                LEDDiffuse.r = cast(ubyte)lerp!float(LEDDiffuseUnlit.r, LEDDiffuseLit.r, _pushedAnimation);
                LEDDiffuse.g = cast(ubyte)lerp!float(LEDDiffuseUnlit.g, LEDDiffuseLit.g, _pushedAnimation);
                LEDDiffuse.b = cast(ubyte)lerp!float(LEDDiffuseUnlit.b, LEDDiffuseLit.b, _pushedAnimation);
                LEDDiffuse.a = cast(ubyte)lerp!float(LEDDiffuseUnlit.a, LEDDiffuseLit.a, _pushedAnimation);

                croppedDepth.aaSoftDisc(x - bx, y - by, 0, largerRadius, L16(LEDDepth));
                croppedDiffuse.aaSoftDisc(x - bx, y - by, 0, largerRadius, LEDDiffuse);
                croppedMaterial.aaSoftDisc(x - bx, y - by, smallRadius, largerRadius, LEDMaterial);
            }
        }
    }

    /// Override this to round the parameter normalized value to some particular values.
    /// For example for a special drag movement with right-click or control-click.
    /// Default does nothing.
    /// Params:
    ///      normalizedValue The main parameter normalized value (0 to 1).
    /// Returns: the mapped value in normalized space (0 to 1).
    double roundParamValue(double normalizedValue, MouseState mstate)
    {
        return normalizedValue;
    }

    override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        if (!containsPoint(x, y))
            return Click.unhandled;

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

        _normalizedValueWhileDragging = _param.getNormalized();
        _displacementInHeightDebt = 0;
        return Click.startDrag;
    }

    // Called when mouse drag this Element.
    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
        _displacementInHeightDebt += cast(float)(dy) / _position.height;

        float modifier = 1.0f;
        if (mstate.shiftPressed || mstate.ctrlPressed)
            modifier *= 0.1f;

        double oldParamValue = _normalizedValueWhileDragging;
        double newParamValue = oldParamValue - _displacementInHeightDebt * modifier * _sensivity;
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

        newParamValue = roundParamValue(newParamValue, mstate);

        if (newParamValue != oldParamValue)
        {
            if (auto fp = cast(FloatParameter)_param)
                fp.setFromGUINormalized(newParamValue);
            else if (auto ip = cast(IntegerParameter)_param)
                ip.setFromGUINormalized(newParamValue);
            else
                assert(false);
            _normalizedValueWhileDragging = newParamValue;
            _displacementInHeightDebt = 0;
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
        _shouldBeHighlighted = containsPoint(x, y);
        setDirtyWhole();
    }

    override void onMouseEnter()
    {
        _param.beginParamHover();
    }

    override void onMouseExit()
    {
        _param.endParamHover();
        _shouldBeHighlighted = false;
        setDirtyWhole();
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

    override void onBeginParameterHover(Parameter sender)
    {
    }

    override void onEndParameterHover(Parameter sender)
    {
    }

protected:

    /// The parameter this knob is linked with.
    Parameter _param;

    float _pushedAnimation;

    /// Sensivity: given a mouse movement in 100th of the height of the knob,
    /// how much should the normalized parameter change.
    float _sensivity;

    bool _shouldBeHighlighted = false;

    float _mousePosOnLast0Cross;
    float _mousePosOnLast1Cross;

    // Normalized value last set while dragging. Necessary for integer paramerers 
    // that may round that normalized value when setting the parameter.
    float _normalizedValueWhileDragging;


    // To support rounded mappings properly.
    double _displacementInHeightDebt = 0.0;

    /// Exists because public angle properties are given in a
    /// different referential, where 0 is at the top
    static float angleConvert(float angle) nothrow @nogc pure
    {
        return angle + PI * 1.5f;
    }

    /// Min angle of the trail, fit for `aaFillSector`.
    float getMinAngle() const pure nothrow @nogc
    {
        return angleConvert(trailMinAngle);
    }

    /// Min angle of the trail, fit for `aaFillSector`.
    float getMaxAngle() const pure nothrow @nogc
    {
        return angleConvert(trailMaxAngle);
    }

    /// Max angle of the trail, fit for `aaFillSector`.
    float getBaseAngle() const pure nothrow @nogc
    {
        return angleConvert(trailBaseAngle);
    }

    /// Angle of the trail, fit for `aaFillSector`.
    float getValueAngle() nothrow @nogc
    {
        return lerp(getMinAngle, getMaxAngle, _param.getNormalized());
    }

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
}
