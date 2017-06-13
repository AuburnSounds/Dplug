import std.stdio;
import std.algorithm;
import std.math;
import std.string;
import std.array;

import waved;
import dplug.core;

// Builds plugins and make an archive

void usage()
{
    writeln("Usage:");
    writeln("        wav-compare fileA.wav fileB.wav");
    writeln;
    writeln("Flags:");
    writeln("        -h, --help   Shows this help");
    writeln;
}

int main(string[] args)
{
    try
    {
        bool help = false;
        string[] files = null;

        for (int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "-h")
                help = true;
            else
                files ~= arg;
        }

        if (help)
        {
            usage();
            return 1;
        }

        if (files.length < 2)
            throw new Exception("2 wav files must be provided");

        if (files.length > 2)
            throw new Exception("2 wav files must be provided");

        string fileA = files[0];
        string fileB = files[1];

        Sound soundA = decodeSound(fileA);
        Sound soundB = decodeSound(fileB);

        if (fileA == fileB)
            writeln(format("warning: comparing %s with itself", fileA));

        if (soundA.channels != soundB.channels)
            throw new Exception(format("%s and %s have different channel count", fileA, fileB));

        if (soundA.sampleRate != soundB.sampleRate)
            throw new Exception(format("%s and %s have different sample rate", fileA, fileB));

        if (soundA.samples.length != soundB.samples.length)
            throw new Exception(format("%s and %s have different length", fileA, fileB));

        // Normalize both sounds by the same amount
        // However we don't apply this factor yet to avoid introducing noise.
        real nFactor = (normalizeFactor(soundA) + normalizeFactor(soundB) ) * 0.5f;


        int N = cast(int)(soundA.samples.length);

        // No need to deinterleave stereo, since the peak difference is what interest us
        real[] difference = new real[N];

        for (int i = 0; i < N; ++i)
        {
            difference[i] = nFactor * abs(cast(real)soundA.samples[i] - soundB.samples[i]);
        }

        real maxPeakDifference = reduce!max(difference);//!("a > b")(difference).front;

        real rms = 0;
        for (int i = 0; i < N; ++i)
            rms +=  difference[i] * difference[i];
        rms = sqrt(rms / N);

        real peakdB = floatToDeciBel(maxPeakDifference);
        real rmsdB = floatToDeciBel(rms);

        writeln;
        writefln(" Comparing %s vs %s", fileA, fileB);
        writefln(" => peak dB difference = %s dB", peakdB);
        writefln(" => RMS dB difference  = %s dB", rmsdB);
        if (peakdB == -real.infinity)
            writeln("    These sounds are identical.");
        writeln;
        return 0;
    }
    catch(Exception e)
    {
        writeln;
        writefln("error: %s", e.msg);
        writeln;
        usage();
        writeln;
        return 1;
    }
}

real normalizeFactor(Sound s)
{
    int N = cast(int)(s.samples.length);

    // Compute RMS
    real rms = 0;
    for (int i = 0; i < N; ++i)
        rms += (cast(real)s.samples[i]) * s.samples[i];
    rms = sqrt(rms / N);
    return 1.0f / (rms + 1e-10f);
}