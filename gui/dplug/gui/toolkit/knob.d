module dplug.gui.toolkit.knob;

import std.math;
import dplug.gui.toolkit.element;

class UIKnob : UIElement
{
public:

    this(UIContext context, Font font, string label)
    {
        super(context);
        _label = label;
        _font = font;
        _value = 0.5f;
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap)
    {
        auto c = RGBA(193, 180, 176, 255);

        if (isMouseOver())
            c = RGBA(213, 200, 196, 255);

        if (isDragged())
            c = RGBA(233, 220, 216, 255);

        int centerx = _position.center.x;
        int centery = _position.center.y;
        int radius = _position.width / 2;
        int radius2 = 0;
        float angle = (_value - 0.5f) * 4.0f;
        int depthRadius = max(radius - 20, 0);
        int depthRadius2 = max(radius - 20, 0);

        float posEdgeX = centerx + sin(angle) * depthRadius2;
        float posEdgeY = centery - cos(angle) * depthRadius2;

        
        diffuseMap.softCircle(centerx, centery, radius - 2, radius, c);

        
        ubyte shininess = 200;
        depthMap.softCircle(centerx, centery, depthRadius, radius, RGBA(255, shininess, 0, 0));

        depthMap.softCircle(centerx, centery, 2, depthRadius, RGBA(150, shininess, 0, 0));


        for (int i = 0; i < 7; ++i)
        {
            float disp = i * 2 * PI / 7.0f;
            float x = centerx + sin(angle + disp) * (radius - 10);
            float y = centery - cos(angle + disp) * (radius - 10);
            depthMap.softCircle(x, y, 5, 7, RGBA(100, 255, 0, 0));
            diffuseMap.softCircle(x, y, 5, 7, RGBA(255, 128, 128, 255));
        }

        diffuseMap.softCircle(posEdgeX, posEdgeY, 0, 15, c);
        //depthMap.aaLine(posEdgeX, posEdgeY, posEdgeX2, posEdgeY2, S16(0));

/*        _font.size = 16;
        _font.color = RGBA(220, 220, 220, 255);
        _font.fillText(surface, _label, _position.center.x, _position.max.y + 20);*/
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
        _value = clamp(_value - dy * 0.003f, 0.0f, 1.0f);
        onValueChanged();
    }

    // override to set the parameter host-side
    void onValueChanged()
    {
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
    string _label;
    Font _font;
    float _value; // between 0 and 1
}
