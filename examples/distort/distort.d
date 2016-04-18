/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
import std.math;

import dplug.core,
       dplug.client,
       dplug.dsp,
       dplug.gui;

mixin(DLLEntryPoint!());

version(VST)
{
    import dplug.vst;
    mixin(VSTEntryPoint!Distort);
}

version(AU)
{
    import dplug.au;
    mixin(AUEntryPoint!Distort);
}

enum : int
{
    paramInput,
    paramDrive,
    paramOutput,
    paramOnOff,
    paramReserved,
}


/// Example mono/stereo distortion plugin.
final class Distort : dplug.client.Client
{
public:

    this()
    {
    }

    override IGraphics createGraphics()
    {
        return new DistortGUI(this); // still in flux
    }

    override PluginInfo buildPluginInfo()
    {
        // change all of these!
        PluginInfo info;
        info.isSynth = false;
        info.hasGUI = true;
        info.pluginID = dplug.core.funcs.CCONST('g', 'f', 'm', '0');
        info.productName = "Destructatorizer";
        info.effectName = "Destructatorizer";
        info.vendorName = "Distort Audio Ltd.";
        info.pluginVersion = 1000;
        return info;
    }

    // This is an optional overload, default is zero parameter.
    override Parameter[] buildParameters()
    {
        // Caution when adding parameters: always add the indices in the same order than the enum
        return [
            new GainParameter(paramInput, "input", 6.0, 0.0),
            new LinearFloatParameter(paramDrive, "drive", "%", 1.0f, 2.0f, 1.0f),
            new GainParameter(paramOutput, "output", 6.0, 0.0),
            new BoolParameter(paramOnOff, "on/off", true),
            new IntegerParameter(paramReserved, "reserved", "", 1, 4, 3),
        ];
    }

    // This override is optional, the default implementation will
    // have one default preset.
    override Preset[] buildPresets()
    {
        return [
            makeDefaultPreset(),
            new Preset("Silence", [0.0f, 0.0f, 0.0f, 1.0f, 0]),
            new Preset("Full-on", [1.0f, 1.0f, 0.4f, 1.0f, 0]),
        ];
    }

    // This override is also optional. It allows to split audio buffers in order to never
    // exceed some amount of frames at once.
    // This can be useful as a cheap chunking for parameter smoothing.
    // Buffer splitting allows to allocate statically or on the stack with less worries.
    override int maxFramesInProcess() pure const nothrow @nogc
    {
        return 128;
    }

    override LegalIO[] buildLegalIO()
    {
        return [
            LegalIO(1, 1),
            LegalIO(1, 2),
            LegalIO(2, 1),
            LegalIO(2, 2),
        ];
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {
        // Clear here any state and delay buffers you might have.

        assert(maxFrames <= 128); // guaranteed by audio buffer splitting

        foreach(channel; 0..2)
        {
            _inputRMS[channel].initialize(sampleRate);
            _outputRMS[channel].initialize(sampleRate);
        }
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info) nothrow @nogc
    {
        assert(frames <= 128); // guaranteed by audio buffer splitting

        int numInputs = cast(int)inputs.length;
        int numOutputs = cast(int)outputs.length;

        int minChan = numInputs > numOutputs ? numOutputs : numInputs;

        float inputGain = deciBelToFloat(readFloatParamValue(paramInput));
        float drive = readFloatParamValue(paramDrive);
        float outputGain = deciBelToFloat(readFloatParamValue(paramOutput));

        bool enabled = readBoolParamValue(paramOnOff);

        float[2] RMS = 0;

        if (enabled)
        {
            for (int chan = 0; chan < minChan; ++chan)
            {
                for (int f = 0; f < frames; ++f)
                {
                    float inputSample = inputGain * 2.0 * inputs[chan][f];

                    // Feed the input RMS computation
                    _inputRMS[chan].nextSample(inputSample);

                    // Distort signal
                    float distorted = tanh(inputSample * drive) / drive;
                    float outputSample = outputGain * distorted;
                    outputs[chan][f] = outputSample;

                    // Feed the output RMS computation
                    _outputRMS[chan].nextSample(outputSample);
                }
            }
        }
        else
        {
            // Bypass mode
            for (int chan = 0; chan < minChan; ++chan)
                outputs[chan][0..frames] = inputs[chan][0..frames];
        }

        // fill with zero the remaining channels
        for (int chan = minChan; chan < numOutputs; ++chan)
            outputs[chan][0..frames] = 0; // D has array slices assignments and operations

        // Update RMS meters from the audio callback
        DistortGUI gui = cast(DistortGUI) graphics();
        if (gui !is null)
        {
            float[2] inputLevels;
            inputLevels[0] = floatToDeciBel(_inputRMS[0].RMS());
            inputLevels[1] = minChan >= 1 ? floatToDeciBel(_inputRMS[1].RMS()) : inputLevels[0];
            gui.inputBargraph.setValues(inputLevels);

            float[2] outputLevels;
            outputLevels[0] = floatToDeciBel(_outputRMS[0].RMS());
            outputLevels[1] = minChan >= 1 ? floatToDeciBel(_outputRMS[1].RMS()) : outputLevels[0];
            gui.outputBargraph.setValues(outputLevels);
        }
    }

private:
    CoarseRMS!float[2] _inputRMS;
    CoarseRMS!float[2] _outputRMS;
}

class DistortGUI : GUIGraphics
{
public:
    Distort _client;

    UISlider inputSlider;
    UIKnob driveKnob;
    UISlider outputSlider;
    UIOnOffSwitch onOffSwitch;
    UIBargraph inputBargraph, outputBargraph;
    UILabel inputLabel, driveLabel, outputLabel, onLabel, offLabel;
    UIPanel leftPanel, rightPanel;

