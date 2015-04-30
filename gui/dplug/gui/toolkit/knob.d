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

    override void preRender(ImageRef!RGBA surface)
    {
        auto c = RGBA(80, 80, 80, 255);

        if (isMouseOver())
            c = RGBA(100, 100, 120, 255);

        if (isDragged())
            c = RGBA(150, 150, 80, 255);


        int centerx = _position.center.x;
        int centery = _position.center.y;
        int radius = _position.width / 2;
        int radius2 = radius / 2;
        float angle = (_value - 0.5f) * 4.0f;
        float posEdgeX = centerx + sin(angle) * radius;
        float posEdgeY = centery - cos(angle) * radius;
        float posEdgeX2 = centerx + sin(angle) * radius2;
        float posEdgeY2 = centery - cos(angle) * radius2;

        surface.softCircle(centerx, centery, radius - 1, radius, c);
        surface.aaLine(posEdgeX, posEdgeY, posEdgeX2, posEdgeY2, RGBA(0,0, 0, 0));

        _font.size = 16;
        _font.color = RGBA(220, 220, 220, 255);
        _font.fillText(surface, _label, _position.center.x, _position.max.y + 20);


    }

    // Called when mouse drag this Element.
    override void onMouseDrag(int x, int y, int dx, int dy)
    {
        _value = _value + dy * 0.001f;
    }

    // Called when mouse drag this Element.
    override void onMouseMove(int x, int y, int dx, int dy)
    {
        int a = 1;
    }

private:
    string _label;
    Font _font;
    int x = 0;

    float _value; // between 0 and 1
}
