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
import dplug.client.preset;

// TODO: if plugin has actual non-empty state chunk, cannot do it yet. See Issue #907.

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
    writeln("        --state     Allow support for state chunk in presets. Only available if your plugin is NOT legacyBinState.");
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
        bool allowState = false;

        for (int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "--state")
            {
                allowState = true;
            }
            else if (arg == "-h" || arg == "--help")
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
            if (!exists(input))
                throw new Exception(format(`"%s" doesn't exist`, input));

            if (input.length > 4 && input[$-4..$] == ".fxp")
            {
                ubyte[] fxpData = cast(ubyte[]) std.file.read(input);
                Preset preset = loadPresetFromFXP(fxpData, allowState);

                // take name from filename
                preset.name = baseName(stripExtension(input));

                presets ~= preset;
            }
            else
                throw new Exception(format(`Input preset "%s" should end in .fxp`, input));
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

    // true if we parsed a V2 Dplug chunk, even if the state is []
    bool isV2Chunk;

    bool hasStateData()
    {
        return stateData.length > 0;
    }

    ubyte[] stateData;

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

// This parser supports: .fxb/.fxp created with Orion and another(?) DAW + the ones created by Dplug .
Preset loadPresetFromFXP(const(ubyte)[] inputFXP, bool allowState)
{
    Preset preset = new Preset();

    uint presetChunkID;
    uint presetChunkLen;
    bool err;
    inputFXP.readRIFFChunkHeader(presetChunkID, presetChunkLen, &err);
    if (err) throw new Exception("Chunk header cannot be read");
    if (presetChunkID != CCONST('C', 'c', 'n', 'K')) throw new Exception("Expected 'CcnK' in preset");

    // Simply ignore the chunk length. Orion doesn't fill that field reliably. See Dplug Issue #765.
    // Besides, presetChunkLen is encoded as Big Endian in most hosts probably, and we parse it as Little Endian.

    presetChunkID = inputFXP.popBE!uint(&err);
    if (err) throw new Exception("input error");

    bool isFXBChunk = false;

    if (presetChunkID != CCONST('F', 'x', 'C', 'k'))
    {
        if (presetChunkID == CCONST('F', 'P', 'C', 'h'))
        {
            isFXBChunk = true;
        }
        else
            throw new Exception("Expected 'FxCk' or 'FPCh' in preset");
    }
            
    int presetVersion = inputFXP.popBE!uint(&err);
    if (err) throw new Exception("input error");
    if (presetVersion != 1) throw new Exception("Only support FXP version 1");

    uint pluginUID = inputFXP.popBE!uint(&err);
    if (err) throw new Exception("input error");
    preset.setUID(pluginUID);

    // fxVersion. We ignore it, since compat is supposed
    // to be encoded in the unique ID already
    inputFXP.skipBytes(4, &err);
    if (err) throw new Exception("input error");

    int numParams = inputFXP.popBE!int(&err);
    if (err) throw new Exception("input error");

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

    if (isFXBChunk)
    {
        // Try to parse a Dplug chunk here.
        uint chunkID = inputFXP.popBE!uint(&err);
        if (err) throw new Exception("input error");

        // nothing to check with minor version
        uint magic = inputFXP.popBE!uint(&err);
        if (err) throw new Exception("input error");
        if (magic != DPLUG_MAGIC)
            throw new Exception("Can not load, magic number didn't match");

        // nothing to check with minor version
        int dplugMajor = inputFXP.popLE!int(&err);
        if (err) throw new Exception("Cannot read Dplug major chunk version");
        if (dplugMajor > 1)
            throw new Exception("presetbank tool doesn't support Dplug chunk above version 1");

        int dplugMinor = inputFXP.popLE!int(&err);
        if (err) throw new Exception("Cannot read Dplug minor chunk version");

        int pluginVersion = inputFXP.popLE!int(&err); // ignore, compat is in plugin ID already
        if (err) throw new Exception("Cannot read plugin version");

        int presetIndex = inputFXP.popLE!int(&err); // ignore
        if (err) throw new Exception("Cannot read preset index");

        // Load parameters values
        int paramNum = inputFXP.popLE!int(&err);
        if (err) throw new Exception("Cannot read parameter number");
        if (numParams != paramNum) 
            throw new Exception("Inconsistent number of parameters, written twice in FBX but different.");

        foreach(int i; 0..numParams)
        {
            float paramValue = inputFXP.popLE!float(&err);
            if (err) throw new Exception("Cannot read parameter value");
            preset.normalizedParams ~= paramValue;
        }

        // Chunk is V2, has a state part
        // which means the plugin MUST NOT have legacyBinState
        if (dplugMajor > 0)
        {
            preset.isV2Chunk = true;
            if (!allowState)
            {
                throw new Exception("Preset was made with a plugin with binState option. But --state was not provided. Possible loss of compatibility. You can only add --state if your plugin IS NOT legacyBinState.");
            }

            int stateLen = inputFXP.popLE!int(&err); // ignore
            if (err) throw new Exception("Cannot read state chunk length");
            if (stateLen < 0)
                throw new Exception("State chunk length has negative length, odd.");
            const(ubyte)[] state = new ubyte[stateLen];
            state = inputFXP[0..stateLen];
            inputFXP = inputFXP[stateLen..$];
            preset.stateData = state.dup;

            if (preset.hasStateData)
            {
                // TODO: unsupported
                throw new Exception("Preset with non-empty state chunks not supported yet in Dplug. Only parameters would be written.");
            }
        }
        return preset;
    }
    else // this is a non-chunk VST2 .fxb
    {
        // parse parameter normalized values
        foreach(paramIndex; 0..numParams)
        {
            float paramValue = inputFXP.popBE!float(&err);
            if (err) throw new Exception("Cannot read parameter value");
            preset.normalizedParams ~= paramValue;
        }
        return preset;
    }
}

static int CCONST(int a, int b, int c, int d) pure nothrow @nogc
{
    return (a << 24) | (b << 16) | (c << 8) | (d << 0);
}

ubyte[] savePresetsToFXB(Preset[] presets)
{
    auto fxb = makeVec!ubyte();

    fxb.writeRIFFChunkHeader(CCONST('C', 'c', 'n', 'K'), 0); // Zero Length. Note: our FXB output seems incorrent here. TODO Compare to Live .fxb.

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