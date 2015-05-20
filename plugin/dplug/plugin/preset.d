module dplug.plugin.preset;

import std.range;
import std.math;
import std.array;

import binrange;

import dplug.plugin.client;


// I can see no reason why dplug shouldn't be able to maintain 
// backward-compatibility with older version in the future.
// However, never say never.
// This number will be incremented for backward-incompatible changes.
enum int DPLUG_SERIALIZATION_MAJOR_VERSION = 0; 

// This number will be incremented for backward-compatible change.
enum int DPLUG_SERIALIZATION_MINOR_VERSION = 0; 

/// A preset is a slot in a plugin preset list
class Preset
{
public:
    this(string name, float[] normalizedParams)
    {
        _name = name;
        _normalizedParams = normalizedParams;
    }

    string name()
    {
        return _name;
    }

    string name(string newName)
    {
        return _name = newName;
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

    void deserializeBinary(O)(float defaultValue, auto ref O input) if (isInputRange!O)
    {
        _name = "";
        int nameLength = input.popLE!int();
        _name.length = nameLength;
        foreach(i; 0..nameLength)
            _name[i] = input.popLE!ubyte();

        foreach(ref np; _normalizedParams)
        {
            float f = input.popLE!float();
            if (isValidNormalizedParam(f))
                np = f;                
            else
            {
                // In case of error, silently fallback on the default value.
                // TODO: is this a good idea?
                np = defaultValue;
            }
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
class PresetBank
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

    void loadPresetFromHost(int index)
    {
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
        auto chunk = appender!(ubyte[])();
        writeChunkHeader(chunk);

        // write number of presets
        chunk.writeLE!int(cast(int)(presets.length));

        foreach(int i, preset; presets)
            preset.serializeBinary(chunk);
        return null;
    }    

private:
    Client _client;
    int _current; // should this be only in VST client?

    void serializeBinary(O)(auto ref O output) if (isOutputRange!O)
    {
        foreach(preset; presets)
            preset.serializeBinary(output);
    }

    void deserializeBinary(O)(auto ref O input) if (isInputRange!O)
    {
        foreach(int i, preset; presets)
        {
            float defaultValue = _client.param(i).getNormalizedDefault();
            preset.deserializeBinary(input);
        }
    }

    void writeChunkHeader(O)(auto ref O output) if (isOutputRange!(O, ubyte))
    {
        // write magic number
        enum uint DPLUG_MAGIC = 0xB20BA92;
        output.writeBE!uint(DPLUG_MAGIC);
        output.writeLE!int(DPLUG_SERIALIZATION_MAJOR_VERSION);
        output.writeLE!int(DPLUG_SERIALIZATION_MINOR_VERSION);

        // write plugin version
        output.writeLE!int(_client.getPluginVersion());
    }
}