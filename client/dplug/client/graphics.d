/**
 * Definition of IGraphics, which controls the UI from the host point of view.
 *
 * Copyright: Copyright Auburn Sounds 2015 and later.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.client.graphics;

import dplug.client.client;
import dplug.client.daw;

enum GraphicsBackend
{
    autodetect,
    win32,
    carbon,
    cocoa,
    x11
}

/// Plugin GUI
interface IGraphics
{
nothrow:
@nogc:
    /// Create an UI, return a system-specific handle for the window/view
    abstract void* openUI(void* parentInfo, 
                          void* controlInfo, 
                          IClient client,
                          GraphicsBackend backend);

    /// Close that UI.
    abstract void closeUI();

    /// Get the current plugin UI size in logical pixels.
    abstract void getGUISize(int* widthLogicalPixels, int* heightLogicalPixels);
}

