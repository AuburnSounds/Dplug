import std.math;

import gfm.image;

import dplug.plugin,
       dplug.vst,
       dplug.gui;

mixin(DLLEntryPoint!());
mixin(VSTEntryPoint!Distort);

/// Example mono/stereo distortion plugin.
final class Distort : dplug.plugin.Client
{
    this()
    {
    }

    override bool isSynth() pure const nothrow
    {
        return false;
    }

    override IGraphics createGraphics()
    {
        return new DistortGUI(this);
    }

    override int getPluginID() pure const nothrow
    {
        return CCONST('g', 'f', 'm', '0'); // change this!
    }

    override void buildParameters()
    {
        addParameter(new FloatParameter(this, 0, "input", "db", 0.0f, 2.0f, 1.0f));
        addParameter(new FloatParameter(this, 1, "drive", "%", 1.0f, 2.0f, 1.0f));
        addParameter(new FloatParameter(this, 2, "output", "db", 0.0f, 1.0f, 0.9f));
        addParameter(new BoolParameter(this, 3, "on/off", "", true));
    }

    // This override is optional, the default implementation will 
    // have one default preset.
    override void buildPresets()
    {
        presetBank.addPreset(makeDefaultPreset());
        presetBank.addPreset(new Preset("Silence", [0.0f, 0.0f, 0.0f, 1.0f]));
        presetBank.addPreset(new Preset("Full-on", [1.0f, 1.0f, 0.4f, 1.0f]));
    }

    override void buildLegalIO()
    {
        addLegalIO(1, 1);
        addLegalIO(1, 2);
        addLegalIO(2, 1);
        addLegalIO(2, 2);
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {
        // Clear here any state and delay buffers you might have.
    }

    override void processAudio(const(double*)[] inputs, double*[]outputs, int frames) nothrow @nogc
    {
        int numInputs = cast(int)inputs.length;
        int numOutputs = cast(int)outputs.length;

        int minChan = numInputs > numOutputs ? numOutputs : numInputs;

        float inputGain = (cast(FloatParameter)param(0)).value();
        float drive = (cast(FloatParameter)param(1)).value();
        float outputGain = (cast(FloatParameter)param(2)).value();

        bool enabled = (cast(BoolParameter)param(3)).value();

        if (enabled)
        {
            for (int chan = 0; chan < minChan; ++chan)
            {
                for (int f = 0; f < frames; ++f)
                {
                    double input = inputGain * 2.0 * inputs[chan][f];
                    double distorted = tanh(input * drive) / drive;
                    outputs[chan][f] = outputGain * distorted;
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
    }
}

class DistortGUI : GUIGraphics
{
    public:
    Distort _client;

    UIKnob inputKnob;
    UIKnob driveKnob;
    UIKnob outputKnob;
    UIOnOffSwitch onOffSwitch;

    Font _font;

    this(Distort client)
    {
        _client = client;
        super(620, 330); // initial size

        // Font data is bundled as a static array
        _font = new Font(cast(ubyte[])( import("VeraBd.ttf") ));
        context.setSkybox( loadImage(cast(ubyte[])(import("skybox.png"))) );

        addChild(inputKnob = new UIKnob(context(), cast(FloatParameter) _client.param(0)));
        addChild(driveKnob = new UIKnob(context(), cast(FloatParameter) _client.param(1)));
        addChild(outputKnob = new UIKnob(context(), cast(FloatParameter) _client.param(2)));
        addChild(onOffSwitch = new UIOnOffSwitch(context(), cast(BoolParameter) _client.param(3)));
    }

    override void reflow(box2i availableSpace)
    {
        _position = availableSpace;

        // For complex UI hierarchy or a variable dimension UI, you would be supposed to
        // put a layout algorithm here and implement reflow (ie. pass the right availableSpace
        // to children). But for simplicity purpose and for the sake of fixed size UI, forcing
        // positions is completely acceptable.
        int x = 100;
        int y = 100;
        int w = 100;
        int h = 100;
        int margin = 60;
        inputKnob.position = box2i(x, y, x + w, y + h);
        x += w + margin;
        driveKnob.position = box2i(x - 10, y, x + w + 10, y + h + 20);
        x += w + margin;
        outputKnob.position = box2i(x, y, x + w, y + h);

        onOffSwitch.position = box2i(90, _position.height - 80, 115, _position.height - 40);

        setDirty(); // mark the whole UI dirty
    }

    float time = 0;

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap, box2i dirtyRect)
    {
        auto croppedDiffuse = diffuseMap.crop(dirtyRect);
        auto croppedDepth = depthMap.crop(dirtyRect);

        // fill with clear color
        croppedDiffuse.fill(RGBA(239, 229, 213, 0));

        // fill with clear depth + shininess
        croppedDepth.fill(RGBA(58, 64, 0, 0));

        _font.size = 20;
        _font.color = RGBA(0, 0, 0, 0);

        diffuseMap.fillText(_font, "Input", 150, 70);
        diffuseMap.fillText(_font, "Drive", 310, 70);
        diffuseMap.fillText(_font, "Output", 470, 70);

        // Decorations
        auto hole = RGBA(32, 32, 0, 0);
        depthMap.fillRect(0, 0, 50, 330, hole);
        depthMap.fillRect(570, 0, 620, 330, hole);
        diffuseMap.fillRect(0, 0, 50, 330, RGBA(150, 140, 140, 0));
        diffuseMap.fillRect(570, 0, 620, 330, RGBA(150, 140, 140, 0));

        depthMap.softCircle(25, 25, 1, 7, RGBA(100, 255, 0, 0));
        depthMap.softCircle(25, 330-25, 1, 7, RGBA(100, 255, 0, 0));
        depthMap.softCircle(620-25, 330-25, 1, 7, RGBA(100, 255, 0, 0));
        depthMap.softCircle(620-25, 25, 1, 7, RGBA(100, 255, 0, 0));
    }
}

