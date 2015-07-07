/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.panel;

import std.math;
import dplug.gui.element;
import dplug.plugin.params;

/// Extends an UIElement with a background color, depth and shininess.
class UIPanel : UIElement
{
public:

    this(UIContext context, RGBA backgroundColor, ubyte depth, ubyte shininess)
    {
        super(context);
        _depth = depth;
        _shininess = shininess;
        _backgroundColor = backgroundColor;
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuse = diffuseMap.crop(dirtyRect);
            auto croppedDepth = depthMap.crop(dirtyRect);

            // fill with clear color
            croppedDiffuse.fill(_backgroundColor);

            // fill with clear depth
            croppedDepth.fill(L16(_depth));
        }
    }

protected:
    ubyte _depth;
    ubyte _shininess;
    RGBA _backgroundColor;
}
