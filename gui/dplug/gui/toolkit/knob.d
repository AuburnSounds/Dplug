module dplug.gui.toolkit.knob;

import dplug.gui.toolkit.element;

class UIKnob : UIElement
{
public:

    this(UIContext context, Font font, string label)
    {
        super(context);
        _label = label;
        _font = font;
    }

    override void preRender(ImageRef!RGBA surface)
    {
        auto c = RGBA(80, 80, 80, 255);

        if (isMouseOver())
            c = RGBA(100, 100, 120, 255);

        if (isDragged())
            c = RGBA(150, 150, 80, 255);

        surface.fillRect(_position.min.x, _position.min.y, _position.max.x, _position.max.y, c);
        _font.size = 16;
        _font.color = RGBA(220, 220, 220, 255);
        _font.fillText(surface, _label, _position.center.x, _position.max.y + 20);
    }

    // Called when mouse drag this Element.
    override void onMouseDrag(int x, int y, int dx, int dy)
    {
        // TODO change plugin parameter, or callback something
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
}
