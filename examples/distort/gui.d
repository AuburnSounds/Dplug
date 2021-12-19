/**
Copyright: Guillaume Piolat 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module gui;

import std.math;

import dplug.math;
import dplug.gui;
import dplug.pbrwidgets;
import dplug.client;
import dplug.flatwidgets;
import dplug.wren;
import leveldisplay;
import main;


// Plugin GUI, based on PBRBackgroundGUI.
// If you don't want to use PBR, you not inherit from it.
class DistortGUI : PBRBackgroundGUI!("basecolor.jpg", "emissive.png", "material.png",
                                     "depth.png", "skybox.jpg",

                                     // Enter here the absolute path to the gfx directory.
                                     // This will allow to reload images at debug-time with the press of ENTER.
                                     `C:\Users\myuser\Products\distort\gfx\`)
{
public:
nothrow:
@nogc:

    this(DistortClient client)
    {
        _client = client;

        static immutable float[7] ratios = [0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
        super( makeSizeConstraintsDiscrete(620, 330, ratios) );


        context.enableWrenSupport();

        // Not yet supported
        //context.wrenSupport.registerUIElement!UIKnob();

        // Note: PBRCompositor default lighting might change in a future version (increase of light to allow white plastics).
        //       So we keep the value.
        PBRCompositor comp = cast(PBRCompositor)compositor;
        comp.light1Color = vec3f(0.26, 0.24, 0.22f) * 0.98f;
        comp.light2Dir = vec3f(-0.5f, 1.0f, 0.23f).normalized;
        comp.light2Color = vec3f(0.36, 0.38f, 0.40) * 1.148;
        comp.light3Dir = vec3f(0.0f, 1.0f, 0.1f).normalized;
        comp.light3Color = vec3f(0.2f, 0.2f, 0.2f) * 0.84f;
        comp.ambientLight = 0.042f;
        comp.skyboxAmount = 0.56f;

        // Sets the number of pixels recomputed around dirtied controls.
        // This is a tradeoff between Emissive light accuracy and speed.
        // A typical good value is 20, and this is the default, as this is
        // what `PBRCompositor` needs for the emissive pass.
        setUpdateMargin(20);

        // All resources are bundled as a string import.
        // You can avoid resource compilers that way.
        // The only cost is that each resource is in each binary, this creates overhead with
        _font = mallocNew!Font(cast(ubyte[])( import("VeraBd.ttf") ));

        // Builds the UI hierarchy
        // Meanwhile, we hardcode each position.

        RGBA litTrailDiffuse = RGBA(151, 119, 255, 100);
        RGBA unlitTrailDiffuse = RGBA(81, 54, 108, 0);

        _knobImageData = loadKnobImage( import("imageknob.png") );
        addChild(_imageKnob = mallocNew!UIImageKnob(context(), _knobImageData, cast(FloatParameter) _client.param(paramBias)));
        _imageKnob.hasTrail = false; // no trail by default

        // Add procedural knobs
        addChild(_driveKnob = mallocNew!UIKnob(context(), cast(FloatParameter) _client.param(paramDrive)));
        _driveKnob.knobRadius = 0.65f;
        _driveKnob.knobDiffuse = RGBA(255, 255, 238, 0);
        _driveKnob.knobMaterial = RGBA(0, 255, 128, 255);
        _driveKnob.numLEDs = 15;
        _driveKnob.litTrailDiffuse = litTrailDiffuse;
        _driveKnob.unlitTrailDiffuse = unlitTrailDiffuse;
        _driveKnob.LEDDiffuseLit = RGBA(40, 40, 40, 100);
        _driveKnob.LEDDiffuseUnlit = RGBA(40, 40, 40, 0);
        _driveKnob.LEDRadiusMin = 0.06f;
        _driveKnob.LEDRadiusMax = 0.06f;

        // Add sliders
        addChild(_inputSlider = mallocNew!UISlider(context(), cast(FloatParameter) _client.param(paramInput)));
        _inputSlider.litTrailDiffuse = litTrailDiffuse;
        _inputSlider.unlitTrailDiffuse = unlitTrailDiffuse;

        addChild(_outputSlider = mallocNew!UISlider(context(), cast(FloatParameter) _client.param(paramOutput)));
        _outputSlider.litTrailDiffuse = litTrailDiffuse;
        _outputSlider.unlitTrailDiffuse = unlitTrailDiffuse;

        // Add switch
        addChild(_onOffSwitch = mallocNew!UIOnOffSwitch(context(), cast(BoolParameter) _client.param(paramOnOff)));
        _onOffSwitch.diffuseOn = litTrailDiffuse;
        _onOffSwitch.diffuseOff = unlitTrailDiffuse;

        // Add bargraphs
        addChild(_inputLevel = mallocNew!UILevelDisplay(context()));
        addChild(_outputLevel = mallocNew!UILevelDisplay(context()));

        // Add resizer corner
        addChild(_resizer = mallocNew!UIWindowResizer(context()));

        // Global color correction.
        // Very useful at the end of the UI creating process.
        // As the sole Raw-only widget it is always on top and doesn't need zOrder adjustment.
        {
            mat3x4!float colorCorrectionMatrix = mat3x4!float(- 0.07f, 1.0f , 1.15f, 0.03f,
                                                              + 0.01f, 0.93f, 1.16f, 0.08f,
                                                              + 0.0f , 1.0f , 1.10f, -0.01f);
            addChild(_colorCorrection = mallocNew!UIColorCorrection(context()));
            _colorCorrection.setLiftGammaGainContrastRGB(colorCorrectionMatrix);
        }
    }

    ~this()
    {
        // Note: UI widgets are owned by the UI and don't need to be destroyed manually
        //       However some of the resources they consumed aren't owned by them, but borrowed.
        _font.destroyFree();
        _knobImageData.destroyFree();
        context.disableWrenSupport();
    }

    override void reflow()
    {
        super.reflow();
        int W = position.width;
        int H = position.height;
        float S = W / cast(float)(context.getDefaultUIWidth());
        _imageKnob.position = rectangle(517, 176, 46, 46).scaleByFactor(S);
        _inputSlider.position = rectangle(190, 132, 30, 130).scaleByFactor(S);
        _outputSlider.position = rectangle(410, 132, 30, 130).scaleByFactor(S);
        _onOffSwitch.position = rectangle(90, 177, 30, 40).scaleByFactor(S);
        _driveKnob.position = rectangle(250, 140, 120, 120).scaleByFactor(S);
        _inputLevel.position = rectangle(150, 132, 30, 130).scaleByFactor(S);
        _outputLevel.position = rectangle(450, 132, 30, 130).scaleByFactor(S);

        _colorCorrection.position = rectangle(0, 0, W, H);
        _resizer.position = rectangle(W-30, H-30, 30, 30);

        // That currently works.
        //context.wrenSupport.interpret("none.wren", `System.print("hello")`);
    }

    void sendFeedbackToUI(float* inputRMS, float* outputRMS, int frames, float sampleRate)
    {
        _inputLevel.sendFeedbackToUI(inputRMS, frames, sampleRate);
        _outputLevel.sendFeedbackToUI(outputRMS, frames, sampleRate);
    }

private:
    DistortClient _client;
    UISlider _inputSlider;
    UIKnob _driveKnob;
    UISlider _outputSlider;
    UIOnOffSwitch _onOffSwitch;
    UILevelDisplay _inputLevel, _outputLevel;
    UIColorCorrection _colorCorrection;
    Font _font;
    KnobImage _knobImageData;
    UIImageKnob _imageKnob;
    UIWindowResizer _resizer;
}
