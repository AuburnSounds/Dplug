import std.stdio;
import std.algorithm;
import std.math;
import std.array;

import waved;
import dplug.core;

// Builds plugins and make an archive

void usage()
{
    writeln("usage: wav-compare file-A.wav file-B.wav");    
    writeln("  -h|--help         shows this help");
}


void main(string[] args)
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
            return;
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
            throw new Exception("Same file!");

        if (soundA.numChannels != 2 || soundB.numChannels != 2)
            throw new Exception("Only support stereo inputs!");

        if (soundA.sampleRate != soundB.sampleRate)
            throw new Exception("Different sample-rate!");

        if (soundA.data.length != soundB.data.length)
            throw new Exception("Different length!");

        int N = cast(int)(soundA.data.length);

        // No need to deinterleave stereo, since the peak difference is what interest us
        double[] difference = new double[N];

        for (int i = 0; i < N; ++i)
        {
            difference[i] = abs(soundA.data[i] - soundB.data[i]);
        }

        double maxPeakDifference = reduce!max(difference);//!("a > b")(difference).front;

        double rms = 0;
        for (int i = 0; i < N; ++i)
            rms +=  difference[i] *  difference[i];
        rms = sqrt(rms / N);

        double peakdB = floatToDeciBel(maxPeakDifference);
        double rmsdB = floatToDeciBel(rms);

        writeln;
        writefln(" Comparing %s vs %s", fileA, fileB);
        writefln(" => peak dB difference = %s dB", peakdB);
        writefln(" => RMS dB difference  = %s dB", rmsdB);
        if (peakdB == -double.infinity) 
            writeln("    These sounds are identical.");
        writeln;
    }
    catch(Exception e)
    {
        writefln("error: %s", e.msg);
    }
}