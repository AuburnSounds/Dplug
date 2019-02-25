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

import dplug.client.binrange;
import dplug.client.client;
import dplug.client.params;

// The current situation is really complicated.
//
// There are 3 types of chunks:
// - "preset" and "bank" chunks are used by VST2. The whole preset "bank" structure exists for VST2.
//   Changing a preset and loading another changes the bank. VST2 is the only format that could
//   store unused presets.
// - AU, VST3 and AAX uses "state chunks" which are storing a single preset and a preset index.
//   On load, the bank from factory is restored but the single preset stored will be changed.
//   However, in AU and AAX the whole concept of the preset bank is there for nothing.

/// I can see no reason why dplug shouldn't be able to maintain
/// backward-compatibility with older versions in the future.
/// However, never say never.
/// This number will be incremented for every backward-incompatible change.
enum int DPLUG_SERIALIZATION_MAJOR_VERSION = 0;

/// This number will be incremented for every backward-compatible change
/// that is significant enough to bump a version number
enum int DPLUG_SERIALIZATION_MINOR_VERSION = 0;

/// A preset is a slot in a plugin preset list
final class Preset
{
public:

    this(string name, const(float)[] normalizedParams) nothrow @nogc
    {
        _name = name.mallocDup;
        _normalizedParams = normalizedParams.mallocDup;
    }

    ~this() nothrow @nogc
    {
        clearName();
        free(_normalizedParams.ptr);
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

    void saveFromHost(Client client) nothrow @nogc
    {
        auto params = client.params();
        foreach(size_t i, param; params)
        {
            _normalizedParams[i] = param.getNormalized();
        }
    }

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
    }

    void serializeBinary(O)(auto ref O output) nothrow @nogc if (isOutputRange!(O, ubyte))
    {
        output.writeLE!int(cast(int)_name.length);

        foreach(i; 0..name.length)
            output.writeLE!ubyte(_name[i]);

        output.writeLE!int(cast(int)_normalizedParams.length);

        foreach(np; _normalizedParams)
            output.writeLE!float(np);
    }

    /// Throws: A `mallocEmplace`d `Exception`
    void unserializeBinary(ref ubyte[] input) @nogc
    {
        clearName();
        int nameLength = input.popLE!int();
        _name = mallocSlice!char(nameLength);
        foreach(i; 0..nameLength)
        {
            ubyte ch = input.popLE!ubyte();
            _name[i] = ch;
        }

        int paramCount = input.popLE!int();

        foreach(int ip; 0..paramCount)
        {
            float f = input.popLE!float();

            // MAYDO: best-effort recovery?
            if (!isValidNormalizedParam(f))
                throw mallocNew!Exception("Couldn't unserialize preset: an invalid float parameter was parsed");

            // There may be more parameters when downgrading
            if (ip < _normalizedParams.length)
                _normalizedParams[ip] = f;
        }
    }

    static bool isValidNormalizedParam(float f) nothrow @nogc
    {
        return (isFinite(f) && f >= 0 && f <= 1);
    }

private:
    char[] _name;
    float[] _normalizedParams;

    void clearName() nothrow @nogc
    {
        if (_name !is null)
        {
            free(_name.ptr);
            _name = null;
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

    /// Allocates and fill a preset chunk
    /// The resulting buffer should be freed with `free`.
    ubyte[] getPresetChunk(int index) nothrow @nogc
    {
        auto chunk = makeVec!ubyte();
        writeChunkHeader(chunk);
        presets[index].serializeBinary(chunk);
        return chunk.releaseData();
    }

    /// Parse a preset chunk and set parameters.
    /// May throw an Exception.
    void loadPresetChunk(int index, ubyte[] chunk)
    {
        checkChunkHeader(chunk);
        presets[index].unserializeBinary(chunk);

        // Not sure why it's there in IPlug, this whole function is probably not
        // doing what it should
        //putCurrentStateInCurrentPreset();
    }

    /// Allocate and fill a bank chunk
    /// The resulting buffer should be freed with `free`.
    ubyte[] getBankChunk() nothrow @nogc
    {
        putCurrentStateInCurrentPreset();
        auto chunk = makeVec!ubyte();
        writeChunkHeader(chunk);

        // write number of presets
        chunk.writeLE!int(cast(int)(presets.length));

        foreach(size_t i, preset; presets)
            preset.serializeBinary(chunk);
        return chunk.releaseData();
    }

    /// Parse a bank chunk and set parameters.
    /// May throw an Exception.
    void loadBankChunk(ubyte[] chunk) @nogc
    {
        checkChunkHeader(chunk);

        int numPresets = chunk.popLE!int();

        // TODO: is there a way to have a dynamic number of presets in the bank? Check with VST and AU
        numPresets = min(numPresets, presets.length);
        foreach(preset; presets[0..numPresets])
            preset.unserializeBinary(chunk);
    }

    /// Gets a state chunk to save the current state.
    /// The returned state chunk should be freed with `free`.
    ubyte[] getStateChunkFromCurrentState() nothrow @nogc
    {
        auto chunk = makeVec!ubyte();
        writeChunkHeader(chunk);

        auto params = _client.params();

        chunk.writeLE!int(_current);

        chunk.writeLE!int(cast(int)params.length);
        foreach(param; params)
            chunk.writeLE!float(param.getNormalized());
        return chunk.releaseData;
    }

    /// Gets a state chunk that would be the current state _if_
    /// preset `presetIndex` was made current first. So it's not
    /// changing the client state.
    /// The returned state chunk should be freed with `free()`.
    ubyte[] getStateChunkFromPreset(int presetIndex) const nothrow @nogc
    {
        auto chunk = makeVec!ubyte();
        writeChunkHeader(chunk);

        auto p = preset(presetIndex);
        chunk.writeLE!int(presetIndex);

        chunk.writeLE!int(cast(int)p._normalizedParams.length);
        foreach(param; p._normalizedParams)
            chunk.writeLE!float(param);
        return chunk.releaseData;
    }

    /// Loads a chunk state, update current state.
    /// May throw an Exception.
    void loadStateChunk(ubyte[] chunk) @nogc
    {
        checkChunkHeader(chunk);

        // This avoid to overwrite the preset 0 while we modified preset N
        int presetIndex = chunk.popLE!int();
        if (!isValidPresetIndex(presetIndex))
            throw mallocNew!Exception("Invalid preset index in state chunk");
        else
            _current = presetIndex;

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

private:
    Client _client;
    int _current; // should this be only in VST client?

    enum uint DPLUG_MAGIC = 0xB20BA92;

    void writeChunkHeader(O)(auto ref O output) const @nogc if (isOutputRange!(O, ubyte))
    {
        // write magic number and dplug version information (not the tag version)
        output.writeBE!uint(DPLUG_MAGIC);
        output.writeLE!int(DPLUG_SERIALIZATION_MAJOR_VERSION);
        output.writeLE!int(DPLUG_SERIALIZATION_MINOR_VERSION);

        // write plugin version
        output.writeLE!int(_client.getPublicVersion().toAUVersion());
    }

    void checkChunkHeader(ref ubyte[] input) @nogc
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
    }
}
