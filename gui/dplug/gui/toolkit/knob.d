module dplug.gui.toolkit.knob;

import dplug.gui.toolkit.element;

class UIKnob : UIElement
{
public:

    this(UIContext context)
    {
        super(context);
    }

    override void preRender(UIRenderer renderer)
    {
        auto c = RGBA(80, 80, 80, 255);
        renderer.viewport.softCircle(position.width/2, position.height/2, 
                                     (position.width-2)/2, position.width/2, c);
        renderer.fillRect(0, 0, _position.width, _position.height);
    }

    // Called when mouse drag this Element.
    override void onMouseDrag(int x, int y, int dx, int dy)
    {
        // TODO change plugin parameter, or callback something
    }

private:
    string _label;
}
