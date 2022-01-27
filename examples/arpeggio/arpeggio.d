/**
Copyright: Guillaume Piolat 2022.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
import std.math;
import dplug.core, dplug.client;

// This define entry points for plugin formats, 
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!MyClient);

enum : int
{
    paramNone
}

final class MyClient : dplug.client.Client
{
public:
nothrow:
@nogc:

    this()
    {
    }

    override PluginInfo buildPluginInfo()
    {
        static immutable PluginInfo pluginInfo = parsePluginInfo(import("plugin.json"));
        return pluginInfo;
    }

    override Parameter[] buildParameters()
    {
        auto params = makeVec!Parameter();
        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io ~= LegalIO(1, 1);
        io ~= LegalIO(2, 2);
        return io.releaseData();
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {
        _sampleRate = cast(int) sampleRate;
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info) nothrow @nogc
    {
        // Every second, emit a 1/2 sec C4 note.
        foreach(n; 0..frames)
        {
            _timer++;
            if (_timer >= _sampleRate)
            {
                int offset = cast(int)n;
                int channel = 0;
                int note = 60; // C5
                int velocity = 100;

                MidiMessage noteOn = makeMidiMessageNoteOn(offset, channel, note, velocity);            
                MidiMessage noteOff = makeMidiMessageNoteOff(offset + _sampleRate/2, channel, note);
            
                // Note: you can send MIDI messages in any order, and in the future. 
                // A priority queue will order them.
                // They are sent in bulk, after this buffer is processed.

                sendMIDIMessage(noteOn);
                sendMIDIMessage(noteOff);
            }
        }
    }
private:
    int _timer;
    int _sampleRate;
}
