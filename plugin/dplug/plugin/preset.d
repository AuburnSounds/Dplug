module dplug.plugin.preset;

import dplug.plugin.client;

/// A preset is a slot in a plugin preset list
class Preset
{
public:
    this(Client client, int index)
    {
        _client = client;
        _index = index;
    }

private:
    bool _initialized = false;
    Client _client;
    int _index;
    string name;
    float[] normalizedParams;
}

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

    Preset preset(int i)
    {
        return _presets[i];
    }

private:
    Client _client;
    Preset[] _presets;


}