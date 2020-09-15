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

import dplug.client : Client;

/// FlatBackgroundGUI provides a background that is loaded from a PNG or JPEG
/// image. The string for backgroundPath should be in "stringImportPaths"
/// specified in dub.json
class FlatBackgroundGUI(string backgroundPath) : GUIGraphics
{
public:
nothrow:
@nogc:

    this(int width, int height, Client client)
    {
        super(width, height, flagRaw, client);
        _backgroundImage = loadOwnedImage(cast(ubyte[])(import(backgroundPath)));
    }
    
    ~this()
    {
        if(_backgroundImage)
            _backgroundImage.destroyFree();
    }
    
    override void reflow(box2i availableSpace)
    {
        bool reallocResizedImage = availableSpace.width != _position.width || availableSpace.height != _position.height;
        
        // Note: the position is entirely decorrelated from the size of _backgroundImage
        _position = availableSpace;

        
        if(reallocResizedImage)
        {
            _backgroundImageResized = mallocNew!(OwnedImage!RGBA)(_position.width, _position.height);
            resizeBilinear(_backgroundImage.toRef(), _backgroundImageResized.toRef());
            setDirtyWhole();
        }
    }
    
    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        auto backgroundRef = _backgroundImageResized.toRef();

        foreach(dirtyRect; dirtyRects)
        {
            int W = dirtyRect.width;
            int H = dirtyRect.height;

            auto croppedRawIn = backgroundRef.cropImageRef(dirtyRect);
            auto croppedRawOut = rawMap.cropImageRef(dirtyRect);
            
            for(int j = 0; j < H; ++j)
            {
                RGBA[] inputRaw = croppedRawIn.scanline(j);
                RGBA[] outputRaw = croppedRawOut.scanline(j);

                for(int i = 0; i < W; ++i)
                {
                    outputRaw[i] = inputRaw[i];
                }
            }
        }
    }
    
private:
    OwnedImage!RGBA _backgroundImage;
    OwnedImage!RGBA _backgroundImageResized;
}