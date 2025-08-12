module parseproject;

import std.json;
import std.regex;
import std.stdio;
import std.string;
import std.process;
import std.algorithm.sorting;
import std.json;
import std.path;
import std.range;
import std.file;
import consolecolors;
import std.algorithm;
import settings;
import var;


class Project
{
    Package[string] packages;

    string[] getAllSourceFiles()
    {
        string[] r;
        foreach(pack; packages)
            r ~= pack.getAllSourceFiles();
        return r;
    }

    // Total number of variables.
    int numVariables()
    {
        int r = 0;
        foreach(pack; packages)
            r += pack.numVariables;
        return r;
    }

    // Total number of effectively modifable variables.
    int numTunableVariables()
    {
        int r = 0;
        foreach(pack; packages)
            r += pack.numTunableVariables;
        return r;
    }

    void pruneWithSettings(TrainingSettings settings)
    {
        foreach(excludedName; settings.excludedPackageNames)
        {
            packages.remove(excludedName);
        }
    }

    Variable[] getVariablesThatMatch(TrainingSettings settings)
    {
        Variable[] r;
         foreach(pack; packages)
         {
             foreach(source; pack.sourceFiles)
             {
                foreach(variable; source.variables)
                {
                    int priority;
                    if (settings.needToAddVariable(variable.name, priority))
                    {
                        if (!variable.tunable)
                            throw new Exception(format("No support for that variable declaration, see --list-vars to see why it's not properly parsed", variable.name));

                        if (variable.type == Variable.Type.i32)
                            throw new Exception("Can't evolve int variables");

                        // take priority from XML rules
                        variable.priority = priority;
                        r ~= variable;
                    }
                }
             }
         }

         // Sort the variables by priority
         sort!("a.priority < b.priority")(r);

         return r;
    }
}

class Package
{
    string name;
    SourceFile[] sourceFiles;

    bool alreadyFirstParsed = false;

    this(string name)
    {
        this.name = name;
    }

    void parse(bool listVars)
    {
        if (alreadyFirstParsed)
            return;

        cwritef("    <lgreen>Searching</lgreen> package <lcyan>%12s</lcyan>", name);
        if (listVars)
            cwriteln;
        alreadyFirstParsed = true;

        int found = 0;
        int tunable = 0;
        int ignored = 0;
        int errors = 0;
        foreach(source; sourceFiles)
        {
            source.parse(listVars);
            found   += source.numVariables;
            ignored += source.numIgnoredVariables;
            tunable += source.numTunableVariables;
        }
        errors = found - tunable - ignored;
        if (found > 0)
        {
            cwritefln(" =&gt; <white>%3s</white> vars found: <lgreen>%3s</lgreen> tunable, <grey>%3s</grey> ignored, <lred>%3s</lred> errors <grey>(--list-vars to check)</>",
                      found, tunable, ignored, errors);
        }
        else
        {
            cwritefln(" =&gt; <white>  0</white> vars found. <grey>(&lt;exclude-package name=\"%s\" /&gt; to skip)</>", name);
        }
    }

    string[] getAllSourceFiles()
    {
        string[] r;
        foreach(source; sourceFiles)
            r ~= source.path;
        return r;
    }

    // Total number of variables.
    int numVariables()
    {
        parse(false);
        int r = 0;
        foreach(source; sourceFiles)
            r += source.numVariables;
        return r;
    }

    // Total number of effectively modifable variables.
    int numTunableVariables()
    {
        parse(false);
        int r = 0;
        foreach(source; sourceFiles)
            r += source.numTunableVariables;
        return r;
    }
}

class SourceFile
{
    string path;
    string originalFileContent;
    this(string path)
    {
        this.path = path;
    }

    Variable[] variables;

    bool alreadyFirstParsed = false;

    // Variable are either:
    // - tunable
    // - ignored (with UDAs)
    // - or not tunable (error parsing)
    int numTunableVars = 0;
    int numIgnoredVars = 0;

    int numTunableVariables()
    {
        parse(false);
        return numTunableVars;
    }

    int numIgnoredVariables()
    {
        parse(false);
        return numIgnoredVars;
    }

    /// num errors = numVariables - numIgnoredVariables - numTunableVariables
    int numVariables()
    {
        parse(false);
        return cast(int)variables.length;
    }

    void parse(bool listVars)
    {
        if (alreadyFirstParsed)
            return;
        alreadyFirstParsed = true;
        originalFileContent = cast(string)(std.file.read(path));

        // find all lines that contains with "@tuning"
        auto allTuningDecl = regex(r"^.*@tuning.*$","m");

        // count occurence of @tuning
        auto captures = matchAll(originalFileContent, allTuningDecl);
        foreach(c; captures)
        {
            Variable v = new Variable(path, c.hit);
            if (v.ignored)
            {
                numIgnoredVars += 1;
            }
            else if (v.tunable) 
            {
                numTunableVars += 1;
            }
            variables ~= v;
            if (listVars)
                v.display();
        }
    }
}



Project parseDubDescription()
{
    Project project = new Project;

    auto dubResult = execute(["dub", "describe"]);

    if (dubResult.status != 0)
        throw new Exception(format("dub returned %s", dubResult.status));

    JSONValue description = parseJSON(dubResult.output);

    foreach (pack; description["packages"].array())
    {
        string absPath = pack["path"].str;
        string packName = pack["name"].str;

        Package p = new Package(packName);

        foreach (file; pack["files"].array())
        {
            string filepath = file["path"].str();

            // only add .d files
            if (filepath.endsWith(".d") || filepath.endsWith(".di") || filepath.endsWith(".json") || filepath.endsWith(".res"))
            {
                p.sourceFiles ~= new SourceFile( buildPath(absPath, filepath) );
            }
        }
        project.packages[packName] = p;
    }
    return project;
}



