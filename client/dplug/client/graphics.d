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
                          void* controlInfo, // must be null, was a Carbon thing
                          IClient client,
                          GraphicsBackend backend);

    /// Close that UI.
    abstract void closeUI();

    /// Get the current plugin UI size in logical pixels.
    abstract void getGUISize(int* widthLogicalPixels, int* heightLogicalPixels);

    /// Used by CLAP and VST3.
    /// Returns: `true` if plugin is resizeable in terms of logical pixels.
    abstract bool isResizeable();

    /// Used by CLAP.
    /// Returns: `true` if plugin is resizeable in terms of logical pixels, horizontally.
    abstract bool isResizeableHorizontally();
    abstract bool isResizeableVertically();

    /// Used by CLAP and VST3.
    /// Returns: Maximum valid size that still fits into a `inoutWidth x inoutHeight` rectangle.
    ///          When one of the criterion is impossible to satisfy, returning a valid size is preferred.
    /// This should work even if the UI is closed.
    abstract void getMaxSmallerValidSize(int* inoutWidth, int* inoutHeight);

    /// Used by VST3.
    /// Returns: Nearest, valid size in logical pixels, given an input size in logical pixels.
    /// This should work even if the UI is closed.
    /// Hack: Used by FLP format to find minimum and maximum size of window in logical pixels.
    abstract void getNearestValidSize(int* inoutWidth, int* inoutHeight);

    /// Used by CLAP and VST3.
    /// Tells the native window to resize itself.
    /// Called by the host when it's one resizing the parent window, and wants our window to follow suit.
    /// This is to be forwarded to IWindow.
    /// Returns: `true` if properly resized.
    abstract bool nativeWindowResize(int newWidthLogicalPixels, int newHeightLogicalPixels);

    /// Used by CLAP.
    /// Returns: `true` if plugin is preserves an apsect ratio, even though it reality sizes will be rounded
    ///          to integer logical pixels.
    ///         false if not resizeable or doesn't preserve a ratio.
    abstract bool isAspectRatioPreserved();

    /// Used by CLAP.
    /// Only makes sense if `isAspectRatioPreserved` returned true, else it's UB.
    abstract int[2] getPreservedAspectRatio();
}

