import std.stdio;
import std.algorithm;
import std.math;
import std.string;
import std.array;
import std.conv;

import waved;
import dplug.core;
import colorize;


void usage()
{
    writeln("Usage:");
    writeln("        wav-compare fileA.wav fileB.wav [-o diff.wav]");
    writeln();
    writeln("Description:");
    writeln("        This qualifies the difference between two files.");
    writeln;
    writeln("Flags:");
    writeln("        -h, --help   Shows this help");
    writeln("        -o <file>    Write instantaneous peak difference in a WAV file (default: wav-diff.wav)");
    writeln;
}

int main(string[] args)
{
    try
    {
        bool help = false;
        string[] files = null;
        string outDiffFile = "wav-diff.wav";

        for (int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "-h")
                help = true;
            else if (arg == "-o")
            {
                i += 1;
                outDiffFile = args[i];
            }
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
            cwriteln(format("warning: comparing %s with itself, do you mean that?", fileA).color(fg.light_yellow));

        if (soundA.channels != soundB.channels)
            throw new Exception(format("%s and %s have different channel count", fileA, fileB));

        if (soundA.sampleRate != soundB.sampleRate)
            throw new Exception(format("%s and %s have different sample rate", fileA, fileB));

        if (soundA.samples.length != soundB.samples.length)
            throw new Exception(format("%s and %s have different length", fileA, fileB));

        // Normalize both sounds by the same amount
        // However we don't apply this factor yet to avoid introducing noise.
        real nFactor = (normalizeFactor(soundA) + normalizeFactor(soundB) ) * 0.5f;
        int channels = soundA.channels;

        int N = cast(int)(soundA.samples.length);

        // No need to deinterleave stereo, since the peak difference is what interest us
        real[] difference = new real[N];
        float[] diffFileContent = new float[N];

        // Note: the WAV output is an absolute value (simply A minus B)
        // while the RMS and peak numbers are given against normalized A and B
        for (int i = 0; i < N; ++i)
        {
            real diff = cast(real)soundA.samples[i] - soundB.samples[i];
            diffFileContent[i] = diff;
            difference[i] = nFactor * abs(diff);
        }

        real maxPeakDifference = reduce!max(difference);//!("a > b")(difference).front;

        real rms = 0;
        for (int i = 0; i < N; ++i)
            rms +=  difference[i] * difference[i];
        rms = sqrt(rms / N);

        real peak_dB = convertLinearGainToDecibel(maxPeakDifference);
        real rms_dB = convertLinearGainToDecibel(rms);

        cwriteln;
        cwritefln(" Comparing %s vs %s", fileA.color(fg.light_white), fileB.color(fg.light_white));
        writeln();
        cwriteln ("    =================================".color(fg.light_white));
        cwritefln("        RMS difference = %s", format("%.2f dB", rms_dB).color(fg.light_yellow));
        cwriteln ("    =================================".color(fg.light_white));
        writeln();

        cwriteln(" An opinion from the comparison program:");
        cwriteln(format("    \"%s\"", getComment(rms_dB, peak_dB)).color(fg.light_cyan));
        writeln();

        if (isFinite(peak_dB - rms_dB))
            cwritefln(" => (Peak - RMS) Crest difference = %s", format("%.2f dB", peak_dB - rms_dB).color(fg.light_green));

        // write absolute difference into
        Sound(soundA.sampleRate, channels, diffFileContent).encodeWAV(outDiffFile);
        cwritefln(" => Difference written in %s (max rel. peak = %s)", 
                  outDiffFile.color(fg.light_white),
                  format("%.2f dB", peak_dB).color(fg.light_green));

        cwriteln;
        return 0;
    }
    catch(Exception e)
    {
        writeln;
        cwritefln(format("error: %s", e.msg).color(fg.light_red));
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

string getComment(float rms_dB, float peak_dB)
{
    if (rms_dB > -10)
    {
        return "This is a big difference, should be something that changes the phase, or something very audible (possibly an error)!";
    }
    else if (rms_dB > -30)
    {
        return "This might be a hearable difference inside your DAW, but this might also require an A/B test if it's mostly a phase thing.";
    }
    else if (rms_dB > -50)
    {
        return "This might be a bit hard to hear but perhaps easy to spot in an A/B test.";
    }
    else if (rms_dB > -80)
    {
        return "This is probably very subtle to hear and I'd say this requires an A/B test!";
    }
    else if (rms_dB > -110)
    {
        return "I doubt you may be able to hear it, but maybe do not take my word for it.";
    }
    else if (!isFinite(rms_dB))
    {
        return "This is identical up to -inf dB. There is nothing to listen to, because there is no difference.";
    }
    else 
    {
        return "I wouldn't even bother trying to hear this difference. It must be incredibly subtle.";
    }
}