/**
Aliased polyphonic syntesizer.

Copyright: Elias Batek 2018, 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
import std.math;
import dplug.core, dplug.client;

// This define entry points for plugin formats, 
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!PolyAlias);

/// Number of max notes playing at the same time
enum maxVoices = 4;

enum double TAU = 2 * PI;

enum : int
{
    paramOsc1WaveForm,
    paramOutputGain,
}

enum WaveForm
{
    saw,
    sine,
    square,
}

static immutable waveFormNames = [__traits(allMembers, WaveForm)];

/// Polyphonic digital-aliasing synth
final class PolyAlias : Client
{
nothrow @nogc:
public:

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
        params ~= mallocNew!EnumParameter(paramOsc1WaveForm, "Waveform", waveFormNames, WaveForm.init);
        params ~= mallocNew!GainParameter(paramOutputGain, "Output Gain", 6.0, 0.0);
        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io ~= LegalIO(0, 1);
        io ~= LegalIO(0, 2);
        return io.releaseData();
    }

    override int maxFramesInProcess()
    {
        return 32; // samples only processed by a maximum of 32 samples
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs)
    {
        _synth.reset(sampleRate);
    }

    override void processAudio(const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info)
    {
        // process MIDI - note on/off and similar
        foreach (msg; getNextMidiMessages(frames))
        {
            if (msg.isNoteOn()) // note on
                _synth.markNoteOn(msg.noteNumber());

            else if (msg.isNoteOff()) // note off
                _synth.markNoteOff(msg.noteNumber());

            else if (msg.isAllNotesOff() || msg.isAllSoundsOff()) // all off
                _synth.markAllNotesOff();
        }

        _synth.waveForm = readParam!WaveForm(paramOsc1WaveForm);
        _synth.outputGain = convertDecibelToLinearGain(readParam!float(paramOutputGain));

        foreach (ref sample; outputs[0][0 .. frames])
            sample = _synth.nextSample();

        // Copy output to every channel
        foreach (chan; 1 .. outputs.length)
            outputs[chan][0 .. frames] = outputs[0][0 .. frames];
    }

private:
    Synth!maxVoices _synth;
}

struct Synth(size_t voicesCount)
{
@safe pure nothrow @nogc:
public:

    static assert(voicesCount > 0, "A synth must have at least 1 voice.");

    bool isPlaying()
    {
        foreach (v; _voices)
            if (v.isPlaying())
                return true;

        return false;
    }

    WaveForm waveForm()
    {
        return _voices[0].waveForm;
    }

    void waveForm(WaveForm value)
    {
        foreach (ref v; _voices)
            v.waveForm = value;
    }

    void markNoteOn(int note)
    {
        foreach (ref v; _voices)
            if (!v.isPlaying)
                return v.play(note);

        // no free voice available, skip
    }

    void markNoteOff(int note)
    {
        foreach (ref v; _voices)
            if (v.isPlaying && (v.note == note))
                v.release();
    }

    void markAllNotesOff()
    {
        foreach (ref v; _voices)
            if (v.isPlaying)
                v.release();
    }

    void reset(float sampleRate)
    {
        foreach (ref v; _voices)
            v.reset(sampleRate);
    }

    float nextSample()
    {
        double sample = 0;

        foreach (ref v; _voices)
            sample += v.nextSample(); // synth

        // lower volume relative to the total count of voices
        sample *= _internalGain;

        // apply gain
        sample *= outputGain;

        return float(sample);
    }

    float outputGain = 1;

private:
    enum double _internalGain = (1.0 / (voicesCount / SQRT1_2));

    VoiceStatus[voicesCount] _voices;
}

struct VoiceStatus
{
@safe pure nothrow @nogc:
public:

    bool isPlaying()
    {
        return _isPlaying;
    }

    int note()
    {
        return _note;
    }

    void waveForm(WaveForm value)
    {
        _osc.waveForm = value;
    }

    WaveForm waveForm()
    {
        return _osc.waveForm;
    }

    void play(int note) @trusted
    {
        _note = note;
        _osc.frequency = convertMIDINoteToFrequency(note); // convertMIDINoteToFrequency() is actually @safe
        _isPlaying = true;
    }

    void release()
    {
        _isPlaying = false;
    }

    void reset(float sampleRate)
    {
        release();
        _osc.sampleRate = sampleRate;
    }

    float nextSample()
    {
        if (!_isPlaying)
            return 0;

        return _osc.nextSample();
    }

private:
    Oscillator _osc;
    bool _isPlaying;
    int _note = -1;
}

struct Oscillator
{
@safe pure nothrow @nogc:
public:

    this(WaveForm waveForm)
    {
        _waveForm = waveForm;
        recalculateDeltaPhase();
    }

    void frequency(float value)
    {
        _frequency = value;
        recalculateDeltaPhase();
    }

    void sampleRate(float value)
    {
        _sampleRate = value;
        recalculateDeltaPhase();
    }

    WaveForm waveForm()
    {
        return _waveForm;
    }

    void waveForm(WaveForm value)
    {
        _waveForm = value;
    }

    double nextSample()
    {
        double sample = void;

        final switch (_waveForm) with (WaveForm)
        {
        case saw:
            sample = 1.0 - (_phase / PI);
            break;

        case sine:
            sample = sin(_phase);
            break;

        case square:
            sample = (_phase <= PI) ? 1.0 : -1.0;
            break;
        }

        _phase += _deltaPhase;

        while (_phase >= TAU)
        {
            _phase -= TAU;
        }

        return sample;
    }

private:
    double _deltaPhase;
    float _frequency;
    double _phase = 0;
    float _sampleRate;
    WaveForm _waveForm;

    void recalculateDeltaPhase()
    {
        _deltaPhase = (_frequency * TAU / _sampleRate);
    }
}
