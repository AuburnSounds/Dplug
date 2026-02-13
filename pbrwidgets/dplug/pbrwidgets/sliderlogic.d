/**
    Helper to make slider-like widgets.

    Copyright: Copyright Auburn Sounds 2015-2026.
    License:   http://www.boost.org/LICENSE_1_0.txt
    Authors:   Guillaume Piolat
*/
module dplug.pbrwidgets.sliderlogic;

import dplug.client.params;
import dplug.gui.element;

/**
    This makes a UIElement able to be a slider for one parameter.

    Encapsulate the slider logic, that sets a parameter for 
    a slider-like `UIelement` that would own a `SliderLogic`.

    `UISliderLogic` is NOT a `UIElement` itself but meant to be
    used as a member of a `UIElement`.    

    To use: 

        1. Initialize with the parameter in question.

         class MyUIElement
         {
             this(UIContext context, Parameter param)
             {
                 sliderLogic.initialize(this, param);
             }

         private:
             SliderLogic sliderLogic;
         }

        2. call `sliderLogic.mouseEnter()` in your `onMouseEnter()`
                `sliderLogic.mouseExit()`  in your `onMouseExit()`
                `sliderLogic.mouseClick()` in your `onMouseClick()`
                `sliderLogic.mouseDrag()`  in your `onMouseDrag()`
                `sliderLogic.stopDrag()`   in your `onStopDrag()`
*/
// FUTURE: allow IntegerParameter
// FUTURE: enable an horizontal mode
struct UISliderLogic
{
public:
nothrow:
@nogc:

    enum vertical = true; 

    /**
        Initialize the slider logic.
        Note: If you want to _disable_ your slider logic, just don't call
        other functions.
     */
    void initialize(UIElement elem, Parameter param)
    {
        _param = param;
        _elem = elem;
        clearCrosspoints();
    }

    /**
        Call this in `onMouseEnter`. Mark the parameter as hovered.
     */
    void mouseEnter()
    {
        _param.beginParamHover();
    }

    /**
         Call this in `onMouseExit`. Set the parameter as not-hovered.
    */
    void mouseExit()
    {
        _lastMouseX = MOUSE_TOO_FAR;
        _lastMouseY = MOUSE_TOO_FAR;
        _param.endParamHover();

        // We assume that the element show something for parameter hovered
        _elem.setDirtyWhole();
    }

    /**
        Call this in `onMouseClick`. This eventually resets the 
        parameter, and start a drag operation.
    */
    Click mouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        _lastMouseX = x;
        _lastMouseY = y;
        _param.beginParamEdit();
        if (isDoubleClick || mstate.altPressed)
        {
            // double-click or ALT => set to default
            if (auto p = cast(FloatParameter)_param)
            {
                p.setFromGUI(p.defaultValue());
            }
            else
                assert(false); // only float parameters supported
        }
        return Click.startDrag;
    }

    /**
        Call this in `onStopDrag`. This stop the drag operation.
    */
    void stopDrag()
    {
        _param.endParamEdit();
    }

    /**
        Call this in `onMouseDrag`.
    */
    void mouseDrag(int x, int y, int dx, int dy, MouseState mstate, float sensitivity = 1.0f)
    {
        _lastMouseX = x;
        _lastMouseY = y;

        float displacement = vertical ? (cast(float)(dy) / _elem.position.height) 
                                      : (cast(float)(-dx) / _elem.position.width);
        float coord = vertical ? y : ( _elem.position.width - x);

        float modifier = 1.0f;
        if (mstate.shiftPressed || mstate.ctrlPressed)
            modifier *= 0.1f;

        double oldParamValue = _param.getNormalized();

        double newParamValue = oldParamValue - displacement * modifier * sensitivity;
        if (mstate.altPressed)
            newParamValue = _param.getNormalizedDefault();

        if (coord > _mousePosOnLast0Cross)
            return;
        if (coord < _mousePosOnLast1Cross)
            return;

        if (newParamValue <= 0 && oldParamValue > 0)
            _mousePosOnLast0Cross = coord;

        if (newParamValue >= 1 && oldParamValue < 1)
            _mousePosOnLast1Cross = coord;

        if (newParamValue < 0)
            newParamValue = 0;
        if (newParamValue > 1)
            newParamValue = 1;

        if (newParamValue > 0)
            _mousePosOnLast0Cross = float.infinity;

        if (newParamValue < 1)
            _mousePosOnLast1Cross = -float.infinity;

        setValue(oldParamValue, newParamValue);
    }

    version(futureWidgetWheel)
    {
        bool mouseWheel(int x, int y,
                        int wheelDeltaX, int wheelDeltaY,
                        MouseState mstate,
                        float steps)
        {
            // In case of integer parameter, the step used for wheeling always match
            // the parameter.
            IntegerParameter paramInt = cast(IntegerParameter)_param;
            double actualSteps = paramInt !is null ? paramInt.numValues() : steps;

            double modifier = 1.0;
            if (paramInt is null)
            {
                if (mstate.shiftPressed || mstate.ctrlPressed)
                    modifier = 0.1;
            }

            double oldParamValue =  _param.getNormalized();
            double newParamValue = oldParamValue + modifier * wheelDeltaY / actualSteps;
            if (newParamValue < 0) newParamValue = 0;
            if (newParamValue > 1) newParamValue = 1;

            _param.beginParamEdit();
            setValue(oldParamValue, newParamValue);
            _param.endParamEdit();

            return true;
        }
    }

    ~this()
    {
    }


private:
    enum int MOUSE_TOO_FAR = 100_000;

    UIElement _elem;
    Parameter _param;

    float _mousePosOnLast0Cross;
    float _mousePosOnLast1Cross;

    int _lastMouseX = MOUSE_TOO_FAR;
    int _lastMouseY = MOUSE_TOO_FAR;

    void clearCrosspoints()
    {
        _mousePosOnLast0Cross = float.infinity;
        _mousePosOnLast1Cross = -float.infinity;
    }

    void setValue(double oldParamValue, double newParamValue)
    {
        if (newParamValue != oldParamValue)
        {
            if (auto p = cast(FloatParameter)_param)
            {
                p.setFromGUINormalized(newParamValue);
            }
            else
                assert(false); // only float parameters supported
        }
    }
}