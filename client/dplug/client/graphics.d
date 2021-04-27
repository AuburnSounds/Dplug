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

    /// Used by VST3.
    /// Returns: `true` if this is resizeable in terms of logical pixels.
    /// This should succeed even f the UI is closed.
    abstract bool isResizeable();

    /// Used by VST3.
    /// Returns: Nearest, valid size in logical pixels, given an input size in logical pixels.
    /// This should work even if the UI is closed.
    abstract void getNearestValidSize(int* inoutWidth, int* inoutHeight);

    /// Used by VST3.
    /// Tells the native window to resize itself.
    /// Called by the host when it's one resizing the parent window, and wants our window to follow suit.
    /// This is to be forwarded to IWindow.
    /// Returns: `true` if properly resized.
    abstract bool nativeWindowResize(int newWidthLogicalPixels, int newHeightLogicalPixels);
}

