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
import consolecolors;
import yxml;
import arch;

// Use case: 
// - compare algorithm
// - batch processing
// - speed measurements
// - non-regressions

// TODO document bufferPattern
// TODO document parameter

void usage()
{
    void flag(string arg, string desc, string possibleValues, string defaultDesc)
    {
        string argStr = format("        %s", arg);
        cwrite(argStr.lcyan);
        for(size_t i = argStr.length; i < 24; ++i)
            write(" ");
        cwritefln("%s".white, desc);
        if (possibleValues)
            cwritefln("                        Possible values: ".grey ~ "%s".yellow, possibleValues);
        if (defaultDesc)
            cwritefln("                        Default: ".grey ~ "%s".lcyan, defaultDesc);
        cwriteln;
    }

    cwriteln;
    cwriteln("This is " ~ "bench".yellow ~ ", the Dplug benchmark tool.");
    cwriteln("It analyzes processing results, using a matrix of plug-ins, configurations and sources.");
    cwriteln();
    cwriteln("FLAGS".white);
    cwriteln();
    flag("-t --times", "Number of samples for speed measures.", null, "30");
    flag("-h --help",  "Shows this help.", null, null);
    flag("-v --verbose",  "Tools are called with verbose output.", null, null);

    cwriteln();
    cwriteln("NOTES".white);
    cwriteln();
    cwriteln("      bench".yellow ~ " expects a " ~ "bench.xml".lcyan ~ " file in the directory it is launched.");
    cwriteln();

    cwriteln();
    cwriteln("EXAMPLE");
    cwriteln();
    cwriteln(`    -------------------------------------- bench.xml ---------------------------------------`.lcyan);
    cwriteln();
    cwriteln(`    &lt;?xml version="1.0" encoding="UTF-8"?&gt;`.lgreen);
    cwriteln(`    &lt;bench&gt;`.lgreen);
    cwriteln();
    cwriteln(`      &lt;!-- This will compare challenger.dll to baseline.dll over presets 0 to 20,`.lmagenta);
    cwriteln(`           and display the speed-up and audio RMS differences.                           --&gt;`.lmagenta);
    cwriteln();    
    cwriteln(`      &lt;baseline&gt;baseline.dll&lt;/baseline&gt;`.lgreen ~ `        &lt;!-- path to baseline VST2 executable     --&gt;`.lmagenta);
    cwriteln(`      &lt;challenger&gt;challenger.dll&lt;/challenger&gt;`.lgreen ~ `  &lt;!-- path to challenger VST2 executable   --&gt;`.lmagenta);
    cwriteln(`      &lt;preset-range min="0" max="20"/&gt;`.lgreen ~ `         &lt;!-- range of VST2 presets to check       --&gt;`.lmagenta);
    cwriteln(`      &lt;source&gt;mysource.wav&lt;/source&gt;`.lgreen ~ `            &lt;!-- add a source to the test             --&gt;`.lmagenta);
    cwriteln(`      &lt;quality-compare/&gt;`.lgreen ~ `                       &lt;!-- perform quality comparison           --&gt;`.lmagenta);
    cwriteln(`      &lt;speed-measure/&gt;`.lgreen ~ `                         &lt;!-- perform speed comparison             --&gt;`.lmagenta);
    cwriteln(`      &lt;times&gt;20&lt;/times&gt;`.lgreen ~ `                        &lt;!-- specify number of speed samples      --&gt;`.lmagenta);
    cwriteln(`    &lt;/bench&gt;`.lgreen);
    cwriteln();
    cwriteln(`    ----------------------------------------------------------------------------------------`.lcyan);
    cwriteln();
    cwriteln();
}

enum string configFile = "bench.xml";

int main(string[] args)
{
    try
    {
        bool help = false;
        bool verbose = false;
        bool timesProvided = false;
        int times;

        for(int i = 1; i < args.length; ++i)
        {
            string arg = args[i];

            if (arg == "-h" || arg == "--help")
            {
                help = true;
            }
            else if (arg == "-v" || arg == "--verbose")
            {
                verbose = true;
            }
            else if (arg == "-t" || arg == "--times")
            {
                timesProvided = true;
                ++i;
                times = to!int(args[i]);
            }
            else
            {
                throw new Exception(format("unexpected argument '%s'", arg));
            }
        }

        if (!configFile.exists())
        {
            error(format("missing file %s", configFile));
            usage();
            return 1;
        }

        if (help)
        {
            usage();
            return 0;
        }

        auto universe = new Universe(verbose);
        universe.parseTask(configFile);
        if (timesProvided)
            universe.speedMeasureCount = times; // cmdline overrides XML for sample count
        universe.executeAllTasks();
        return 0;
    }
    catch(Exception e)
    {
        import std.stdio;
        cwritefln("error: %s".lred, e.msg);
        return 1;
    }
}

