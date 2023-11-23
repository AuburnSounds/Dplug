/**
On/Off switch.

Copyright: Copyright Auburn Sounds 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Guillaume Piolat
*/
module dplug.pbrwidgets.onoffswitch;

import std.math: exp, abs;
import dplug.core.math;
import dplug.gui.element;
import dplug.gui.bufferedelement;
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
    @ScriptProperty bool drawDepth = true;
    @ScriptProperty bool drawDiffuse = true;
    @ScriptProperty bool drawMaterial = true;
    @ScriptProperty bool drawHole = true;     // if drawDepth && drawHole, draw Z hole
    @ScriptProperty bool drawEmissive = true; // if drawEmissive && !drawDiffuse, draw just the emissive channel
    

    /// Left and right border, in fraction of the widget's width.
    /// Cannot be > 0.5f
    @ScriptProperty float borderHorz = 0.1f;

    /// Top and bottom border, in fraction of the widget's width.*
    /// Cannot be > 0.5f
    @ScriptProperty float borderVert = 0.1f;

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
        // The switch is in a subrect
        int width = _position.width;
        int height = _position.height;

        box2i switchRect = box2i( cast(int)(0.5f + width * borderHorz),
                                  cast(int)(0.5f + height * borderVert),
                                  cast(int)(0.5f + width * (1 - borderHorz)),
                                  cast(int)(0.5f + height * (1 - borderVert)) );

        ubyte red    = cast(ubyte)(lerp!float(diffuseOff.r, diffuseOn.r, _animation));
        ubyte green  = cast(ubyte)(lerp!float(diffuseOff.g, diffuseOn.g, _animation));
        ubyte blue   = cast(ubyte)(lerp!float(diffuseOff.b, diffuseOn.b, _animation));
        int emissive = cast(ubyte)(lerp!float(diffuseOff.a, diffuseOn.a, _animation));

        if (isMouseOver || isDragged)
            emissive += 40;

        if (emissive > 255)
            emissive = 255;

        // Workaround issue https://issues.dlang.org/show_bug.cgi?id=23076
        // Regular should not be inlined here.
        static float lerpfloat(float a, float b, float t) pure nothrow @nogc
        {
            pragma(inline, false);
            return t * b + (1 - t) * a;
        }

        L16 depthA = L16(cast(short)(lerpfloat(depthHigh, depthLow, _animation)));
        L16 depthB = L16(cast(short)(lerpfloat(depthLow, depthHigh, _animation)));

        RGBA diffuseColor = RGBA(red, green, blue, cast(ubyte)emissive);

        foreach(dirtyRect; dirtyRects)
        {
            auto cDepth = depthMap.cropImageRef(dirtyRect);

            // Write a plain color in the diffuse and material map.
            box2i validRect = dirtyRect.intersection(switchRect);
            if (!validRect.empty)
            {
                ImageRef!RGBA cDiffuse = diffuseMap.cropImageRef(validRect);
                if (drawDiffuse)
                {
                    cDiffuse.fillAll(diffuseColor);
                }
                else if (drawEmissive)
                {
                    cDiffuse.fillRectAlpha(0, 0, cDiffuse.w, cDiffuse.h, diffuseColor.a);
                }
                if (drawMaterial)
                    materialMap.cropImageRef(validRect).fillAll(material);
            }

            // dig a hole
            if (drawDepth)
            {
                if (drawHole)
                    cDepth.fillAll(L16(holeDepth));

                if (orientation == Orientation.vertical)
                    verticalSlope(cDepth, switchRect, depthA, depthB);
                else
                    horizontalSlope(cDepth, switchRect, depthA, depthB);
            }
        }
    }

    override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        if (!_canBeDragged)
        {
            // inside gesture, refuse new clicks that could call
            // excess beginParamEdit()/endParamEdit()
            return Click.unhandled;
        }

        // ALT + click => set it to default
        if (mstate.altPressed) // reset on ALT + click
        {
            _param.beginParamEdit();
            _param.setFromGUI(_param.defaultValue());
        }
        else
        {
            // Any click => invert
            // Note: double-click doesn't reset to default, would be annoying
            _param.beginParamEdit();
            _param.setFromGUI(!_param.value());
        }
        _canBeDragged = false;
        return Click.startDrag;
    }

    override void onMouseEnter()
    {
        _param.beginParamHover();
        setDirtyWhole();
    }

    override void onMouseExit()
    {
         _param.endParamHover();
        setDirtyWhole();
    }

    override void onStopDrag()
    {
        // End parameter edit at end of dragging, even if no parameter change happen,
        // so that touch automation restore previous parameter value at the end of the mouse 
        // gesture.
        _param.endParamEdit();
        _canBeDragged = true;
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

    override void onBeginParameterHover(Parameter sender)
    {
    }

    override void onEndParameterHover(Parameter sender)
    {
    }

protected:

    /// The parameter this switch is linked with.
    BoolParameter _param;

    /// To prevent multiple-clicks having an adverse effect on automation.
    bool _canBeDragged = true;

private:
    float _animation;
}

private:
void fillRectAlpha(bool CHECKED=true, V)(auto ref V v, int x1, int y1, int x2, int y2, ubyte alpha) nothrow @nogc
if (isWritableView!V && is(RGBA : ViewColor!V))
{
    sort2(x1, x2);
    sort2(y1, y2);
    static if (CHECKED)
    {
        if (x1 >= v.w || y1 >= v.h || x2 <= 0 || y2 <= 0 || x1==x2 || y1==y2) return;
        if (x1 <    0) x1 =   0;
        if (y1 <    0) y1 =   0;
        if (x2 >= v.w) x2 = v.w;
        if (y2 >= v.h) y2 = v.h;
    }

    foreach (y; y1..y2)
    {
        RGBA[] scan = v.scanline(y);
        foreach (x; x1..x2)
        {
            scan[x].a = alpha;
        }
    }
}