module utils;
import std.process;
import std.string;
import std.file;
import std.path;
import std.datetime;
import std.ascii;
import std.functional : not;
import std.exception;
import std.algorithm.searching;
import std.process;

import consolecolors;

import commonmarkd;

void info(const(char)[] msg)
{
    cwritefln("info: %s".white,escapeCCL(msg));
}

void warning(const(char)[] msg)
{
    cwritefln("warning: %s".yellow, escapeCCL(msg));
}

void error(const(char)[] msg)
{
    cwritefln("error: %s".lred, escapeCCL(msg));
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
    cwritefln("$ %s".lcyan, cmd);
    auto pid = spawnShell(cmd);
    auto errorCode = wait(pid);
    //cwritefln(" => returned error code %s", errorCode);
    if (errorCode != 0)
        throw new ExternalProgramErrored(errorCode, format("Command '%s' returned %s", cmd, errorCode));
}

int unsafeCommand(string cmd)
{
    cwritefln("$ %s".lcyan, cmd);
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
        if (verbose) cwritefln("    => Create directory %s".lgreen, to);
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
        if (verbose) cwritefln("    => Copy %s to %s".lgreen, from, to);
        std.file.copy(from, to);
        return 1;
    }
}

int currentYear()
{
    SysTime time = Clock.currTime(UTC());
    return time.year;
}


string expandDplugVariables(string input)
{
    static string expandEnvVar(string name) 
    { 
        string envvar = environment.get(name);
        if (envvar is null)
        {
            throw new Exception(format("Unknown variable $%s.", name));
        }
        else
            return envvar;
    }
    return expandVars!expandEnvVar(input);
}





/**
Copyright: © 2012-2013 Matthias Dondorff, 2012-2016 Sönke Ludwig
Authors: Matthias Dondorff, Sönke Ludwig

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
// From DUB

// Variable expansion

/// Expand variables using `$VAR_NAME` or `${VAR_NAME}` syntax.
/// `$$` escapes itself and is expanded to a single `$`.
private string expandVars(alias expandVar)(string s)
{
    string result = "";

    static bool isVarChar(char c)
    {
        return isAlphaNum(c) || c == '_';
    }

    while (true)
    {
        auto pos = s.indexOf('$');
        if (pos < 0)
        {
            result ~= s;
            return result;
        }
        result ~= s[0..pos];
        s = s[pos + 1 .. $];
        enforce(s.length > 0, "Variable name expected at end of string");
        switch (s[0])
        {
            case '$':
                result ~= '$';
                s = s[1 .. $];
                break;
            case '{':
                pos = s.indexOf('}');
                enforce(pos >= 0, "Could not find '}' to match '${'");
                result ~= expandVar(s[1 .. pos]);
                s = s[pos + 1 .. $];
                break;
            default:
                pos = s.representation.countUntil!(not!isVarChar);
                if (pos < 0)
                    pos = s.length;
                result ~= expandVar(s[0 .. pos]);
                s = s[pos .. $];
                break;
        }
    }
}

unittest
{
    string[string] vars =
    [
        "A" : "a",
        "B" : "b",
    ];

    string expandVar(string name) 
    { 
        auto p = name in vars; enforce(p, name); 
        return *p; 
    }

    assert(expandVars!expandVar("") == "");
    assert(expandVars!expandVar("x") == "x");
    assert(expandVars!expandVar("$$") == "$");
    assert(expandVars!expandVar("x$$") == "x$");
    assert(expandVars!expandVar("$$x") == "$x");
    assert(expandVars!expandVar("$$$$") == "$$");
    assert(expandVars!expandVar("x$A") == "xa");
    assert(expandVars!expandVar("x$$A") == "x$A");
    assert(expandVars!expandVar("$A$B") == "ab");
    assert(expandVars!expandVar("${A}$B") == "ab");
    assert(expandVars!expandVar("$A${B}") == "ab");
    assert(expandVars!expandVar("a${B}") == "ab");
    assert(expandVars!expandVar("${A}b") == "ab");

    import std.exception : assertThrown;
    assertThrown(expandVars!expandVar("$"));
    assertThrown(expandVars!expandVar("${}"));
    assertThrown(expandVars!expandVar("$|"));
    assertThrown(expandVars!expandVar("x$"));
    assertThrown(expandVars!expandVar("$X"));
    assertThrown(expandVars!expandVar("${"));
    assertThrown(expandVars!expandVar("${X"));

    assert(expandVars!expandVar("$${DUB_EXE:-dub}") == "${DUB_EXE:-dub}");
}
