/*
Cockos WDL License

Copyright (C) 2005 - 2015 Cockos Incorporated
Copyright (C) 2015 and later Auburn Sounds

Portions copyright other contributors, see each source file for more information

This software is provided 'as-is', without any express or implied warranty.  In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
1. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
1. This notice may not be removed or altered from any source distribution.
*/

/// Base client implementation.

module dplug.client.client;

import core.stdc.string;
import core.stdc.stdio;

import std.container;

import gfm.core;

import dplug.core.funcs;
import dplug.client.params;
import dplug.client.preset;
import dplug.client.midi;
import dplug.client.graphics;
import dplug.client.daw;


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
    DAW getDAW();
}

/// Describe the version of plugin.
struct PluginVersion
{
    int majorVersion;
    int minorVersion;
    int patchVersion;
}

// Statically known features of the plugin.
// There is some default for explanation purpose, but you really ought to override them all.
struct PluginInfo
{
    string vendorName = "Witty Audio Ltd.";
    string effectName = "Destructatorizer";
    string productName = "Destructatorizer";
    bool hasGUI = false;
    bool isSynth = false;

    /// While it seems no VST host use this ID as a unique
    /// way to identify a plugin, common wisdom is to try to
    /// get a sufficiently random one to avoid conflicts.
    int pluginID = CCONST('g', 'f', 'm', '0');

    // Plugin version in x.x.x.x decimal form.
    int pluginVersion = 1000;
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
        _info = buildPluginInfo();

        buildLegalIO();
        _params = buildParameters();
        // Create presets
        _presetBank = new PresetBank(this);
        buildPresets();

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

        // Must be done there rather than in
        // effEditOpen for some reason.
        // TODO: do it really lazily
        //createGraphicsLazily();

        _initialized = true;
    }

    ~this()
    {
        if (_initialized)
        {
            debug ensureNotInGC("dplug.plugin.Client");
            _initialized = false;

            // Destroy graphics
            if (_graphics !is null)
                _graphics.destroy();

            // Destroy parameters
            foreach(p; _params)
                p.destroy();
        }
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

    /// Returns: Array of presets.
    final PresetBank presetBank() nothrow @nogc
    {
        return _presetBank;
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
        createGraphicsLazily();
        assert(_graphics !is null);
        _graphics.openUI(parentInfo, _hostCommand.getDAW());
    }

    final bool getGUISize(int* width, int* height)
    {
        createGraphicsLazily();
        if (_graphics)
        {
            _graphics.getGUISize(width, height);
            return true;
        }
        else
            return false;
    }

    /// ditto
    final void closeGUI()
    {
        _graphics.closeUI();
    }

    // This should be called only by a client implementation
    void setParameterFromHost(int index, float value) nothrow @nogc
    {
        param(index).setFromHost(value);
    }

    /// Override if you create a plugin with UI.
    IGraphics createGraphics()
    {
        return null;
    }

    // Getter for the IGraphics interface
    final IGraphics graphics() nothrow @nogc
    {
        return _graphics;
    }

    // Getter for the IHostCommand interface
    final IHostCommand hostCommand()
    {
        return _hostCommand;
    }

    /// Override to clear state (eg: resize and clear delay lines) and allocate buffers.
    /// Important: This will be called by the audio thread.
    ///            So you should not use the GC in this callback.
    abstract void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc;

    /// Override to set the plugin latency in samples.
    /// Unfortunately most of the time latency is dependent on the sampling rate and frequency,
    /// but most hosts don't support latency changes.
    int latencySamples() pure const nothrow /// Returns: Plugin latency in samples.
    {
        return 0;
    }

    /// Override to declare the maximum number of samples to accept
    /// If greater, the audio buffers will be splitted up.
    /// This splitting have several benefits:
    /// - help allocating temporary audio buffers on the stack
    /// - keeps memory usage low and reuse it
    /// - allow faster-than-buffer-size parameter changes
    /// Returns: Maximum number of samples
    int maxFramesInProcess() pure const nothrow @nogc
    {
        return 0; // default returns 0 which means "do not split"
    }

    /// Process incoming MIDI messages.
    /// This is called before processAudio for each message.
    /// Override to do something with them;
    /// TODO: this does not currently work with the buffer split.
    void processMidiMsg(MidiMessage message) nothrow @nogc
    {
        // Default behaviour: do nothing.
    }

    /// Process some audio.
    /// Override to make some noise.
    /// In processAudio you are always guaranteed to get valid pointers
    /// to all the channels the plugin requested.
    /// Unconnected input pins are zeroed.
    /// Important: This will be called by the audio thread.
    ///            You should not use the GC in this callback.
    ///
    /// Number of frames are guaranteed to be less or equal to what the last reset() call said.
    /// Number of inputs and outputs are guaranteed to be exactly what the last reset() call said.
    /// Warning: Do not modify the pointers!
    abstract void processAudio(const(double*)[] inputs, double*[]outputs, int frames) nothrow @nogc;

    // for plugin client implementations only
    final void setHostCommand(IHostCommand hostCommand)
    {
        _hostCommand = hostCommand;
    }

    /// Returns a new default preset.
    final Preset makeDefaultPreset()
    {
        float[] values;
        foreach(param; _params)
            values ~= param.getNormalizedDefault();
        return new Preset("Default", values);
    }

    // Getters for fields in _info

    final bool hasGUI() pure const nothrow @nogc
    {
        return _info.hasGUI;
    }

    final bool isSynth() pure const nothrow @nogc
    {
        return _info.isSynth;
    }

    final string effectName() pure const nothrow @nogc
    {
        return _info.effectName;
    }

    final string vendorName() pure const nothrow @nogc
    {
        return _info.vendorName;
    }

    final string productName() pure const nothrow @nogc
    {
        return _info.productName;
    }

    /// Returns: Plugin version in x.x.x.x decimal form.
    final int getPluginVersion() pure const nothrow @nogc
    {
        return _info.pluginVersion;
    }

    /// Returns: Plugin ID.
    final int getPluginID() pure const nothrow @nogc
    {
        return _info.pluginID;
    }

protected:

    /// Override this method to implement parameter creation.
    /// This is an optional overload, default implementation declare no parameters.
    Parameter[] buildParameters()
    {
        return [];
    }

    /// Override this methods to load/fill presets.
    /// See_also: addPreset.
    void buildPresets()
    {
        presetBank.addPreset(makeDefaultPreset());
    }

    /// Override this method to tell what plugin you are.
    /// Mandatory override, fill the fields with care.
    abstract PluginInfo buildPluginInfo();

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

    PluginInfo _info;

private:
    Parameter[] _params;

    PresetBank _presetBank;

    struct LegalIO
    {
        int numInputs;
        int numOuputs;
    }

    LegalIO[] _legalIOs;

    int _maxInputs, _maxOutputs; // maximum number of input/outputs

    InputPin[] _inputPins;
    OutputPin[] _outputPins;

    final void createGraphicsLazily()
    {
        // First GUI opening create the graphics object
        if ( (_graphics is null) && hasGUI())
        {
            _graphics = createGraphics();
            assert(_graphics !is null); // don't forget to override the createGraphics method
        }
    }

    bool _initialized; // destructor flag
}

