import std.math;

import waved,
       dplug.dsp;

import std.stdio;

void main()
{
    Sound sound = decodeWAV("my_wav_file.wav");

    GoldRabiner gold;

    if (sound.numChannels != 1)
    {
        writefln("Only works for mono input");
        return;
    }

    gold.initialize(sound.sampleRate);

    size_t N = sound.data.length;

    float[] pitch = new float[N];
    float[] voicedness = new float[N];

    for (int i = 0; i < sound.data.length; ++i)
    {
        if (!gold.next(sound.data[i], &pitch[i], &voicedness[i]))
        {
            pitch[i] = 0;
            voicedness[i] = 0;
        }
    }

    sound.data = pitch;
    sound.encodeWAV("pitch.wav");

    sound.data = voicedness;
    sound.encodeWAV("voicedness.wav");
}
