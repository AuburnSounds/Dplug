/**
Simplest synthesizer example.

Copyright: Guillaume Piolat 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
import std.complex;
import std.math;
import dplug.core, dplug.client;

// This define entry points for plugin formats,
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!SimpleMonoSynth);

/// Simplest VST synth you could make.
final class SimpleMonoSynth : dplug.client.Client
{
public:
nothrow:
@nogc:

    this()
    {
    }

    override PluginInfo buildPluginInfo()
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
        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io ~= LegalIO(0, 1);
        io ~= LegalIO(0, 2);
        return io.releaseData();
    }

    override int maxFramesInProcess() pure const
    {
        return 32; // samples only processed by a maximum of 32 samples
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs)
    {
        _phase = complex(1, 0);
        _sampleRate = sampleRate;
        _voiceStatus.initialize();
        _pitchBend = 0;
        _expression = 1;
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info)
    {
        foreach(MidiMessage msg; getNextMidiMessages(frames))
        {
            if (msg.isNoteOn())
                _voiceStatus.markNoteOn(msg.noteNumber());
            else if (msg.isNoteOff())
                _voiceStatus.markNoteOff(msg.noteNumber());
            else if (msg.isAllNotesOff() || msg.isAllSoundsOff())
                _voiceStatus.markAllNotesOff();
            else if (msg.isPitchBend())
                _pitchBend = msg.pitchBend();
            else if (msg.isControlChange() && msg.controlChangeControl() == MidiControlChange.expressionController)
                _expression = msg.controlChangeValue0to1();
        }

        if (_voiceStatus.isAVoicePlaying)
        {
            float freq = convertMIDINoteToFrequency(_voiceStatus.lastNotePlayed + _pitchBend);
            Complex!float phasor = complex!float(cos(2 * PI * freq / _sampleRate), sin(2 * PI * freq / _sampleRate));

            foreach(smp; 0..frames)
            {
                outputs[0][smp] = _phase.im * _expression;
                _phase *= phasor;
            }
            _phase /= abs!float(_phase); // resync oscillator
        }
        else
        {
            outputs[0][0..frames] = 0;
        }

        // Copy output to every channel
        foreach(chan; 1..outputs.length)
            outputs[chan][0..frames] = outputs[0][0..frames];
    }

private:
    VoicesStatus _voiceStatus;
    Complex!float _phase;
    float _sampleRate;
    float _expression;
    float _pitchBend;
}

// Maintain list of active voices/notes
struct VoicesStatus
{
nothrow:
@nogc:

    // Reset state
    void initialize()
    {
        _played[] = 0;
        _currentNumberOfNotePlayed = 0;
        _timestamp = 0;
    }

    bool isAVoicePlaying()
    {
        return _currentNumberOfNotePlayed > 0;
    }

    int lastNotePlayed()
    {
        return _lastNotePlayed;
    }

    // useful to maintain list of most recently played note
    void timeHasElapsed(int frames)
    {
        _timestamp += frames;
    }

    void markNoteOn(int note)
    {
        _lastNotePlayed = note;

        _played[note]++;
        _currentNumberOfNotePlayed++;

        _timestamps[note] = _timestamp;
    }

    void markNoteOff(int note)
    {
        if (_played[note] > 0)
        {
            _played[note]--;
            _currentNumberOfNotePlayed--;
            if (_currentNumberOfNotePlayed > 0)
                lookForMostRecentlyPlayedActiveNote();
        }
    }

    void markAllNotesOff()
    {
        _played[] = 0;
        _currentNumberOfNotePlayed = 0;
    }

private:

    int _currentNumberOfNotePlayed;

    int _lastNotePlayed;
    int _timestamp;

    int[128] _played;
    int[128] _timestamps;


    // looking for most recently played note still in activity
    void lookForMostRecentlyPlayedActiveNote()
    {
        assert(_currentNumberOfNotePlayed > 0);
        int mostRecent = int.min; // will wrap in 26H, that would be a long note
        for (int n = 0; n < 128; n++)
        {
            if (_played[n] && _timestamps[n] > mostRecent)
            {
                mostRecent = _timestamps[n];
                _lastNotePlayed = n;
            }
        }
    }
}
