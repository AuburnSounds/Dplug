module dplug.gui.toolkit.slider;

import dplug.gui.toolkit.element;

class UISlider : UIElement
{
public:

    this(UIContext context, bool snapOnIntegerPosition)
    {
        super(context);

        _snapOnIntegerPosition = snapOnIntegerPosition;

        backgroundColor = RGBA(28, 32, 38, 255);
    }

    override void preRender(ImageRef!RGBA surface)
    {
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
    

    bool _snapOnIntegerPosition;
}
