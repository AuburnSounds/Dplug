/**
The root widget to inherit from for a flat UI.

Copyright: Guillaume Piolat 2015-2018.
Copyright: Ethan Reker 2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.flatwidgets.flatbackgroundgui;

import gfm.math.box;
import dplug.core.nogc;
import dplug.core.file;
import dplug.graphics.color;
import dplug.graphics.image;
import dplug.graphics.view;
import dplug.graphics.drawex;

import dplug.core.nogc;
import dplug.gui.graphics;
import dplug.gui.element;

/// FlatBackgroundGUI provides a background that is loaded from a PNG or JPEG
/// image. The string for backgroundPath should be in "stringImportPaths"
/// specified in dub.json
class FlatBackgroundGUI(string backgroundPath) : GUIGraphics
{
public:
nothrow:
@nogc:

    this(int width, int height)
    {
        super(width, height, flagRaw);
        _backgroundImage = loadOwnedImage(cast(ubyte[])(import(backgroundPath)));
    }
    
    ~this()
    {
        if(_backgroundImage)
            _backgroundImage.destroyFree();
    }
    
    override void reflow(box2i availableSpace)
    {
        _position = availableSpace;
    }
    
    /// Fill diffuse map with diffuse from background image.  Alpha is ignored since ideally a background image will not
    /// need an alpha channel.
    /// Material and depth maps are zeroed out to initialize them. Otherwise this can lead to nasty errors.
    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        foreach(dirtyRect; dirtyRects)
        {
            auto croppedRawIn = _backgroundImage.crop(dirtyRect);
            auto croppedRawOut = rawMap.crop(dirtyRect);

            immutable RGBA inputMaterial = RGBA(0, 0, 0, 0);
            immutable L16 inputDepth = L16(0);

            for(int j = 0; j < dirtyRect.height; ++j)
            {
                RGBA[] inputRaw = croppedRawIn.scanline(j);
                RGBA[] outputRaw = croppedRawOut.scanline(j);

                for(int i = 0; i < dirtyRect.width; ++i)
                {
                    outputRaw[i] = inputRaw[i];
                }
            }
        }
    }
    
private:
    OwnedImage!RGBA _backgroundImage;
}