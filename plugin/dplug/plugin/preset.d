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

private:
    string _name;
    float[] _normalizedParams;
}
/*
/// A preset bank is a collection of presets
class PresetBank
{
public:
    this(Client client, int numPresets)
    {
        _client = client;
        for (int i = 0; i < numPresets; ++i)
            _presets[i] = new Preset(client, i);
    }

    void addPreset(Preset preset)
    {
        _presets ~= preset;
    }

    Preset preset(int i)
    {
        return _presets[i];
    }

private:
    Client _client;
    Preset[] _presets;


}
*/