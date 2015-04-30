// See licenses/WDL_license.txt

/// Base client implementation.

module dplug.plugin.client;

import std.container;
import core.stdc.string;
import core.stdc.stdio;

import dplug.plugin.params;
import dplug.plugin.graphics;


class InputPin
{
public:
    this()
    {
        _isConnected = false;
    }

    bool isConnected() pure const nothrow
    {
        return _isConnected;
    }

private:
    bool _isConnected;
}

class OutputPin
{
public:
    this()
    {
        _isConnected = false;
    }

    bool isConnected() pure const nothrow
    {
        return _isConnected;
    }

private:
    bool _isConnected;
}


/// A plugin client can send commands to the host.
/// This interface is injected after the client creation though.
interface IHostCommand
{
    void beginParamEdit(int paramIndex);
    void paramAutomate(int paramIndex, float value);
    void endParamEdit(int paramIndex);
    bool requestResize(int width, int height);
}



/// Plugin interface, from the client point of view.
/// This client has no knowledge of thread-safety, it must be handled externally.
/// User plugins derivate from this class.
/// Plugin formats wrappers owns one dplug.plugin.Client as a member.
class Client
{
public:

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

        _inputPins.length = _maxInputs;
        for (int i = 0; i < _maxInputs; ++i)
            _inputPins[i] = new InputPin();

        _outputPins.length = _maxOutputs;
        for (int i = 0; i < _maxOutputs; ++i)
            _outputPins[i] = new OutputPin();

        _graphics = createGraphics();
    }

    final int maxInputs() pure const nothrow @nogc
    {
        return _maxInputs;
    }

    final int maxOutputs() pure const nothrow @nogc
    {
        return _maxInputs;
    }

    /// Returns: Array of parameters.
    final Parameter[] params() nothrow @nogc
    {
        return _params;
    }

    /// Returns: The parameter indexed by index.
    final Parameter param(int index) nothrow @nogc
    {
        return _params[index];
    }

    /// Returns: true if index is a valid parameter index.
    final bool isValidParamIndex(int index) nothrow @nogc
    {
        return index >= 0 && index < _params.length;
    }

    /// Returns: true if index is a valid input index.
    final bool isValidInputIndex(int index) nothrow @nogc
    {
        return index >= 0 && index < maxInputs();
    }

    /// Returns: true if index is a valid output index.
    final bool isValidOutputIndex(int index) nothrow @nogc
    {
        return index >= 0 && index < maxOutputs();
    }

    /// Sets the number of used input channels.
    final bool setNumUsedInputs(int numInputs) nothrow @nogc
    {
        int max = maxInputs();
        if (numInputs > max)
            return false;
        for (int i = 0; i < max; ++i)
            _inputPins[i]._isConnected = (i < numInputs);
        return true;
    }

    /// Sets the number of used output channels.
    final bool setNumUsedOutputs(int numOutputs) nothrow @nogc
    {
        int max = maxOutputs();
        if (numOutputs > max)
            return false;
        for (int i = 0; i < max; ++i)
            _outputPins[i]._isConnected = (i < numOutputs);
        return true;
    }

    /// Override this methods to implement a GUI.
    final void openGUI(void* parentInfo)
    {
        _graphics.openUI(parentInfo);
    }

    /// ditto
    final void closeGUI()
    {
        _graphics.closeUI();
    }

    // This should be called only by a client implementation
    void setParameterFromHost(int index, float value)
    {
        if (hasGUI())
        {
            // TODO warn the GUI
        }

        param(index).setFromHost(value);
    }

    void setParameterFromGUI(int index, float value)
    {
        param(index).setFromGUI(value);
        _hostCommand.paramAutomate(index, value);
    }

    /// Override and return your brand name.
    string vendorName() pure const nothrow
    {
        return "Witty Audio LTD";
    }

    /// Override and return your product name.
    string productName() pure const nothrow
    {
        return "Destructatorizer";
    }

    /// Override this method to give a plugin ID.
    /// While it seems no VST host use this ID as a unique
    /// way to identify a plugin, common wisdom is to try to
    /// get a sufficiently random one to avoid conflicts.
    abstract int getPluginID() pure const nothrow;

    /// Returns: Plugin version in x.x.x.x decimal form.
    int getPluginVersion() pure const nothrow
    {
        return 1000;
    }

    /// Override to choose whether the plugin is a synth.
    abstract bool isSynth() pure const nothrow;
    
    /// Override and return something else to make a plugin with UI.
    IGraphics createGraphics()
    {
        return new NullGraphics();
    }

    final bool hasGUI()
    {
        return cast(NullGraphics)_graphics is null;        
    }

    // Getter for the IGraphics interface
    final IGraphics graphics()
    { 
        return _graphics;
    }

    // Getter for the IHostCommand interface
    final IHostCommand hostCommand()
    {
        return _hostCommand;
    }


    /// Override to clear state state (eg: delay lines) and allocate buffers.
    /// Important: This will be called by the audio thread.
    ///            You should not use the GC in this callback.
    ///            But you can use malloc.
    abstract void reset(double sampleRate, int maxFrames) nothrow @nogc;

    /// Override to set the plugin latency in samples.
    /// Most of the time this is dependant on the sampling rate, but most host
    /// don't support latency changes.
    int latencySamples() pure const nothrow /// Returns: Plugin latency in samples.
    {
        return 0;
    }

    /// Process some audio.
    /// Override to make some noise.
    /// In processAudio you are always guaranteed to get valid pointers
    /// to all the channels the plugin requested.
    /// Unconnected input pins are zeroed.
    /// Important: This will be called by the audio thread.
    ///            You should not use the GC in this callback.
    abstract void processAudio(double **inputs, double **outputs, int frames) nothrow @nogc;

    // for plugin client implementations only
    final void setHostCommand(IHostCommand hostCommand)
    {
        _hostCommand = hostCommand;
    }

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

    IGraphics _graphics;

    IHostCommand _hostCommand;

private:
    Parameter[] _params;

    struct LegalIO
    {
        int numInputs;
        int numOuputs;
    }

    LegalIO[] _legalIOs;

    int _maxInputs, _maxOutputs; // maximum number of input/outputs

    InputPin[] _inputPins;
    OutputPin[] _outputPins;
}