class Plugin
{
    string pluginPath;
    string shortName;
    SysTime pluginTimestamp;
    double[int] parameterValues;
    string bufferPattern; // null for default
    ProcessMeasurements lastMeasurements;

    Arch arch;  


    string cacheID; // string used for unique ID in encoded wav files

    void toString(scope void delegate(const(char)[]) sink)
    {
        sink(shortName);

        sink("(");
        sink(archName(arch));
        sink(")");

        foreach (int paramIndex, double paramvalue; parameterValues)
            formattedWrite(sink, " %s=%s", paramIndex, paramvalue);
    }

    this(const(char)[] pluginPath, int cacheIDInt)
    {
        this.pluginPath = pluginPath.idup;
        enforce(exists(pluginPath), format("Can't find plugin file '%s'", pluginPath));
        pluginTimestamp = pluginPath.timeLastModified;
        this.shortName = pluginPath.baseName.stripExtension.idup;
        this.arch = detectArch(pluginPath);
        this.cacheID = "#" ~ to!string(cacheIDInt);
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

    this(const(char)[] wavPath, const(char)[] outputDirectory)
    {
        this.wavPath = wavPath.idup;
        this.shortName = wavPath.baseName.stripExtension.idup;
        this.outputDirectory = outputDirectory.idup;
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
            cwritef("  %s vs %s = %.4fs vs %.4fs =&gt; ".grey, challenger.shortName, universe.baseline, 
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
            string msg = "=&gt; Global speed-up for %s = " ~ "%+.2s%%";
            msg = (globalSpeedUp > 2) ? msg.lgreen : ((globalSpeedUp < -2) ? msg.lred : msg.yellow);
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
    bool verbose;

    int speedMeasureCount = 30; // default

    string xmlDir;
    string outputDir = "bench";

    auto allPlugins()
    {
        return chain(only(baseline), challengers);
    }

    this(bool verbose)
    {
        this.verbose = verbose;
    }

    void parseTask(string xmlPath)
    {
        xmlDir = xmlPath.dirName;

        string content = cast(string)(std.file.read(xmlPath));
        XmlDocument doc;
        doc.parse(content);

        parseBaseline(doc.root);
        parseChallengers(doc.root);
        parsePresets(doc.root);
        parseSources(doc.root);
        parseProcessors(doc.root);
    }

    Plugin parsePlugin(XmlElement pluginTag, int cacheID)
    {
        const(char)[] pluginPath = pluginTag.textContent.strip;

        auto plugin = new Plugin(pluginPath, cacheID);
        foreach(e; pluginTag.getChildrenByTagName("buffer-size"))
        {
            plugin.bufferPattern = e.getAttribute("pattern").idup; // null means default, process will choose one for you
        }

        foreach(e; pluginTag.getChildrenByTagName("parameter"))
        {
            const(char)[] parameterIndexStr = e.getAttribute("index");
            if (parameterIndexStr is null)
                throw new Exception(`parameter node must have 'index' attribute set (example: index="0")`);
            int parameterIndex = to!int(parameterIndexStr);
            const(char)[] parameterValueStr = e.getAttribute("value");
            if (parameterValueStr is null)
                throw new Exception(`parameter node must have 'value' attribute set (example: value="0.5")`);
            double parameterValue = to!double(parameterValueStr);

            plugin.parameterValues[parameterIndex] = parameterValue;
        }
        return plugin;
    }

    void parseBaseline(XmlElement doc)
    {
        auto elems = doc.getChildrenByTagName("baseline").array;
        if (elems.length == 0)
            throw new Exception("baseline must be provided");
        if (elems.length > 1)
            throw new Exception(format("Only single baseline must be provided, not %s", elems.length));

        baseline = parsePlugin(elems[0], 0); // baseline has cacheID 0

    }

    void parseChallengers(XmlElement doc)
    {
        int cacheID = 1;
        foreach(e; doc.getChildrenByTagName("challenger"))
        {
            auto plugin = parsePlugin(e, cacheID); // challengers have cacheID > 1
            challengers ~= plugin;
            cacheID++;
        }
    }

    void parsePresets(XmlElement doc)
    {
        foreach(e; doc.getChildrenByTagName("preset"))
        {
            const(char)[] presetS = e.textContent;
            string s = presetS[1..$].idup;
            int presetIndex = to!int(presetS);
            configurations ~= new TaskConfiguration(presetIndex);
        }

        foreach(e; doc.getChildrenByTagName("preset-range"))
        {
            const(char)[] attr = e.getAttribute("min");
            int min = attr.to!int;
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

    void parseSources(XmlElement doc)
    {
        foreach(e; doc.getChildrenByTagName("source"))
        {
            const(char)[] sourcePath = e.textContent.strip;

            if (!exists(sourcePath))
                throw new Exception(format("source '%s' doesn't exist.", sourcePath));

            sources ~= new Source(sourcePath, outputDir);
        }
    }

    void parseProcessors(XmlElement doc)
    {
        if (doc.hasChildWithTagName("quality-compare"))
        {
            processors ~= new QualityCompareProcessor();
        }
        
        if (doc.hasChildWithTagName("speed-measure"))
        {
            processors ~= new SpeedMeasureProcessor();
        }        

        if (doc.hasChildWithTagName("times"))
        {
            const(char)[] stimes =  doc.firstChildByTagName("times").textContent;
            speedMeasureCount = stimes.to!int;
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
         // Caching was mostly useless, so it's not lazy anymore.
        string outputFile = pathForEncode(plugin, conf, source, "wav");
        string xmlFile = pathForEncode(plugin, conf, source, "xml");
        encode(plugin, conf, source, outputFile, xmlFile);
        plugin.lastMeasurements.parse(xmlFile);
    }

    void encode(Plugin plugin, TaskConfiguration conf, Source source, string outputFile, string xmlPath)
    {
        int times = speedMeasureCount;
        mkdirRecurse(dirName(outputFile));
        string exeProcess = processExecutablePathForThisArch(plugin.arch);
        string parameterValues;
        const(char)[] bufferPattern = (plugin.bufferPattern is null) ? "" : (" -buffer " ~ plugin.bufferPattern);
        string verboseStr = verbose ? " -vverbose" : "";
        foreach (int paramIndex, double paramvalue; plugin.parameterValues)
        {
            parameterValues ~= format(" -param %s %s", paramIndex, paramvalue);
        }
        string cmd = format(`%s -precise -t %s -i "%s" -o "%s" -preset %s%s -output-xml "%s" "%s"%s%s`, 
                            exeProcess, times, source.wavPath, outputFile, conf.presetIndex, parameterValues, xmlPath, plugin.pluginPath,
                            bufferPattern, verboseStr);
        safeCommand(cmd);
    }
}



string pathForEncode(Plugin plugin, TaskConfiguration conf, Source source, string ext)
{
    return buildPath(source.outputDirectory, format("%s-%s-%s.%s", source.shortName, conf.presetIndex, plugin.cacheID, ext));
}

struct ProcessMeasurements
{
    string input;
    string output;
    int times;
    bool precise;
    bool preroll;
    string bufferPattern;
    int preset;
    string plugin;
    SysTime pluginTimestamp; // time last modified
    double[int] parameters;

    double minSeconds;
    double[] runSeconds;

    void parse(string xmlPath)
    {
        string content = cast(string)(std.file.read(xmlPath));
        XmlDocument doc;
        doc.parse(content);

        parse(doc.root);
    }

    void parse(XmlElement doc)
    {
        XmlElement paramNode = doc.firstChildByTagName("parameters");

        input = paramNode.firstChildByTagName("input").textContent.idup;
        output = paramNode.firstChildByTagName("output").textContent.idup;
        times = paramNode.firstChildByTagName("times").textContent.to!int;
        if (paramNode.hasChildWithTagName("precise")) precise = true;
        if (paramNode.hasChildWithTagName("preroll")) preroll = true;
        bufferPattern = paramNode.firstChildByTagName("buffer").textContent.idup;
        preset = paramNode.firstChildByTagName("preset").textContent.to!int;
        plugin = paramNode.firstChildByTagName("plugin").textContent.idup;
        pluginTimestamp = SysTime.fromISOExtString(paramNode.firstChildByTagName("plugin_timestamp").textContent);

        foreach(e; paramNode.getChildrenByTagName("param"))
        {
            int parameterIndex = e.getAttribute("index").to!int;
            double parameterValue = e.getAttribute("value").to!double;
            parameters[parameterIndex] = parameterValue;
        }

        minSeconds = doc.firstChildByTagName("min_seconds").textContent.to!double;

        foreach(e; doc.getChildrenByTagName("run_seconds"))
        {
            runSeconds ~= e.textContent.to!double;
        }
    }

    size_t taskHash()
    {
        size_t hash = parameters.hashOf;
        hash = pluginTimestamp.hashOf(hash);
        return hash;
    }
}
