// See licenses/WDL_license.txt
module dplug.plugin.client;

import std.container;
import core.stdc.string;
import core.stdc.stdio;

/// Holds a plugin client parameter description and value.
class Parameter
{
public:
    this(string name, string label, float defaultValue = 0)
    {
        _name = name;
        _value = defaultValue;
    }

    @property void set(float x) pure nothrow
    {
        _value = x;
    }

    @property float get() pure const nothrow
    {
        return _value;
    }

    string name() pure const nothrow
    {
        return _name;
    }

    string label() pure const nothrow
    {
        return _label;
    }

    void toStringN(char* buffer, size_t numBytes)
    {
        snprintf(buffer, numBytes, "%2.2f", _value);
    }

private:
    string _name;  // eg: "Gain", "Drive"
    string _label; // eg: "sec", "dB", "%"
    float _value;
}

/// Generic plugin interface, from the client point of view.
/// Client wrappers owns one, so no inheritance needed.
class Client
{
public:

    this(int uniqueID)
    {
        _uniqueID = uniqueID;
        _pluginVersion = 1000; // 1.0.0.0 by default
    }

    /// Returns: Array of parameters.
    Parameter[] params()
    {
        return _params;
    }

    Parameter param(size_t index)
    {
        return _params[index];
    }

    bool isValidParamIndex(int index)
    {
        return index >= 0 && index < _params.length;
    }

    void addParameter(Parameter param)
    {
        _params ~= param;
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
    Parameter[] _params;
    int _uniqueID; // VST specific
    uint _pluginVersion;
}

