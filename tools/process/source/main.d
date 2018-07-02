import std.stdio;
import std.algorithm;
import std.range;
import std.conv;
import std.string;

import waved;

import dplug.host;


void usage()
{
    writeln();
    writeln("Auburn Sounds plugin benchmark\n");
    writeln("usage: process [-i input.wav] [-o output.wav] [-precise] [-preroll] [-t times] [-h] [-buffer <bufferSize>] [-preset <index>] plugin.dll\n");
    writeln();
    writeln("Params:");
    writeln("  -i       Specify an input file (default: process silence)");
    writeln("  -o       Specify an output file (default: do not output a file)");
    writeln("  -t       Process the input multiple times (default: 1)");  
    writeln("  -h       Display this help"); 
    writeln("  -precise Use experimental time, much more precise measurement (Windows-only)");
    writeln("  -preroll Process one second of silence before measurement");     
    writeln("  -buffer  Process audio by given chunk size (default: all-at-once)");
    writeln("  -preset  Choose preset to process audio with");    
    writeln;
}

void main(string[]args)
{
    try
    {
        string pluginPath = null;
        string outPath = null;
        string inPath = null;
        int bufferSize = 256;
        bool help = false;
        bool preRoll = false;
        bool precise = false;
        int times = 1;
        int preset = -1; // none

        for(int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "-i")
            {
                if (inPath)
                    throw new Exception("Multiple input paths provided");
                ++i;
                inPath = args[i];
            }
            else if (arg == "-o")
            {
                if (outPath)
                    throw new Exception("Multiple output paths provided");
                ++i;
                outPath = args[i];
            }
            else if (arg == "-buffer")
            {
                ++i;
                bufferSize = to!int(args[i]);
            }
            else if (arg == "-preroll")
            {
                preRoll = true;
            }
            else if (arg == "-precise")
            {
                precise = true;
            }
            else if (arg == "-t")
            {
                ++i;
                times = to!int(args[i]);
            }
            else if (arg == "-preset")
            {
                 ++i;
                preset = to!int(args[i]);
            }
            else if (arg == "-h")
            {
                help = true;
            }
            else
            {
                if (pluginPath)
                    throw new Exception("Multiple plugin paths provided");
                pluginPath = arg;
            }
        }
        if (help)
        {
            usage();
            return;
        }
	    if (pluginPath is null)
            throw new Exception("No plugin path provided");
        if (times < 1)
            throw new Exception("Sound must be processed at least 1 time");

        float[] leftChannelInput;
        float[] rightChannelInput;
        float[] leftChannelOutput;
        float[] rightChannelOutput;


        Sound sound;

        if (inPath)
            sound = decodeSound(inPath);
        else
        {
            // ten seconds of silence
            sound.channels = 2;
            sound.sampleRate = 44100;
            sound.samples = new float[44100 * 2 * 10];
            sound.samples[] = 0;

            inPath = "10 seconds of silence";
        }

        if (sound.channels != 2)
            throw new Exception("Only support stereo inputs");
        if (bufferSize < 1)
            throw new Exception("bufferSize is < 1");

        int maxBufferSize = 16384;
        if (bufferSize > 16384) // 370ms @ 44100hz
        {
            bufferSize = 16384;
            writefln("Buffer clamped to 16384.");
        }

        int N = sound.lengthInFrames();

        double sampleDurationMs = (1000.0 * N) / sound.sampleRate;

        writefln("This sounds lasts %s ms at a sampling-rate of %s Hz.", sampleDurationMs, sound.sampleRate);

        leftChannelInput.length = N;
        rightChannelInput.length = N;
        leftChannelOutput.length = N;
        rightChannelOutput.length = N;

        for (int i = 0; i < N; ++i)
        {
            leftChannelInput[i] = sound.samples[i * 2];
            rightChannelInput[i] = sound.samples[i * 2 + 1];
        }

        writeln;
        writefln("Starting speed measurement of %s", pluginPath);
        writefln("%s will be processed %s time(s)", inPath, times);
        if (outPath)
            writefln("Output written to %s", outPath);

        getCurrentThreadHandle();

        long timeBeforeInit = getTickUs(precise);
        IPluginHost host = createPluginHost(pluginPath);
        host.setSampleRate(sound.sampleRate);
        host.setMaxBufferSize(bufferSize);
        host.beginAudioProcessing();

        if (preset != -1)
            host.loadPreset(preset);
        long timeAfterInit = getTickUs(precise);

        writefln("Initialization took %s", convertMicroSecondsToDisplay(timeAfterInit - timeBeforeInit));

        // Process one second of silence to warm things-up and avoid first buffer effect
        if (preRoll)
        {
            writeln;
            writefln("Pre-rolling 1 second of silence...");
            int silenceLength = sound.sampleRate;
            float[] silenceL = new float[silenceLength];
            float[] silenceR = new float[silenceLength];
            silenceL[] = 0;
            silenceR[] = 0;
            float*[2] inChannels, outChannels;
            inChannels[0] = silenceL.ptr;
            inChannels[1] = silenceR.ptr,
            outChannels[0] = silenceL.ptr;
            outChannels[1] = silenceR.ptr;
            for (int buf = 0; buf < silenceLength / bufferSize; ++buf)
            {
                host.processAudioFloat(inChannels.ptr, outChannels.ptr, bufferSize);
                inChannels[0] += bufferSize;
                inChannels[1] += bufferSize;
                outChannels[0] += bufferSize;
                outChannels[1] += bufferSize;
            }
            // remaining samples
            host.processAudioFloat(inChannels.ptr, outChannels.ptr, silenceLength % bufferSize);
        }

        double[] measures;

        for (int t = 0; t < times; ++t)
        {
            writeln;
            writefln(" * Measure %s: Start processing %s...", t, inPath);
            long timeA = getTickUs(precise);

            float*[2] inChannels, outChannels;
            inChannels[0] = leftChannelInput.ptr;
            inChannels[1] = rightChannelInput.ptr,
            outChannels[0] = leftChannelOutput.ptr;
            outChannels[1] = rightChannelOutput.ptr;

            for (int buf = 0; buf < N / bufferSize; ++buf)
            {
                host.processAudioFloat(inChannels.ptr, outChannels.ptr, bufferSize);
                inChannels[0] += bufferSize;
                inChannels[1] += bufferSize;
                outChannels[0] += bufferSize;
                outChannels[1] += bufferSize;
            }

            // remaining samples
            host.processAudioFloat(inChannels.ptr, outChannels.ptr, N % bufferSize);

            long timeB = getTickUs(precise);
            long measure = timeB - timeA;
            writefln("   Processed %s in %s", inPath, convertMicroSecondsToDisplay(measure));

            measures ~= cast(double)measure;
        }

        if (times > 1)
        {
            writeln;
            writefln("Results:");

            double minTime = double.infinity;
            foreach(m; measures)
            {
                minTime = min(minTime, m);
            }
            double medianTime = median(measures);
            double averageTime = average(measures);
            writefln(" * minimum time: %s => %.2f x real-time", convertMicroSecondsToDisplay(minTime), 1000.0*sampleDurationMs / minTime);
            writefln(" * median  time: %s => %.2f x real-time", convertMicroSecondsToDisplay(medianTime), 1000.0*sampleDurationMs / medianTime);
            writefln(" * average time: %s => %.2f x real-time", convertMicroSecondsToDisplay(averageTime), 1000.0*sampleDurationMs / averageTime);
        }

        // write output if necessary
        if (outPath)
        {
            sound.samples = interleave(leftChannelOutput, rightChannelOutput).array;
            encodeWAV(sound, outPath);
        }

        host.endAudioProcessing();
        host.close();
    }
    catch(Exception e)
    {
        import std.stdio;
        writefln("error: %s", e.msg);
        usage();
    }
}

