import std.stdio;
import std.algorithm;
import std.range;
import std.conv;
import std.parallelism;

import waved;

import dplug.host;
import dplug.window;


void usage()
{
    writeln();
    writeln("Auburn Sounds plugin loader\n");
    writeln("usage: stress-plugin [-t times] [-h] [-gui] [-preset <p>] [-buffer <samples>] plugin.dll|plugin.vst\n");

}

void main(string[]args)
{
    try
    {
        string pluginPath = null;
        int times = 1;
        bool help = false;
        bool gui = false;
        int preset = -1;
        int bufLength = 16384 * 16;

        for(int i = 1; i < args.length; ++i)
        {
            string arg = args[i];

            if (arg == "-t")
            {
                ++i;
                times = to!int(args[i]);
            }
            else if (arg == "-h")
            {
                help = true;
            }
            else if (arg == "-buffer")
            {
                ++i;
                bufLength = to!int(args[i]);
            }
            else if (arg == "-preset")
            {
                ++i;
                preset = to!int(args[i]);
            }
            else if (arg == "-gui")
            {
                gui = true;
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

        float[][] buffers;
        buffers.length = 2;
        buffers[0].length = bufLength;
        buffers[1].length = bufLength;
        double invN = 1.0 / (2.0 ^^ 31);
        for (int i = 0; i < bufLength; ++i)
        {
            buffers[0][i] = (i ^ 1324643) * invN;
            buffers[1][i] = ((i+1) ^ 1324643) * invN;
        }

        long timeBeforeMeasures = getTickMs();

        double[] measures;
        for (int t = 0; t < times; ++t)
        {
            long timeBeforeInit = getTickMs();

            IPluginHost host = createPluginHost(pluginPath);


            host.setSampleRate(44100);
            host.setMaxBufferSize(bufLength);
            if (preset != -1)
                host.loadPreset(preset);

            foreach(thread; iota(2).parallel)
            {
                if (thread == 0)
                {
                    // On thread 0, open and close the UI

                    IWindow hostWindow;
                    if (gui)
                    {
                        hostWindow = createHostWindow(host);
                    }

                    long timeAfterInit = getTickMs();
                    writefln("Initialization took %s ms", timeAfterInit - timeBeforeInit);
                    measures ~= timeAfterInit - timeBeforeInit;

                    if (gui)
                    {
                        // stop after 1 sec
                        while(getTickMs() < 1000 + timeBeforeInit)
                            hostWindow.waitEventAndDispatch();

                        host.closeUI();
                        hostWindow.destroy();
                    }

                }
                else if (thread == 1)
                {
                    // Audio processing
                    float*[2] p = [ buffers[0].ptr, buffers[1].ptr ];
                    host.processAudioFloat(p.ptr, p.ptr, bufLength);
                }
            }

            host.close();
        }

        long timeAfterMeasures = getTickMs();

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
            writefln(" * minimum load+close time: %s ms", minTime);
            writefln(" * median  load+close time: %s ms", medianTime);
            writefln(" * average load+close time: %s ms", averageTime);
            writefln(" * total time: %s ms", timeAfterMeasures - timeBeforeMeasures);
        }
    }
    catch(Exception e)
    {
        import std.stdio;
        writefln("error: %s", e.msg);
        usage();
    }
}

long getTickMs() nothrow @nogc
{
    import core.time;
    return convClockFreq(MonoTime.currTime.ticks, MonoTime.ticksPerSecond, 1_000);
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
