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
    this(string name, float[] normalizedParams)
    {
        _name = name;
        _normalizedParams = normalizedParams;
    }

    void setNormalized(int paramIndex, float value)
    {
        _normalizedParams[paramIndex] = value;
    }

    string name()
    {
        return _name;
    }

    string name(string newName)
    {
        return _name = newName;
    }

    void saveFromHost(Client client)
    {
        auto params = client.params();
        foreach(int i, param; params)
        {
            _normalizedParams[i] = param.getNormalized();
        }
    }

    void loadFromHost(Client client)
    {
        auto params = client.params();
        foreach(int i, param; params)
            param.setFromHost(_normalizedParams[i]);
    }

    void serializeBinary(O)(auto ref O output) if (isOutputRange!(O, ubyte))
    {
        foreach(np; _normalizedParams)
            output.writeLE!int(cast(int)_name.length);
        foreach(i; 0..name.length)
            output.writeLE!ubyte(_name[i]);

        foreach(np; _normalizedParams)
            output.writeLE!float(np);
    }

    void unserializeBinary(ref ubyte[] input)
    {
        _name = "";
        int nameLength = input.popLE!int();
        _name.reserve(nameLength);
        foreach(i; 0..nameLength)
            _name ~= input.popLE!ubyte();

        foreach(ref np; _normalizedParams)
        {
            float f = input.popLE!float();
            if (isValidNormalizedParam(f))
                np = f;
            else
                throw new Exception("Couldn't unserialize preset: an invalid float parameter was parsed");
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


    // Initially empty
    this(Client client)
    {
        _client = client;
        _current = 0;
    }

    void addPreset(Preset preset)
    {
        presets ~= preset;
    }

    Preset preset(int i)
    {
        return presets[i];
    }

    int numPresets()
    {
        return cast(int)presets.length;
    }

    int currentPresetIndex() @nogc nothrow
    {
        return _current;
    }

    Preset currentPreset()
    {
        int ind = currentPresetIndex();
        if (!isValidPresetIndex(ind))
            return null;
        return presets[ind];
    }

    bool isValidPresetIndex(int index)
    {
        return index >= 0 && index < numPresets();
    }

    // Save current state to current preset. This updates the preset bank to reflect the state change.
    // This will be unnecessary once we haver internal preset management.
    void putCurrentStateInCurrentPreset()
    {        
        presets[_current].saveFromHost(_client);
    }

    void loadPresetFromHost(int index)
    {
        putCurrentStateInCurrentPreset();
        presets[index].loadFromHost(_client);
        _current = index;
    }

    /// Allocates and fill a preset chunk
    ubyte[] getPresetChunk(int index)
    {
        auto chunk = appender!(ubyte[])();
        writeChunkHeader(chunk);
        presets[index].serializeBinary(chunk);
        return chunk.data;
    }

    /// Allocate and fill a bank chunk
    ubyte[] getBankChunk()
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

    /// Parse a bank chunk and set parameters.
    /// May throw an Exception.
    void loadBankChunk(ubyte[] chunk)
    {
        checkChunkHeader(chunk);

        int numPresets = chunk.popLE!int();

        // TODO: is there a way to have a dynamic number of presets in VST?
        numPresets = min(numPresets, presets.length);
        foreach(preset; presets[0..numPresets])
            preset.unserializeBinary(chunk);
    }

private:
    Client _client;
    int _current; // should this be only in VST client?

    void serializeBinary(O)(auto ref O output) if (isOutputRange!O)
    {
        foreach(preset; presets)
            preset.serializeBinary(output);
    }

    void unserializeBinary(I)(auto ref I input) if (isInputRange!O)
    {
        foreach(int i, preset; presets)
        {
            float defaultValue = _client.param(i).getNormalizedDefault();
            preset.deserializeBinary(input);
        }
    }

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