static auto interleave(Range1, Range2)(Range1 a, Range2 b)
{
    return a.zip(b).map!(a => only(a[0], a[1])).joiner();
}

double average(double[] arr)
{
    double sum = 0;
    foreach(d; arr)
        sum += d;
    return sum / arr.length;
}

double median(double[] arr)
{
    arr.sort(); // harmless
    if (arr.length % 2 == 0)
    {
        return (arr[arr.length/2] + arr[arr.length/2-1])/2;
    }
    else
    {
        return arr[arr.length/2];
    }
}

// Returns: "0.1 ms" when given 100 us
string convertMicroSecondsToDisplay(double us)
{
    double ms = (us / 1000.0);
    return format("%.1f ms", ms);
}


version(Windows)
{
    import core.sys.windows.windows;
    __gshared HANDLE hThread;

    extern(Windows) BOOL QueryThreadCycleTime(HANDLE   ThreadHandle, PULONG64 CycleTime) nothrow @nogc;
    long qpcFrequency;
    void getCurrentThreadHandle()
    {
        hThread = GetCurrentThread();    
        QueryPerformanceFrequency(&qpcFrequency);
    }
}
else
{
    void getCurrentThreadHandle()
    {
    }
}

static long getTickUs(bool precise) nothrow @nogc
{
    version(Windows)
    {
        if (precise)
        {
            // Note about -precise measurement
            // We use the undocumented fact that QueryThreadCycleTime
            // seem to return a counter in QPC units.
            // That may not be the case everywhere, so -precise is not reliable and should
            // never be the default.
            import core.sys.windows.windows;
            ulong cycles;
            BOOL res = QueryThreadCycleTime(hThread, &cycles);
            assert(res != 0);
            real us = 1000.0 * cast(real)(cycles) / cast(real)(qpcFrequency);
            return cast(long)(0.5 + us);
        }
        else
        {
            import core.time;
            return convClockFreq(MonoTime.currTime.ticks, MonoTime.ticksPerSecond, 1_000_000);
        }
    }
    else
    {
        import core.time;
        return convClockFreq(MonoTime.currTime.ticks, MonoTime.ticksPerSecond, 1_000_000);
    }
}