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



/// Plugin interface, from the client point of view.
/// Client wrappers owns one.
/// User plugins derivate from this class.
class Client
{
public:

    alias Flags = int;
    enum : Flags
    {
        IsSynth = 1,
        HasGUI  = 2
    }

    this()
    {
        buildParameters();
    }

    /// Returns: Array of parameters.
    final Parameter[] params()
    {
        return _params;
    }

    /// Returns: The parameter indexed by index.
    final Parameter param(size_t index)
    {
        return _params[index];
    }

    /// Returns: true if index is a valid parameter index.
    final bool isValidParamIndex(int index)
    {
        return index >= 0 && index < _params.length;
    }

    /// Override this methods to implement a GUI.
    void onOpenGUI()
    {
    }

    /// ditto
    void onCloseGUI()
    {
    }

    /// Override this method to give a plugin ID.
    /// While it seems no VST host use this ID as a unique
    /// way to identify a plugin, common wisdom is to try to 
    /// get a sufficiently random one to avoid conflicts.
    abstract int getPluginID();

    /// Returns: Plugin version in x.x.x.x decimal form.
    int getPluginVersion()
    {
        return 1000;
    }

    /// Override to declare the plugin properties
    abstract Flags getFlags();

    void reset(double sampleRate, size_t maxFrames)
    {
    }

protected:

    /// Override this methods to implement parameter creation.
    /// See_also: addParameter.
    abstract void buildParameters();

    final addParameter(Parameter param)
    {
        _params ~= param;
    }


    void ProcessAudio(float** inouts)
    {
    }

private:
    Parameter[] _params;
}

