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

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!S16 depthMap)
    {
        auto c = RGBA(80, 80, 80, 255);

        if (isMouseOver())
            c = RGBA(100, 100, 120, 255);

        if (isDragged())
            c = RGBA(150, 150, 80, 255);

        int centerx = _position.center.x;
        int centery = _position.center.y;
        int radius = _position.width / 2;
        int radius2 = 0;
        float angle = (_value - 0.5f) * 4.0f;
        int depthRadius = max(radius - 20, 0);
        int depthRadius2 = max(radius - 35, 0);

        float posEdgeX = centerx + sin(angle) * depthRadius2;
        float posEdgeY = centery - cos(angle) * depthRadius2;

        
        diffuseMap.softCircle(centerx, centery, depthRadius, radius, c);

        
        depthMap.softCircle(centerx, centery, depthRadius, radius, S16(32000));
        depthMap.softCircle(posEdgeX, posEdgeY, 0, 15, S16(0));

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
