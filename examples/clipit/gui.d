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

        super(500, 500); // fixed size

        //static immutable float[8] scales = [1.0f, 1.25f, 1.5f];
        //super(makeSizeConstraintsDiscrete(500, 500, scales)); // WIP

        //super(makeSizeConstraintsContinuous(500, 500, 1.0f, 3.0f)); // WIP

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

        immutable int knobX1 = 70;
        immutable int knobX2 = 308;
        immutable int knobY1 = 101;
        immutable int knobY2 = 320;
        immutable int knobWidth = 128;
        immutable int knobHeight = 128;

        _inputGainKnob.position = box2i(knobX1, knobY1, knobX1 + knobWidth, knobY1 + knobHeight);
        _clipKnob.position = box2i(knobX2, knobY1, knobX2 + knobWidth, knobY1 + knobHeight);
        _outputGainKnob.position = box2i(knobX1, knobY2, knobX1 + knobWidth, knobY2 + knobHeight);
        _mixKnob.position = box2i(knobX2, knobY2, knobX2 + knobWidth, knobY2 + knobHeight);

        immutable int switchX = 380;
        immutable int switchY = 28;
        immutable int switchWidth = 51;
        immutable int switchHeight = 21;

        _modeSwitch.position = box2i(switchX, switchY, switchX + switchWidth, switchY  + switchHeight);
        _resizerHint.position = rectangle(W-20, H-20, 20, 20);
    }

    // This is just to show how to use with dplug:canvas
    override void onDrawRaw(ImageRef!RGBA rawMap,box2i[] dirtyRects) 
    {
        super.onDrawRaw(rawMap,dirtyRects);

        foreach(dirtyRect; dirtyRects)
        {
            auto cRaw = rawMap.cropImageRef(dirtyRect);
            canvas.initialize(cRaw);
            canvas.translate(-dirtyRect.min.x, -dirtyRect.min.y);

            // gradients have to be recreated for each dirtyRect
            auto gradient = canvas.createLinearGradient(0, 0, 100*1.414, 100*1.414);
            gradient.addColorStop(0.0f, RGBA(255, 50, 128, 255));
            gradient.addColorStop(1.0f, RGBA(128, 128, 128, 0));

         //   canvas.fillStyle = RGBA(255, 0, 0, 255);//gradient;
/*
            canvas.beginPath;
                canvas.moveTo(0, 0);
                canvas.lineTo(200, 0);
                canvas.lineTo(0, 200);
                canvas.fill();*/
        }

    }

private:
    Canvas canvas;
    
    UIFilmstripKnob _inputGainKnob;
    UIFilmstripKnob _clipKnob;
    UIFilmstripKnob _outputGainKnob;
    UIFilmstripKnob _mixKnob;
    UIImageSwitch   _modeSwitch;
    UIWindowResizer _resizerHint;
}
