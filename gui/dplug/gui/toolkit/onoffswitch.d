/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.toolkit.onoffswitch;

import std.math;
import dplug.gui.toolkit.element;
import dplug.gui.drawex;
import dplug.plugin.params;

class UIOnOffSwitch : UIElement, IParameterListener
{
public:

    this(UIContext context, BoolParameter param)
    {
        super(context);
        _param = param;
        _param.addListener(this);
    }

    override void close()
    {
        _param.removeListener(this);
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap, box2i[] dirtyRects)
    {
        // dig a hole
        RGBA bgDepth = RGBA(0, 200, 0, 0);
        depthMap.fill(bgDepth);

        // The switch is in a subrect

        int width = _position.width;
        int height = _position.height;
        float border = 0.1f;
        box2i switchRect = 
            box2i ( cast(int)(0.5f + width * border),
                    cast(int)(0.5f + height * border),
                    cast(int)(0.5f + width * (1-border)),
                    cast(int)(0.5f + height * (1-border)) );
        

        bool isOn = _param.value();
        int emissive = isOn ? 128 : 0;
        if (isMouseOver || isDragged)
            emissive += 50;
        ubyte red = 230;
        ubyte green = 80;
        ubyte blue = 43;

        auto diffuseColor = RGBA(red, green, blue, cast(ubyte)emissive);

        auto croppedDiffuse = diffuseMap.crop(switchRect);        
        croppedDiffuse.fill(diffuseColor);

        ubyte shininess = 100;
        RGBA colorLow = RGBA(0, shininess, 0, 0);
        RGBA colorHigh = RGBA(120, shininess, 0, 0);        

        if (isOn)
        {
            verticalSlope(depthMap, switchRect, colorLow, colorHigh);
        }
        else
        {
            verticalSlope(depthMap, switchRect, colorHigh, colorLow);
        }
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        // double-click => set to default
        _param.beginParamEdit();
        _param.setFromGUI(!_param.value());
        _param.endParamEdit();
        return true;
    }

    override void onMouseEnter()
    {
        setDirty();
    }

    override void onMouseExit()
    {
        setDirty();
    }

    override void onParameterChanged(Parameter sender) nothrow @nogc
    {
        setDirty();
    }

protected:

    /// The parameter this switch is linked with.
    BoolParameter _param;
}
