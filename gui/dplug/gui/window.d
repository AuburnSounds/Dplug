module dplug.gui.window;

import ae.utils.graphics;

interface IWindow
{
    // To put in your message loop
    void waitEventAndDispatch();

    // If exit was requested
    bool terminated();
}