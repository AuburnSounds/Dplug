/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.onoffswitch;

import std.math;
import dplug.gui.element;
import dplug.gui.drawex;
import dplug.plugin.params;

class UIOnOffSwitch : UIElement, IParameterListener
{
public:

    RGBA diffuse = RGBA(230, 80, 43, 0);
    RGBA material = RGBA(192, 10, 128, 255);
    float animationTimeConstant = 10.0f;

    this(UIContext context, BoolParameter param)
    {
        super(context);
        _param = param;
        _param.addListener(this);
        _initialized = true;
        _animation = 0.0f;
    }

    ~this()
    {
        if (_initialized)
        {
            debug ensureNotInGC("UIOnOffSwitch");
            _param.removeListener(this);
            _initialized = false;
        }
    }

    override void onAnimate(double dt, double time)
    {
        float target = _param.value() ? 1 : 0;

        float newAnimation = lerp(_animation, target, 1.0 - exp(-dt * animationTimeConstant));

        if (abs(newAnimation - _animation) > 0.001f)
        {
            _animation = newAnimation;
            setDirty();
        }
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        // dig a hole
        depthMap.fill(L16(0));

        // The switch is in a subrect
        int width = _position.width;
        int height = _position.height;
        float border = 0.1f;
        box2i switchRect = box2i( cast(int)(0.5f + width * border),
                                  cast(int)(0.5f + height * border),
                                  cast(int)(0.5f + width * (1 - border)),
                                  cast(int)(0.5f + height * (1 - border)) );

        bool isOn = _param.value();
        int emissive = cast(int)(0.5f + 1 + 194 * _animation);
        if (isMouseOver || isDragged)
            emissive += 60;

        RGBA diffuseColor = RGBA(diffuse.r, diffuse.g, diffuse.b, cast(ubyte)emissive);

        diffuseMap.crop(switchRect).fill(diffuseColor);

        ubyte shininess = 100;
        float colorLow = 0.0f;
        float colorHigh = 30000.0f;
        L16 depthUp = L16(cast(short)(lerp(colorHigh, colorLow, _animation)));
        L16 depthDown = L16(cast(short)(lerp(colorLow, colorHigh, _animation)));
        verticalSlope(depthMap, switchRect, depthUp, depthDown);
    
        materialMap.crop(switchRect).fill(material);
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

    override void onBeginParameterEdit(Parameter sender)
    {
    }

    override void onEndParameterEdit(Parameter sender)
    {
    }

protected:

    /// The parameter this switch is linked with.
    BoolParameter _param;

    bool _initialized = true; // destructor flag

private:
    float _animation;
}
