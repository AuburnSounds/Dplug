/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.knob;

import std.math;
import dplug.gui.element;
import dplug.gui.drawex;
import dplug.plugin.params;

class UIKnob : UIElement, IParameterListener
{
public:

    this(UIContext context, FloatParameter param)
    {
        super(context);
        _param = param;
        _sensivity = 0.25f;
        _param.addListener(this);
        _initialized = true;
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

        float knobRadius = radius * 0.75f;

        float a1 = PI * 3/4;
        float a2 = a1 + PI * 1.5f * normalizedValue;
        float a3 = a1 + PI * 1.5f;


        RGBA trailColorLit = RGBA(230, 80, 43, 192);
        RGBA trailColorUnlit = RGBA(150, 40, 20, 8);

        diffuseMap.aaFillSector(cast(int)centerx, cast(int)centery, radius * 0.85f, radius * 0.97f, a1, a2, trailColorLit);
        diffuseMap.aaFillSector(cast(int)centerx, cast(int)centery, radius * 0.85f, radius * 0.97f, a2, a3, trailColorUnlit);



        //
        // Draw knob
        //

        Material matKnob = Material.silver;

        float angle = (normalizedValue - 0.5f) * 4.8f;
        float depthRadius = std.algorithm.max(knobRadius * 3.0f / 5.0f, 0);
        float depthRadius2 = std.algorithm.max(knobRadius * 3.0f / 5.0f, 0);

        float posEdgeX = centerx + sin(angle) * depthRadius2;
        float posEdgeY = centery - cos(angle) * depthRadius2;

        diffuseMap.softCircleFloat(centerx, centery, knobRadius - 1, knobRadius, matKnob.diffuse( (isMouseOver || isDragged) ? 20 : 0 ));

        depthMap.softCircleFloat(centerx, centery, depthRadius, knobRadius, L16(65535));
        depthMap.softCircleFloat(centerx, centery, 0, depthRadius, L16(150 * 256));

        materialMap.softCircleFloat(centerx, centery, depthRadius - 1, depthRadius, matKnob.material(0));


        // LEDs
        for (int i = 0; i < 7; ++i)
        {
            float disp = i * 2 * PI / 7.0f;
            float x = centerx + sin(angle + disp) * (knobRadius * 4 / 5);
            float y = centery - cos(angle + disp) * (knobRadius * 4 / 5);

            float smallRadius = knobRadius * 5 / 55;
            float largerRadius = knobRadius * 7 / 55;

            ubyte emissive = 40;
            if (isDragged())
                emissive = 255;

            auto ledColor = RGBA(255, 140, 220, emissive);

//            depthMap.softCircleFloat!2.0f(x, y, largerRadius, largerRadius * 2.0f, L16(20000));

            depthMap.softCircleFloat/*!2.0f*/(x, y, 0, largerRadius, L16(65000));
            diffuseMap.softCircleFloat(x, y, 0, largerRadius, ledColor);
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

        double newParamValue = _param.getNormalized() - displacementInHeight * modifier * _sensivity;
        if (newParamValue < 0)
            newParamValue = 0;
        if (newParamValue > 1)
            newParamValue = 1;

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

protected:

    /// The parameter this knob is linked with.
    FloatParameter _param;

    /// Sensivity: given a mouse movement in 100th of the height of the knob,
    /// how much should the normalized parameter change.
    float _sensivity;

    bool _initialized; // destructor flag
}
