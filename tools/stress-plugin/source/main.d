import std.stdio;
import std.algorithm;
import std.range;
import std.conv;

import waved;

import dplug.host;
import dplug.window;
import ae.utils.graphics;


void usage()
{
    writeln();
    writeln("Auburn Sounds plugin loader\n");
    writeln("usage: stress-load [-t times] [-h] [-gui] plugin.dll|plugin.vst\n");

}

void main(string[]args)
{
    try
    {
        string pluginPath = null;
        int times = 1;
        bool help = false;
        bool gui = false;

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

        double[] measures;
        for (int t = 0; t < times; ++t)
        {
            long timeBeforeInit = getTickMs();

            IPluginHost host = createPluginHost(pluginPath);
            host.setSampleRate(44100);
            host.setMaxBufferSize(1024);

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

            host.close();
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
            writefln(" * minimum load+close time: %s ms", minTime);
            writefln(" * median  load+close time: %s ms", medianTime);
            writefln(" * average load+close time: %s ms", averageTime);
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

