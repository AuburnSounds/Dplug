/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.toolkit.slider;

import std.math;
import dplug.gui.toolkit.element;
import dplug.gui.drawex;
import dplug.plugin.params;

class UISlider : UIElement, IParameterListener
{
public:

    this(UIContext context, FloatParameter param)
    {
        super(context);
        _param = param;
        _param.addListener(this);

        _sensivity = 1.0f;
    }

    override void close()
    {
        _param.removeListener(this);
    }

    /// Returns: sensivity.
    float sensivity()
    {
        return _sensivity;
    }

    /// Sets sensivity.
    float sensivity(float sensivity)
    {
        return _sensivity = sensivity;
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap, box2i[] dirtyRects)
    {
        // dig a metal hole
      //  depthMap.crop(dirtyRect).fill(RGBA(0, 64, 0, 0));
      //  diffuseMap.crop(dirtyRect).fill(RGBA(64, 64, 64, 0));

        // dig a thinner hole

        // The switch is in a subrect

        int width = _position.width;
        int height = _position.height;

        box2i deeperHole = 
            box2i ( cast(int)(0.5f + width * 0.35f),
                    2,
                   cast(int)(0.5f + width * (1-0.35f)),
                    height - 2 );

        
        

       

        float value = _param.getNormalized();

        int handleHeight = (height + 2) / 4;
        int handleWidth = cast(int)(0.5f + width * 0.7f);

        int posX = cast(int)(0.5f + (width - handleWidth) / 2);
        int posY = cast(int)(0.5f + (1 - value) * (height - handleHeight));
        assert(posX >= 0);
        assert(posY >= 0);

        box2i handleRect = box2i(posX, posY, posX + handleWidth, posY + handleHeight);


        // Paint deeper hole
        {
            box2i deeperHoleBlack = box2i(deeperHole.min.x, deeperHole.min.y, deeperHole.max.x, std.algorithm.max(deeperHole.min.y, posY - 1));
            box2i deeperHoleLit = box2i(deeperHole.min.x, std.algorithm.min(deeperHole.max.y, posY + handleHeight), deeperHole.max.x, deeperHole.max.y);
            
            diffuseMap.crop(deeperHoleBlack).fill(RGBA(150, 40, 20, 16));
            diffuseMap.crop(deeperHoleLit).fill(RGBA(230, 80, 43, 128));
            depthMap.crop(deeperHole).fill(RGBA(0, 64, 0, 0));
        }

        // Paint handle of slider
        {
            ubyte emissive = 16;
            if (isDragged || isMouseOver)
                emissive = 64;

            ubyte shininess = 255;

            diffuseMap.crop(handleRect).fill(RGBA(230, 230, 230, emissive));

            auto c0 = RGBA(58, shininess, 0, 0);
            auto c1 = RGBA(255, shininess, 0, 0);
            auto c2 = RGBA(200, shininess, 0, 0);

            int h0 = handleRect.min.y;
            int h1 = (handleRect.min.y * 3 + handleRect.max.y + 2) / 4;
            int h2 = handleRect.center.y;
            int h3 = (handleRect.min.y + handleRect.max.y * 3 + 2) / 4;
            int h4 = handleRect.max.y;

            verticalSlope(depthMap, box2i(handleRect.min.x, h0, handleRect.max.x, h1), c0, c1);
            verticalSlope(depthMap, box2i(handleRect.min.x, h1, handleRect.max.x, h2), c1, c2);
            verticalSlope(depthMap, box2i(handleRect.min.x, h2, handleRect.max.x, h3), c2, c1);
            verticalSlope(depthMap, box2i(handleRect.min.x, h3, handleRect.max.x, h4), c1, c0);

            
        }
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        // double-click => set to default
        if (isDoubleClick)
        {
            _param.setFromGUI(_param.defaultValue());
        }

        return true; // to initiate dragging
    }

    // Called when mouse drag this Element.
    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
        float displacementInHeight = cast(float)(dy) / _position.height;
        float extent = _param.maxValue() - _param.minValue();

        float modifier = 1.0f;
        if (mstate.shiftPressed || mstate.ctrlPressed)
            modifier *= 0.1f;

        // TODO: this will break with log params
        float currentValue = _param.value();
        _param.setFromGUI(currentValue - displacementInHeight * modifier * _sensivity * extent);
    }

    // For lazy updates
    override void onBeginDrag()
    {
        _param.beginParamEdit();
        setDirty();
    }

    override  void onStopDrag()
    {
        _param.endParamEdit();
        setDirty();
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
    FloatParameter _param;

    /// Sensivity: given a mouse movement in 100th of the height of the knob, 
    /// how much should the normalized parameter change.
    float _sensivity;
}
