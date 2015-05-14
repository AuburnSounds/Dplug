module dplug.gui.toolkit.knob;

import std.math;
import dplug.gui.toolkit.element;
import dplug.gui.drawex;
import dplug.plugin.params;

class UIKnob : UIElement
{
public:

    this(UIContext context, FloatParameter param)
    {
        super(context);
        _param = param;
        _sensivity = 0.25f;
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

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap)
    {
        auto c = RGBA(193, 180, 176, 0);

        float normalizedValue = _param.getNormalized();


        // We'll draw entireyl in the largest centered square in _position.
        box2i subSquare;
        if (_position.width > _position.height)
        {
            int offset = (_position.width - _position.height) / 2;
            int minX = _position.min.x + offset;
            subSquare = box2i(minX, _position.min.y, minX + _position.height, _position.max.y);
        }
        else
        {
            int offset = (_position.height - _position.width) / 2;
            int minY = _position.min.y  + offset;
            subSquare = box2i(_position.min.x, minY, _position.max.x, minY + _position.width);
        }
        float radius = subSquare.width * 0.5f;
        float centerx = (subSquare.min.x + subSquare.max.x - 1) * 0.5f;
        float centery = (subSquare.min.y + subSquare.max.y - 1) * 0.5f;

        float knobRadius = radius * 0.7f;

        float a1 = PI * 3/4;
        float a2 = a1 + PI * 1.5f * normalizedValue;
        diffuseMap.aaFillSector(cast(int)centerx, cast(int)centery, radius * 0.85, radius * 1.0, a1, a2, RGBA(128, 32, 32, 64));

            //void fillSector(V, COLOR)(auto ref V v, int x, int y, int r0, int r1, real a0, real a1, COLOR c)


        //
        // Draw knob
        //
        


        float angle = (normalizedValue - 0.5f) * 4.8f;
        float depthRadius = max(knobRadius * 3.0f / 5.0f, 0);
        float depthRadius2 = max(knobRadius * 3.0f / 5.0f, 0);

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

    override bool onMousePreClick(int x, int y, int button, bool isDoubleClick)
    {
        setDirty();
        return true; // to initiate dragging
    }

    // Called when mouse drag this Element.
    override void onMouseDrag(int x, int y, int dx, int dy)
    {
        setDirty();
        float displacementInHeight = cast(float)(dy) / _position.height;
        float extent = _param.maxValue() - _param.minValue();

        // TODO: this will break with log params
        float currentValue = _param.value;
        _param.setFromGUI(currentValue - displacementInHeight * _sensivity * extent);
    }

    // For lazy updates
    override void onBeginDrag()
    {
        setDirty();
    }

    override  void onStopDrag()
    {
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

protected:

    /// The parameter this knob is linked with.
    FloatParameter _param;

    /// Sensivity: given a mouse movement in 100th of the height of the knob, 
    /// how much should the normalized parameter change.
    float _sensivity;
}
