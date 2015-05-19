module dplug.plugin.preset;

import std.range;
import std.math;

import binrange;

import dplug.plugin.client;


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

    void serializeBinary(O)(auto ref O output) if (isOutputRange!O)
    {
        foreach(np; _normalizedParams)
            output.writeLE!float(np);
    }

    void deserializeBinary(O)(float defaultValue, auto ref O input) if (isInputRange!O)
    {
        foreach(ref np; _normalizedParams)
        {
            float f = popLE!float(input);
            if (isValidNormalizedParam(f))
            {
                np = f;                
            }
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

private:
    Client _client;
    int _current; // should this be only in VST client?
}