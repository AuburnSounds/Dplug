import std.stdio;
import std.algorithm;
import std.math;
import std.string;
import std.array;
import std.conv;
import std.file;
import std.path;

import consolecolors;
import dplug.core.vec;
import dplug.core.binrange;

void usage()
{
    writeln("Usage:");
    writeln("       presetbank <input0> <input1> -o output.fxb");
    writeln();
    writeln("Description:");
    writeln("       Merges presets into one bank.");
    writeln;
    writeln("       Input sources can be:");
    writeln("        - a FXP file whose filename matches the following syntax:");
//    writeln("        - a directory containing such FXP files, which is scanned");

    writeln("Flags:");
    writeln("        -h, --help  Shows this help");
    writeln("        -o          Output bank. For now, this need to be a .fxb file path.");
    writeln;
}

// Note: use a preset that "does nothing" for measurement.
// If you use a preset which does a 7 second reverb sound, then it doesn't make sense to measure such "latency",
// since it doesn't have to be compensated for.
int main(string[] args)
{
    try
    {
        bool help = false;
        string[] inputs;
        string output = "output.fxb";

        for (int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "-h" || arg == "--help")
                help = true;           
            else if (arg == "-o")
            {
                ++i;
                output = args[i];
            }
            else
            {
                inputs ~= args[i];
            }
        }

        if (help)
        {
            usage();
            return 1;
        }

        Preset[] presets;

        // Read all preset files
        foreach(input; inputs)
        {
            if (exists(input) && input.length > 4 && input[$-4..$] == ".fxp")
            {
                ubyte[] fxpData = cast(ubyte[]) std.file.read(input);
                Preset preset = loadPresetFromFXP(fxpData);

                // take name from filename
                preset.name = baseName(stripExtension(input));

                presets ~= preset;
            }
            else
                throw new Exception(format(`Input is "nbame" but should end in .fxp`, input));
        }

        if (presets.length == 0)
        {
            usage();
            return 1;
        }
        cwriteln(format("  =&gt; %s presets parsed", presets.length).lgreen);

        if (!(output.length > 4 && output[$-4..$] == ".fxb"))
            throw new Exception("Output must end in .fxb");

        ubyte[] fxb = savePresetsToFXB(presets);
        std.file.write(output, fxb);
        cwriteln(format("  =&gt; exported to %s", output).lgreen);

        return 0;      
    }
    catch(Exception e)
    {
        writeln;
        cwriteln(format("error: %s", escapeCCL(e.msg)).lred);
        writeln;
        usage();
        writeln;
        return 1;
    }
}

// Abstract representation for presets
class Preset
{
    // Unlimited length name, UTF-8 is allowed here (but won't be exported).
    string name;

    float[] normalizedParams;

    int numParameters()
    {
        return cast(int) normalizedParams.length;
    }

    // <Optional metadata>

    // the UID is used to match a plugin unique ID with the preset
    bool hasUID = false;
    uint UID = 0;
    void setUID(uint UID)
    {
        this.UID = UID;
        this.hasUID = true;
    }


    // </Optional metadata>
}

Preset loadPresetFromFXP(ubyte[] inputFXP)
{    
    Preset preset = new Preset();

    uint presetChunkID;
    uint presetChunkLen;
    inputFXP.readRIFFChunkHeader(presetChunkID, presetChunkLen);
    if (presetChunkID != CCONST('C', 'c', 'n', 'K')) throw new Exception("Expected 'CcnK' in preset");
    inputFXP.skipBytes(presetChunkLen);

    presetChunkID = inputFXP.popBE!uint();
    if (presetChunkID != CCONST('F', 'x', 'C', 'k')) throw new Exception("Expected 'FxCk' in preset");
            
    int presetVersion = inputFXP.popBE!uint();
    if (presetVersion != 1) throw new Exception("Only support FXP version 1");

    uint pluginUID = inputFXP.popBE!uint();
    preset.setUID(pluginUID);

    // fxVersion. We ignore it, since compat is supposed
    // to be encoded in the unique ID already
    inputFXP.skipBytes(4);

    int numParams = inputFXP.popBE!int();

    // parse name
    char[28] nameBuf;
    int nameLen = 28;
    foreach(nch; 0..28)
    {
        char c = inputFXP.front;
        nameBuf[nch] = c;
        inputFXP.popFront();
        if (c == '\0' && nameLen == 28) 
            nameLen = nch;
    }
    preset.name = nameBuf[0..nameLen].idup;

    // parse parameter normalized values
    foreach(paramIndex; 0..numParams)
        preset.normalizedParams ~= inputFXP.popBE!float();    
    return preset;
}


static int CCONST(int a, int b, int c, int d) pure nothrow @nogc
{
    return (a << 24) | (b << 16) | (c << 8) | (d << 0);
}


ubyte[] savePresetsToFXB(Preset[] presets)
{
    auto fxb = makeVec!ubyte();

    fxb.writeRIFFChunkHeader(CCONST('C', 'c', 'n', 'K'), 0);
    
    fxb.writeBE!uint(CCONST('F', 'x', 'B', 'k'));
    fxb.writeBE!uint(1); // TODO: proper fxVersion here

    // find a unique plugin ID in first presetb
    bool foundUID;
    uint UID = 0;
    foreach(p; presets)
    {
        if (p.hasUID)
        {
            UID = p.UID;
            foundUID = true;
            break;
        }
    }
    if (!foundUID)
        throw new Exception("UID not found in presets, can't output a FXB bank");
    
    fxb.writeBE!uint(UID);
    fxb.writeBE!uint(1); // TODO: proper fxVersion here

    fxb.writeBE!uint(cast(uint)(presets.length));

    foreach(padding; 0..128)
        fxb.writeBE!ubyte(0);

    foreach(preset; presets)
    {
        // write FXP content
        fxb.writeRIFFChunkHeader(CCONST('C', 'c', 'n', 'K'), 0);
        fxb.writeBE!uint(CCONST('F', 'x', 'C', 'k'));
        fxb.writeBE!uint(1);
        fxb.writeBE!uint(UID);
        fxb.writeBE!uint(1); // TODO: proper fxVersion here

        int numParams = cast(int)(preset.normalizedParams.length);
        fxb.writeBE!uint(numParams);

        // write name (28 chars)
        char[28] nameBuf;
        nameBuf[] = '\0';

        string presetName = preset.name;
        int len = cast(int)(presetName.length);
        if (len > 27) len = 27;
        nameBuf[0..len] = presetName[0..len]; // TODO:error about non-ASCII chars, if any
        
        foreach(nch; 0..28)
        {
            fxb.writeBE!ubyte(nameBuf[nch]);
        }


        for (int param = 0; param < numParams; ++param)
        {
            fxb.writeBE!float(preset.normalizedParams[param]);
        }
    }
    return fxb.releaseData;
}