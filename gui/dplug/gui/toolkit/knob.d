module dplug.gui.toolkit.knob;

import dplug.gui.toolkit.element;

class UIKnob : UIElement
{
public:    

    this(UIContext context, string label)
    {
        super(context);
        _label = label;
        backgroundColor = RGBA(0, 0, 0, 255);
    }

    void setSize(int width, int height)
    {
        _width = width;
        _height = height;
    }

    override void reflow(box2i availableSpace)
    {
        _position = box2i(availableSpace.min.x, availableSpace.min.y, availableSpace.min.x + _width, availableSpace.min.y + _height);
    }

    override void preRender(UIRenderer renderer)
    {
        auto c = RGBA(80, 80, 80, 255);
        renderer.viewport.softCircle(_width/2, _height/2, (_height-2)/2, _height/2, c);
        renderer.fillRect(0, 0, _position.width, _position.height);
    }

    // Called when mouse drag this Element.
    override void onMouseDrag(int x, int y, int dx, int dy)
    {
        // TODO change plugin parameter
    }

private:
    string _label;
    int _width = 50;
    int _height = 50;
}
