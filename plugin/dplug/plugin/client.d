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
        buildLegalIO();
        buildParameters();

        _maxInputs = 0;
        _maxOutputs = 0;

        foreach(legalIO; _legalIOs)
        {
            if (_maxInputs < legalIO.numInputs)
                _maxInputs = legalIO.numInputs;
            if (_maxOutputs < legalIO.numOuputs)
                _maxOutputs = legalIO.numOuputs;
        }
    }

    int maxInputs()
    {
        return _maxInputs;
    }

    int maxOutputs()
    {
        return _maxInputs;
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

    /// Returns: true if index is a valid input index.
    final bool isValidInputIndex(int index)
    {
        return index >= 0 && index < maxInputs();
    }

    /// Returns: true if index is a valid output index.
    final bool isValidOutputIndex(int index)
    {
        return index >= 0 && index < maxOutputs();
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

    /// Override to declare the plugin properties.
    abstract Flags getFlags();

    /// Override to clear state state (eg: delay lines) and allocate buffers.
    abstract void reset(double sampleRate, size_t maxFrames);

    /// Process some audio.
    /// Override to make some noise.
    abstract void processAudio(double **inputs, double **outputs, int frames);

protected:

    /// Override this methods to implement parameter creation.
    /// See_also: addParameter.
    abstract void buildParameters();

    /// Adds a parameter.
    final addParameter(Parameter param)
    {
        _params ~= param;
    }

    /// Override this method to tell which I/O are legal.
    /// See_also: addLegalIO.
    abstract void buildLegalIO();

    /// Adds a legal I/O.
    final addLegalIO(int numInputs, int numOutputs)
    {
        _legalIOs ~= LegalIO(numInputs, numOutputs);
    }

private:
    Parameter[] _params;

    struct LegalIO
    {
        int numInputs;
        int numOuputs;
    }

    LegalIO[] _legalIOs;

    int _maxInputs, _maxOutputs; // maximum number of input/outputs
}

