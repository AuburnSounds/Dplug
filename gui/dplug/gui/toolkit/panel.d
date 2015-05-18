module dplug.gui.toolkit.panel;

import std.math;
import dplug.gui.toolkit.element;
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

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap, box2i dirtyRect)
    {
        auto croppedDiffuse = diffuseMap.crop(dirtyRect);
        auto croppedDepth = depthMap.crop(dirtyRect);

        // fill with clear color
        croppedDiffuse.fill(_backgroundColor);

        // fill with clear depth + shininess
        croppedDepth.fill(RGBA(_depth, _shininess, 0, 0));        
    }

protected:
    ubyte _depth;
    ubyte _shininess;
    RGBA _backgroundColor;
}
