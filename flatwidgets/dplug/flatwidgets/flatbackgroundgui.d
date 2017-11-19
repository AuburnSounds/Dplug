/**
 * The root widget to inherit from for a flat UI.
 *
 * Copyright: Copyright Auburn Sounds 2015-2017.
 * Copyright: Cut Through Recordings 2017.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Ethan Reker
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
        super(width, height);
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
    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuseIn = _backgroundImage.crop(dirtyRect);
            auto croppedDiffuseOut = diffuseMap.crop(dirtyRect);
            auto croppedMaterialOut = materialMap.crop(dirtyRect);
            auto croppedDepthOut = depthMap.crop(dirtyRect);

            immutable RGBA inputMaterial = RGBA(0, 0, 0, 0);
            immutable L16 inputDepth = L16(0);

            for(int j = 0; j < dirtyRect.height; ++j){
                RGBA[] inputDiffuse = croppedDiffuseIn.scanline(j);
                RGBA[] outputDiffuse = croppedDiffuseOut.scanline(j);
                RGBA[] outputMaterial = croppedMaterialOut.scanline(j);
                L16[] outputDepth = croppedDepthOut.scanline(j);

                for(int i = 0; i < dirtyRect.width; ++i){
                    outputDiffuse[i] = inputDiffuse[i];
                    outputMaterial[i] = inputMaterial;
                    outputDepth[i] = inputDepth;
                }
            }
        }
    }
    
private:
    OwnedImage!RGBA _backgroundImage;
}