module main;

import std;
import utils;
import consolecolors;

void usage()
{
    void flag(string arg, string desc, string possibleValues, string defaultDesc)
    {
        string argStr = format("  %s", arg);
        cwrite(argStr.lcyan);
        for(size_t i = argStr.length; i < 19; ++i)
            write(" ");
        cwritefln("%s", desc);
        if (possibleValues)
            cwritefln("                   Accepts: ".grey ~ "%s".yellow, possibleValues);
        if (defaultDesc)
            cwritefln("                   Default: ".grey ~ "%s", defaultDesc.orange);
   //     cwriteln;
    }

    cwriteln();
    cwriteln( "This is the <strong><lcyan>all-plugins</lcyan></strong> tool: run a command inside several sub-directories.🔧");
    cwriteln("The subdirectory is read from plugin-list.json");
    cwriteln();
    cwriteln( "Usage: <lcyan>all-plugins -- &lt;command&gt;</>");
    cwriteln();
    cwriteln("────────── <on_blue> FLAGS </> ────────── 😸🚩".white);
    cwriteln();
    flag("--", "Command start after that flag", null, null);
    flag("-h --help", "Show this help", null, null);
    flag("--pause", "Press enter between each action", null, null);
    cwriteln();
}

int main(string[] args)
{
    try
    {
        enableConsoleUTF8();       
        string[] command = null;
        bool help;

        // Expand macro arguments
        for (int i = 1; i < args.length; )
        {
            string arg = args[i];
            if (arg == "--help" || arg == "-h")
            {
                help = true;
            }
            else if (arg == "--")
            {
                command = args[i+1 .. $];
                break;
            }
            else
                throw new Exception(format("unknown argumen %s, did you forgot --", arg));
            ++i;
        }

        if (help)
        {
            usage();
            return 0;
        }

        if (command.length == 0)
        {
            throw new Exception("No command given, see --help");
        }

        // read list of plugins
        JSONValue configFile = parseJSON(cast(string)(std.file.read("all-plugins.json")));

        JSONValue[] jsonProjects = configFile["projects"].array;
        string[] projects;
        foreach(p; jsonProjects)
            projects ~= p.str;
        
        auto cwd = getcwd();
        scope(exit) cwd.chdir;

        foreach(project; projects)
        {
            auto path = cwd.buildPath(project);

            cwritefln("# Moving to sub-directory %s/".lmagenta, project);
            path.chdir;
            safeCommand( command.join(" ") );
            cwritefln("# End sub-directory %s/".lmagenta, project);
            cwd.chdir;
        }
        return 0;
    }    
    catch(CCLException e)
    {
        cwritefln("error: %s", e.msg);
        return 1;
    }
    catch(Exception e)
    {
        cwritefln("error: %s", escapeCCL(e.msg));
        return 1;
    }
}
