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
    paramNote,
    paramVelocity,
    paramSpeed,
    paramLength
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
        params ~= mallocNew!IntegerParameter(paramNote, "note", "", 0, 127, 65);
        params ~= mallocNew!IntegerParameter(paramVelocity, "velocity", "", 0, 127, 100);
        params ~= mallocNew!LogFloatParameter(paramSpeed, "speed", "secs", 0.001f, 10.0f, 1.0f);
        params ~= mallocNew!LinearFloatParameter(paramLength, "length", "%", 0.0f, 200.0f, 50.0f);
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
        _timer = 0;
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info) nothrow @nogc
    {
        int note = readParam!int(paramNote);
        int velocity = readParam!int(paramVelocity);

        double delayBetweenNoteOnInSamples = _sampleRate * readParam!float(paramSpeed);
        if (delayBetweenNoteOnInSamples < 1) 
            delayBetweenNoteOnInSamples = 1;

        int noteDuration = cast(int)(0.5f + delayBetweenNoteOnInSamples * readParam!float(paramLength) * 0.01);
        assert(noteDuration >= 0);

        // Every second, emit a 1/2 sec C4 note.
        foreach(n; 0..frames)
        {
            _timer += 1;
            while (_timer >= delayBetweenNoteOnInSamples) // should output note?
            {
                _timer -= delayBetweenNoteOnInSamples;

                int offset = cast(int)n;
                int channel = 0;

                MidiMessage noteOn  = makeMidiMessageNoteOn(offset,                 channel, note, velocity);            
                MidiMessage noteOff = makeMidiMessageNoteOff(offset + noteDuration, channel, note);
            
                // The MIDI messages are stable-sorted by offset.
                // If the offset is the same, the order of `sendMIDIMessage` calls is preserved though.
                // Consequently, for notes with zero length, send the note-on before note-off. Else you can mix everything up, or
                // send whole future patterns without limits.
                sendMIDIMessage(noteOn);
                sendMIDIMessage(noteOff);
            }
        }
    }
private:
    double _timer; // time accumulator
    int _sampleRate;
}