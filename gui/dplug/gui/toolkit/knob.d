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
        auto c = RGBA(x++ & 255, 80, 80, 255);

        if (isMouseOver())
            c = RGBA(100, 100, 120, 255);

        /*if (isFocused())
            c = RGBA(150, 80, 80, 255);
        if (isDragged())
            c = RGBA(150, 150, 80, 255);
*/

        renderer.viewport.softCircle(position.width/2, position.height/2, 
                                     (position.width-2)/2, position.width/2, c);
        renderer.fillRect(0, 0, _position.width, _position.height);
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
    int x = 0;
}
