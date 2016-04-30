/**
 * Copyright: Copyright Auburn Sounds 2015 and later.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.client.preset;

import std.range;
import std.math;
import std.array;
import std.algorithm;

import dplug.client.binrange;
import dplug.client.client;


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
    this(string name, float[] normalizedParams) nothrow @nogc
    {
        _name = name;
        _normalizedParams = normalizedParams;
    }

    void setNormalized(int paramIndex, float value) nothrow @nogc
    {
        _normalizedParams[paramIndex] = value;
    }

    string name() pure nothrow @nogc
    {
        return _name;
    }

    string name(string newName) pure nothrow @nogc
    {
        return _name = newName;
    }

    void saveFromHost(Client client) nothrow @nogc
    {
        auto params = client.params();
        foreach(int i, param; params)
        {
            _normalizedParams[i] = param.getNormalized();
        }
    }

    void loadFromHost(Client client) nothrow
    {
        auto params = client.params();
        foreach(int i, param; params)
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

    void serializeBinary(O)(auto ref O output) if (isOutputRange!(O, ubyte))
    {
        output.writeLE!int(cast(int)_name.length);

        foreach(i; 0..name.length)
            output.writeLE!ubyte(_name[i]);

        output.writeLE!int(cast(int)_normalizedParams.length);

        foreach(np; _normalizedParams)
            output.writeLE!float(np);
    }

    void unserializeBinary(ref ubyte[] input)
    {
        _name = "";
        int nameLength = input.popLE!int();
        _name.reserve(nameLength);
        foreach(i; 0..nameLength)
        {
            ubyte ch = input.popLE!ubyte();
            _name ~= ch;
        }

        int paramCount = input.popLE!int();

        foreach(int ip; 0..paramCount)
        {
            float f = input.popLE!float();

            // TODO: best-effort recovery?
            if (!isValidNormalizedParam(f))
                throw new Exception("Couldn't unserialize preset: an invalid float parameter was parsed");

            // There may be more parameters when downgrading
            if (ip < _normalizedParams.length)
                _normalizedParams[ip] = f;
        }
    }

    static bool isValidNormalizedParam(float f)
    {
        return (isFinite(f) && f >= 0 && f <= 1);
    }

private:
    string _name;
    float[] _normalizedParams;
}

/// A preset bank is a collection of presets
final class PresetBank
{
public:

    // Extends an array or Preset
    Preset[] presets;
    alias presets this;

    // Create a preset bank
    this(Client client, Preset[] presets_)
    {
        _client = client;
        presets = presets_;
        _current = 0;
    }

    deprecated void addPreset(Preset preset)
    {
        assert(false);
    }

    Preset preset(int i) nothrow @nogc
    {
        return presets[i];
    }

    int numPresets() nothrow @nogc
    {
        return cast(int)presets.length;
    }

    int currentPresetIndex() @nogc nothrow
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

    void loadPresetByNameFromHost(string name) nothrow
    {
        foreach(int index, preset; presets)
            if (preset.name == name)
                loadPresetFromHost(index);
    }

    void loadPresetFromHost(int index) nothrow
    {
        putCurrentStateInCurrentPreset();
        presets[index].loadFromHost(_client);
        _current = index;
    }

    /// Enqueue a new preset and load it
    void addNewDefaultPresetFromHost(string presetName) nothrow
    {
        float[] values;
        foreach(param; _client.params)
            values ~= param.getNormalizedDefault();
        presets ~= new Preset(presetName, values);
        loadPresetFromHost(cast(int)(presets.length) - 1);
    }

    /// Allocates and fill a preset chunk
    ubyte[] getPresetChunk(int index)
    {
        auto chunk = appender!(ubyte[])();
        writeChunkHeader(chunk);
        presets[index].serializeBinary(chunk);
        return chunk.data;
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
    ubyte[] getBankChunk() nothrow
    {
        putCurrentStateInCurrentPreset();
        auto chunk = appender!(ubyte[])();
        writeChunkHeader(chunk);

        // write number of presets
        chunk.writeLE!int(cast(int)(presets.length));

        foreach(int i, preset; presets)
            preset.serializeBinary(chunk);
        return chunk.data;
    }

    /// Parse a bank chunk and set parameters.
    /// May throw an Exception.
    void loadBankChunk(ubyte[] chunk)
    {
        checkChunkHeader(chunk);

        int numPresets = chunk.popLE!int();

        // TODO: is there a way to have a dynamic number of presets in the bank? Check with VST and AU
        numPresets = min(numPresets, presets.length);
        foreach(preset; presets[0..numPresets])
            preset.unserializeBinary(chunk);
    }

    /// Gets a chunk with current state
    ubyte[] getStateChunk() nothrow
    {
        auto chunk = appender!(ubyte[])();
        writeChunkHeader(chunk);

        auto params = _client.params();

        chunk.writeLE!int(_current);

        chunk.writeLE!int(cast(int)params.length);
        foreach(param; params)
            chunk.writeLE!float(param.getNormalized());
        return chunk.data;
    }

    /// Loads a chunk state, update current state.
    /// May throw an Exception.
    void loadStateChunk(ubyte[] chunk)
    {
        checkChunkHeader(chunk);

        // This avoid to overwrite the preset 0 while we modified preset N
        int presetIndex = chunk.popLE!int();
        if (!isValidPresetIndex(presetIndex))
            throw new Exception("Invalid preset index in state chunk");
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

    void writeChunkHeader(O)(auto ref O output) if (isOutputRange!(O, ubyte))
    {
        // write magic number and dplug version information (not the tag version)
        output.writeBE!uint(DPLUG_MAGIC);
        output.writeLE!int(DPLUG_SERIALIZATION_MAJOR_VERSION);
        output.writeLE!int(DPLUG_SERIALIZATION_MINOR_VERSION);

        // write plugin version
        output.writeLE!int(_client.getPluginVersion());
    }

    void checkChunkHeader(ref ubyte[] input)
    {
        // nothing to check with minor version
        uint magic = input.popBE!uint();
        if (magic !=  DPLUG_MAGIC)
            throw new Exception("Can not load, magic number didn't match");

        // nothing to check with minor version
        int dplugMajor = input.popLE!int();
        if (dplugMajor > DPLUG_SERIALIZATION_MAJOR_VERSION)
            throw new Exception("Can not load chunk done with a newer, incompatible dplug library");

        int dplugMinor = input.popLE!int();
        // nothing to check with minor version

        // TODO: how to handle breaking binary compatibility here?
        int pluginVersion = input.popLE!int();
    }
}
