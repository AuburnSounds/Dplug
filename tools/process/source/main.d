import std.stdio;
import std.algorithm;
import std.range;
import std.conv;

import waved;

import dplug.host;


void usage()
{
    writeln();
    writeln("Auburn Sounds plugin benchmark\n");
    writeln("usage: process [-i input.wav] [-o output.wav] [-t times] [-h] [-b <bufferSize>] [-preset <index>] plugin.dll\n");

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
            else if (arg == "-b")
            {
                ++i;
                bufferSize = to!int(args[i]);
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
            sound.numChannels = 2;
            sound.sampleRate = 44100;
            sound.data = new float[44100 * 2 * 10]; 
            sound.data[] = 0;

            inPath = "10 seconds of silence";
        }

        if (sound.numChannels != 2)
            throw new Exception("Only support stereo inputs");
        if (bufferSize < 1)
            throw new Exception("bufferSize is < 1");

        int N = sound.lengthInFrames();

        double sampleDurationMs = (1000.0 * N) / sound.sampleRate;

        writefln("This sounds lasts %s ms at a sampling-rate of %s Hz.", sampleDurationMs, sound.sampleRate);
        
        leftChannelInput.length = N;
        rightChannelInput.length = N;
        leftChannelOutput.length = N;
        rightChannelOutput.length = N;

        for (int i = 0; i < N; ++i)
        {
            leftChannelInput[i] = sound.data[i * 2];
            rightChannelInput[i] = sound.data[i * 2 + 1];
        }

        writeln;
        writefln("Starting speed measurement of %s", pluginPath);
        writefln("%s will be processed %s time(s)", inPath, times);
        if (outPath)
            writefln("Ouput sound will be output to %s", outPath);

        IPluginHost host = createPluginHost(pluginPath);
        host.setSampleRate(sound.sampleRate);        
        host.setMaxBufferSize(bufferSize);
        if (preset != -1)
            host.loadPreset(preset);

        long getTickMs() nothrow @nogc
        {
            import core.time;
            return convClockFreq(MonoTime.currTime.ticks, MonoTime.ticksPerSecond, 1_000);
        }

        double[] measures;

        for (int t = 0; t < times; ++t)
        {
            writeln;
            writefln(" * Measure %s: Start processing %s...", t, inPath);
            long timeA = getTickMs();

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

            long timeB = getTickMs();
            long measure = timeB - timeA;
            writefln("   Processed %s with %s in %s ms", inPath, pluginPath, measure);

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
            writefln(" * minimum time: %s ms => %s x real-time", minTime, sampleDurationMs / minTime);
            writefln(" * median  time: %s ms => %s x real-time", medianTime, sampleDurationMs / medianTime);
            writefln(" * average time: %s ms => %s x real-time", averageTime, sampleDurationMs / averageTime);
        }

        // write output if necessary
        if (outPath)
        {
            sound.data = interleave(leftChannelOutput, rightChannelOutput).array;
            encodeWAV(sound, outPath);
        }

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
