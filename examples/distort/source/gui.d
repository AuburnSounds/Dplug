module gui;

import core.stdc.stdlib;

import std.math;

import dplug.core;
import dplug.math;
import dplug.gui;
import dplug.pbrwidgets;
import dplug.client;
import dplug.flatwidgets;
import dplug.wren;
import leveldisplay;
import main;

//debug = voxelExport;

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
        // This needs to be adjusted visually.
        setUpdateMargin(30);

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

        debug(voxelExport)
            context.requestUIScreenshot(); // onScreenshot will be called at next render, can be called from anywhere
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
            writeFile(`/home/myuser/plugin-trace.json`, context.profiler.toBytes());
            browseNoGC("https://ui.perfetto.dev/"); // A webtool to read that trace
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

    debug(voxelExport)
    {
        // Show how to do a .qb export of final PBR render
        override void onScreenshot(ImageRef!RGBA finalRender,
                                   WindowPixelFormat pixelFormat,
                                   ImageRef!RGBA diffuseMap,
                                   ImageRef!L16 depthMap,
                                   ImageRef!RGBA materialMap)
        {
            ubyte[] qb = encodeScreenshotAsQB(finalRender, pixelFormat, depthMap); // alternatively: encodeScreenshotAsPNG
            if (qb)
            {
                writeFile(`/my/path/to/distort.qb`, qb);
                free(qb.ptr);
            }
        }
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

