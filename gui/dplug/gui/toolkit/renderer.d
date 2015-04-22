module dplug.gui.toolkit.renderer;

import gfm.math;
import ae.utils.graphics;
import dplug.gui.window;

// class able to draw pixels
class UIRenderer
{
public:
    this()
    {
    }

    void setFrameBuffer(ImageRef!RGBA fb)
    {
        _fb = fb;
    }

    void setColor(int r, int g, int b, int a = 255)
    {
        _currentColor = RGBA(cast(ubyte)r, cast(ubyte)g, cast(ubyte)b, cast(ubyte)a);
    }

    void fillRect(int x, int y, int width, int height)
    {
        viewport().fillRect(x, y, x + width, y + height, _currentColor);
    }

    void drawRect(int x, int y, int width, int height)
    {
        viewport().rect(x, y, x + width, y + height, _currentColor);
    }

    void copy(Image!RGBA image, int x, int y)
    {
        image.blitTo(viewport(), x, y);
    }

    auto viewport()
    {
        return _fb.crop(_viewportRect.min.x, _viewportRect.min.y, _viewportRect.max.x, _viewportRect.max.y);
    }

    void setViewport(int x, int y, int width, int height)
    {
        _viewportRect = box2i(x, y, x + width, y + height);
    }

private:
    ImageRef!RGBA _fb;
    ImageRef!RGBA _viewport;
    box2i _viewportRect;
    RGBA _currentColor;

}