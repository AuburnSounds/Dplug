import std.stdio;
import std.algorithm;
import std.math;
import std.string;
import std.array;
import std.conv;

import dplug.core;
import dplug.host;

import consolecolors;
import waved;

void usage()
{
    writeln("Usage:");
    writeln("        latency-check [-preset n] [-param n value] <plugin-path>");
    writeln();
    writeln("Description:");
    writeln("        This measures latency on a stereo plug-in.");
    writeln;
    writeln("Flags:");
    writeln("        -h, --help  Shows this help");
    writeln("        -preset     Choose preset to process audio with.");
    writeln("        -param      Set parameter value after loading preset");
    writeln("        -sr         Test only one sample-rate");
    writeln("        -pw         Augment duration of dirac to avoid zero output (default = 1)");
    writeln;
}

// Note: use a preset that "does nothing" for measurement.
// If you use a preset which does a 7 second reverb sound, then it doesn't make sense to measure such "latency",
// since it doesn't have to be compensated for.
int main(string[] args)
{
    try
    {
        bool help = false;
        string pluginPath = null;
        int preset = -1; // none
        float[int] parameterValues;
        int pw = 1;

        // Note: 11025 and 22050 are mandatory for auval
        double[] sampleRates = [11025, 22050, 44100, 48000, 88200, 96000, 192000];
        bool firstSRFlag = true;

        for (int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "-h" || arg == "--help")
                help = true;
            else if (arg == "-preset")
            {
                ++i;
                preset = to!int(args[i]);
            }
            else if (arg == "-sr")
            {
                if (firstSRFlag) 
                {
                    sampleRates = [];
                    firstSRFlag = false;
                }
                ++i;
                sampleRates ~= to!double(args[i]);
            }
            else if (arg == "-pw")
            {
                ++i;
                pw = to!int(args[i]);
            }
            else if (arg == "-param")
            {
                ++i;
                int paramIndex = to!int(args[i]);
                ++i;
                float paramValue = to!float(args[i]);
                parameterValues[paramIndex] = paramValue;
            }
            else 
            {
                if (pluginPath is null)
                    pluginPath = arg;
                else
                    help = true;
            }
        }

        if (pluginPath is null)
            help = true;

        if (help)
        {
            usage();
            return 1;
        }

        if (pw < 1 || pw > 100)
        {
            throw new Exception("-pw should be set between 1 and 100 included");
        }

        IPluginHost host = createPluginHost(pluginPath);
        if (preset != -1)
            host.loadPreset(preset);

        foreach (int paramIndex, float paramvalue; parameterValues)
        {
            host.setParameter(paramIndex, paramvalue);
        }

        int N = 192000 * 10; // 10 seconds at 192000

        // to avoid pre-roll effects, dirac is at sample E
        // energy before E won't be integrated
        int E = 192000; 

        float[] diracL = new float[N];
        float[] diracR = new float[N];

        int numChannels = 2;

        float[] processedL = new float[N];
        float[] processedR = new float[N];

        float*[] inputPointers = new float*[numChannels];
        float*[] outputPointers = new float*[numChannels];
        inputPointers[0] = diracL.ptr;
        inputPointers[1] = diracR.ptr;
        outputPointers[0] = processedL.ptr;
        outputPointers[1] = processedR.ptr;

        writeln;


        foreach (sampleRate ; sampleRates)
        {
            cwritefln("*** Testing at sample rate %s".white, sampleRate);
            host.setSampleRate(sampleRate);
            host.setMaxBufferSize(N);
            if (!host.setIO(numChannels, numChannels))
                throw new Exception(format("Unsupported I/O: %d inputs, %d outputs", numChannels, numChannels));
            host.beginAudioProcessing();

            float latencyReported = host.getLatencySamples();

            diracL[0..N] = 0;
            diracL[E..E + pw] = 1;
            diracR[0..N] = 0;
            diracR[E..E + pw] = 1;

            host.processAudioFloat(inputPointers.ptr, outputPointers.ptr, N);

            // write output to WAV
            {
                string filename = format("processed-%s.wav", sampleRate);
                writefln("  Output written to %s", filename);
                Sound s = Sound(cast(int)(0.5f+sampleRate), 1, processedL);
                encodeWAV(s, filename);
            }

            // NaN check!= of the output
            foreach(n; 0..N)
            {
                if (isNaN(processedL[n]) || isNaN(processedR[n]))
                    throw new Exception("NaN detected in output");
            }

            // Note: we only look at latency for the left channel, assuming both channels will be similar
            double energy = 0;
            double firstMoment = 0;
            foreach(n; E..N)
            {
                double sample = processedL[n];
                energy += sample*sample;
                firstMoment += (n-E) * sample * sample;
            }

            if (energy == 0)
                throw new Exception("Processing a dirac yields silent output, written to zero-output.wav");

            float latencyMeasured = firstMoment / energy;
            
            float latencyReportedMs = 1000.0 * latencyReported / sampleRate;
            host.endAudioProcessing();
            if (pw != 1)
            {
                cwritefln("Warning: pw is != 1 so latency with be reported wrongly".yellow);
            }

            if (abs(latencyReported - latencyMeasured) <= 0.5f)
                cwritefln("  Reported %s samples (%.3f ms), measured %s samples => OK".lgreen, latencyReported, latencyReportedMs, latencyMeasured);
            else
                cwritefln("  Reported %s samples (%.3f ms), measured %s samples => ERROR".lred, latencyReported, latencyReportedMs, latencyMeasured);
            writeln;
        }
        host.close();
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

