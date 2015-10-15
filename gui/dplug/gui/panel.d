/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.panel;

import std.math;
import dplug.gui.element;
import dplug.client.params;

/// Extends an UIElement with a background color, depth and shininess.
class UIPanel : UIElement
{
public:

    this(UIContext context, RGBA backgroundColor, RGBA material, L16 depth)
    {
        super(context);
        _depth = depth;
        _material = material;
        _backgroundColor = backgroundColor;
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        foreach(dirtyRect; dirtyRects)
        {
            // fill diffuse map
            diffuseMap.crop(dirtyRect).fill(_backgroundColor);

            // fill material map
            materialMap.crop(dirtyRect).fill(_material);

            // fill depth map
            depthMap.crop(dirtyRect).fill(_depth);
        }
    }

protected:
    L16 _depth;
    RGBA _backgroundColor;
    RGBA _material;
}
