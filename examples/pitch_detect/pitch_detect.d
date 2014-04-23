import std.math;

import waved,
       dplug.dsp;

import std.stdio;

void main(string[] args)
{
    if (args.length != 2)
    {
        writefln("usage: pitch_detect input.wav");
        return;
    }

    Sound input = decodeWAV(args[1]);

    GoldRabiner gold;
    int sampleRate = input.sampleRate;

    int N = input.lengthInFrames();

    // flatten to mono
    float[] mono = new float[N];

    for (int i = 0; i < N; ++i)
    {
        mono[i] = 0;
        for (int j = 0; j < input.numChannels; ++j)
        {
            mono[i] += input.data[i * input.numChannels + j];
        }
        mono[i] /= input.numChannels;
    }

    gold.initialize(sampleRate);

    float[] pitch = new float[N];
    float[] note = new float[N];
    float[] voicedness = new float[N];

    for (int i = 0; i < N; ++i)
    {
        if (!gold.next(mono[i], &pitch[i], &voicedness[i]))
        {
            pitch[i] = 0;
            voicedness[i] = 0;
        }

        // when the signal is unvoiced, pitch measured (which does not make sense then) is way higher due to large number of zero crossings
        note[i] = pitch[i];
        if (voicedness[i] < 0.8)
        {
            note[i] = 1 / 8.0f;
        }        

        // for easy waveform display
        double frequency = 1.0 / (note[i] + 0.0000000001);
        double midiNote = frequencyToMIDI!double(frequency);
        note[i] = linmap!float(midiNote, 0, 127, -1.0f, 1.0f, );
    }

    Sound(sampleRate, 1, pitch).encodeWAV("pitch.wav");
    Sound(sampleRate, 1, voicedness).encodeWAV("voicedness.wav");

    // Grossly resynthetize with a sawtooth

    Wavetable sawtooth;
    sawtooth.initialize(2048, WaveformType.SAWTOOTH);

    WavetableOsc osc;
    osc.initialize(&sawtooth, sampleRate);

    float[] synthesized = new float[N];

    for (int i = 0; i < N; ++i)
    {
        double frequency = 1.0 / (pitch[i] + 0.0000000001);
        if (frequency <= 20)
            synthesized[i] = 0;
        else
            synthesized[i] = voicedness[i] * osc.next(frequency / 2);
    }

    Sound(sampleRate, 1, synthesized).encodeWAV("synthesized.wav");

}
