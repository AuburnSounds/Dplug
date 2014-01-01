// See licenses/WDL_license.txt
module dplug.plugin.client;

import std.container;

/// Holds a plugin client parameter description and value.
struct Parameter
{
public:
    this(string name, float initialValue = 0)
    {
        _name = name;
    }

    @property void value(float x) pure nothrow
    {
        _value = x;
    }

    @property float value() pure const nothrow
    {
        return _value;
    }

    string name() pure const nothrow
    {
        return _name;
    }

private:
    string _name;
    float _value;
}

/// Generic plugin interface, from the client point of view.
/// Client wrappers owns one, so no inheritance needed.
struct Client
{
public:

    this(int uniqueID)
    {
        _uniqueID = uniqueID;
        _pluginVersion = 1000; // 1.0.0.0 by default
    }

    /// Returns: Array of parameters.
    ref Array!Parameter params()
    {
        return _params;
    }

    void addParameter(Parameter param)
    {
        _params.insertBack(param);
    }

    int uniqueID() pure const nothrow
    {
        return _uniqueID;
    }

    int pluginVersion() pure const nothrow
    {
        return _pluginVersion;
    }

protected:
    Array!Parameter _params;
    int _uniqueID; // VST specific
    uint _pluginVersion;
}

