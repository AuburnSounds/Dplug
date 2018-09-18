/**
Copyright: Elias Batek 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synthesis;

import std.math;
import dplug.core.nogc;
import dplug.core.math;

enum TAU = 2 * PI;

enum WaveForm
{
    saw,
    sine,
    square,
}

final class Oscillator
{
@safe pure nothrow @nogc:

    private
    {
        float _frequency;
        float _phase = 0;
        float _phaseSummand;
        float _sampleRate;
        WaveForm _waveForm;
    }

    public
    {
        @property
        {
            void frequency(float value)
            {
                this._frequency = value;
                this.updatePhaseSummand();
            }
        }

        @property
        {
            void sampleRate(float value)
            {
                this._sampleRate = value;
                this.updatePhaseSummand();
            }
        }

        @property
        {
            WaveForm waveForm()
            {
                return this._waveForm;
            }

            void waveForm(WaveForm value)
            {
                this._waveForm = value;
            }
        }
    }

    public this(WaveForm waveForm)
    {
        this._waveForm = waveForm;
        this.updatePhaseSummand();
    }

    public
    {
        float synthesizeNext()
        {
            float sample = void;

            final switch (this._waveForm) with (WaveForm)
            {
            case saw:
                sample = 1.0 - (this._phase / PI);
                break;

            case sine:
                sample = sin(this._phase);
                break;

            case square:
                sample = (this._phase <= PI) ? 1.0 : -1.0;
                break;
            }

            this._phase += this._phaseSummand;
            while (this._phase >= TAU)
            {
                this._phase -= TAU;
            }

            return sample;
        }
    }

    private
    {
        void updatePhaseSummand()
        {
            pragma(inline, true);
            this._phaseSummand = (this._frequency * TAU / this._sampleRate);
            //this._phase = 0;
        }
    }
}

final class VoiceStatus
{
@safe nothrow @nogc:

    private
    {
        Oscillator _osc;
        bool _isPlaying;
        int _note;
    }

    public pure
    {
        @property
        {
            bool isPlaying()
            {
                return this._isPlaying;
            }
        }

        @property
        {
            int note()
            {
                return this._note;
            }
        }

        @property
        {
            void waveForm(WaveForm value)
            {
                this._osc.waveForm = value;
            }

            WaveForm waveForm()
            {
                return this._osc.waveForm;
            }
        }
    }

    public this(WaveForm waveForm) @system
    {
        this._osc = mallocNew!Oscillator(waveForm);
        this._note = -1;
    }

    public pure
    {
        void play(int note) @trusted
        {
            this._note = note;
            this._osc.frequency = convertMIDINoteToFrequency(note);
            this._isPlaying = true;
        }

        void release()
        {
            this._isPlaying = false;
        }

        void reset(float sampleRate)
        {
            this.release();
            this._osc.sampleRate = sampleRate;
        }

        float synthesizeNext()
        {
            if (!this._isPlaying)
            {
                return 0;
            }

            return this._osc.synthesizeNext();
        }
    }
}

final class Synth(size_t voicesCount)
{
    static assert(voicesCount > 0, "A synth must have at least 1 voice.");

@safe nothrow:

    private
    {
        VoiceStatus[voicesCount] _voices;
    }

    public pure @nogc
    {
        @property bool isPlaying()
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

        @property
        {
            WaveForm waveForm()
            {
                return this._voices[0].waveForm;
            }

            void waveForm(WaveForm value)
            {
                foreach (v; this._voices)
                {
                    v.waveForm = value;
                }
            }
        }
    }

    public this(WaveForm waveForm) @system
    {
        foreach (ref v; this._voices)
        {
            v = mallocNew!VoiceStatus(waveForm);
        }
    }

    public pure @nogc
    {
        void markNoteOn(int note)
        {
            VoiceStatus v = this.getUnusedVoice();
            if (v is null)
            {
                /+
                    No voice available

                    well, one could override one, but:
                     - always overriding the 1st one is lame
                     - a smart algorithm would make this example more complicated
                +/
                return;
            }

            v.play(note);
        }

        void markNoteOff(int note)
        {
            foreach (v; this._voices)
            {
                if (v.isPlaying && (v.note == note))
                {
                    v.release();
                }
            }
        }

        void reset(float sampleRate)
        {
            foreach (v; this._voices)
            {
                v.reset(sampleRate);
            }
        }

        float synthesizeNext()
        {
            float sample = 0;

            foreach (v; this._voices)
            {
                sample += (v.synthesizeNext() / voicesCount); // synth + lower volume
            }

            return sample;
        }
    }

    private
    {
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
}
