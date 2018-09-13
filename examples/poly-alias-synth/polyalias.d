import std.math;
import dplug.core, dplug.client, dplug.vst;
import synthesis;

// This creates the DLL entry point
mixin(DLLEntryPoint!());

// This creates the VST entry point
mixin(VSTEntryPoint!PolyAlias);

private
{
    // Number of max notes playing at the same time
    enum maxVoices = 4;

    enum Params : int
    {
        osc1WaveForm,
    }

    immutable waveFormNames = [__traits(allMembers, WaveForm)];
}

/// Polyphonic digital-aliasing synth
final class PolyAlias : dplug.client.Client
{
nothrow @nogc:

    private
    {
        Synth!maxVoices _synth;
    }

    public this()
    {
        super();

        assumeNothrowNoGC((PolyAlias this_) {
            this_._synth = mallocNew!(typeof(this._synth))(WaveForm.saw);
        })(this);
    }

    public override
    {
        PluginInfo buildPluginInfo()
        {
            // Plugin info is parsed from plugin.json here at compile time.
            // Indeed it is strongly recommended that you do not fill PluginInfo
            // manually, else the information could diverge.
            static immutable PluginInfo pluginInfo = parsePluginInfo(import("plugin.json"));
            return pluginInfo;
        }

        override Parameter[] buildParameters()
        {
            auto params = makeVec!Parameter();
            params.pushBack(mallocNew!EnumParameter(Params.osc1WaveForm, "Osc 1: Waveform", waveFormNames, 0));
            return params.releaseData();
        }

        override LegalIO[] buildLegalIO()
        {
            auto io = makeVec!LegalIO();
            io.pushBack(LegalIO(0, 1));
            io.pushBack(LegalIO(0, 2));
            return io.releaseData();
        }

        override int maxFramesInProcess() pure const
        {
            return 32; // samples only processed by a maximum of 32 samples
        }

        override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs)
        {
            this._synth.reset(sampleRate);
        }

        override void processAudio(const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info)
        {
            foreach (msg; getNextMidiMessages(frames))
            {
                if (msg.isNoteOn())
                {
                    this._synth.markNoteOn(msg.noteNumber());
                }
                else if (msg.isNoteOff())
                {
                    this._synth.markNoteOff(msg.noteNumber());
                }
            }

            this._synth.waveForm = cast(WaveForm)(readEnumParamValue(Params.osc1WaveForm));

            foreach (ref sample; outputs[0][0 .. frames])
            {
                sample = this._synth.synthesizeNext();
            }

            // Copy output to every channel
            foreach (chan; 1 .. outputs.length)
            {
                outputs[chan][0 .. frames] = outputs[0][0 .. frames];
            }
        }
    }
}
