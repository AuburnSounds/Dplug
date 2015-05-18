module dplug.gui.toolkit.knob;

import std.math;
import dplug.gui.toolkit.element;
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
    }

    override void close()
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

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap, box2i dirtyRect)
    {
        auto c = RGBA(193, 180, 176, 0);


        if (isMouseOver || isDragged)
            c.a = 20;

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

        float knobRadius = radius * 0.8f;

        float a1 = PI * 3/4;
        float a2 = a1 + PI * 1.5f * normalizedValue;
        RGBA trailColor = (isMouseOver() || isDragged()) ? RGBA(160, 64, 64, 192) : RGBA(160, 64, 64, 64);


        diffuseMap.aaFillSector(cast(int)centerx, cast(int)centery, radius * 0.83, radius * 0.97, a1, a2, trailColor);


        depthMap.aaFillSector(cast(int)centerx, cast(int)centery, radius * 0.8f, radius * 1.0, PI * 3/4 - 0.04f, PI * 9/4 + 0.04f, RGBA(30, 0, 0, 0));


        //
        // Draw knob
        //

        float angle = (normalizedValue - 0.5f) * 4.8f;
        float depthRadius = std.algorithm.max(knobRadius * 3.0f / 5.0f, 0);
        float depthRadius2 = std.algorithm.max(knobRadius * 3.0f / 5.0f, 0);

        float posEdgeX = centerx + sin(angle) * depthRadius2;
        float posEdgeY = centery - cos(angle) * depthRadius2;
        
        diffuseMap.softCircle(centerx, centery, knobRadius - 1, knobRadius, c);
        
        ubyte shininess = 200;
        depthMap.softCircle(centerx, centery, depthRadius, knobRadius, RGBA(255, shininess, 0, 0));
        depthMap.softCircle(centerx, centery, 0, depthRadius, RGBA(150, shininess, 0, 0));



        // LEDs
        for (int i = 0; i < 7; ++i)
        {
            float disp = i * 2 * PI / 7.0f;
            float x = centerx + sin(angle + disp) * (knobRadius * 4 / 5);
            float y = centery - cos(angle + disp) * (knobRadius * 4 / 5);

            float smallRadius = knobRadius * 5 / 60;
            float largerRadius = knobRadius * 7 / 60;

            ubyte emissive = 15;
            ubyte green = 128;
            if (isMouseOver())
                emissive = 128;
            if (isDragged())
            {
                if (i == 0)
                    green = 255;
                emissive = 255;
            }
            
            RGBA color = RGBA(255, green, 128, emissive);

            depthMap.softCircle(x, y, smallRadius, largerRadius, RGBA(100, 255, 0, 0));
            diffuseMap.softCircle(x, y, smallRadius, largerRadius, color);
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
        float extent = _param.maxValue() - _param.minValue();

        float modifier = 1.0f;
        if (mstate.shiftPressed || mstate.ctrlPressed)
            modifier *= 0.1f;

        // TODO: this will break with log params
        float currentValue = _param.value;
        _param.setFromGUI(currentValue - displacementInHeight * modifier * _sensivity * extent);
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
}
