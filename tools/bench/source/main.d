/**
Copyright: Auburn Sounds 2015-2018.
License:   All Rights Reserved.
*/
import std.array;
import std.stdio;
import std.format;
import std.exception;
import std.algorithm;
import std.range;
import std.string;
import std.conv;
import std.path;
import std.file;
import std.datetime;
import utils;

import waved;
import colorize;
import arsd.dom;


// Use case: 
// - compare algorithm
// - batch processing
// - speed measurements
// - non-regressions

void usage()
{
    writeln;
    writeln("Auburn Sounds benchmark tool");
    writeln("Matrix of plug-ins, configurations and WAV sources");
    writeln;
    writeln("Usage: bench [-h] [-f] [<bench.xml>]");
    writeln("    -h, --help    Print this message");
    writeln("    -t, --times   Changes number of speed measures (default: 30)");
    writeln("    -f, --force   Force reprocessing of cached outputs");
    writeln;
    writeln("Note: if task file is not provided, uses bench.xml");
    writeln;
}

int main(string[] args)
{
    try
    {
        bool help;
        bool forceEncode;
        string taskFile = "bench.xml";
        int times = 30;

        for(int i = 1; i < args.length; ++i)
        {
            string arg = args[i];

            if (arg == "-h" || arg == "--help")
            {
                help = true;
            }
            else if (arg == "-f" || arg == "--force")
            {
                forceEncode = true;
            }
            else if (arg == "-t" || arg == "--times")
            {
                ++i;
                times = to!int(args[i]);
            }
            else
            {
                if (taskFile)
                {
                    throw new Exception("only one XML file can be provided");
                }
                taskFile = arg;
            }
        }

        if (help)
        {
            usage();
            return 0;
        }        

        // Check that the config file exists
        if (!exists(taskFile))
            throw new Exception(format("%s does not exist", taskFile));

        auto universe = new Universe(forceEncode, times);
        universe.parseTask(taskFile);
        universe.executeAllTasks();
        return 0;
    }
    catch(Exception e)
    {
        import std.stdio;
        writeln("error: ", e.msg);
        return 1;
    }
}

class Plugin
{
    string pluginPath;
    string shortName;
    SysTime pluginTimestamp;
    double[int] parameterValues;
    ProcessMeasurements lastMeasurements;

    bool is64b;

    static bool detectPEBitness(string pluginPath) // true if 64-bit, false else
    {
        import std.stdio;
        File f = File(pluginPath, "rb");
        f.seek(0x3c);

        short[1] bufOffset;
        short[] offset = f.rawRead(bufOffset[]);

        f.seek(offset[0]);

        ubyte[6] buf;
        ubyte[] flag = f.rawRead(buf[]);

        if (flag[] == "PE\x00\x00\x4C\x01")
            return false;
        else if (flag[] == "PE\x00\x00\x64\x86")
            return true;
        else
            throw new Exception("Couldn't parse file as PE");
    }

    void toString(scope void delegate(const(char)[]) sink)
    {
        sink(shortName);
        if (is64b) sink("(64-bit)");
        else sink("(32-bit)");
        foreach (int paramIndex, double paramvalue; parameterValues)
            formattedWrite(sink, " %s=%s", paramIndex, paramvalue);
    }

    this(string pluginPath)
    {
        this.pluginPath = pluginPath;
        enforce(exists(pluginPath), format("Can't find plugin file '%s'", pluginPath));
        pluginTimestamp = pluginPath.timeLastModified;
        this.shortName = pluginPath.baseName.stripExtension;
        this.is64b = detectPEBitness(pluginPath);
    }

    // TODO: add parameter values too?
    size_t taskHash()
    {
        size_t hash = parameterValues.hashOf;
        hash = pluginTimestamp.hashOf(hash);
        return hash;
    }
}

class TaskConfiguration
{
    int presetIndex;

    this(int presetIndex)
    {
        this.presetIndex = presetIndex;
    }
}

class Source
{
    string wavPath;
    string shortName;
    string outputDirectory;

    this(string wavPath, string outputDirectory)
    {
        this.wavPath = wavPath;
        this.shortName = wavPath.baseName.stripExtension;
        this.outputDirectory = outputDirectory;
    }
}

abstract class Processor
{
    void afterProcess(Universe universe, TaskConfiguration conf, Source source);
    void reduceResults();
}

class QualityCompareProcessor : Processor
{
    override void afterProcess(Universe universe, TaskConfiguration conf, Source source)
    {
        string baselineFile = pathForEncode(universe.baseline, conf, source, "wav");
        foreach(challenger; universe.challengers)
        {
            string challengerFile = pathForEncode(challenger, conf, source, "wav");
            string cmd = format(`wav-compare --quiet "%s" "%s"`, baselineFile, challengerFile);
            safeCommand(cmd);
        }
    }

    override void reduceResults()
    {}
}

