module utils;

import std.process;
import std.string;
import std.file;
import std.path;
import std.datetime;

import commonmarkd;
import colorize;

bool enableColoredOutput = true;

string white(string s) @property
{
    if (enableColoredOutput) return s.color(fg.light_white);
    return s;
}

string grey(string s) @property
{
    if (enableColoredOutput) return s.color(fg.white);
    return s;
}

string cyan(string s) @property
{
    if (enableColoredOutput) return s.color(fg.light_cyan);
    return s;
}

string green(string s) @property
{
    if (enableColoredOutput) return s.color(fg.light_green);
    return s;
}

string yellow(string s) @property
{
    if (enableColoredOutput) return s.color(fg.light_yellow);
    return s;
}

string red(string s) @property
{
    if (enableColoredOutput) return s.color(fg.light_red);
    return s;
}

void info(string msg)
{
    cwritefln("info: %s".white, msg);
}

void warning(string msg)
{
    cwritefln("warning: %s".yellow, msg);
}

void error(string msg)
{
    cwritefln("error: %s".red, msg);
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

string convertMarkdownFileToHTML(string markdownFile)
{
    string res = `<!DOCTYPE html><html><head><title></title><meta charset="utf-8"></head><body>`
    ~ convertMarkdownToHTML(markdownFile,  MarkdownFlag.dialectCommonMark | MarkdownFlag.permissiveAutoLinks)
    ~ `</body></html>`;
    return res;
}

void safeCommand(string cmd)
{
    cwritefln("$ %s".cyan, cmd);
    auto pid = spawnShell(cmd);
    auto errorCode = wait(pid);
    //cwritefln(" => returned error code %s", errorCode);
    if (errorCode != 0)
        throw new ExternalProgramErrored(errorCode, format("Command '%s' returned %s", cmd, errorCode));
}

int unsafeCommand(string cmd)
{
    cwritefln("$ %s".cyan, cmd);
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

/// Recursive directory copy.
/// https://forum.dlang.org/post/n7hc17$19jg$1@digitalmars.com
/// Returns: number of copied files
int copyRecurse(string from, string to, bool verbose)
{
  //  from = absolutePath(from);
  //  to = absolutePath(to);

    if (isDir(from))
    {
        if (verbose) cwritefln("    => Create directory %s".green, to);
        mkdirRecurse(to);

        auto entries = dirEntries(from, SpanMode.shallow);
        int result = 0;
        foreach (entry; entries)
        {
            auto dst = buildPath(to, entry.name[from.length + 1 .. $]);
            result += copyRecurse(entry.name, dst, verbose);
        }
        return result;
    }
    else
    {
        if (verbose) cwritefln("    => Copy %s to %s".green, from, to);
        std.file.copy(from, to);
        return 1;
    }
}

int currentYear()
{
    SysTime time = Clock.currTime(UTC());
    return time.year;
}