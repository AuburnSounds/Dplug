module dplug.gui.toolkit.renderer;

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
        // TODO
    }

    void drawRect(int x, int y, int width, int height)
    {
        // TODO
    }

    void copy(Image!RGBA image, int x, int y)
    {
        // TODO
    }

    void setViewport(int x, int y, int width, int height)
    {
        // TODO
    }

private:
    ImageRef!RGBA _fb;
    RGBA _currentColor;

}