class SpeedMeasureProcessor : Processor
{
    double[][string] speedUps;

    override void afterProcess(Universe universe, TaskConfiguration conf, Source source)
    {
        foreach(challenger; universe.challengers)
        {
            double baselineSec = universe.baseline.lastMeasurements.minSeconds;
            double challengerSeconds = challenger.lastMeasurements.minSeconds;
            double percents = (baselineSec / challengerSeconds - 1) * 100;
            speedUps[challenger.shortName] ~= percents;
            cwritef("  %s vs %s = %.3fs vs %.3fs => ".grey, challenger.shortName, universe.baseline, 
                                                              challengerSeconds, baselineSec);
            cwritefln("%+.2s%%".yellow, percents);
        }
    }

    override void reduceResults()
    {        
        foreach(string challenger; speedUps.byKey)
        {
            double percents = 0;
            foreach(s; speedUps[challenger])
                percents += s;
            double globalSpeedUp = percents / speedUps[challenger].length;
            string msg = "=> Global speed-up for %s = " ~ "%+.2s%%";
            msg = (globalSpeedUp > 2) ? msg.green : ((globalSpeedUp < -2) ? msg.red : msg.yellow);
            cwritefln(msg, challenger, globalSpeedUp);
        }        
    }
}

class Universe
{
    Plugin baseline;
    Plugin[] challengers;
    TaskConfiguration[] configurations;
    Source[] sources;
    Processor[] processors;

    bool forceEncode;
    int speedMeasureCount = 30;

    string xmlDir;
    string sourceDirectory = "p:/Samples";
    string outputDir = "bench";

    auto allPlugins()
    {
        return chain(only(baseline), challengers);
    }

    this(bool forceEncode, int speedMeasureCount)
    {
        this.forceEncode = forceEncode;
        this.speedMeasureCount = speedMeasureCount;
    }

    void parseTask(string xmlPath)
    {
        xmlDir = xmlPath.dirName;

        string content = cast(string)(std.file.read(xmlPath));
        auto doc = new Document();
        doc.parseUtf8(content, true, true);

        parseDirectories(doc);
        parseBaseline(doc);
        parseChallengers(doc);
        parsePresets(doc);
        parseSources(doc);
        parseProcessors(doc);
    }

    void parseDirectories(Document doc)
    {
        foreach(e; doc.getElementsByTagName("source-dir"))
        {
            sourceDirectory = e.innerText;
        }

        foreach(e; doc.getElementsByTagName("output-dir"))
        {
            outputDir = e.innerText;
        }
    }

    Plugin parsePlugin(Element pluginTag)
    {
        string pluginPath = pluginTag.innerText.strip;
        if (!pluginPath.isAbsolute)
            pluginPath = buildPath(xmlDir, pluginPath);

        auto plugin = new Plugin(pluginPath);
        foreach(e; pluginTag.getElementsByTagName("parameter"))
        {
            string parameterIndexStr = e.getAttribute("index");
            if (parameterIndexStr is null)
                throw new Exception(`parameter node must have 'index' attribute set (example: index="0")`);
            int parameterIndex = to!int(parameterIndexStr);

            string parameterValueStr = e.getAttribute("value");
            if (parameterValueStr is null)
                throw new Exception(`parameter node must have 'value' attribute set (example: value="0.5")`);
            double parameterValue = to!double(parameterValueStr);

            plugin.parameterValues[parameterIndex] = parameterValue;
        }
        return plugin;
    }

    void parseBaseline(Document doc)
    {
        auto elems = doc.getElementsByTagName("baseline");
        if (elems.length == 0)
            throw new Exception("Baseline must be provided");
        if (elems.length > 1)
            throw new Exception(format("Only single baseline must be provided, not %s", elems.length));

        baseline = parsePlugin(elems[0]);

    }

    void parseChallengers(Document doc)
    {
        foreach(e; doc.getElementsByTagName("challenger"))
        {
            auto plugin = parsePlugin(e);
            challengers ~= plugin;
        }
    }

    void parsePresets(Document doc)
    {
        foreach(e; doc.getElementsByTagName("preset"))
        {
            int presetIndex = to!int(e.innerText);
            configurations ~= new TaskConfiguration(presetIndex);
        }

        foreach(e; doc.getElementsByTagName("preset-range"))
        {
            int min = e.getAttribute("min").to!int;
            int max = e.getAttribute("max").to!int;
            foreach(presetIndex; min..max + 1)
            {
                configurations ~= new TaskConfiguration(presetIndex);
            }
        }

        // If no presets were specified use preset 0
        if (configurations.empty)
        {
            configurations ~= new TaskConfiguration(0);
        }
    }

