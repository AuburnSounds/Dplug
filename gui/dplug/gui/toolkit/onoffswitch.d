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

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap, box2i dirtyRect)
    {
        bool isOn = _param.value();


        int emissive = isOn ? 192 : 0;
        if (isMouseOver || isDragged)
            emissive += 63;

        emissive = 0;

        auto diffuseColor = RGBA(255, 0, 0, cast(ubyte)emissive);

        auto croppedDiffuse = diffuseMap.crop(dirtyRect);
        auto croppedDepth = depthMap.crop(dirtyRect);

        croppedDiffuse.fill(diffuseColor);

        RGBA colorLow = RGBA(0, 0, 0, 255);
        RGBA colorHigh = RGBA(255, 0, 0, 255);

        box2i rect = box2i(0, 0, _position.width, _position.height);

        if (isOn)
            verticalSlope(depthMap, rect, colorLow, colorHigh);
        else
            verticalSlope(depthMap, rect, colorHigh, colorLow);

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
