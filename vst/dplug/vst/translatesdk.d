/**
* Simple C++ header translation for us with the VST SDK.
* Copyright: Guillaume Piolat 2018.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.vst.translatesdk;
import std.string;

mixin(translateCppHeaderToD(cast(string) import("aeffect.h") ~ import("aeffectx.h")));

string translateCppHeaderToD(string source) @safe
{
    int index = 0;

    string nextLine()
    {
        if (index >= source.length)
            return null;

        int lastIndex = index;
        while(source[index] != '\n')
            index++;
        index++;
        int offset = 1;
        if (index - 2 >= 0 && source[index - 2] == '\r')
            offset = 2;
        return source[lastIndex..index-offset];
    }

    static int indexOfChar(string source, char needle) pure @safe
    {
        int max = cast(int)(source.length);
        for(int i = 0; i < max; ++i)
        {
            if (source[i] == needle)
                return i;
        }
        return -1;
    }

    static int indexOf(string source, string needle) pure @safe
    {
        int max = cast(int)(source.length) - cast(int)needle.length;
        for(int i = 0; i < max; ++i)
        {
            if (source[i] == needle[0])
            {
                for (int j = 1; j < needle.length; ++j)
                {
                    if (source[i+j] != needle[j])
                        goto nope;
                }
                return i; // found
            }
            nope:
        }
        return -1;
    }

    static bool startsWith(string source, string prefix) pure @safe
    {
        if (source.length < prefix.length)
            return false;
        return source[0..prefix.length] == prefix;
    }

    static string replace(string source, string replaceThis, string byThis) pure @safe
    {
        int ind = indexOf(source, replaceThis);
        if (ind != -1)
            return source[0..ind] ~ byThis ~ source[ind+replaceThis.length..$];
        else
            return source;
    }

    string result;

    bool inMultilineComment = false;
    
    // state machine, very simple
    bool inEnum = false;
    bool inStruct = false;
    bool inMethod = false;

    bool inSharpIf = false;
    bool inSharpElseOrElif = false;

    result ~= "alias short VstInt16;\n";
    result ~= "alias int VstInt32;\n";
    result ~= "alias long VstInt64;\n";
    result ~= "alias ptrdiff_t VstIntPtr;\n";

    for(string line = nextLine(); line !is null; line = nextLine())
    {

  
        // strip spaces and TABs
        while (line.length > 1 && (line[0] == ' ' || line[0] == '\t'))
        {
            line = line[1..$];
        }

        // remove single-line comments
        int posSingleLineComment = indexOf(line, "//");
        if (posSingleLineComment != -1)
        {
            line = line[0..posSingleLineComment];            
        }

        // strip line-ending spaces and TABS
        while (line.length >= 1 && (line[$-1] == ' ' || line[$-1] == '\t'))
        {
            line = line[0..$-1];
        }

        if (line.length == 0)
            continue;


        // passed comments, preprocessor emulation
        // something that seems to work with the VST2 SDK: go into every #if, but never in #else or #elif
        if (line[0] == '#')
        {
            if (startsWith(line, "#pragma"))
            {
                continue;
            }
            else if (startsWith(line, "#if"))
            {
                inSharpIf = true;
                continue;
            }
            else if (startsWith(line, "#define"))
            {
                continue;
            }
            else if (startsWith(line, "#elif") || startsWith(line, "#else"))
            {
                inSharpIf = false;
                inSharpElseOrElif = true;
                continue;
            }
            else if (startsWith(line, "#endif"))
            {
                inSharpIf = false;
                inSharpElseOrElif = false;
                continue;
            }            
        }
        if (inSharpElseOrElif)
        {
            continue; // ignore lines in #else or #elif
        }

        // replace the DECLARE_VST_DEPRECATED preprocessor macro
        int iDep = indexOf(line, "DECLARE_VST_DEPRECATED");
        while(iDep != -1)
        {            
            int iFirstOpenParen = indexOfChar(line[iDep..$], '(') + iDep;
            int iFirstClosParen = indexOfChar(line[iDep..$], ')') + iDep;
         
            if (iFirstOpenParen == -1 || iFirstClosParen == -1)
                break;
 
            line = line[0..iDep] 
                    ~ "DEPRECATED_" 
                    ~ line[iFirstOpenParen+1..iFirstClosParen] 
                    ~ line[iFirstClosParen+1..$];
            iDep = indexOf(line, "DECLARE_VST_DEPRECATED");
        }

        // passed preprocessor and comments

        if (startsWith(line, "typedef"))
        {
            if (startsWith(line, "typedef struct"))
                line = line[8..$];
            else
                continue;
        }
        if (!inStruct && startsWith(line, "struct "))
        {
            bool isForward = (line[$-1] == ';');
            if (isForward)
                continue;

            inStruct = true;
            string structName = line[7..$];
            if (structName == "AEffect") // hackish but else it's a macro job
                line = "align(8) " ~ line;
            result ~= line ~ "\n";
            continue;
        }
        else if (!inEnum && startsWith(line, "enum "))
        {
            inEnum = true;
            string enumName = line[5..$];
            result ~= "alias " ~ enumName ~ " = int;\n";
            result ~= "enum : " ~ enumName ~ "\n";
            continue;
        }
        else if (startsWith(line, "{"))
        {
            if (inEnum || (inStruct && !inMethod))
                result ~= "{\n";
            continue;
        }
        else if (startsWith(line, "}"))
        {
            if (inStruct)
            {
                if (inMethod)
                    inMethod = false;
                else
                {
                    inStruct = false;
                    result ~= "}\n\n";
                }
            }

            if (inEnum)
            {
                inEnum = false;
                result ~= "}\n\n";
            }
            continue;
        }
        else if (inEnum)
        {
            result ~= "   " ~ line ~ "\n";
        }
        else if (inStruct)
        {
            // is this a method? the line would contain parens
            if (indexOfChar(line, '(') != -1 
                || indexOfChar(line, ')') != -1)
            {
                inMethod = true;
                continue;
            }

            // fix up keyword-named fields
            if (line[$-8..$] == "version;")
                line = line[0..$-8] ~ "version_;";

            // fix up array declarations
            int indOpen = indexOfChar(line, '[');
            int indClose = indexOfChar(line, ']');
            int indSpace = indexOfChar(line, ' ');
            // position of the first space is where we'll move the indexing
            if (indOpen != -1 && indClose != -1 && indSpace != -1
                && indSpace < indOpen && indClose > indOpen)
            {
                line = line[0..indSpace] 
                      ~ line[indOpen..indClose+1] 
                      ~ line[indSpace..indOpen]
                      ~ line[indClose+1..$];
            }
            // replace some unknown types
            line = replace(line, "unsigned char", "char");

            if (!inMethod)
                result ~= "   " ~ line ~ "\n";
        }
    }

    // Parsing C++ function declaration is harder than the rest of the header, deferred
    result ~= "alias extern(C) nothrow VstIntPtr function(AEffect* effect, VstInt32 opcode, VstInt32 index, VstIntPtr value, void* ptr, float opt) AEffectDispatcherProc;\n";
    result ~= "alias extern(C) nothrow @nogc VstIntPtr function(AEffect* effect, VstInt32 opcode, VstInt32 index, VstIntPtr value, void* ptr, float opt) HostCallbackFunction;\n";
    result ~= "alias extern(C) nothrow void function(AEffect* effect, float** inputs, float** outputs, VstInt32 sampleFrames) AEffectProcessProc;\n";
    result ~= "alias extern(C) nothrow void function(AEffect* effect, double** inputs, double** outputs, VstInt32 sampleFrames) AEffectProcessDoubleProc;\n";
    result ~= "alias extern(C) nothrow void function(AEffect* effect, VstInt32 index, float parameter) AEffectSetParameterProc;\n";
    result ~= "alias extern(C) nothrow float function(AEffect* effect, VstInt32 index) AEffectGetParameterProc;";
    return result;
}

unittest
{
    // For debugging purpose, uses the same parser but at runtime.
    auto S = translateCppHeaderToD(cast(string)( import("aeffect.h") ~ import("aeffectx.h")));
}