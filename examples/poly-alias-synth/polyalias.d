/**
Aliased polyphonic syntesizer.

Copyright: Elias Batek 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
import std.math;
import dplug.core, dplug.client;
import synthesis;

// This define entry points for plugin formats, 
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!PolyAlias);


// Number of max notes playing at the same time
enum TAU = 2 * PI;
enum maxVoices = 4;

enum : int
{
    paramOsc1WaveForm,
}

enum WaveForm
{
    saw,
    sine,
    square,
}

/// Polyphonic digital-aliasing synth
final class PolyAlias : dplug.client.Client
{
public:
nothrow:
@nogc:    

    this()
    {
        _synth = mallocNew!(Synth!maxVoices)(WaveForm.saw);
    }

    ~this()
    {
        destroyFree(_synth);
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
        
        static immutable waveFormNames = [ __traits(allMembers, WaveForm) ];
        params ~= mallocNew!EnumParameter(paramOsc1WaveForm, "Waveform", waveFormNames, 0);

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
        _synth.reset(sampleRate);
    }

    override void processAudio(const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info)
    {
        foreach (msg; getNextMidiMessages(frames))
        {
            if (msg.isNoteOn())
            {
                _synth.markNoteOn(msg.noteNumber());
            }
            else if (msg.isNoteOff())
            {
                _synth.markNoteOff(msg.noteNumber());
            }
            else if (msg.isAllNotesOff() || msg.isAllSoundsOff())
            {
                _synth.markAllNotesOff();
            }
        }

        _synth.waveForm = readParam!WaveForm(paramOsc1WaveForm);

        foreach (ref sample; outputs[0][0 .. frames])
        {
            sample = _synth.nextSample();
        }

        // Copy output to every channel
        foreach (chan; 1 .. outputs.length)
        {
            outputs[chan][0 .. frames] = outputs[0][0 .. frames];
        }
    }

private:
    Synth!maxVoices _synth;
}



final class Synth(size_t voicesCount)
{
public:
nothrow:
@nogc:   

    static assert(voicesCount > 0, "A synth must have at least 1 voice.");

    bool isPlaying()
    {
        foreach(v; this._voices)
        {
            if (v.isPlaying())
            {
                return true;
            }
        }
        return false;
    }

    WaveForm waveForm()
    {
        return this._voices[0].waveForm;
    }

    void waveForm(WaveForm value)
    {
        foreach (v; _voices)
        {
            v.waveForm = value;
        }
    }

    this(WaveForm waveForm)
    {
        foreach (ref v; _voices)
        {
            v = mallocNew!VoiceStatus(waveForm);
        }
    }

    ~this()
    {
        foreach (ref v; _voices)
        {
            destroyFree(v);
        }
    }

    void markNoteOn(int note)
    {
        VoiceStatus v = this.getUnusedVoice();
        if (v is null)
        {
            // Voice stealing not implmented here
            return;
        }

        v.play(note);
    }

    void markNoteOff(int note)
    {
        foreach (v; _voices)
        {
            if (v.isPlaying && (v.note == note))
            {
                v.release();
            }
        }
    }

    void markAllNotesOff()
    {
        foreach (v; _voices)
        {
            if (v.isPlaying)
            {
                v.release();
            }
        }
    }

    void reset(float sampleRate)
    {
        foreach (v; _voices)
        {
            v.reset(sampleRate);
        }
    }

    float nextSample()
    {
        float sample = 0;

        foreach (v; _voices)
        {
            sample += (v.nextSample() / voicesCount); // synth + lower volume
        }
        return sample;
    }

private:
    VoiceStatus[voicesCount] _voices;

    VoiceStatus getUnusedVoice()
    {
        foreach (v; this._voices)
        {
            if (!v.isPlaying)
            {
                return v;
            }
        }
        return null;
    }
}

final class VoiceStatus
{
public:
nothrow:
@nogc:

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

    this(WaveForm waveForm)
    {
        _osc = mallocNew!Oscillator(waveForm);
        _note = -1;
    }

    ~this()
    {
        destroyFree(_osc);
    }

    void play(int note)
    {
        _note = note;
        _osc.frequency = convertMIDINoteToFrequency(note);
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
        {
            return 0;
        }

        return _osc.nextSample();
    }

private:
    Oscillator _osc;
    bool _isPlaying;
    int _note;
}


final class Oscillator
{
public:
nothrow:
@nogc:

    this(WaveForm waveForm)
    {
        _waveForm = waveForm;
        updatePhaseSummand();
    }

    void frequency(float value)
    {
        _frequency = value;
        updatePhaseSummand();
    }

    void sampleRate(float value)
    {
        _sampleRate = value;
        updatePhaseSummand();
    }

    WaveForm waveForm()
    {
        return _waveForm;
    }

    void waveForm(WaveForm value)
    {
        _waveForm = value;
    }

    float nextSample()
    {
        float sample = void;

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

        _phase += _phaseSummand;
        while (_phase >= TAU)
        {
            _phase -= TAU;
        }
        return sample;
    }

private:
    float _frequency;
    float _phase = 0;
    float _phaseSummand;
    float _sampleRate;
    WaveForm _waveForm;

    void updatePhaseSummand()
    {
        _phaseSummand = (_frequency * TAU / _sampleRate);
    }
}

