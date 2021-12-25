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
import arch;


// Use case: 
// - compare algorithm
// - batch processing
// - speed measurements
// - non-regressions


void usage()
{
    void flag(string arg, string desc, string possibleValues, string defaultDesc)
    {
        string argStr = format("        %s", arg);
        cwrite(argStr.cyan);
        for(size_t i = argStr.length; i < 24; ++i)
            write(" ");
        cwritefln("%s".white, desc);
        if (possibleValues)
            cwritefln("                        Possible values: ".grey ~ "%s".yellow, possibleValues);
        if (defaultDesc)
            cwritefln("                        Default: ".grey ~ "%s".cyan, defaultDesc);
        cwriteln;
    }

    cwriteln;
    cwriteln("This is " ~ "bench".yellow ~ ", the Dplug benchmark tool.");
    cwriteln("It analyzes processing results, using a matrix of plug-ins, configurations and sources.");
    cwriteln();
    cwriteln("FLAGS".white);
    cwriteln();
    flag("-f --force", "Update cache of processed files.", null, "no");
    flag("-t --times", "Number of samples for speed measures.", null, "30");
    flag("-h --help",  "Shows this help.", null, null);

    cwriteln();
    cwriteln("NOTES".white);
    cwriteln();
    cwriteln("      bench".yellow ~ " expects a " ~ "bench.xml".cyan ~ " file in the directory it is launched.");
    cwriteln();

    cwriteln();
    cwriteln("EXAMPLE");
    cwriteln();
    cwriteln(`    -------------------------------------- bench.xml ---------------------------------------`.cyan);
    cwriteln();
    cwriteln(`    <?xml version="1.0" encoding="UTF-8"?>`.green);
    cwriteln(`    <bench>`.green);
    cwriteln();
    cwriteln(`      <!-- This will compare challenger.dll to baseline.dll over presets 0 to 20,`.magenta);
    cwriteln(`           and display the speed-up and audio RMS differences.                           -->`.magenta);
    cwriteln();    
    cwriteln(`      <baseline>baseline.dll</baseline>`.green ~ `        <!-- path to baseline VST2.4 executable   -->`.magenta);
    cwriteln(`      <challenger>challenger.dll</challenger>`.green ~ `  <!-- path to challenger VST2.4 executable -->`.magenta);
    cwriteln(`      <preset-range min="0" max="20"/>`.green ~ `         <!-- range of VST2.4 presets to check     -->`.magenta);
    cwriteln(`      <source>mysource.wav</source>`.green ~ `            <!-- add a source to the test             -->`.magenta);
    cwriteln(`      <quality-compare/>`.green ~ `                       <!-- perform quality comparison           -->`.magenta);
    cwriteln(`      <speed-measure/>`.green ~ `                         <!-- perform speed comparison             -->`.magenta);
    cwriteln(`      <times>20</times>`.green ~ `                        <!-- specify number of speed samples      -->`.magenta);
    cwriteln(`    </bench>`.green);
    cwriteln();
    cwriteln(`    ----------------------------------------------------------------------------------------`.cyan);
    cwriteln();
    cwriteln();
}

enum string configFile = "bench.xml";

int main(string[] args)
{
    try
    {
        bool help;
        bool forceEncode;  
        bool timesProvided = false;
        int times;

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

        auto universe = new Universe(forceEncode);
        universe.parseTask(configFile);
        if (timesProvided)
            universe.speedMeasureCount = times; // cmdline overrides XML for sample count
        universe.executeAllTasks();
        return 0;
    }
    catch(Exception e)
    {
        import std.stdio;
        cwritefln("error: %s".red, e.msg);
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

    this(string pluginPath, int cacheIDInt)
    {
        this.pluginPath = pluginPath;
        enforce(exists(pluginPath), format("Can't find plugin file '%s'", pluginPath));
        pluginTimestamp = pluginPath.timeLastModified;
        this.shortName = pluginPath.baseName.stripExtension;
        this.arch = detectArch(pluginPath);
        this.cacheID = "#" ~ to!string(cacheIDInt);
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
            cwritef("  %s vs %s = %.4fs vs %.4fs => ".grey, challenger.shortName, universe.baseline, 
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
    int speedMeasureCount = 30; // default

    string xmlDir;
    string sourceDirectory = "p:/Samples";
    string outputDir = "bench";

    auto allPlugins()
    {
        return chain(only(baseline), challengers);
    }

    this(bool forceEncode)
    {
        this.forceEncode = forceEncode;
    }

    void parseTask(string xmlPath)
    {
        xmlDir = xmlPath.dirName;

        string content = cast(string)(std.file.read(xmlPath));
        auto doc = new Document();
        doc.parseUtf8(content, true, true);

        parseBaseline(doc);
        parseChallengers(doc);
        parsePresets(doc);
        parseSources(doc);
        parseProcessors(doc);
    }

    Plugin parsePlugin(Element pluginTag, int cacheID)
    {
        string pluginPath = pluginTag.innerText.strip;
        
        auto plugin = new Plugin(pluginPath, cacheID);
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
            throw new Exception("baseline must be provided");
        if (elems.length > 1)
            throw new Exception(format("Only single baseline must be provided, not %s", elems.length));

        baseline = parsePlugin(elems[0], 0); // baseline has cacheID 0

    }

    void parseChallengers(Document doc)
    {
        int cacheID = 1;
        foreach(e; doc.getElementsByTagName("challenger"))
        {
            auto plugin = parsePlugin(e, cacheID); // challengers have cacheID > 1
            challengers ~= plugin;
            cacheID++;
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
            string sourcePath = e.innerText.strip;

            if (!exists(sourcePath))
                throw new Exception(format("source '%s' doesn't exist.", sourcePath));

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

        if (doc.getElementsByTagName("times").length > 0)
        {
            speedMeasureCount = doc.getElementsByTagName("times")[0].innerText.to!int;
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
        string exeProcess = processExecutablePathForThisArch(plugin.arch);
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
    return buildPath(source.outputDirectory, format("%s-%s-%s.%s", source.shortName, conf.presetIndex, plugin.cacheID, ext));
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
