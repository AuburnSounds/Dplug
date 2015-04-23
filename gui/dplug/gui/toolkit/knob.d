module dplug.gui.toolkit.knob;

import dplug.gui.toolkit.element;

class UIKnob : UIElement
{
public:    

    this(UIContext context, string label)
    {
        super(context);
        _label = label;
    }

    override void reflow(box2i availableSpace)
    {
        int width = 50;
        int height = 50;
        _position = box2i(availableSpace.min.x, availableSpace.min.y,availableSpace.min.x + width, availableSpace.min.y + height);
    }

    override void preRender(UIRenderer renderer)
    {
        auto c = RGBA(80, 80, 80, 255);
        renderer.viewport.softCircle(25, 25, 20, 24, c);
        renderer.fillRect(0, 0, _position.width, _position.height);
    }

private:
    string _label;
}
