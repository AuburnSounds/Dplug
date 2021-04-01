/**
Copyright: Guillaume Piolat 2015-2017
Copyright: Ethan Reker 2017
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module gui;

import dplug.gui;
import dplug.flatwidgets;
import dplug.client;
import dplug.canvas;

import main;

// Plugin GUI, based on FlatBackgroundGUI.
// This allows to use knobs rendered with Knobman
class ClipitGUI : FlatBackgroundGUI!("background.png")
{
public:
nothrow:
@nogc:

    ClipitClient _client;

    this(ClipitClient client)
    {
        _client = client;

        super(makeSizeConstraintsContinuous(500, 500, 0.5f, 2.0f));

        // Sets the number of pixels recomputed around dirtied controls.
        // Since we aren't using PBR we can set this value to 0 to save
        // on resources.
        // If you are mixing PBR and flat elements, you may want to set this
        // to a higher value such as 20.
        setUpdateMargin(0);

        // All resources are bundled as a string import.
        // You can avoid resource compilers that way.
        // The only cost is that each resource is in each binary, this creates overhead 
        OwnedImage!RGBA knobImage = loadOwnedImage(cast(ubyte[])(import("knob.png")));
        OwnedImage!RGBA switchOnImage = loadOwnedImage(cast(ubyte[])(import("switchOn.png")));
        OwnedImage!RGBA switchOffImage = loadOwnedImage(cast(ubyte[])(import("switchOff.png")));

        // Creates all widets and adds them as children to the GUI
        // widgets are not visible until their positions have been set
        int numFrames = 101;


        _inputGainKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramInputGain), knobImage, numFrames);
        addChild(_inputGainKnob);
        
        _clipKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramClip), knobImage, numFrames);
        addChild(_clipKnob);
        
        _outputGainKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramOutputGain), knobImage, numFrames);
        addChild(_outputGainKnob);
        
        _mixKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramMix), knobImage, numFrames);
        addChild(_mixKnob);

        addChild(_modeSwitch = mallocNew!UIImageSwitch(context(), cast(BoolParameter) _client.param(paramMode), switchOnImage, switchOffImage));       

        addChild(_resizerHint = mallocNew!UIWindowResizer(context()));        
    }

    override void reflow()
    {
        super.reflow();

        int W = position.width;
        int H = position.height;

        // Calculate weighted positions based on the width and height of the position
        int knobX1 = cast(int)(0.14 * W);
        int knobX2 = cast(int)(0.616 * W);
        int knobY1 = cast(int)(0.202 * H);
        int knobY2 = cast(int)(0.64 * H);
        int knobWidth = cast(int)(0.256 * W);
        int knobHeight = cast(int)(0.256 * H);

        _inputGainKnob.position  = box2i(knobX1, knobY1, knobX1 + knobWidth, knobY1 + knobHeight);
        _clipKnob.position       = box2i(knobX2, knobY1, knobX2 + knobWidth, knobY1 + knobHeight);
        _outputGainKnob.position = box2i(knobX1, knobY2, knobX1 + knobWidth, knobY2 + knobHeight);
        _mixKnob.position        = box2i(knobX2, knobY2, knobX2 + knobWidth, knobY2 + knobHeight);

        int switchX = cast(int)(0.76 * W);
        int switchY = cast(int)(0.056 * H);
        int switchWidth = cast(int)(0.1 * W);
        int switchHeight = cast(int)(0.04 * H);
 
        _modeSwitch.position = box2i(switchX, switchY, switchX + switchWidth, switchY  + switchHeight);      
        _resizerHint.position = rectangle(W-30, H-30, 30, 30);
    }

private:
    UIFilmstripKnob _inputGainKnob;
    UIFilmstripKnob _clipKnob;
    UIFilmstripKnob _outputGainKnob;
    UIFilmstripKnob _mixKnob;
    UIImageSwitch   _modeSwitch;
    UIWindowResizer _resizerHint;
}
