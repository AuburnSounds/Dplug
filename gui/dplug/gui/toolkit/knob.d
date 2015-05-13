module dplug.gui.toolkit.knob;

import std.math;
import dplug.gui.toolkit.element;
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
        float angle = (normalizedValue - 0.5f) * 4.8f;
        float depthRadius = max(radius * 3.0f / 5.0f, 0);
        float depthRadius2 = max(radius * 3.0f / 5.0f, 0);

        float posEdgeX = centerx + sin(angle) * depthRadius2;
        float posEdgeY = centery - cos(angle) * depthRadius2;
        
        diffuseMap.softCircle(centerx, centery, radius - 1, radius, c);
        
        ubyte shininess = 200;
        depthMap.softCircle(centerx, centery, depthRadius, radius, RGBA(255, shininess, 0, 0));
        depthMap.softCircle(centerx, centery, 0, depthRadius, RGBA(150, shininess, 0, 0));

//        diffuseMap.fillSector(centerx, centery, radius, radius * 1.5f, 0, angle, RGBA(255, 0, 0, 255));
 //       depthMap.fillSector(centerx, centery, radius, radius * 1.5f, 0, angle, RGBA(20, 10, 0, 255));


        for (int i = 0; i < 7; ++i)
        {
            float disp = i * 2 * PI / 7.0f;
            float x = centerx + sin(angle + disp) * (radius * 4 / 5);
            float y = centery - cos(angle + disp) * (radius * 4 / 5);

            float smallRadius = radius * 5 / 60;
            float largerRadius = radius * 7 / 60;

            ubyte emissive = 15;
            if (isMouseOver())
                emissive = 128;
            if (isDragged())
                emissive = 255;

            depthMap.softCircle(x, y, smallRadius, largerRadius, RGBA(100, 255, 0, 0));
            diffuseMap.softCircle(x, y, smallRadius, largerRadius, RGBA(255, 180, 128, emissive));
        }

        diffuseMap.softCircle(posEdgeX, posEdgeY, 0, 15, c);
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
