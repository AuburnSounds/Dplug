/**
Copyright: Ethan Reker 2023
License: MIT
*/
module gui;

import dplug.gui;
import dplug.flatwidgets;
import dplug.client;
import dplug.canvas;

import main;

class ExampleGUI : FlatBackgroundGUI!("background.png",
                                     `$HOME/Programming/dplug-faust-example/gfx/`)
{
public:
nothrow:
@nogc:

    ExampleClient _client;

    this(ExampleClient client)
    {
        _client = client;

        static immutable float[7] ratios = [0.5f, 1.0f, 1.5f, 2.0f, 3.0f];
        super( makeSizeConstraintsDiscrete(352, 108, ratios) );

        setUpdateMargin(0);

        OwnedImage!RGBA knobImage = loadOwnedImage(cast(ubyte[])(import("knob.png")));

        int numFrames = 100;

        _dampKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramDamp), knobImage, numFrames);
        addChild(_dampKnob);

        _roomSizeKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramRoomSize), knobImage, numFrames);
        addChild(_roomSizeKnob);

        _stereoSpreadKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramStereoSpread), knobImage, numFrames);
        addChild(_stereoSpreadKnob);

        _wetKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramWet), knobImage, numFrames);
        addChild(_wetKnob);

        addChild(_resizerHint = mallocNew!UIWindowResizer(context()));
    }

    override void reflow()
    {
        super.reflow();

        int W = position.width;
        int H = position.height;

        float S = W / cast(float)(context.getDefaultUIWidth());

        immutable int knobWidth = 64;
        immutable int knobHeight = 64;

        _dampKnob.position =         rectangle(12,  32, knobWidth, knobHeight).scaleByFactor(S);
        _roomSizeKnob.position =     rectangle(100, 32, knobWidth, knobHeight).scaleByFactor(S);
        _stereoSpreadKnob.position = rectangle(188, 32, knobWidth, knobHeight).scaleByFactor(S);
        _wetKnob.position =          rectangle(276, 32, knobWidth, knobHeight).scaleByFactor(S);

        _resizerHint.position = rectangle(W-30, H-30, 30, 30);
    }

private:
    UIFilmstripKnob _dampKnob;
    UIFilmstripKnob _roomSizeKnob;
    UIFilmstripKnob _stereoSpreadKnob;
    UIFilmstripKnob _wetKnob;
    UIWindowResizer _resizerHint;
}
