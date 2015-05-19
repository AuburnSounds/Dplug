module dplug.plugin.preset;

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

private:
    Client _client;
    int _current; // should this be only in VST client?
}