/**
Copyright: Guillaume Piolat 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module gui;

import std.math;

import gfm.math;
import dplug.gui;
import dplug.pbrwidgets;
import dplug.client;

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

    DistortClient _client;

    UISlider inputSlider;
    UIKnob driveKnob;
    UISlider outputSlider;
    UIOnOffSwitch onOffSwitch;
    UIBargraph inputBargraph, outputBargraph;
    UIColorCorrection colorCorrection;

    Font _font;

    KnobImage _knobImageData;
    UIImageKnob _imageKnob;

    this(DistortClient client)
    {
        _client = client;
        super(_initialWidth, _initialHeight); // size


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
        setUpdateMargin(19);

        // All resources are bundled as a string import.
        // You can avoid resource compilers that way.
        // The only cost is that each resource is in each binary, this creates overhead with
        _font = mallocNew!Font(cast(ubyte[])( import("VeraBd.ttf") ));

        // Builds the UI hierarchy
        // Note: when Dplug has resizeable UI, all positionning is going
        // to move into a reflow() override.
        // Meanwhile, we hardcode each position.

        KnobImage _knobImageData;

        _knobImageData = loadKnobImage( import("imageknob.png") );
        addChild(_imageKnob = mallocNew!UIImageKnob(context(), _knobImageData, cast(FloatParameter) _client.param(paramBias)));


        // Add procedural knobs
        addChild(driveKnob = mallocNew!UIKnob(context(), cast(FloatParameter) _client.param(paramDrive)));


        // Add sliders
        addChild(inputSlider = mallocNew!UISlider(context(), cast(FloatParameter) _client.param(paramInput)));
        

        addChild(outputSlider = mallocNew!UISlider(context(), cast(FloatParameter) _client.param(paramOutput)));
        

        // Add switch
        addChild(onOffSwitch = mallocNew!UIOnOffSwitch(context(), cast(BoolParameter) _client.param(paramOnOff)));
        

        // Add bargraphs
        addChild(inputBargraph = mallocNew!UIBargraph(context(), 2, -80.0f, 6.0f));
        
        addChild(outputBargraph = mallocNew!UIBargraph(context(), 2, -80.0f, 6.0f));
        
        static immutable float[2] startValues = [0.0f, 0.0f];
        inputBargraph.setValues(startValues);
        outputBargraph.setValues(startValues);

        // Global color correction.
        // Very useful at the end of the UI creating process.
        // As the sole Raw-only widget it is always on top and doesn't need zOrder adjustment.
        {
            mat3x4!float colorCorrectionMatrix = mat3x4!float(- 0.07f, 1.0f , 1.15f, 0.03f,
                                                              + 0.01f, 0.93f, 1.16f, 0.08f,
                                                              + 0.0f , 1.0f , 1.10f, -0.01f);
            addChild(colorCorrection = mallocNew!UIColorCorrection(context()));
            colorCorrection.setLiftGammaGainContrastRGB(colorCorrectionMatrix);
        }
    }

    override void reflow(box2i availableSpace)
    {
        super.reflow(availableSpace);

        RGBA litTrailDiffuse = RGBA(151, 119, 255, 100);
        RGBA unlitTrailDiffuse = RGBA(81, 54, 108, 0);

        _imageKnob.position = box2i.rectangle(relativeWidth(517), relativeHeight(176), relativeWidth(46), relativeHeight(46));
        _imageKnob.hasTrail = false; // no trail by default

        driveKnob.position = box2i.rectangle(relativeWidth(250), relativeHeight(140), relativeWidth(120), relativeHeight(120));
        driveKnob.knobRadius = 0.65f;
        driveKnob.knobDiffuse = RGBA(255, 255, 238, 0);
        driveKnob.knobMaterial = RGBA(0, 255, 128, 255);
        driveKnob.numLEDs = 15;
        driveKnob.litTrailDiffuse = litTrailDiffuse;
        driveKnob.unlitTrailDiffuse = unlitTrailDiffuse;
        driveKnob.LEDDiffuseLit = RGBA(40, 40, 40, 100);
        driveKnob.LEDDiffuseUnlit = RGBA(40, 40, 40, 0);
        driveKnob.LEDRadiusMin = 0.06f;
        driveKnob.LEDRadiusMax = 0.06f;

        inputSlider.position = box2i.rectangle(relativeWidth(190), relativeHeight(132), relativeWidth(30), relativeHeight(130));
        inputSlider.litTrailDiffuse = litTrailDiffuse;
        inputSlider.unlitTrailDiffuse = unlitTrailDiffuse;

        outputSlider.position = box2i.rectangle(relativeWidth(410), relativeHeight(132), relativeWidth(30), relativeHeight(130));
        outputSlider.litTrailDiffuse = litTrailDiffuse;
        outputSlider.unlitTrailDiffuse = unlitTrailDiffuse;

        onOffSwitch.position = box2i.rectangle(relativeWidth(90), relativeHeight(177), relativeWidth(30), relativeHeight(40));
        onOffSwitch.diffuseOn = litTrailDiffuse;
        onOffSwitch.diffuseOff = unlitTrailDiffuse;

        inputBargraph.position = box2i.rectangle(relativeWidth(150), relativeHeight(132), relativeWidth(30), relativeHeight(130));

        outputBargraph.position = box2i.rectangle(relativeWidth(450), relativeHeight(132), relativeWidth(30), relativeHeight(130));

        colorCorrection.position = box2i.rectangle(0, 0, _position.width, _position.height);
    }

    /// This on only a temporary addition for testing the resizing ability of dplug
    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        if(isDoubleClick)
        {
            if(_position.width == _initialHeight * 2)
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

    ~this()
    {
        _font.destroyFree();
        _knobImageData.destroyFree();        
    }

private:
    int _initialWidth = 620, _initialHeight = 330;

    int relativeWidth(int val)
    {
        return cast(int)((cast(float)val / _initialWidth) * _position.width);
    }

    int relativeHeight(int val)
    {
        return cast(int)((cast(float)val / _initialHeight) * _position.height);
    }
}
