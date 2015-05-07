import std.math;

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
    public:
    Distort _client;

    UIKnob inputKnob;
    UIKnob driveKnob;
    UIKnob outputKnob;

    Font _font;

    this(Distort client)
    {
        _client = client;
        super(620, 330); // initial size

        // Font data is bundled as a static array
        _font = new Font(cast(ubyte[])( import("VeraBd.ttf") ));

        addChild(inputKnob = new class UIKnob
                 {
                     this()
                     {
                         super(this.outer.context(), this.outer._font, "input");
                     }

                     override void onValueChanged()
                     {
                         auto client = this.outer._client;
                         int paramIndex = 0;
                         client.setParameterFromGUI(paramIndex, _value);
                     }
                 });

        addChild(driveKnob = new class UIKnob
                 {
                     this()
                     {
                         super(this.outer.context(), this.outer._font, "drive");
                     }

                     override void onValueChanged()
                     {
                         auto client = this.outer._client;
                         int paramIndex = 1;
                         client.setParameterFromGUI(paramIndex, _value);
                     }
                 });
        addChild(outputKnob = new class UIKnob
                 {
                     this()
                     {
                         super(this.outer.context(), this.outer._font, "output");
                     }

                     override void onValueChanged()
                     {
                         auto client = this.outer._client;
                         int paramIndex = 2;
                         client.setParameterFromGUI(paramIndex, _value);
                     }
                 });
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
        driveKnob.position = box2i(x, y, x + w, y + h);
        x += w + margin;
        outputKnob.position = box2i(x, y, x + w, y + h);
    }

    float time = 0;

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!S16 depthMap)
    {
        for (int y = _dirtyRect.min.y; y < _dirtyRect.max.y; ++y)
        {
            S16[] depthScan = depthMap.scanline(y);
            RGBA[] diffuseScan = diffuseMap.scanline(y);
            for (int x = _dirtyRect.min.x; x < _dirtyRect.max.x; ++x)
            {
                diffuseScan.ptr[x] = RGBA(239, 229, 213, 255);
                depthScan.ptr[x].l = 0;
            }
        }
    }
}

