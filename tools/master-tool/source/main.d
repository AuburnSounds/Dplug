import std.process;
import std.string;
import std.stdio;
import consolecolors;

void usage()
{
    void flag(string arg, string desc, string possibleValues, string defaultDesc)
    {
        string argStr = format("        %s", arg);
        cwrite(argStr.lcyan);
        for(size_t i = argStr.length; i < 24; ++i)
            write(" ");
        cwritefln("%s", desc);
        if (possibleValues)
            cwritefln("                        Possible values: ".grey ~ "%s".yellow, possibleValues);
        if (defaultDesc)
            cwritefln("                        Default: ".grey ~ "%s".lcyan, defaultDesc);
    }

    void command(string name, string desc)
    {
        string argStr = format("        %s", name);
        cwrite(argStr.yellow);
        for(size_t i = argStr.length; i < 24; ++i)
            write(" ");
        cwritefln("%s", desc);
    }

    cwriteln();
    cwriteln( "This is the " ~ "dplug".lcyan ~ " master tool: it calls other dplug tools from DUB registry,");
    cwriteln( "so you don't have to build them.");
    cwriteln();
    cwriteln("AVAILABLE COMMANDS");
    cwriteln();
    command("build", "Build an audio plug-in");
    command("process", "Process a .wav file or silence with a VST2 audio plug-in");
    command("bench", "Benchmark several plug-ins against each other");
    command("abtest", "Perform an A/B comparison between two sound files");
    command("wav-compare", "Compare two .wav files");
    cwriteln();
    cwriteln("FLAGS");
    cwriteln();
    flag("-h --help", "Shows this help", null, null);
    flag("-v --verbose", "Shows details of command line sent to other tools", null, null);
    cwriteln();
    cwriteln("EXAMPLES");
    cwriteln();
    cwriteln("        dplug build --help".lcyan ~  "      # Calls dplug-build tool, display its help".lgreen);
    cwriteln("        dplug --help".lcyan ~  "            # Display 'dplug' master tool's own --help".lgreen);
    cwriteln("        dplug --verbose build".lcyan ~  "   # 'dplug' master tool is verbose, but not dplug-build".lgreen);
    cwriteln();
}

int main(string[] args)
{
    bool help = false;
    bool verbose = false;
    string command = null;

    try
    {     
        // No arguments, pass it all to --help
        if (args.length == 1)
            help = true;
        else
        {
            // removes first arg
            args = args[1..$];

            // pull --help and --verbose arguments, if any
            for (size_t n = 0; n < args.length; ++n)
            {
                string arg = args[n];
                if (arg == "-h" || arg == "--help")
                    help = true;
                else if (arg == "-v" || arg == "--verbose")
                    verbose = true;
                else 
                {
                    // removes excess arguments
                    args = args[n..$];
                    break;
                }
            }

            // If something remain, call a command
            if (args.length > 0)
            {
                // Check first argument, it is --help?
                command = args[0];

                // Argument beyond the first are escaped
                string rest = "";
                for (size_t n = 1; n < args.length; ++n)
                {
                    if (n > 1)
                        rest ~= " ";
                    rest ~= escapeShellArgument(args[n]);
                }

                string dubRun = "dub run";
                if (!verbose) dubRun ~= " -q";

                if (command == "-h" || command == "--help")
                    help = true;
                else if (command == "build")
                {
                    safeCommand(dubRun ~ " dplug:dplug-build -- " ~ rest, verbose);
                }
                else if (command == "process")
                {
                    safeCommand(dubRun ~ " dplug:process -- " ~ rest, verbose);
                }
                else if (command == "bench")
                {
                    safeCommand(dubRun ~ " dplug:bench -- " ~ rest, verbose);
                }
                else if (command == "abtest") // process
                {
                    safeCommand(dubRun ~ " dplug:abtest -- " ~ rest, verbose);
                }
                else if (command == "wav-compare") // process
                {
                    safeCommand(dubRun ~ " dplug:wav-compare -- " ~ rest, verbose);
                }
                else
                {
                    throw new CCLException(format(`'%s' is not a dplug command. See 'dplug --help'.`, escapeCCL(command).yellow));
                }
            }
        }

        // --verbose, but no command given, strange
        if (verbose && (command is null))
            help = true;

        if (help)
        {
            usage();
            return 0;
        }

        return 0;
    }
    catch(ExternalProgramErrored e)
    {
        // To blur the distinction between dplug tool and subcommands, do not display the error code.
        if (verbose) error(escapeCCL(e.msg));
        return e.errorCode;
    }
    catch(CCLException e) // An exception with a coloured message
    {
        cwritefln("\n<lred>Error:</lred> %s", e.msg);
        return -1;
    }
    catch(Exception e) // An uncoloured exception.
    {
        cwritefln("\n<lred>Error:</lred> %s", escapeCCL(e.msg));
        return -1;
    }
}

void info(const(char)[] msg)
{
    cwritefln("info: %s",escapeCCL(msg));
}

void warning(const(char)[] msg)
{
    cwritefln("warning: %s".yellow, escapeCCL(msg));
}

void error(const(char)[] msg)
{
    cwritefln("Error: %s".lred, escapeCCL(msg));
}

class ExternalProgramErrored : Exception
{
    public
    {
        @safe pure nothrow this(int errorCode,
                                string message,
                                string file =__FILE__,
                                size_t line = __LINE__,
                                Throwable next = null)
        {
            super(message, file, line, next);
            this.errorCode = errorCode;
        }

        int errorCode;
    }
}

void safeCommand(string cmd, bool verbose)
{
    if (verbose) 
        cwritefln("$ %s".lcyan, escapeCCL(cmd));
    auto pid = spawnShell(cmd);
    auto errorCode = wait(pid);
    //cwritefln(" =&gt; returned error code %s", errorCode);
    if (errorCode != 0)
        throw new ExternalProgramErrored(errorCode, format("Command '%s' returned %s", cmd, errorCode));
}

int unsafeCommand(string cmd)
{
    cwritefln("$ %s".lcyan, escapeCCL(cmd));
    auto pid = spawnShell(cmd);
    auto errorCode = wait(pid);
    return errorCode;
}

string escapeXMLString(string s)
{
    s = s.replace("&", "&amp;");
    s = s.replace("<", "&lt;");
    s = s.replace(">", "&gt;");
    s = s.replace("\"", "&quot;");
    s = s.replace("\'", "&apos;");
    return s;
}

// Currently this only escapes spaces...
string escapeShellArgument(string arg)
{
    version(Windows)
    {
        return `"` ~ arg ~ `"`;
    }
    else
        return arg.replace(" ", "\\ ");
}
