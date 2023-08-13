/**
 * Definitions of presets and preset banks.
 *
 * Copyright: Copyright Auburn Sounds 2015 and later.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.client.preset;

import core.stdc.stdlib: free;

import std.range.primitives;
import std.math;
import std.array;
import std.algorithm.comparison;

import dplug.core.vec;
import dplug.core.nogc;
import dplug.core.binrange;

import dplug.client.client;
import dplug.client.params;

// The current situation is quite complicated.
// 
// See https://github.com/AuburnSounds/Dplug/wiki/Roles-of-the-PresetBank
// for an explanation of the bizarre "PresetBank".

/// Dplug chunks start with this.
enum uint DPLUG_MAGIC = 0xB20BA92;

/// I can see no reason why Dplug shouldn't be able to maintain
/// state chunks backward-compatibility with older versions in the future.
/// However, never say never.
/// This number will be incremented for every backward-incompatible change.
version(futureBinState) enum int DPLUG_SERIALIZATION_MAJOR_VERSION = 1;
else enum int DPLUG_SERIALIZATION_MAJOR_VERSION = 0;

/// This number will be incremented for every backward-compatible change
/// that is significant enough to bump a version number
enum int DPLUG_SERIALIZATION_MINOR_VERSION = 0;

// Compilation failures for futureBinState in combinations that don't work (yet!)
version(futureBinState) {
    version(LV2) static assert(0, "futureBinState is currently not supported for LV2 plugins!");
    
    version(VST2) {
        version(legacyVST2Chunks) static assert(0, "futureBinState requires futureVST2Chunks for VST2!");
    }
}

/// A preset is a slot in a plugin preset list
final class Preset
{
public:

    this(string name, const(float)[] normalizedParams, const(ubyte)[] stateData = null) nothrow @nogc
    {
        _name = name.mallocDup;
        _normalizedParams = normalizedParams.mallocDup;
        if (stateData) 
            _stateData = stateData.mallocDup;
    }

    ~this() nothrow @nogc
    {
        clearName();
        free(_normalizedParams.ptr);
        clearData();
    }

    void setNormalized(int paramIndex, float value) nothrow @nogc
    {
        _normalizedParams[paramIndex] = value;
    }

    const(char)[] name() pure nothrow @nogc
    {
        return _name;
    }

    void setName(const(char)[] newName) nothrow @nogc
    {
        clearName();
        _name = newName.mallocDup;
    }

    version(futureBinState) void setStateData(ubyte[] data) nothrow @nogc
    {
        clearData();
        _stateData = data.mallocDup;
    }

    void saveFromHost(Client client) nothrow @nogc
    {
        auto params = client.params();
        foreach(size_t i, param; params)
        {
            _normalizedParams[i] = param.getNormalized();
        }

        version(futureBinState)
        {{
            clearData(); // Forget possible existing _stateData
            Vec!ubyte chunk;
            client.saveState(chunk);
            _stateData = chunk.releaseData;
        }}
    }

    // TODO: should this return an error if any encountered?
    void loadFromHost(Client client) nothrow @nogc
    {
        auto params = client.params();
        foreach(size_t i, param; params)
        {
            if (i < _normalizedParams.length)
                param.setFromHost(_normalizedParams[i]);
            else
            {
                // this is a new parameter that old presets don't know, set default
                param.setFromHost(param.getNormalizedDefault());
            }
        }

        version(futureBinState)
        {
            // loadFromHost seems to best effort, no error reported on parse failure
            client.loadState(_stateData); 
        }
    }

    static bool isValidNormalizedParam(float f) nothrow @nogc
    {
        return (isFinite(f) && f >= 0 && f <= 1);
    }

    inout(float)[] getNormalizedParamValues() inout nothrow @nogc
    {
        return _normalizedParams;
    }

    version(futureBinState) ubyte[] getStateData() nothrow @nogc
    {
        return _stateData;
    }

private:
    char[] _name;
    float[] _normalizedParams;
    ubyte[] _stateData;

    void clearName() nothrow @nogc
    {
        if (_name !is null)
        {
            free(_name.ptr);
            _name = null;
        }
    }

    void clearData() nothrow @nogc
    {
        if (_stateData !is null)
        {
            free(_stateData.ptr);
            _stateData = null;
        }
    }
}

/// A preset bank is a collection of presets
final class PresetBank
{
public:

    // Extends an array or Preset
    Vec!Preset presets;

    // Create a preset bank
    // Takes ownership of this slice, which must be allocated with `malloc`,
    // containing presets allocated with `mallocEmplace`.
    this(Client client, Preset[] presets_) nothrow @nogc
    {
        _client = client;

        // Copy presets to own them
        presets = makeVec!Preset(presets_.length);
        foreach(size_t i; 0..presets_.length)
            presets[i] = presets_[i];

        // free input slice with `free`
        free(presets_.ptr);

        _current = 0;
    }

    ~this() nothrow @nogc
    {
        // free all presets
        foreach(p; presets)
        {
            // if you hit a break-point here, maybe your
            // presets weren't allocated with `mallocEmplace`
            p.destroyFree();
        }
    }

    inout(Preset) preset(int i) inout nothrow @nogc
    {
        return presets[i];
    }

    int numPresets() nothrow @nogc
    {
        return cast(int)presets.length;
    }

    int currentPresetIndex() nothrow @nogc
    {
        return _current;
    }

    Preset currentPreset() nothrow @nogc
    {
        int ind = currentPresetIndex();
        if (!isValidPresetIndex(ind))
            return null;
        return presets[ind];
    }

    bool isValidPresetIndex(int index) nothrow @nogc
    {
        return index >= 0 && index < numPresets();
    }

    // Save current state to current preset. This updates the preset bank to reflect the state change.
    // This will be unnecessary once we haver internal preset management.
    void putCurrentStateInCurrentPreset() nothrow @nogc
    {
        presets[_current].saveFromHost(_client);
    }

    void loadPresetByNameFromHost(string name) nothrow @nogc
    {
        foreach(size_t index, preset; presets)
            if (preset.name == name)
                loadPresetFromHost(cast(int)index);
    }

    void loadPresetFromHost(int index) nothrow @nogc
    {
        putCurrentStateInCurrentPreset();
        presets[index].loadFromHost(_client);
        _current = index;
    }

    /// Enqueue a new preset and load it
    void addNewDefaultPresetFromHost(string presetName) nothrow @nogc
    {
        Parameter[] params = _client.params;
        float[] values = mallocSlice!float(params.length);
        scope(exit) values.freeSlice();

        foreach(size_t i, param; _client.params)
            values[i] = param.getNormalizedDefault();

        presets.pushBack(mallocNew!Preset(presetName, values));
        loadPresetFromHost(cast(int)(presets.length) - 1);
    }
  
    /// Gets a state chunk to save the current state.
    /// The returned state chunk should be freed with `free`.
    ubyte[] getStateChunkFromCurrentState() nothrow @nogc
    {
        auto chunk = makeVec!ubyte();
        this.writeStateChunk(chunk);
        return chunk.releaseData;
    }

    /// Gets a state chunk that would be the current state _if_
    /// preset `presetIndex` was made current first. So it's not
    /// changing the client state.
    /// The returned state chunk should be freed with `free()`.
    ubyte[] getStateChunkFromPreset(int presetIndex) nothrow @nogc
    {
        auto chunk = makeVec!ubyte();
        this.writePresetChunkData(chunk, presetIndex);
        return chunk.releaseData;
    }

    /// Loads a chunk state, update current state.
    /// May throw an Exception.
    void loadStateChunk(ubyte[] chunk) @nogc
    {
        int mVersion = checkChunkHeader(chunk);

        // This avoid to overwrite the preset 0 while we modified preset N
        int presetIndex = chunk.popLE!int();
        if (!isValidPresetIndex(presetIndex))
            throw mallocNew!Exception("Invalid preset index in state chunk");
        else
            _current = presetIndex;

        version(futureBinState) {

            // Binary state future tag.
            if (mVersion == 0) loadChunkV1(chunk);
            else loadChunkV2(chunk);
        } else {

            loadChunkV1(chunk);
        }
    }

private:
    Client _client;
    int _current; // should this be only in VST client?

    // Loads chunk without binary save state
    void loadChunkV1(ref ubyte[] chunk) @nogc
    {
        // Load parameters values
        auto params = _client.params();
        int numParams = chunk.popLE!int();
        foreach(int i; 0..numParams)
        {
            float normalized = chunk.popLE!float();
            if (i < params.length)
                params[i].setFromHost(normalized);
        }
    }

    version(futureBinState) {

        // Loads chunk with binary save state
        void loadChunkV2(ref ubyte[] chunk) @nogc
        {
            // Load parameters values
            auto params = _client.params();
            int numParams = chunk.popLE!int();
            foreach(int i; 0..numParams)
            {
                float normalized = chunk.popLE!float();
                if (i < params.length)
                    params[i].setFromHost(normalized);
            }

            int dataLength = chunk.popLE!int();
            bool parseSuccess = _client.loadState(chunk[0..dataLength]);
            if (!parseSuccess)
                throw mallocNew!Exception("Invalid user-defined state chunk");
        }
    }
    
    version(futureBinState) {

        // Writes preset chunk with V2 method
        void writeStateChunk(ref Vec!ubyte chunk) nothrow @nogc
        {
            writeChunkHeader(chunk, 1);

            auto params = _client.params();

            chunk.writeLE!int(_current);

            chunk.writeLE!int(cast(int)params.length);
            foreach(param; params)
                chunk.writeLE!float(param.getNormalized());

            size_t chunkLenIndex = chunk.length;
            chunk.writeLE!int(0); // temporary chunk length value

            size_t before = chunk.length;
            _client.saveState(chunk); // append state to chunk
            size_t after = chunk.length;

            // Write actual value for chunk length.
            ubyte[] indexPos = chunk.ptr[chunkLenIndex.. chunkLenIndex+4];
            indexPos.writeLE!int(cast(int)(after - before));
        }
    } else {

        // Writes chunk with V1 method
        void writeStateChunk(ref Vec!ubyte chunk) nothrow @nogc
        {
            writeChunkHeader(chunk, 0);

            auto params = _client.params();

            chunk.writeLE!int(_current);

            chunk.writeLE!int(cast(int)params.length);
            foreach(param; params)
                chunk.writeLE!float(param.getNormalized());
        }
    }

    version(futureBinState) {

        // Writes preset chunk with V2 method
        void writePresetChunkData(ref Vec!ubyte chunk, int presetIndex) nothrow @nogc
        {
            writeChunkHeader(chunk, 1);

            auto p = preset(presetIndex);
            chunk.writeLE!int(presetIndex);

            chunk.writeLE!int(cast(int)p._normalizedParams.length);
            foreach(param; p._normalizedParams)
                chunk.writeLE!float(param);
            
            chunk.writeLE!int(cast(int)p._stateData.length);
            chunk.pushBack(p._stateData[0..$]);
        }
    } else {

        // Writes chunk with V1 method
        void writePresetChunkData(ref Vec!ubyte chunk, int presetIndex) nothrow @nogc
        {
            writeChunkHeader(chunk, 0);

            auto p = preset(presetIndex);
            chunk.writeLE!int(presetIndex);

            chunk.writeLE!int(cast(int)p._normalizedParams.length);
            foreach(param; p._normalizedParams)
                chunk.writeLE!float(param);
        }
    }

    void writeChunkHeader(O)(auto ref O output, int version_=DPLUG_SERIALIZATION_MAJOR_VERSION) const @nogc if (isOutputRange!(O, ubyte))
    {
        // write magic number and dplug version information (not the tag version)
        output.writeBE!uint(DPLUG_MAGIC);
        output.writeLE!int(DPLUG_SERIALIZATION_MAJOR_VERSION);
        output.writeLE!int(DPLUG_SERIALIZATION_MINOR_VERSION);

        // write plugin version
        output.writeLE!int(_client.getPublicVersion().toAUVersion());
    }

    int checkChunkHeader(ref ubyte[] input) @nogc
    {
        // nothing to check with minor version
        uint magic = input.popBE!uint();
        if (magic !=  DPLUG_MAGIC)
            throw mallocNew!Exception("Can not load, magic number didn't match");

        // nothing to check with minor version
        int dplugMajor = input.popLE!int();
        if (dplugMajor > DPLUG_SERIALIZATION_MAJOR_VERSION)
            throw mallocNew!Exception("Can not load chunk done with a newer, incompatible dplug library");

        int dplugMinor = input.popLE!int();
        // nothing to check with minor version

        // TODO: how to handle breaking binary compatibility here?
        int pluginVersion = input.popLE!int();
        return dplugMajor;
    }
}

/// Loads an array of `Preset` from a FXB file content.
/// Gives ownership of the result, in a way that can be returned by `buildPresets`.
/// IMPORTANT: if you store your presets in FXB form, the following limitations 
///   * One _add_ new parameters to the plug-in, no reorder or deletion
///   * Don't remap the parameter (in a way that changes its normalized value)
/// They are the same limitations that exist in Dplug in minor plugin version.
///
/// Params:
///    maxCount Maximum number of presets to take, -1 for all of them
///
/// Example:
///       override Preset[] buildPresets()
///       {
///           return loadPresetsFromFXB(this, import("factory-presets.fxb"));
///       }
///
/// Note: It is **heavily recommended** to create the FXB chunk with the Dplug `presetbank` tool.
///       Else it is unknown if it will work.
Preset[] loadPresetsFromFXB(Client client, string inputFBXData, int maxCount = -1) nothrow @nogc
{
    ubyte[] fbxCopy = cast(ubyte[]) mallocDup(inputFBXData);
    ubyte[] inputFXB = fbxCopy;
    scope(exit) free(fbxCopy.ptr);

    Vec!Preset result = makeVec!Preset();

    static int CCONST(int a, int b, int c, int d) pure nothrow @nogc
    {
        return (a << 24) | (b << 16) | (c << 8) | (d << 0);
    }

    try
    {
        uint bankChunkID;
        uint bankChunkLen;
        inputFXB.readRIFFChunkHeader(bankChunkID, bankChunkLen);

        void error() @nogc
        {
            throw mallocNew!Exception("Error in parsing FXB");
        }

        if (bankChunkID != CCONST('C', 'c', 'n', 'K')) error;
        inputFXB.skipBytes(bankChunkLen);
        uint fbxChunkID = inputFXB.popBE!uint();
        if (fbxChunkID != CCONST('F', 'x', 'B', 'k')) error;
        inputFXB.skipBytes(4); // fxVersion

        // if uniqueID has changed, then the bank is not compatible and should error
        char[4] uid = client.getPluginUniqueID();
        if (inputFXB.popBE!uint() != CCONST(uid[0], uid[1], uid[2], uid[3])) error;

        // fxVersion. We ignore it, since compat is supposed
        // to be encoded in the unique ID already
        inputFXB.popBE!uint();

        int numPresets = inputFXB.popBE!int();
        if ((maxCount != -1) && (numPresets > maxCount))
            numPresets = maxCount;
        if (numPresets < 1) error; // no preset in band, probably not what you want

        inputFXB.skipBytes(128);

        // Create presets
        for(int presetIndex = 0; presetIndex < numPresets; ++presetIndex)
        {
            Preset p = client.makeDefaultPreset();
            uint presetChunkID;
            uint presetChunkLen;
            inputFXB.readRIFFChunkHeader(presetChunkID, presetChunkLen);
            if (presetChunkID != CCONST('C', 'c', 'n', 'K')) error;
            inputFXB.skipBytes(presetChunkLen);

            presetChunkID = inputFXB.popBE!uint();
            if (presetChunkID != CCONST('F', 'x', 'C', 'k')) error;
            int presetVersion = inputFXB.popBE!uint();
            if (presetVersion != 1) error;
            if (inputFXB.popBE!uint() != CCONST(uid[0], uid[1], uid[2], uid[3])) error;

            // fxVersion. We ignore it, since compat is supposed
            // to be encoded in the unique ID already
            inputFXB.skipBytes(4);

            int numParams = inputFXB.popBE!int();
            if (numParams < 0) error;

            // parse name
            char[28] nameBuf;
            int nameLen = 28;
            foreach(nch; 0..28)
            {
                char c = inputFXB.front;
                nameBuf[nch] = c;
                inputFXB.popFront();
                if (c == '\0' && nameLen == 28) 
                    nameLen = nch;
            }
            p.setName(nameBuf[0..nameLen]);

            // parse parameter normalized values
            int paramRead = numParams;
            if (paramRead > cast(int)(client.params.length))
                paramRead = cast(int)(client.params.length);
            for (int param = 0; param < paramRead; ++param)
            {
                p.setNormalized(param, inputFXB.popBE!float());
            }

            // skip excess parameters (this case should never happen so not sure if it's to be handled)
            for (int param = paramRead; param < numParams; ++param)
                inputFXB.skipBytes(4);

            result.pushBack(p);
        }
    }
    catch(Exception e)
    {
        destroyFree(e);

        // Your preset file for the plugin is not meant to be invalid, so this is a bug.
        // If you fail here, parsing has created an `error()` call.
        assert(false); 
    }

    return result.releaseData();
}
