/**
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
    
    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
		foreach(dirtyRect; dirtyRects)
		{
			auto croppedDiffuseIn = _backgroundImage.crop(dirtyRect);
			auto croppedDiffuseOut = diffuseMap.crop(dirtyRect);


			for(int j = 0; j < dirtyRect.height; ++j){
				RGBA[] input = croppedDiffuseIn.scanline(j);
				RGBA[] output = croppedDiffuseOut.scanline(j);

				for(int i = 0; i < dirtyRect.width; ++i){
                    output[i] = input[i];
				}
			}
		}
    }
    
private:
    OwnedImage!RGBA _backgroundImage;
}