    Font _font;

    this(Distort client)
    {
        _client = client;
        super(620, 330); // initial size

        // Font data is bundled as a static array
        _font = new Font(cast(ubyte[])( import("VeraBd.ttf") ));
        context.setSkybox( loadImage(cast(ubyte[])(import("skybox.jpg"))) );

        // Buils the UI hierarchy
        addChild(inputSlider = new UISlider(context(), cast(FloatParameter) _client.param(paramInput)));
        addChild(driveKnob = new UIKnob(context(), cast(FloatParameter) _client.param(paramDrive)));
        addChild(outputSlider = new UISlider(context(), cast(FloatParameter) _client.param(paramOutput)));
        addChild(onOffSwitch = new UIOnOffSwitch(context(), cast(BoolParameter) _client.param(paramOnOff)));

        addChild(inputBargraph = new UIBargraph(context(), 2, -80.0f, 6.0f));
        addChild(outputBargraph = new UIBargraph(context(), 2, -80.0f, 6.0f));

        RGBA textColor = RGBA(32, 16, 16, 0);
        addChild(inputLabel = new UILabel(context(), _font, "Input"));
        inputLabel.textSize = 17;
        inputLabel.textColor = textColor;

        addChild(driveLabel = new UILabel(context(), _font, "Drive"));
        driveLabel.textSize = 17;
        driveLabel.textColor = textColor;

        addChild(outputLabel = new UILabel(context(), _font, "Output"));
        outputLabel.textSize = 17;
        outputLabel.textColor = textColor;

        addChild(onLabel = new UILabel(context(), _font, "ON"));
        onLabel.textSize = 13;
        onLabel.textColor = textColor;

        addChild(offLabel = new UILabel(context(), _font, "OFF"));
        offLabel.textSize = 13;
        offLabel.textColor = textColor;

        addChild(leftPanel = new UIPanel(context(), RGBA(150, 140, 140, 0),
                                                    RMSP(128, 255, 255, 255), L16(defaultDepth / 2)));
        addChild(rightPanel = new UIPanel(context(), RGBA(150, 140, 140, 0),
                                                     RMSP(128, 255, 255, 255), L16(defaultDepth / 2)));

        inputBargraph.setValues([1.0f, 0.5f]);
        outputBargraph.setValues([0.7f, 0.0f]);
    }

    ~this()
    {
        debug ensureNotInGC("DistortGUI");
        _font.destroy();
    }

    override void reflow(box2i availableSpace)
    {
        _position = availableSpace;

        // For complex UI hierarchy or a variable dimension UI, you would be supposed to
        // put a layout algorithm here and implement reflow (ie. pass the right availableSpace
        // to children). But for simplicity purpose and for the sake of fixed size UI, forcing
        // positions is completely acceptable.
        inputSlider.position = box2i(135, 100, 165, 230).translate(vec2i(40, 0));
        driveKnob.position = box2i(250, 105, 250 + 120, 105 + 120).translate(vec2i(30, 0));
        outputSlider.position = box2i(455, 100, 485, 230).translate(vec2i(-20, 0));

        onOffSwitch.position = box2i(110, 145, 140, 185);

        inputBargraph.position = inputSlider.position.translate(vec2i(30, 0));
        outputBargraph.position = outputSlider.position.translate(vec2i(30, 0));

        inputLabel.setCenterAndResize(210, 70);
        driveLabel.setCenterAndResize(340, 65);
        outputLabel.setCenterAndResize(470, 70);
        onLabel.setCenterAndResize(125, 123);
        offLabel.setCenterAndResize(125, 210);

        leftPanel.position = box2i(0, 0, 50, 330);
        rightPanel.position = box2i(570, 0, 620, 330);
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        // In onDraw, you are supposed to only update diffuseMap and depthMap in the dirtyRects areas.
        // This rules can be broken when sufficiently far from another UIElement.

        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuse = diffuseMap.crop(dirtyRect);


            // fill with clear color
            // Albedo RGB + Emissive
            for (int y = dirtyRect.min.y; y < dirtyRect.max.y; ++y)
            {
                RGBA[] outDiffuse = diffuseMap.scanline(y);
                ubyte emissive = 0; // for rendering efficiency, avoid emissive background
                for (int x = dirtyRect.min.x; x < dirtyRect.max.x; ++x)
                {
                    int r = 233;
                    int g = 235;
                    int b = 236;
                    float randomPhase = ( ((y + 1013904223) * 1664525) & 511) * 2 * PI / 32;
                    int sine = cast(int)(4 * sin(randomPhase + x * 2 * PI / 150 + ( (y & 3) ? PI : 0 )));
                    r += sine;
                    g += sine;
                    b += sine;
                    RGBA color = RGBA(cast(ubyte)r, cast(ubyte)g, cast(ubyte)b, emissive);
                    outDiffuse[x] = color;
                }
            }

            // default depth is approximately ~22% of the possible height, but you can choose any other value
            for (int y = dirtyRect.min.y; y < dirtyRect.max.y; ++y)
            {
                L16[] outDepth = depthMap.scanline(y);
                for (int x = dirtyRect.min.x; x < dirtyRect.max.x; ++x)
                {
                    int randomX = x * 1664525 + 1013904223;
                    int randomDepth = (69096 * (y + randomX)) & 127;
                    ushort depth = cast(ushort)( defaultDepth + randomDepth );
                    outDepth[x] = L16(depth);
                }
            }

            // fill material map
            // Roughness Metalness Specular Physical
            auto croppedMaterial = materialMap.crop(dirtyRect);
            croppedMaterial.fill(RMSP(120, 255, 128, 255));
        }
    }
}

