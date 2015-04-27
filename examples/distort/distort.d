import std.math;

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
        addParameter(new FloatParameter("input", "db", 0.0f, 2.0f, 1.0f));
        addParameter(new FloatParameter("drive", "%", 1.0f, 2.0f, 1.0f));
        addParameter(new FloatParameter("output", "db", 0.0f, 1.0f, 0.9f));
    }

    override void buildLegalIO()
    {
        addLegalIO(1, 1);
        addLegalIO(1, 2);
        addLegalIO(2, 1);
        addLegalIO(2, 2);
    }

    override void reset(double sampleRate, int maxFrames)
    {
        // Clear here any state and delay buffers you might have.
    }

    override void processAudio(double **inputs, double **outputs, int frames) nothrow @nogc
    {
        int numInputs = maxInputs();
        int numOutputs = maxOutputs();

        int minChan = numInputs > numOutputs ? numOutputs : numInputs;

        float inputGain = (cast(FloatParameter)param(0)).value();        
        float drive = (cast(FloatParameter)param(1)).value();
        float outputGain = (cast(FloatParameter)param(2)).value();

        for (int chan = 0; chan < minChan; ++chan)
            for (int f = 0; f < frames; ++f)
            {
                double input = inputGain * 2.0 * inputs[chan][f];
                double distorted = tanh(input * drive) / drive;
                outputs[chan][f] = outputGain * distorted;
            }

        // fill with zero the remaining channels
        for (int chan = minChan; chan < numOutputs; ++chan)
            outputs[chan][0..frames] = 0; // D has array slices assignments and operations
    }
}

class DistortGUI : GUIGraphics
{
    Distort _client;

    UIKnob inputKnob;
    UIKnob driveKnob;
    UIKnob outputKnob;

    this(Distort client)
    {
        _client = client;
        super(800, 600); // initial size
        
        addChild(inputKnob = new UIKnob(context()));
        addChild(driveKnob = new UIKnob(context()));
        addChild(outputKnob = new UIKnob(context()));
    }

    override void reflow(box2i availableSpace)
    {
        _position = availableSpace;

        // For complex UI hierarchy or a variable dimension UI, you would be supposed to 
        // put a layout algorithm here and implement reflow (ie. pass the right availableSpace
        // to children). But for simplicity purpose and for the sake of fixed size UI, forcing 
        // positions is completely acceptable.
        inputKnob.position = box2i(0, 0, 50, 50);
        driveKnob.position = box2i(100, 100, 150, 150);
        outputKnob.position = box2i(0, 100, 50, 150);
    }
    
    override void preRender(ImageRef!RGBA surface)
    {
        auto c = RGBA(80, 80, 80, 255);
        surface.fill(c);
    }
}

