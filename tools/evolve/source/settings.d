module settings;

import std.file;
import std.conv;
import std.regex;
import yxml;
import consolecolors;
import utils;

void build(TrainingSettings settings)
{
    version(OSX)
        safeCommand(settings.buildCommandMacOS);
    else
        safeCommand(settings.buildCommandWindows);
}


class TrainingSettings
{
    string buildCommandMacOS = null;
    string buildCommandWindows = null;
    string fitnessCommand = null;

    string[] excludedPackageNames = DEFAULT_IGNORED_PACKAGES;


    //string[] sources;

    bool[string] addedVariableNames;
    int[string] addedVariablePriority;

    string[] addedVariablePatterns;
    int[] patternsPriority;
    Regex!char[] addedVariableRegexp; // syntax is like D's regex patterns, you can add all with ".*"

    bool needToAddVariable(string name, out int priority)
    {
        if ((name in addedVariableNames) !is null)
        {
            priority = addedVariablePriority[name];
            return true;
        }

        // Does is match a pattern?
        foreach(size_t regexpIndex, regexp; addedVariableRegexp)
        {
            auto captures = match(name, regexp);
            if (captures)
            {
                priority = patternsPriority[regexpIndex];
                return true;
            }
        }
        return false;
    }

    void buildRegexes()
    {
        foreach(s;  addedVariablePatterns)
        {
            addedVariableRegexp ~= regex(s);

        }

    }
}

static immutable string[] DEFAULT_IGNORED_PACKAGES =
[
    "intel-intrinsics", "gamut", "wren-port", 
    "dplug:flp", "dplug:window", "dplug:pbr-widgets", "dplug:vst2", "dplug:vst3",
    "dplug:au", "dplug:client", "dplug-aax", "dplug:graphics", "dplug:flat-widgets",
    "dplug:x11", "dplug:wren-support", "dplug:core", "dplug:fft", "dplug:math",
    "dplug:macos", "dplug:gui", "dplug:canvas", "dplug:dsp", "dplug:lv2"
];

TrainingSettings parseTrainingSettings(string xmlPath)
{
    string content = cast(string)(std.file.read(xmlPath));
    XmlDocument doc;
    doc.parse(content);
    if (doc.isError)
        throw new Exception(doc.errorMessage.idup);

    TrainingSettings settings = new TrainingSettings;

    if (doc.root.tagName != "training")
        throw new Exception("expected <training> as root XML anchor");

    foreach(e; doc.root.getChildrenByTagName("exclude-package"))
    {
        settings.excludedPackageNames ~= e.getAttribute("name").idup;
    }

    foreach(e; doc.root.getChildrenByTagName("build-command-windows"))
    {
        settings.buildCommandWindows = e.innerHTML.idup;
    }

    foreach(e; doc.root.getChildrenByTagName("build-command-macos"))
    {
        settings.buildCommandMacOS = e.innerHTML.idup;
    }
    if (settings.buildCommandWindows is null)
        throw new Exception("Need <build-command-windows>");
    if (settings.buildCommandMacOS is null)
        throw new Exception("Need <build-command-macos>");

    foreach(e; doc.root.getChildrenByTagName("fitness-command"))
    {
        settings.fitnessCommand = e.innerHTML.idup;
    }

    if (settings.fitnessCommand is null)
        throw new Exception("Missing <fitness-command>myfitnesscommand.exe</fitness-command>");   


    int priority = 0;

    foreach(e; doc.root.getChildrenByTagName("var"))
    {
        if (e.getAttribute("name"))
        {
            settings.addedVariableNames[e.getAttribute("name").idup] = true;
            settings.addedVariablePriority[e.getAttribute("name").idup] = priority++;
        }
        else if (e.getAttribute("pattern"))
        {
            settings.addedVariablePatterns ~= e.getAttribute("pattern").idup;
            settings.patternsPriority ~= priority++;
        }
        else
            throw new Exception(`<var> must have "name" or "pattern" attribute.`);
    }

    settings.buildRegexes();
    return settings;
}


