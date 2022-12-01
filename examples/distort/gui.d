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

                                     // In development, enter here the absolute path to the gfx directory.
                                     // This allows to reload background images at debug-time with the press of ENTER.
                                     `/home/myuser/my/path/to/Dplug/examples/distort/gfx/`)
{
public:
nothrow:
@nogc:

    this(DistortClient client)
    {
        _client = client;

        static immutable float[7] ratios = [0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
        super( makeSizeConstraintsDiscrete(620, 330, ratios) );

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
        setUpdateMargin(20); // TODO: put this in reflow, depends on scale factor

        // All resources are bundled as a string import.
        // You can avoid resource compilers that way.
        // The only cost is that each resource is in each binary, this creates overhead with
        _font = mallocNew!Font(cast(ubyte[])( import("VeraBd.ttf") ));

        // Builds the UI hierarchy
        // Meanwhile, we hardcode each position.  

        _knobImageData = loadKnobImage( import("imageknob.png") );
        addChild(_imageKnob = mallocNew!UIImageKnob(context(), _knobImageData, cast(FloatParameter) _client.param(paramBias)));

        // Add procedural knobs
        addChild(_driveKnob = mallocNew!UIKnob(context(), cast(FloatParameter) _client.param(paramDrive)));

        // Add sliders
        addChild(_inputSlider = mallocNew!UISlider(context(), cast(FloatParameter) _client.param(paramInput)));

        addChild(_outputSlider = mallocNew!UISlider(context(), cast(FloatParameter) _client.param(paramOutput)));

        // Add switch
        addChild(_onOffSwitch = mallocNew!UIOnOffSwitch(context(), cast(BoolParameter) _client.param(paramOnOff)));
  

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

        // Enable all things Wren
        mixin(fieldIdentifiersAreIDs!DistortGUI); // Each UIElement in this object receives its identifier as runtime ID, ie. _inputSlider receives ID "_inputSlider"
        context.enableWrenSupport();
        //debug
        //    context.wrenSupport.addModuleFileWatch("plugin", `/my/absolute/path/to/plugin.wren`); // debug => live reload, enter absolute path here
        //else
            context.wrenSupport.addModuleSource("plugin", import("plugin.wren"));                 // no debug => static scripts
        context.wrenSupport.registerScriptExports!DistortGUI; // Note: for now, only UIElement should be @ScriptExport
        context.wrenSupport.callCreateUI();
    }

    override void onAnimate(double dt, double time)
    {
        context.wrenSupport.callReflowWhenScriptsChange(dt);
    }

    ~this()
    {
        // Note: UI widgets are owned by the UI and don't need to be destroyed manually
        //       However some of the resources they consumed aren't owned by them, but borrowed.
        _font.destroyFree();
        _knobImageData.destroyFree();
        context.disableWrenSupport();

        version(Dplug_ProfileUI)
        {
            context.traceProfiler.saveToFile(`/home/myuser/plugin-trace.json`);
        }
    }

    override void reflow()
    {
        super.reflow();
        context.wrenSupport.callReflow();
    }

    void sendFeedbackToUI(float* inputRMS, float* outputRMS, int frames, float sampleRate)
    {
        _inputLevel.sendFeedbackToUI(inputRMS, frames, sampleRate);
        _outputLevel.sendFeedbackToUI(outputRMS, frames, sampleRate);
    }

private:
    DistortClient _client;

    // Resources
    Font _font;
    KnobImage _knobImageData;

    // Widgets can be exported to Wren. This allow styling through a plugin.wren script.
    @ScriptExport 
    {
        UISlider _inputSlider;
        UIKnob _driveKnob;
        UISlider _outputSlider;
        UIOnOffSwitch _onOffSwitch;
        UILevelDisplay _inputLevel, _outputLevel;
        UIColorCorrection _colorCorrection;
        UIImageKnob _imageKnob;
        UIWindowResizer _resizer;
    }
}

