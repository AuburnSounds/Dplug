/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.pbrwidgets.panel;

import std.math;
import dplug.gui.element;
import dplug.client.params;

/// An UIPanel is simply a plain rectangle with a depth, material and diffuse.
class UIPanel : UIElement
{
public:
nothrow:
@nogc:

    this(UIContext context, RGBA diffuse, RGBA material, L16 depth)
    {
        super(context);
        _depth = depth;
        _material = material;
        _diffuse = diffuse;
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        foreach(dirtyRect; dirtyRects)
        {
            // fill diffuse map
            diffuseMap.cropImageRef(dirtyRect).fillAll(_diffuse);

            // fill material map
            materialMap.cropImageRef(dirtyRect).fillAll(_material);

            // fill depth map
            depthMap.cropImageRef(dirtyRect).fillAll(_depth);
        }
    }

protected:
    L16 _depth;
    RGBA _diffuse;
    RGBA _material;
}
