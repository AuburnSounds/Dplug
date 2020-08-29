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

    UIFilmstripKnob inputGainKnob;
    UIFilmstripKnob clipKnob;
    UIFilmstripKnob outputGainKnob;
    UIFilmstripKnob mixKnob;
    UIImageSwitch modeSwitch;

    this(ClipitClient client)
    {
        _client = client;
        super(_initialWidth, _initialHeight); // size

        // Sets the number of pixels recomputed around dirtied controls.
        // Since we aren't using pbr we can set this value to 0 to save
        // on resources.
        // If you are mixing pbr and flat elements, you may want to set this
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
        inputGainKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramInputGain), knobImage, numFrames);
        addChild(inputGainKnob);
        clipKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramClip), knobImage, numFrames);
        addChild(clipKnob);
        outputGainKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramOutputGain), knobImage, numFrames);
        addChild(outputGainKnob);
        mixKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramMix), knobImage, numFrames);
        addChild(mixKnob);
        modeSwitch = mallocNew!UIImageSwitch(context(), cast(BoolParameter) _client.param(paramMode), switchOnImage, switchOffImage);
        addChild(modeSwitch);
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

            canvas.fillStyle = gradient;

            canvas.beginPath;
                canvas.moveTo(0, 0);
                canvas.lineTo(200, 0);
                canvas.lineTo(0, 200);
                canvas.fill();
        }

    }

    override void reflow(box2i availableSpace)
    {
        super.reflow(availableSpace);
        _position = availableSpace;

        // Builds the UI hierarchy
        immutable int W = _position.width;
        immutable int H = _position.height;
        
        // Calculate weighted positions based on the width and height of the position
        immutable int knobX1 = cast(int)(0.14 * W);
        immutable int knobX2 = cast(int)(0.616 * W);
        immutable int knobY1 = cast(int)(0.202 * H);
        immutable int knobY2 = cast(int)(0.64 * H);
        immutable int knobWidth = cast(int)(0.256 * W);
        immutable int knobHeight = cast(int)(0.256 * H);

        inputGainKnob.reflow(box2i(knobX1, knobY1, knobX1 + knobWidth, knobY1 + knobHeight));
        clipKnob.reflow(box2i(knobX2, knobY1, knobX2 + knobWidth, knobY1 + knobHeight));
        outputGainKnob.reflow(box2i(knobX1, knobY2, knobX1 + knobWidth, knobY2 + knobHeight));
        mixKnob.reflow(box2i(knobX2, knobY2, knobX2 + knobWidth, knobY2 + knobHeight));

        immutable int switchX = cast(int)(0.76 * W);
        immutable int switchY = cast(int)(0.056 * H);
        immutable int switchWidth = cast(int)(0.1 * W);
        immutable int switchHeight = cast(int)(0.04 * H);

        modeSwitch.reflow(box2i(switchX, switchY, switchX + switchWidth, switchY  + switchHeight));
    }

    /// This on only a temporary addition for testing the resizing ability of dplug
    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        if(isDoubleClick)
        {
            if(_position.width == 1000)
            {
                _client.hostCommand().requestResize(_initialWidth, _initialHeight);
            }
            else
            {
                _client.hostCommand().requestResize(_initialWidth * 2, _initialHeight * 2);
            }
            return true;
        }
        return false;
    }

    // this struct object should not be since it contains everything rasterizer-related
    Canvas canvas; 

private:
    int _initialWidth = 500, _initialHeight = 500;
}
