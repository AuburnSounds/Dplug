module utils;

import std.process;
import std.format;
import std.array;
import consolecolors;


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


void safeCommand(string cmd)
{
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