    void parseSources(Document doc)
    {
        foreach(e; doc.getElementsByTagName("source"))
        {
            string sourcePath;
            if (e.innerText.isAbsolute)
                sourcePath = e.innerText.strip;
            else
                sourcePath = buildPath(sourceDirectory, e.innerText);

            sources ~= new Source(sourcePath, outputDir);
        }
    }

    void parseProcessors(Document doc)
    {
        if (doc.getElementsByTagName("quality-compare").length > 0)
        {
            processors ~= new QualityCompareProcessor();
        }
        
        if (doc.getElementsByTagName("speed-measure").length > 0)
        {
            processors ~= new SpeedMeasureProcessor();
        }
    }

    void executeAllTasks()
    {
        // For each source, for each preset, test every encoder
        foreach(source; sources)
        {
            foreach(conf; configurations)
            {
                executeSingleTask(source, conf);
            }
        }

        cwriteln;

        foreach(processor; processors)
            processor.reduceResults();
    }

    void executeSingleTask(Source source, TaskConfiguration conf)
    {
        foreach(plugin; allPlugins)
        {
            lazyEncode(plugin, conf, source);
        }

        foreach(processor; processors)
        {
            processor.afterProcess(this, conf, source);
        }
    }

    // Updates plugin.lastMeasurements with calculated or cached results
    void lazyEncode(Plugin plugin, TaskConfiguration conf, Source source)
    {
        string outputFile = pathForEncode(plugin, conf, source, "wav");
        string xmlFile = pathForEncode(plugin, conf, source, "xml");

        bool isCached = exists(outputFile) && exists(xmlFile);

        bool pluginTimestampDiffer = true;

        // compare timestamps of plugins
        if (isCached && !forceEncode)
        {
            plugin.lastMeasurements.parse(xmlFile);
            pluginTimestampDiffer = plugin.lastMeasurements.taskHash != plugin.taskHash;
        }

        bool doEncode = pluginTimestampDiffer || forceEncode;

        if (doEncode)
        {
            encode(plugin, conf, source, outputFile, xmlFile);
            plugin.lastMeasurements.parse(xmlFile);
        }
    }

    void encode(Plugin plugin, TaskConfiguration conf, Source source, string outputFile, string xmlPath)
    {
        int times = speedMeasureCount;
        mkdirRecurse(dirName(outputFile));
        string exeProcess = plugin.is64b ? "process64" : "process";
        string parameterValues;
        foreach (int paramIndex, double paramvalue; plugin.parameterValues)
        {
            parameterValues ~= format(" -param %s %s", paramIndex, paramvalue);
        }
        string cmd = format(`%s -precise -t %s -i "%s" -o "%s" -preset %s%s -output-xml "%s" "%s"`, 
                            exeProcess, times, source.wavPath, outputFile, conf.presetIndex, parameterValues, xmlPath, plugin.pluginPath);
        safeCommand(cmd);
    }
}



string pathForEncode(Plugin plugin, TaskConfiguration conf, Source source, string ext)
{
    return buildPath(source.outputDirectory, format("%s-%s-%s.%s", source.shortName, conf.presetIndex, plugin.shortName, ext));
}

struct ProcessMeasurements
{
    string input;
    string output;
    int times;
    bool precise;
    bool preroll;
    int buffer;
    int preset;
    string plugin;
    SysTime pluginTimestamp; // time last modified
    double[int] parameters;

    double minSeconds;
    double[] runSeconds;

    void parse(string xmlPath)
    {
        string content = cast(string)(std.file.read(xmlPath));
        auto doc = new Document();
        doc.parseUtf8(content, true, true);

        parse(doc);
    }

    void parse(Document doc)
    {
        input = doc.getElementsByTagName("input")[0].innerText;
        output = doc.getElementsByTagName("output")[0].innerText;
        times = doc.getElementsByTagName("times")[0].innerText.to!int;
        if (doc.getElementsByTagName("precise").length > 0) precise = true;
        if (doc.getElementsByTagName("preroll").length > 0) preroll = true;
        buffer = doc.getElementsByTagName("buffer")[0].innerText.to!int;
        preset = doc.getElementsByTagName("preset")[0].innerText.to!int;
        plugin = doc.getElementsByTagName("plugin")[0].innerText;
        pluginTimestamp = SysTime.fromISOExtString(doc.getElementsByTagName("plugin_timestamp")[0].innerText);

        foreach(e; doc.getElementsByTagName("param"))
        {
            int parameterIndex = e.getAttribute("index").to!int;
            double parameterValue = e.getAttribute("value").to!double;
            parameters[parameterIndex] = parameterValue;
        }

        minSeconds = doc.getElementsByTagName("min_seconds")[0].innerText.to!double;

        foreach(e; doc.getElementsByTagName("run_seconds"))
        {
            runSeconds ~= e.innerText.to!double;
        }
    }

    size_t taskHash()
    {
        size_t hash = parameters.hashOf;
        hash = pluginTimestamp.hashOf(hash);
        return hash;
    }
}
