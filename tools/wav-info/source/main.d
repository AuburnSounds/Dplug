import std.stdio;
import std.algorithm;
import std.math;
import std.string;
import std.array;
import std.conv;

import waved;
import dplug.core;
import consolecolors;


void usage()
{
    writeln("Usage:");
    writeln("        wav-info file.wav");
    writeln();
    writeln("Description:");
    writeln("        This describes a WAV files and its content.");
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

        if (files.length != 1)
            throw new Exception("Exactly one WAV file must be provided");

        Sound sound = decodeSound(files[0]);

        cwriteln;
        cwritefln("Analysing %s ...", files[0].white);
        cwriteln;

        string humanReadableDuration = convertSecondsToHuman( sound.lengthInFrames() / cast(double)(sound.sampleRate) );

       

        cwritefln("   * Channels      = %s", sound.channels.colored);
        cwritefln("   * Sampling rate = %s Hz", sound.sampleRate.colored);
        cwritefln("   * Duration      = %s samples (%s)", sound.lengthInFrames().colored, humanReadableDuration.colored);
        cwriteln;
        
        int N = cast(int)(sound.lengthInFrames());
        int channels = sound.channels;
        real sampleRate = sound.sampleRate;

        // Analyze each channel independently
        foreach(chan; 0..channels)
        {   
            // Measure latency if used as a convolution kernel
            real energy = 0;
            real firstMoment = 0;
            real maxPeak = -real.infinity;

            foreach(n; 0..N)
            {
                real sample = sound.sample(chan, n);
                energy += sample*sample;
                firstMoment += n * sample * sample;

                real peak = abs(sample);
                if (maxPeak < peak)
                    maxPeak = peak;
            }            

            real rms = sqrt(energy / N);
            real latencyMeasured = firstMoment / energy;
            real peak_dB = convertLinearGainToDecibel(maxPeak);
            real rms_dB = convertLinearGainToDecibel(rms);
            string readableLatency = convertSecondsToHuman( latencyMeasured / sampleRate );

            cwritefln("     Channel #%s", chan);
            cwritefln("       * Energy            = %s", format("%.10g", energy).colored);
            cwritefln("       * Peak              = %s", format("%.10g dB", peak_dB).colored);
            cwritefln("       * RMS over duration = %s", format("%.10g dB", rms_dB).colored);
            cwritefln("       * Latency           = %s samples (%s)", format("%g", latencyMeasured).colored, readableLatency.colored);
            writeln();
        }
        return 0;
    }
    catch(Exception e)
    {
        writeln;
        cwritefln(format("error: %s", escapeCCL(e.msg)).lred);
        writeln;
        usage();
        writeln;
        return 1;
    }
}

string convertSecondsToHuman(double seconds)
{
    double mag = abs(seconds);
    if (mag >= 1)
    {
        return format("%.1g sec", seconds);
    }
    else if (mag >= 0.01)
    {
        return format("%s ms", cast(int)(0.5 + seconds * 1000));
    }
    else if (mag >= 0.001)
    {
        return format("%.2g ms", seconds * 1000);
    }
    else
        return format("%.2g us", seconds * 1000000);
}

// highlight
string colored(string s)
{
    return s.yellow;
}
string colored(int s)
{
    return to!string(s).yellow;
}