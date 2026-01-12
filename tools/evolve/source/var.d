module var;

import std.string;
import std.regex;
import std.conv;
static import std.file;
import std.algorithm;
import consolecolors;
import settings;
import utils;
import yxml;

class Variable
{
    enum Type
    {
        fp32,
        i32
    }
    string sourceFilePath;  // where to find it
    string hit;             // complete line capture    

    bool tunable;         // Could it be evolved in principle? or parse error/not supported
    bool ignored;         // Can't be selected for evolution because of some UDAs saying so.

    bool stopEvolution = false;
   
    
    Type type;
    string name;          // only if tunable
    bool isEnum;          // only if tunable
    string preWhitespace;


    string originalValueString; // only if tunable
    double originalValue; // only if tunable and type == Type.fp
    double currentValue;  // only if tunable and type == Type.fp
    double bestKnownValue;
    double bestKnownValueFitness = double.infinity; // bad fitness
    int originalValueI;   // only if tunable and type == Type.integer

    int priority;         // for sorting by priority

    string tagString;

    string comment = "// generated"; // can be null

    string regenWithValue(double value)
    {
        assert(type == Type.fp32);
        string valueString = (originalValue == value && originalValueString !is null) ? originalValueString : format("%13f", value); 
        return format("%s@tuning %s%sfloat %s = %s; %s", 
                      preWhitespace, 
                      tagString, 
                      isEnum ? "enum " : "", 
                      name, 
                      valueString,
                      comment);  
    }

    void disableFurtherChanges()
    {
        stopEvolution = true;
    }

    this(string sourceFilePath, string hit)
    {
        this.sourceFilePath = sourceFilePath;
        this.hit = stripRight(hit);
        parseHit;
        if (isPromotedToParameter)
            ignored = true;
        if (isOptimal)
            ignored = true;
        if (isManyDependees)
            ignored = true;
        if (isChangesLatency)
            ignored = true;
        if (isSubjective)
            ignored = true;
        if (isIgnore)
            ignored = true;
        if (isDubious)
            ignored = true;
    }

    void display()
    {
        bool ignore = false;
        if (ignored)
        {
            cwritefln("    - <grey>%s</grey>", escapeCCL(hit));
        }
        else if (tunable)
        {
            cwritefln("    - <lgreen>%s</lgreen>", escapeCCL(hit));
        }
        else
            cwritefln("    - <lred>%s</lred>", escapeCCL(hit));
    }

    void parseHit()
    {
        auto capturesF = matchFirst(hit, simpleFloatVar);
        auto capturesI = matchFirst(hit, simpleIntVar);
        if (capturesF)
        {
            type = Type.fp32;
            preWhitespace = capturesF[1];
            tagString = capturesF[2];
            isEnum = capturesF[3] != "";
            name = capturesF[4];
            string floatLiteral = capturesF[5];
            comment = capturesF[6];
            if (floatLiteral.endsWith("L"))
                floatLiteral = floatLiteral[0..$-1];
            else if (floatLiteral.endsWith("f"))
                floatLiteral = floatLiteral[0..$-1];
            originalValueString = floatLiteral;
            originalValue = to!double(floatLiteral); // parse at double, because why not
            currentValue = originalValue;
            bestKnownValue = originalValue; // assume the original value is kinda good
            tunable = true;
        }
        else if (capturesI)
        {
            // int isn't really supported actually
            type = Type.i32;
            preWhitespace = capturesI[1];
            tagString = capturesI[2];
            isEnum = capturesI[3] != "";
            name = capturesI[4];
            string intLiteral = capturesI[5];
            comment = capturesI[6];
            originalValueString = intLiteral;
            originalValueI = to!int(intLiteral);
            tunable = true;
        }
        else
        {
            tunable = false;
        }
    }

    bool isPromotedToParameter()
    {
        return tagString.canFind("@promotedToParameter");
    }

    bool isOptimal()
    {
        return tagString.canFind("@optimal");
    }

    bool isManyDependees()
    {
        return tagString.canFind("@manyDependees");
    }

    bool isChangesLatency()
    {
        return tagString.canFind("@changesLatency");
    }

    bool isIgnore()
    {
        return tagString.canFind("@ignore");
    }

    bool isSubjective()
    {
        return tagString.canFind("@subjective");
    }

    bool isDubious()
    {
        return tagString.canFind("@dubious");
    }

    void setValue(double value, bool verbose)
    {
        assert(type == Type.fp32);
        if (currentValue == value)
            return;

        if (verbose)
            cwritefln("      <lgreen>Setting</lgreen> <lcyan>%s</lcyan> to <yellow>%s</yellow>", name, value);

        string fileContent = cast(string)(std.file.read(sourceFilePath));

        // make declaration regex that also match a particular identifier
        string regexpWithName = SIMPLE_FLOAT_REGEX.replace(`(\w+)`, "(" ~ name ~ ")");

        auto myDecl = regex(regexpWithName, "m");

        // count occurrence of @tuning
        string newContent = replaceFirst(fileContent, myDecl, regenWithValue(value));
        std.file.write(sourceFilePath, newContent);

        currentValue = value;
    }

    void setOriginalValue(bool verbose)
    {
        setValue(originalValue, verbose);
    }

    void setBestKnownValue(bool verbose)
    {
        if (stopEvolution)
            return;
        // set to best know value, also the best know value becomes the original!
        setValue(bestKnownValue, verbose);
        originalValue = bestKnownValue;
        originalValueString = null; // forget original string
    }
}

enum string SIMPLE_FLOAT_REGEX = 
  `^( *)@tuning\s+((?:@\w+\s+)*)(enum\s+)?float\s+(\w+)\s*\=\s*(-?\d+(?:\.\d+f?)?)\s*;\s*((?://.*)?)$`;
__gshared auto simpleFloatVar = regex(SIMPLE_FLOAT_REGEX,"m");
__gshared auto simpleIntVar = regex(`^(.*)@tuning\s+((?:@\w+\s+)*)(enum\s+)?int\s+(\w+)\s*\=\s*(-?\d+(?:\.\d+f?)?)\s*;\s*((?://.*)?)$`,"m");

// Evaluate cost function, where the current state is.
double evaluate(TrainingSettings settings)
{
    cwriteln("    <lgreen>Measuring</lgreen> fitness...");

    // For each source, return a global score.
    safeCommand(settings.fitnessCommand); // this program writes fitness.xml of the form

    // <?xml version="1.0" encoding="UTF-8"?>
    // <results>
    //    <metric name="xxxx" value="<score>" />
    // </results>

    // get score in fitness.xml in current directory
    string content = cast(string)(std.file.read("fitness.xml"));
    XmlDocument doc;
    doc.parse(content);
    if (doc.isError)
        throw new Exception(doc.errorMessage.idup);

    if (doc.root.tagName != "results")
        throw new Exception("expected <results> as root XML anchor");

    foreach(e; doc.root.getChildrenByTagName("metric"))
    {
        double fitness = to!double(e.getAttribute("value"));
        //cwritefln("              <white>=&gt;</white> <yellow>%s</yellow>", fitness);
        return fitness;
    }

    throw new Exception("No metric result found, evaluation failed");
}