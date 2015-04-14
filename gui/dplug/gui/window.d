module dplug.gui.window;

import ae.utils.graphics;

interface IWindow
{
    // must be called prior drawing
    Image!RGBA* getRGBABuffer();

    // release the buffer and swap buffers
    void swapBuffers();
}