module dplug.gui.graphics;

import dplug.plugin.client;
import dplug.plugin.graphics;

import dplug.gui.window;

// This is the interface between a plugin client and a IWindow.

class GUIGraphics : Graphics, IWindowListener
{
    this(Client client)
    {
        super(client);

        _window = null;     
    }

    // Graphics implementation

    override void openUI(void* parentInfo)
    {
        // create window (TODO: cache it)
        _window = createWindow(parentInfo, this);
    }

    override void closeUI()
    {
        // release window
        _window.terminate();
    }

    // IWindowListener

    override void onKeyDown(Key key)
    {
    }

    override void onKeyUp(Key up)
    {
    }

    // an image you have to draw to, or return that nothing has changed
    void onDraw(WindowFrameBuffer wfb, out bool needRedraw)
    {    
        int disp = 0;

        for (int j = 0; j < wfb.height; ++j)
        {
            for (int i = 0; i < wfb.width; ++i)
            {
                int offset = i * 4 + j * wfb.byteStride;
                wfb.pixels[offset] = (i+disp*2) & 255;
                wfb.pixels[offset+1] = (j+disp) & 255;
                wfb.pixels[offset+2] = 0;
                wfb.pixels[offset+ 3] = 255;
            }
        }
        needRedraw = true;
    }

protected:
    Client _client;
    IWindow _window;
}
