import std.stdio;
import std.algorithm;
import std.math;
import std.string;
import std.array;
import std.conv;

import dplug.core;
import dplug.host;

import consolecolors;
import audioformats;

void usage()
{
    writeln("Usage:");
    writeln("        latency-check [-preset n] [-param n value] <plugin-path>");
    writeln();
    writeln("Description:");
    writeln("        This measures latency on a stereo plug-in.");
    writeln;
    writeln("Flags:");
    writeln("        -h, --help        Shows this help");
    writeln("        -preset           Choose preset to process audio with.");
    writeln("        -output           Output full processed files (default = false).");
    writeln("        -param            Set parameter value after loading preset");
    writeln("        -sr               Test only one sample-rate");
    writeln("        -preroll <secs>   Preroll duration (default = 2). This inserts <secs> time before preroll noise and dirac measure.");
    writeln("        -tail <secs>      Tail duration (default = 5). This inserts <secs> time after dirac in order to make the measure.");
    writeln;
    writeln("Explanations:");
    writeln("        To minimize errors, plugin is fed with:");
    writeln("           1. a 100ms burst of noise");
    writeln("           2. then -preroll seconds silence");
    writeln("           3. then a single dirac sample");
    writeln("           4. then a -tail seconds silence");
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
        double prerollSecs = 2.0;
        double tailSecs = 5.0;

        // Note: 11025 and 22050 are mandatory for auval
        double[] sampleRates = [11025, 22050, 44100, 48000, 88200, 96000, 192000];
        bool firstSRFlag = true;
        bool outputResults = false;

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
            else if (arg == "-output")
            {
                outputResults = true;                
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
            else if (arg == "-preroll")
            {
                ++i;
                prerollSecs = to!double(args[i]);
            }
            else if (arg == "-tail")
            {
                ++i;
                tailSecs = to!double(args[i]);
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

        if (prerollSecs < 0)
            throw new Exception("-preroll should be a >= 0 number of seconds");

        

        writeln;

        foreach (sampleRate ; sampleRates)
        {
            cwritefln("*** Testing at sample rate %s".white, sampleRate);

            IPluginHost host = createPluginHost(pluginPath);
            if (preset != -1)
                host.loadPreset(preset);

            foreach (int paramIndex, float paramvalue; parameterValues)
            {
                host.setParameter(paramIndex, paramvalue);
            }
            
            int noiseInSamples = cast(int)(sampleRate * 0.1); // 100ms of sample to warm the plugin (especially dynamics)
            int prerollInSamples = cast(int)(sampleRate * prerollSecs); // should let the processed sound tail out. Increase if unsure.
            int tailInSamples = cast(int)(sampleRate * tailSecs); // 5 seconds of latency should be enough for anybody

            int totalSamples = noiseInSamples + prerollInSamples + tailInSamples;

            int numChannels = 2;

            float[] testL = buildTestSignal(noiseInSamples, prerollInSamples, tailInSamples);
            float[] testR = testL.dup;
            float[] processedL = new float[testL.length];
            float[] processedR = new float[testR.length];
            float*[] inputPointers = new float*[numChannels];
            float*[] outputPointers = new float*[numChannels];
            inputPointers[0] = testL.ptr;
            inputPointers[1] = testR.ptr;
            outputPointers[0] = processedL.ptr;
            outputPointers[1] = processedR.ptr;

            host.setSampleRate(sampleRate);
            host.setMaxBufferSize(totalSamples); // TODO: tunable buffer size
            if (!host.setIO(numChannels, numChannels))
                throw new Exception(format("Unsupported I/O: %d inputs, %d outputs", numChannels, numChannels));
            host.beginAudioProcessing();

            float latencyReported = host.getLatencySamples();

            host.processAudioFloat(inputPointers.ptr, outputPointers.ptr, totalSamples);

            // write output to WAV
            if (outputResults)
            {
                string filename = format("processed-%s.wav", sampleRate);
                writefln("  Left output written to %s", filename);
                saveAsWAV(processedL, filename, 1, sampleRate);
            }

            // NaN check!= of the output
            foreach(n; 0..totalSamples)
            {
                if (isNaN(processedL[n]) || isNaN(processedR[n]))
                    throw new Exception("NaN detected in output");
            }

            // Check that the last preroll moments are actually near zero
            foreach(n; noiseInSamples+prerollInSamples-8..noiseInSamples+prerollInSamples)
            {
                if (! ( nearSilence(processedL[n]) && nearSilence(processedR[n]) ))
                    throw new Exception("Output not silent after the end of preroll. See -output to advise.");
            }

            // Check that the last tail moments are actually near zero
            foreach(n; totalSamples-8..totalSamples)
            {
                if (! ( nearSilence(processedL[n]) && nearSilence(processedR[n]) ))
                    throw new Exception("Output not silent after the end of tail. See -output to advise. " ~
                                        "Most probably your plugin has infinite tail or long feedback.");
            }

            // Note: we only look at latency for both channels.
            real energyL = 0, energyR = 0;
            real firstMomentL = 0, firstMomentR = 0;

            int diracPositionInput = noiseInSamples+prerollInSamples;

           
            foreach(n; diracPositionInput..totalSamples)
            {
                real sample = processedL[n]; // TODO should increase precision here...
                energyL += sample*sample;
                firstMomentL += (n-diracPositionInput) * sample * sample;
            }
            foreach(n; diracPositionInput..totalSamples)
            {
                real sample = processedR[n]; // TODO should increase precision here...
                energyR += sample*sample;
                firstMomentR += (n-diracPositionInput) * sample * sample;
            }

            if (energyL == 0)
                throw new Exception("Processing a dirac yields silent output in left channel, written to zero-output.wav");
            if (energyR == 0)
                throw new Exception("Processing a dirac yields silent output in right channel, written to zero-output.wav");
            
            double latencyMeasuredL = firstMomentL / energyL;
            double latencyMeasuredR = firstMomentR / energyR;

            writefln("Measured latency for left channel: %s samples", latencyMeasuredL);
            writefln("                    right channel: %s samples", latencyMeasuredR);
            if (abs(latencyMeasuredL - latencyMeasuredR) > 0.5f)
            {
                throw new Exception("left and right report differing latencies");
            }
            
            // take the mean as "measured"
            float latencyMeasured = (latencyMeasuredL + latencyMeasuredR)*0.5f;

            float latencyReportedMs = 1000.0 * latencyReported / sampleRate;
            host.endAudioProcessing();
            if (pw != 1)
            {
                cwritefln("Warning: pw is != 1 so latency with be reported wrongly".yellow);
            }

            if (abs(latencyReported - latencyMeasured) <= 0.5f)
                cwritefln("  Reported %s samples (%.3f ms), measured %s samples =&gt; OK".lgreen, latencyReported, latencyReportedMs, latencyMeasured);
            else
                cwritefln("  Reported %s samples (%.3f ms), measured %s samples =&gt; ERROR".lred, latencyReported, latencyReportedMs, latencyMeasured);
            writeln;

            host.close();
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

// Return signal:
// 0                     
// <-- noiseInSamples --><-- prerollInSamples --><-- tailInSamples -->
// [      noise         ][         0.0          ][1.0 0.0 ...      0.0]

float[] buildTestSignal(int noiseInSamples,
                        int prerollInSamples,
                        int tailInSamples)
{
    int N = 0;
    uint seed = 0xDEADDEAD;
    float[] result = new float[noiseInSamples + prerollInSamples + tailInSamples];
    for (; N < noiseInSamples; ++N)
    {
        seed = (seed = (seed * 1664525) + 1013904223);
        result[N] = -1.0f + 2.0f * (seed * 2.32831e-10f);
    }
    result[noiseInSamples..noiseInSamples+prerollInSamples] = 0.0f;
    
    // Our dirac
    result[noiseInSamples+prerollInSamples] = 1.0f;
    result[noiseInSamples+prerollInSamples+1..$] = 0.0f;

    return result;
}

bool nearSilence(float x)
{
    return fast_fabs(x) < 1e-7f; // -140dB
}