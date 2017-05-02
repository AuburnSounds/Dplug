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
    mixin(VSTEntryPoint!ExamplePlugin);
}

version(AU)
{
    import dplug.au;
    mixin(AUEntryPoint!ExamplePlugin);
}

/*enum : int
{
	//Define parameters here
}*/


/// Example mono/stereo distortion plugin.
final class ExamplePlugin : dplug.client.Client
{
public:
nothrow:
@nogc:

    this()
    {
    }

    // The information that is duplicated here and in plugin.json should be the same
    override PluginInfo buildPluginInfo()
    {
        // change all of these!
        PluginInfo info;
        info.vendorName = "Witty Audio";
        info.vendorUniqueID = "Wity";
        info.pluginName = "Destructatorizer";
        info.pluginUniqueID = "WiDi";
        info.pluginVersion = PluginVersion(1, 0, 0);
        info.isSynth = false;
        info.receivesMIDI = false;
        info.hasGUI = true;
        return info;
    }

    // This is an optional overload, default is zero parameter.
    // Caution when adding parameters: always add the indices
    // in the same order than the parameter enum.
    override Parameter[] buildParameters()
    {
        auto params = makeAlignedBuffer!Parameter();
		
        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeAlignedBuffer!LegalIO();
        io.pushBack(LegalIO(1, 1));
        io.pushBack(LegalIO(1, 2));
        io.pushBack(LegalIO(2, 1));
        io.pushBack(LegalIO(2, 2));
        return io.releaseData();
    }

    // This override is optional, the default implementation will
    // have one default preset.
    override Preset[] buildPresets() nothrow @nogc
    {
        auto presets = makeAlignedBuffer!Preset();
        presets.pushBack( makeDefaultPreset() );

        static immutable float[] silenceParams = [0.0f, 0.0f, 0.0f, 1.0f, 0];
        presets.pushBack( mallocEmplace!Preset("Silence", silenceParams) );

        static immutable float[] fullOnParams = [1.0f, 1.0f, 0.4f, 1.0f, 0];
        presets.pushBack( mallocEmplace!Preset("Full-on", fullOnParams) );
        return presets.releaseData();
    }

    // This override is also optional. It allows to split audio buffers in order to never
    // exceed some amount of frames at once.
    // This can be useful as a cheap chunking for parameter smoothing.
    // Buffer splitting also allows to allocate statically or on the stack with less worries.
    override int maxFramesInProcess() const //nothrow @nogc
    {
        return 128;
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

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, 
                               TimeInfo info) nothrow @nogc
    {
        assert(frames <= 128); // guaranteed by audio buffer splitting

        int numInputs = cast(int)inputs.length;
        int numOutputs = cast(int)outputs.length;

        int minChan = numInputs > numOutputs ? numOutputs : numInputs;

        float[2] RMS = 0;

		for (int chan = 0; chan < minChan; ++chan)
		{
			for (int f = 0; f < frames; ++f)
			{
				float inputSample = inputs[chan][f];

				outputs[chan][f] = inputSample;

			}
		}

		// Bypass mode
		for (int chan = 0; chan < minChan; ++chan)
			outputs[chan][0..frames] = inputs[chan][0..frames];

        // fill with zero the remaining channels
        for (int chan = minChan; chan < numOutputs; ++chan)
            outputs[chan][0..frames] = 0; // D has array slices assignments and operations

        // Update RMS meters from the audio callback
        // The IGraphics object must be acquired and released, so that it does not
        // disappear under your feet
        if (ExamplePluginGUI gui = cast(ExamplePluginGUI) graphicsAcquire())
        {
            float[2] inputLevels;
            inputLevels[0] = floatToDeciBel(_inputRMS[0].RMS());
            inputLevels[1] = minChan >= 1 ? floatToDeciBel(_inputRMS[1].RMS()) : inputLevels[0];

            float[2] outputLevels;
            outputLevels[0] = floatToDeciBel(_outputRMS[0].RMS());
            outputLevels[1] = minChan >= 1 ? floatToDeciBel(_outputRMS[1].RMS()) : outputLevels[0];

            graphicsRelease();
        }
    }

    override IGraphics createGraphics()
    {
        return mallocEmplace!ExamplePluginGUI(this);
    }

private:
    CoarseRMS!float[2] _inputRMS;
    CoarseRMS!float[2] _outputRMS;
}

class ExamplePluginGUI : GUIGraphics
{
public:
nothrow:
@nogc:

    ExamplePlugin _client;

    Font _font;

    this(ExamplePlugin client)
    {
        _client = client;
        super(620, 330); // initial size

        // Font data is bundled as a static array
        _font = mallocEmplace!Font(cast(ubyte[])( import("VeraBd.ttf") ));
        context.setSkybox( loadOwnedImage(cast(ubyte[])(import("skybox.jpg"))) );

        // Build the UI hierarchy
        
    }

    ~this()
    {
        _font.destroyFree();
    }

    override void reflow(box2i availableSpace)
    {
        _position = availableSpace;

        // For complex UI hierarchy or a variable dimension UI, you would be supposed to
        // put a layout algorithm here and implement reflow (ie. pass the right availableSpace
        // to children). But for simplicity purpose and for the sake of fixed size UI, forcing
        // positions is completely acceptable.
        
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        // In onDraw, you are supposed to only update diffuseMap, depthMap and materialMap in the dirtyRects areas.
        // See also the wiki: https://github.com/p0nce/dplug/wiki/Advices-for-creating-UIs-with-dplug

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

            // Default depth is approximately ~22% of the possible height, but you can choose any other value
            // Here we add some noise too.
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

            // Fill. material map.
            // Which is "RMSP": Roughness Metalness Specular Physical
            auto croppedMaterial = materialMap.crop(dirtyRect);
            croppedMaterial.fill(RMSP(120, 255, 128, 255));
        }
    }
}

