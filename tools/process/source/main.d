import std.stdio;
import std.algorithm;
import std.array;
import std.range;
import std.conv;
import std.string;
import std.file;
import std.path;

import arsd.dom;
import waved;

import dplug.host;


void usage()
{
    writeln();
    writeln("Auburn Sounds plugin benchmark\n");
    writeln("Usage: process [-i input.wav] [-o output.wav] [-precise] [-preroll] [-t times] [-h] [-buffer <bufferSize>] [-preset <index>] [-param <index> <value>] [-output-xml <filename>] plugin.dll\n");
    writeln();
    writeln("Params:");
    writeln("  -i <file.wav>          Specify an input file (default: process silence)");
    writeln("  -o <file.wav>          Specify an output file (default: do not output a file)");
    writeln("  -t <count>             Process the input multiple times (default: 1)");
    writeln("  -h, --help             Display this help");
    writeln("  -precise               Use experimental time, more precise measurement BUT much less accuracy (Windows-only)");
    writeln("  -preroll               Process one second of silence before measurement");
    writeln("  -buffer <pattern>      Process audio by given chunk pattern (Default: 256)");
    writeln("                           This is a small language:");
    writeln(`                             *           : all remaining samples`);
    writeln(`                             64          : process by 64 samples`);
    writeln(`                             64, 512     : process by 64 samples, then only by 512 samples`);
    writeln(`                             1,1024,loop : process 1 samples, then 1, then loop that pattern.`);
    writeln(`                           Helpful to find buffer bugs in your plugin. Pattern applied separately in preroll.`);
    writeln("  -preset                Choose preset to process audio with");    
    writeln("  -param                 Set parameter value after loading preset");
    writeln("  -show-params           Set parameter value after loading preset");
    writeln("  -output-xml            Write measurements into an xml file instead of stdout");
    writeln("  -vverbose              Be verbose even if -output-xml was specified");
    writeln;
}

// XML output format:
/*
<?xml version="1.0" encoding="UTF-8"?>
<measurements>
    <parameters>
        <input>bass.wav</input>
        <output>our-bass.wav</output>
        <times>1</times>
        <precise/>
        <preroll/>
        <buffer>256</buffer>
        <preset>1</preset>
        <param index="0" value="0.4" />
        <param index="1" value="0.8" />
        <plugin>cool_effect.dll</plugin>
        <plugin_timestamp>YYYY-MM-DDTHH:MM:SS.FFFFFFFTZ</plugin_timestamp>
    </parameters>
    <min_seconds>0.11</min_seconds>
    <avg_seconds>0.11</avg_seconds>
    <median_seconds>0.11</median_seconds>
    <run_seconds>0.15</run_seconds>
    <run_seconds>0.13</run_seconds>
    <run_seconds>0.19</run_seconds>
    <run_seconds>0.16</run_seconds>
</measurements>
*/

enum int ALL_REMAINING_BUF = -1;
enum int LOOP_PATTERN = -2;

