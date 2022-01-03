/**
On/Off switch.

Copyright: Copyright Auburn Sounds 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Guillaume Piolat
*/
module dplug.pbrwidgets.onoffswitch;

import std.math;
import dplug.core.math;
import dplug.gui.element;
import dplug.client.params;

class UIOnOffSwitch : UIElement, IParameterListener
{
public:
nothrow:
@nogc:

    enum Orientation
    {
        vertical,
        horizontal
    }
    @ScriptProperty RGBA diffuseOff = RGBA(230, 80, 43, 0);
    @ScriptProperty RGBA diffuseOn = RGBA(230, 80, 43, 200);
    @ScriptProperty RGBA material = RGBA(192, 10, 128, 255);
    @ScriptProperty float animationTimeConstant = 10.0f;
    @ScriptProperty ushort depthLow = 0;
    @ScriptProperty ushort depthHigh = 30000;
    @ScriptProperty ushort holeDepth = 0;
    @ScriptProperty Orientation orientation = Orientation.vertical;

    this(UIContext context, BoolParameter param)
    {
        super(context, flagAnimated | flagPBR);
        _param = param;
        _param.addListener(this);
        _animation = 0.0f;
    }

    ~this()
    {
        _param.removeListener(this);
    }

    override void onAnimate(double dt, double time) nothrow @nogc
    {
        float target = _param.valueAtomic() ? 1 : 0;

        float newAnimation = lerp(_animation, target, 1.0 - exp(-dt * animationTimeConstant));

        if (abs(newAnimation - _animation) > 0.001f)
        {
            _animation = newAnimation;
            setDirtyWhole();
        }
    }

    override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        // dig a hole
        depthMap.fillAll(L16(holeDepth));

        // The switch is in a subrect
        int width = _position.width;
        int height = _position.height;
        float border = 0.1f;
        box2i switchRect = box2i( cast(int)(0.5f + width * border),
                                  cast(int)(0.5f + height * border),
                                  cast(int)(0.5f + width * (1 - border)),
                                  cast(int)(0.5f + height * (1 - border)) );

        ubyte red    = cast(ubyte)(lerp!float(diffuseOff.r, diffuseOn.r, _animation));
        ubyte green  = cast(ubyte)(lerp!float(diffuseOff.g, diffuseOn.g, _animation));
        ubyte blue   = cast(ubyte)(lerp!float(diffuseOff.b, diffuseOn.b, _animation));
        int emissive = cast(ubyte)(lerp!float(diffuseOff.a, diffuseOn.a, _animation));

        if (isMouseOver || isDragged)
            emissive += 40;

        if (emissive > 255)
            emissive = 255;

        RGBA diffuseColor = RGBA(red, green, blue, cast(ubyte)emissive);

        // Write a plain color in the diffuse and material map.
        box2i validRect = box2i(0, 0, diffuseMap.w, diffuseMap.h).intersection(switchRect);

        diffuseMap.cropImageRef(validRect).fillAll(diffuseColor);
        materialMap.cropImageRef(validRect).fillAll(material);

        L16 depthA = L16(cast(short)(lerp!float(depthHigh, depthLow, _animation)));
        L16 depthB = L16(cast(short)(lerp!float(depthLow, depthHigh, _animation)));

        if (orientation == Orientation.vertical)
            verticalSlope(depthMap, switchRect, depthA, depthB);
        else
            horizontalSlope(depthMap, switchRect, depthA, depthB);
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        // ALT + click => set it to default
        if (mstate.altPressed) // reset on ALT + click
        {
            _param.beginParamEdit();
            _param.setFromGUI(_param.defaultValue());
            _param.endParamEdit();
        }
        else
        {
            // Any click => invert
            // Note: double-click doesn't reset to default, would be annoying
            _param.beginParamEdit();
            _param.setFromGUI(!_param.value());
            _param.endParamEdit();
        }
        return true;
    }

    override void onMouseEnter()
    {
        setDirtyWhole();
    }

    override void onMouseExit()
    {
        setDirtyWhole();
    }

    override void onParameterChanged(Parameter sender) nothrow @nogc
    {
        setDirtyWhole();
    }

    override void onBeginParameterEdit(Parameter sender)
    {
    }

    override void onEndParameterEdit(Parameter sender)
    {
    }

protected:

    /// The parameter this switch is linked with.
    BoolParameter _param;

private:
    float _animation;
}