int main(string[]args)
{
    try
    {
        string pluginPath = null;
        string outPath = null;
        string inPath = null;
        string bufferPatternStr = "256";
        
        bool help = false;
        bool preRoll = false;
        bool precise = false;
        bool verbose = true;
        bool vverbose = false;
        bool showParams = false;
        int times = 1;
        int preset = -1; // none
        float[int] parameterValues;
        string xmlFilename;

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
                bufferPatternStr = args[i];
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
            else if (arg == "-param")
            {
                ++i;
                int paramIndex = to!int(args[i]);
                ++i;
                float paramValue = to!float(args[i]);
                parameterValues[paramIndex] = paramValue;
            }
            else if (arg == "-output-xml")
            {
                ++i;
                xmlFilename = args[i];
                verbose = false;
            }
            else if (arg == "-vverbose")
            {
                vverbose = true;
            }
            else if (arg == "-show-params")
            {
                showParams = true;
            }
            else if (arg == "-h" || arg == "--help")
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

        int[] bufferPattern = parseBufferPattern(bufferPatternStr);

        bool outputXML = xmlFilename !is null;
        Document xmlOutput;

        if (outputXML)
        {
            xmlOutput = new Document;
            xmlOutput.setProlog(`<?xml version="1.0" encoding="UTF-8"?>`);
            xmlOutput.root = xmlOutput.createElement("measurements");
            Element parametersXml = xmlOutput.root.addChild("parameters");

            foreach (index, value; parameterValues)
            {
                parametersXml.addChild("param")
                             .setAttribute("index", to!string(index))
                             .setAttribute("value", to!string(value));
            }
            
            pluginPath = pluginPath.absolutePath.buildNormalizedPath;

            // store singular parameters
            parametersXml.addChild("input").innerText = inPath;

            parametersXml.addChild("output").innerText = outPath;

            parametersXml.addChild("buffer").innerText = bufferPatternStr;
            if (preRoll) parametersXml.addChild("preroll");
            if (precise) parametersXml.addChild("precise");
            parametersXml.addChild("times").innerText = times.to!string;
            parametersXml.addChild("preset").innerText = preset.to!string;
            parametersXml.addChild("plugin").innerText = pluginPath;
            parametersXml.addChild("plugin_timestamp").innerText = pluginPath.timeLastModified.toISOExtString;
        }

        // this flag is only there to be verbose even in -outpu-xml scenario
        if (vverbose)
        {
            verbose = true;
        }
        
        if (help)
        {
            usage();
            return 0;
        }
	    if (pluginPath is null)
            throw new Exception("No plugin path provided");
        if (times < 1)
            throw new Exception("Sound must be processed at least 1 time");

        Sound sound;

        if (inPath)
            sound = decodeSound(inPath);
        else
        {
            // ten seconds of stereo silence
            sound.channels = 2;
            sound.sampleRate = 44100;
            sound.samples = new float[44100 * 2 * 10];
            sound.samples[] = 0;

            inPath = "10 seconds of silence";
        }

        int N = sound.lengthInFrames();

        double sampleDurationMs = (1000.0 * N) / sound.sampleRate;

        if (verbose) writefln("This sounds lasts %s ms at a sampling-rate of %s Hz.", sampleDurationMs, sound.sampleRate);

        int numChannels = sound.channels;

        float[][] inputChannels;
        float[][] outputChannels;
        inputChannels.length = numChannels;
        outputChannels.length = numChannels;

        foreach(chan; 0..numChannels)
        {
            inputChannels[chan].length = N;
            outputChannels[chan].length = N;
        }

        // Copy input to inputChannels
        foreach(chan; 0..numChannels)
        {
            for (int i = 0; i < N; ++i)
            {
                inputChannels[chan][i] = sound.samples[i * numChannels + chan];
            }
        }

        if (verbose)
        {
            writeln;
            writefln("Starting speed measurement of %s", pluginPath);
            writefln("%s will be processed %s time(s)", inPath, times);
            if (outPath)
                writefln("Output written to %s", outPath);
        }

        getCurrentThreadHandle();

        // Get first buffer size
        int currentMaxBufferSize;
        {
            PatternInterpreter interp;
            int silenceLength = sound.sampleRate;
            interp.initialize(preRoll ? silenceLength : N, bufferPattern);
            currentMaxBufferSize = interp.getNextBufferSize();
        }

        long timeBeforeInit = getTickUs(precise);
        IPluginHost host = createPluginHost(pluginPath);
        host.setSampleRate(sound.sampleRate);
        host.setMaxBufferSize(currentMaxBufferSize);
        if (verbose) writefln("Setting initial buffer size to %s\n", currentMaxBufferSize);
        if (!host.setIO(numChannels, numChannels))
            throw new Exception(format("Unsupported I/O: %s inputs, %s outputs", numChannels, numChannels));

        host.beginAudioProcessing();

        void ensureBufferSize(int bufSize)
        {
            bool doChange = (bufSize > currentMaxBufferSize); // Note: hosts may change buffer size more than this

            //bool doChange = (bufSize != currentMaxBufferSize); // Note: this perform more buffer size change than necessary
            
            if (doChange)
            {
                if (verbose) writefln("Changing buffer size to %s\n", bufSize);
                host.endAudioProcessing();
                currentMaxBufferSize = bufSize;
                host.setMaxBufferSize(bufSize);
                host.beginAudioProcessing();
            }
        }

        if (preset != -1)
            host.loadPreset(preset);
        
        foreach (int paramIndex, float paramvalue; parameterValues)
        {
            host.setParameter(paramIndex, paramvalue);
        }

        if (showParams)
        {
            writeln;
            writeln("Parameters:");
            int count = host.getParameterCount();
            for(int p = 0; p < count; ++p)
            {
                writefln("  - %d %s value = %f", p, host.getParameterName(p), host.getParameter(p));
            }
            writeln;
        }

        long timeAfterInit = getTickUs(precise);

        if (verbose) writefln("Initialization took %s", convertMicroSecondsToDisplay(timeAfterInit - timeBeforeInit));

        float*[] inputPointers = new float*[numChannels];
        float*[] outputPointers = new float*[numChannels];

        float[][] silence = new float[][numChannels];
        float[][] dummyOut = new float[][numChannels];
        foreach(chan; 0..numChannels)
        {
            silence[chan].length = N;
            silence[chan][0..N] = 0;
            dummyOut[chan].length = N; // will be filled with NaNs
        }

        // Process one second of silence to warm things-up and avoid first buffer effect
        if (preRoll)
        {
            if (verbose) writeln;
            if (verbose) writefln("Pre-rolling 1 second of silence...");
            int silenceLength = sound.sampleRate;

            foreach(chan; 0..numChannels)
            {
                inputPointers[chan] = silence[chan].ptr;
                outputPointers[chan] = dummyOut[chan].ptr;
            }

            PatternInterpreter interp;
            interp.initialize(silenceLength, bufferPattern);
            while (!interp.finished())
            {
                int bufsize = interp.getNextBufferSize();
                ensureBufferSize(bufsize);

                host.processAudioFloat(inputPointers.ptr, outputPointers.ptr, bufsize);
                foreach(chan; 0..numChannels)
                {
                    inputPointers[chan] += bufsize;
                    outputPointers[chan] += bufsize;
                }
            }
        }

        double[] measures;


        for (int t = 0; t < times; ++t)
        {
            if (verbose) writeln;
            if (verbose) writefln(" * Measure %s: Start processing %s...", t, inPath);
            long timeA = getTickUs(precise);

            foreach(chan; 0..numChannels)
            {
                inputPointers[chan] = inputChannels[chan].ptr;
                outputPointers[chan] = outputChannels[chan].ptr;
            }

            // Iterate by buffer size following the pattern.
            PatternInterpreter interp;
            interp.initialize(N, bufferPattern);
            while (!interp.finished())
            {
                int bufSize = interp.getNextBufferSize();
                ensureBufferSize(bufSize);

                host.processAudioFloat(inputPointers.ptr, outputPointers.ptr, bufSize);
                foreach(chan; 0..numChannels)
                {
                    inputPointers[chan] += bufSize;
                    outputPointers[chan] += bufSize;
                }
            }

            long timeB = getTickUs(precise);
            long measureUs = timeB - timeA;
            if (verbose) writefln("   Processed %s in %s", inPath, convertMicroSecondsToDisplay(measureUs));

            measures ~= cast(double)measureUs;

            if (outputXML)
                xmlOutput.root.addChild("run_seconds").innerText = (measureUs / 1_000_000.0).to!string;
        }

        double minTime = measures[0];
        double medianTime = measures[0];
        double averageTime = measures[0];

        if (times > 1)
        {
            if (verbose) writeln;
            if (verbose) writefln("Results:");

            minTime = double.infinity;
            foreach(m; measures)
            {
                minTime = min(minTime, m);
            }
            medianTime = median(measures);
            averageTime = average(measures);
            if (verbose) writefln(" * minimum time: %s => %.2f x real-time", convertMicroSecondsToDisplay(minTime), 1000.0*sampleDurationMs / minTime);
            if (verbose) writefln(" * median  time: %s => %.2f x real-time", convertMicroSecondsToDisplay(medianTime), 1000.0*sampleDurationMs / medianTime);
            if (verbose) writefln(" * average time: %s => %.2f x real-time", convertMicroSecondsToDisplay(averageTime), 1000.0*sampleDurationMs / averageTime);

            if (verbose && precise)
            {
                version(Windows)
                {
                    writeln(" (Warning: -precise was used, those numbers are precise but less *accurate*)");
                }
            }
        }

        if (outputXML)
        {
            xmlOutput.root.addChild("min_seconds").innerText = (minTime / 1_000_000.0).to!string;
            xmlOutput.root.addChild("avg_seconds").innerText = (averageTime / 1_000_000.0).to!string;
            xmlOutput.root.addChild("median_seconds").innerText = (medianTime / 1_000_000.0).to!string;
        }

        // write output if necessary
        if (outPath)
        {
            // Copy processed output back into `sound`
            foreach(chan; 0..numChannels)
            {
                for (int i = 0; i < N; ++i)
                {
                    sound.samples[i * numChannels + chan] = outputChannels[chan][i];
                }
            }
            encodeWAV(sound, outPath);
        }

        host.endAudioProcessing();
        host.close();

        // Dump xml
        if (outputXML) xmlOutput.getData.toFile(xmlFilename);

        return 0;
    }
    catch(Exception e)
    {
        import std.stdio;
        writefln("error: %s", e.msg);
        usage();
        return 1;
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
    import core.sys.windows.windef;
    import core.sys.windows.winbase;
    __gshared HANDLE hThread;

    extern(Windows) BOOL QueryThreadCycleTime(HANDLE   ThreadHandle, PULONG64 CycleTime) nothrow @nogc;
    long qpcFrequency;
    void getCurrentThreadHandle()
    {
        hThread = GetCurrentThread();

        // VCVrack hack is better than trying to find a "cycle per seconds"
        // for QueryThreadCycleTime
        qpcFrequency = 2_500_000;
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

int[] parseBufferPattern(const(char)[] s)
{
    int[] r;
    foreach(token; split(s, ","))
    {
        if (token == "*")
        {
            r ~= ALL_REMAINING_BUF;
        }
        if (token == "loop")
        {
            r ~= LOOP_PATTERN;
        }
        else
        {
            int samples = to!int(token);
            if (samples > int.max)
                throw new Exception("Much too high buffer size, this will eat up RAM in a real scenario. What are you trying to do?");
            if (samples <= 0)
                throw new Exception("Zero or negative numbers not allowed in pattern");
            r ~= samples;            
        }
    }

    if (r is null)
        throw new Exception("Empty buffer pattern");
    return r;
}


// Interpret buffer sizes
// use: while (!finished) 
//          bufsize = getNextBufferSize()
struct PatternInterpreter
{
public:

    void initialize(int totalSamples, int[] pattern)
    {
        _totalSamples = totalSamples;
        _pattern = pattern;
        _index = 0;
        _processedSamples = 0;
    }

    bool finished()
    {
        return _processedSamples >= _totalSamples;
    }

    int getNextBufferSize()
    {
    start:
        assert(_processedSamples < _totalSamples);
        int command = _pattern[_index];
        if (command == ALL_REMAINING_BUF)
        {
            int r = _totalSamples - _processedSamples;
            _processedSamples = _totalSamples;
            return r;
        }
        else if (command == LOOP_PATTERN)
        {
            _index = 0;
            goto start;
        }
        else
        {
            int r = command;
            int max =  _totalSamples - _processedSamples;
            if (r > max)
                r = max;
            
            assert(r > 0);
            _processedSamples += r;
            if (_index + 1 < _pattern.length)
                _index = _index + 1;
            return r;
        }
    }

private:
    int[] _pattern;
    int _index;
    int _processedSamples;
    int _totalSamples;


}