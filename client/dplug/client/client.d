/*
Cockos WDL License

Copyright (C) 2005 - 2015 Cockos Incorporated
Copyright (C) 2015 - 2017 Auburn Sounds

Portions copyright other contributors, see each source file for more information

This software is provided 'as-is', without any express or implied warranty.  In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
1. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
1. This notice may not be removed or altered from any source distribution.
*/

/// Base client implementation. Every plugin format implementation hold a `Client` member.
module dplug.client.client;

import core.atomic;
import core.stdc.string;
import core.stdc.stdio;

import std.container;

import dplug.core.nogc;
import dplug.core.math;
import dplug.core.alignedbuffer;

import dplug.client.params;
import dplug.client.preset;
import dplug.client.midi;
import dplug.client.graphics;
import dplug.client.daw;


version = lazyGraphicsCreation;

/// A plugin client can send commands to the host.
/// This interface is injected after the client creation though.
interface IHostCommand
{
nothrow @nogc:
    void beginParamEdit(int paramIndex);
    void paramAutomate(int paramIndex, float value);
    void endParamEdit(int paramIndex);
    bool requestResize(int width, int height);
    DAW getDAW();
}

// Plugin version in major.minor.patch form.
struct PluginVersion
{
    int major;
    int minor;
    int patch;

    int toVSTVersion() pure const nothrow @nogc
    {
        assert(major < 10 && minor < 10 && patch < 10);
        return major * 1000 + minor * 100 + patch*10;
    }

    int toAUVersion() pure const nothrow @nogc
    {
        assert(major < 256 && minor < 256 && patch < 256);
        return (major << 16) | (minor << 8) | patch;
    }

    int toAAXPackageVersion() pure const nothrow @nogc
    {
        // For AAX, considered binary-compatible unless major version change
        return major;
    }
}


// Statically known features of the plugin.
// There is some default for explanation purpose, but you really ought to override them all.
// Most of it is redundant with plugin.json, in the future the JSON will be parsed instead.
struct PluginInfo
{
    string vendorName = "Witty Audio";

    /// Used in AU only.
    char[4] vendorUniqueID = "Wity";

    string pluginName = "Destructatorizer";

    /// Used for both VST and AU.
    /// In AU it is namespaced by the manufacturer. In VST it
    /// should be unique. While it seems no VST host use this
    /// ID as a unique way to identify a plugin, common wisdom
    /// is to try to get a sufficiently random one.
    char[4] pluginUniqueID = "WiDi";

    // Plugin version information. 
    // It's important that the version you fill at runtime is identical to the
    // one in `plugin.json` else you won't pass AU validation.
    //
    // Note: For AU, 0.x.y is supposed to mean "do not cache", however it is
    //       unknown what it actually changes. AU caching hasn't caused any problem
    //       and can probably be ignored.
    deprecated("Use publicVersion instead") alias pluginVersion = publicVersion;
    PluginVersion publicVersion = PluginVersion(0, 0, 0);

    /// True if the plugin has a graphical UI. Easy way to disable it.
    bool hasGUI = false;

    /// True if the plugin "is a synth". This has only a semantic effect.
    bool isSynth = false;

    /// True if the plugin should receive MIDI events.
    /// Warning: receiving MIDI forces you to call `getNextMidiMessages`
    /// with the right number of `frames`, every buffer.
    bool receivesMIDI = false;

    /// Used for being at the right place in list of plug-ins.
    PluginCategory category;
}

/// This allows to write things life tempo-synced LFO.
struct TimeInfo
{
    /// BPM
    double tempo = 120;

    /// Current time from the beginning of the song in samples.
    long timeInSamples = 0;

    /// Whether the host sequencer is currently playing
    bool hostIsPlaying;
}

/// Describe a combination of input channels count and output channels count
struct LegalIO
{
    int numInputChannels;
    int numOutputChannels;
}

/// Plugin interface, from the client point of view.
/// This client has no knowledge of thread-safety, it must be handled externally.
/// User plugins derivate from this class.
/// Plugin formats wrappers owns one dplug.plugin.Client as a member.
class Client
{
public:
nothrow:
@nogc:

    this()
    {
        _info = buildPluginInfo();

        // Create legal I/O combinations
        _legalIOs = buildLegalIO();

        // Create parameters.
        _params = buildParameters();

        // Check parameter consistency
        // This avoid mistake when adding/reordering parameters in a plugin.
        foreach(int i, Parameter param; _params)
        {
            // If you fail here, this means your buildParameter() override is incorrect.
            // Check the values of the index you're giving.
            // They should be 0, 1, 2, ..., N-1
            // Maybe you have duplicated a line or misordered them.
            assert(param.index() == i);

            // Sets owner reference.
            param.setClientReference(this);
        }

        // Create presets
        _presetBank = mallocNew!PresetBank(this, buildPresets());


        _maxFramesInProcess = maxFramesInProcess();

        _maxInputs = 0;
        _maxOutputs = 0;
        foreach(legalIO; _legalIOs)
        {
            if (_maxInputs < legalIO.numInputChannels)
                _maxInputs = legalIO.numInputChannels;
            if (_maxOutputs < legalIO.numOutputChannels)
                _maxOutputs = legalIO.numOutputChannels;
        }

        version (lazyGraphicsCreation) {}
        else
        {
            createGraphicsLazily();
        }

        _midiQueue = makeMidiQueue();
    }

    ~this()
    {
        // Destroy graphics
        if (_graphics !is null)
        {
            // Acquire _graphicsIsAvailable forever
            // so that it's the last time the audio uses it,
            // and we can wait for its exit in _graphics destructor
            while(!cas(&_graphicsIsAvailable, true, false))
            {
                // MAYDO: relax CPU
            }
            _graphics.destroyFree();
        }

        // Destroy presets
        _presetBank.destroyFree();

        // Destroy parameters
        foreach(p; _params)
            p.destroyFree();
        _params.freeSlice();
        _legalIOs.freeSlice();
    }

    final int maxInputs() pure const nothrow @nogc
    {
        return _maxInputs;
    }

    final int maxOutputs() pure const nothrow @nogc
    {
        return _maxOutputs;
    }

    /// Returns: Array of parameters.
    final inout(Parameter[]) params() inout nothrow @nogc
    {
        return _params;
    }

    /// Returns: Array of legal I/O combinations.
    final LegalIO[] legalIOs() nothrow @nogc
    {
        return _legalIOs;
    }

    /// Returns: true if the following I/O combination is a legal one.
    ///          < 0 means "do not check"
    final bool isLegalIO(int numInputChannels, int numOutputChannels) pure const nothrow @nogc
    {
        foreach(io; _legalIOs)
            if  ( ( (numInputChannels < 0)
                    ||
                    (io.numInputChannels == numInputChannels) )
                  &&
                  ( (numOutputChannels < 0)
                    ||
                    (io.numOutputChannels == numOutputChannels) )
                )
                return true;

        return false;
    }

    /// Returns: Array of presets.
    final PresetBank presetBank() nothrow @nogc
    {
        return _presetBank;
    }

    /// Returns: The parameter indexed by index.
    final inout(Parameter) param(int index) inout nothrow @nogc
    {
        return _params.ptr[index];
    }

    /// Returns: true if index is a valid parameter index.
    final bool isValidParamIndex(int index) const nothrow @nogc
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

    // Note: openGUI, getGUISize and closeGUI are guaranteed
    // synchronized by the client implementation
    final void* openGUI(void* parentInfo, void* controlInfo, GraphicsBackend backend) nothrow @nogc
    {
        createGraphicsLazily();
        return (cast(IGraphics)_graphics).openUI(parentInfo, controlInfo, _hostCommand.getDAW(), backend);
    }

    final bool getGUISize(int* width, int* height) nothrow @nogc
    {
        createGraphicsLazily();
        auto graphics = (cast(IGraphics)_graphics);
        if (graphics)
        {
            graphics.getGUISize(width, height);
            return true;
        }
        else
            return false;
    }

    /// ditto
    final void closeGUI() nothrow @nogc
    {
        (cast(IGraphics)_graphics).closeUI();
    }

    // This should be called only by a client implementation.
    void setParameterFromHost(int index, float value) nothrow @nogc
    {
        param(index).setFromHost(value);
    }

    /// Override if you create a plugin with UI.
    /// The returned IGraphics must be allocated with `mallocEmplace`.
    IGraphics createGraphics() nothrow @nogc
    {
        return null;
    }

    /// Getter for the IGraphics interface
    /// This is intended for the audio thread and has acquire semantics.
    /// Not reentrant! You can't call this twice without a graphicsRelease first.
    /// Returns: null if feedback from audio thread is not welcome.
    final IGraphics graphicsAcquire() nothrow @nogc
    {
        if (cas(&_graphicsIsAvailable, true, false))
            return _graphics;
        else
            return null;
    }

    /// Mirror function to release the IGraphics from the audio-thread.
    /// Do not call if graphicsAcquire() returned `null`.
    final void graphicsRelease() nothrow @nogc
    {
        // graphicsAcquire should have been called before
        // MAYDO: which memory order here? Don't looks like we need a barrier.
        atomicStore(_graphicsIsAvailable, true);
    }

    // Getter for the IHostCommand interface
    final IHostCommand hostCommand() nothrow @nogc
    {
        return _hostCommand;
    }

    /// Override to clear state (eg: resize and clear delay lines) and allocate buffers.
    /// Important: This will be called by the audio thread.
    ///            So you should not use the GC in this callback.
    abstract void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc;

    /// Override to set the plugin latency in samples.
    /// Plugin latency can depend on `sampleRate` but no other value.
    /// If you want your latency to depend on a `Parameter` your only choice is to
    /// pessimize the needed latency and compensate in the process callback.
    /// Returns: Plugin latency in samples.
    int latencySamples(double sampleRate) pure const nothrow @nogc
    {
        return 0; // By default, no latency introduced by plugin
    }

    /// Override to set the plugin tail length in seconds.
    /// This is the amount of time before silence is reached with a silent input.
    /// Returns: Plugin tail size in seconds.
    float tailSizeInSeconds() pure const nothrow @nogc
    {
        return 0.100f; // default: 100ms
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

    /// Process some audio.
    /// Override to make some noise.
    /// In processAudio you are always guaranteed to get valid pointers
    /// to all the channels the plugin requested.
    /// Unconnected input pins are zeroed.
    /// This callback is the only place you may call `getNextMidiMessages()` (it is
    /// even required for plugins receiving MIDI).
    ///
    /// Number of frames are guaranteed to be less or equal to what the last reset() call said.
    /// Number of inputs and outputs are guaranteed to be exactly what the last reset() call said.
    /// Warning: Do not modify the pointers!
    abstract void processAudio(const(float*)[] inputs,    // array of input channels
                               float*[] outputs,           // array of output channels
                               int frames,                // number of sample in each input & output channel
                               TimeInfo timeInfo          // time information associated with this signal frame
                               ) nothrow @nogc;

    /// Should only be called in `processAudio`.
    /// This return a slice of MIDI messages corresponding to the next `frames` samples.
    /// Useful if you don't want to process messages every samples, or every split buffer.
    final const(MidiMessage)[] getNextMidiMessages(int frames) nothrow @nogc
    {
        return _midiQueue.getNextMidiMessages(frames);
    }

    /// Returns a new default preset.
    final Preset makeDefaultPreset() nothrow @nogc
    {
        // MAYDO: use mallocSlice for perf
        auto values = makeVec!float();
        foreach(param; _params)
            values.pushBack(param.getNormalizedDefault());
        return mallocNew!Preset("Default", values.releaseData);
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

    final bool receivesMIDI() pure const nothrow @nogc
    {
        return _info.receivesMIDI;
    }

    final string vendorName() pure const nothrow @nogc
    {
        return _info.vendorName;
    }

    final char[4] getVendorUniqueID() pure const nothrow @nogc
    {
        return _info.vendorUniqueID;
    }

    final string pluginName() pure const nothrow @nogc
    {
        return _info.pluginName;
    }

    /// Returns: Plugin "unique" ID.
    final char[4] getPluginUniqueID() pure const nothrow @nogc
    {
        return _info.pluginUniqueID;
    }

    /// Returns: Plugin full name "$VENDOR $PRODUCT"
    final void getPluginFullName(char* p, int bufLength) const nothrow @nogc
    {
        snprintf(p, bufLength, "%.*s %.*s",
                 _info.vendorName.length, _info.vendorName.ptr,
                 _info.pluginName.length, _info.pluginName.ptr);
    }

    /// Returns: Plugin version in x.x.x.x decimal form.
    deprecated("Use getPublicVersion instead") alias getPluginVersion = getPublicVersion;
    final PluginVersion getPublicVersion() pure const nothrow @nogc
    {
        return _info.publicVersion;
    }

    /// Boilerplate function to get the value of a `FloatParameter`, for use in `processAudio`.
    final float readFloatParamValue(int paramIndex) nothrow @nogc
    {
        auto p = param(paramIndex);
        assert(cast(FloatParameter)p !is null); // check it's a FloatParameter
        return unsafeObjectCast!FloatParameter(p).valueAtomic();
    }

    /// Boilerplate function to get the value of an `IntParameter`, for use in `processAudio`.
    final int readIntegerParamValue(int paramIndex) nothrow @nogc
    {
        auto p = param(paramIndex);
        assert(cast(IntegerParameter)p !is null); // check it's an IntParameter
        return unsafeObjectCast!IntegerParameter(p).valueAtomic();
    }

    final int readEnumParamValue(int paramIndex) nothrow @nogc
    {
        auto p = param(paramIndex);
        assert(cast(EnumParameter)p !is null); // check it's an EnumParameter
        return unsafeObjectCast!EnumParameter(p).valueAtomic();
    }

    /// Boilerplate function to get the value of a `BoolParameter`,for use in `processAudio`.
    final bool readBoolParamValue(int paramIndex) nothrow @nogc
    {
        auto p = param(paramIndex);
        assert(cast(BoolParameter)p !is null); // check it's a BoolParameter
        return unsafeObjectCast!BoolParameter(p).valueAtomic();
    }

    /// For plugin format clients only.
    final void setHostCommand(IHostCommand hostCommand) nothrow @nogc
    {
        _hostCommand = hostCommand;
    }

    /// For plugin format clients only.
    /// Enqueues an incoming MIDI message.
    void enqueueMIDIFromHost(MidiMessage message)
    {
        _midiQueue.enqueue(message);
    }

    /// For plugin format clients only.
    /// Calls processAudio repeatedly, splitting the buffers.
    /// Splitting allow to decouple memory requirements from the actual host buffer size.
    /// There is few performance penalty above 512 samples.
    void processAudioFromHost(float*[] inputs,
                              float*[] outputs,
                              int frames,
                              TimeInfo timeInfo
                              ) nothrow @nogc
    {

        if (_maxFramesInProcess == 0)
        {
            processAudio(inputs, outputs, frames, timeInfo);
        }
        else
        {
            // Slice audio in smaller parts
            while (frames > 0)
            {
                // Note: the last slice will be smaller than the others
                int sliceLength = frames;
                if (sliceLength > _maxFramesInProcess)
                    sliceLength = _maxFramesInProcess;

                processAudio(inputs, outputs, sliceLength, timeInfo);

                // offset all input buffer pointers
                for (int i = 0; i < cast(int)inputs.length; ++i)
                    inputs[i] = inputs[i] + sliceLength;

                // offset all output buffer pointers
                for (int i = 0; i < cast(int)outputs.length; ++i)
                    outputs[i] = outputs[i] + sliceLength;

                frames -= sliceLength;

                // timeInfo must be updated
                timeInfo.timeInSamples += sliceLength;
            }
            assert(frames == 0);
        }
    }

    /// For plugin format clients only.
    /// Calls `reset()`.
    /// Must be called by the audio thread.
    void resetFromHost(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {
        // Clear outstanding MIDI messages (now invalid)
        _midiQueue.initialize();

        // We potentially give to the client implementation a lower value
        // for the maximum number of frames
        if (_maxFramesInProcess != 0 && _maxFramesInProcess < maxFrames)
            maxFrames = _maxFramesInProcess;

        // Calls the reset virtual call
        reset(sampleRate, maxFrames, numInputs, numOutputs);
    }

protected:

    /// Override this method to implement parameter creation.
    /// This is an optional overload, default implementation declare no parameters.
    /// The returned slice must be allocated with `malloc`/`mallocSlice` and contains
    /// `Parameter` objects created with `mallocEmplace`.
    Parameter[] buildParameters()
    {
        return [];
    }

    /// Override this methods to load/fill presets.
    /// This function must return a slice allocated with `malloc`,
    /// that contains presets crteated with `mallocEmplace`.
    Preset[] buildPresets() nothrow @nogc
    {
        auto presets = makeVec!Preset();
        presets.pushBack( makeDefaultPreset() );
        return presets.releaseData();
    }

    /// Override this method to tell what plugin you are.
    /// Mandatory override, fill the fields with care.
    abstract PluginInfo buildPluginInfo();

    /// Override this method to tell which I/O are legal.
    /// The returned slice must be allocated with `malloc`/`mallocSlice`.
    abstract LegalIO[] buildLegalIO();

    IGraphics _graphics;

    // Used as a flag that _graphics can be used (by audio thread or for destruction)
    shared(bool) _graphicsIsAvailable = false;

    IHostCommand _hostCommand;

    PluginInfo _info;

private:
    Parameter[] _params;

    PresetBank _presetBank;

    LegalIO[] _legalIOs;

    int _maxInputs, _maxOutputs; // maximum number of input/outputs

    // Cache result of maxFramesInProcess(), maximum frame length
    int _maxFramesInProcess;

    // Container for awaiting MIDI messages.
    MidiQueue _midiQueue;

    final void createGraphicsLazily() nothrow @nogc
    {
        // First GUI opening create the graphics object
        // no need to protect _graphics here since the audio thread
        // does not write to it
        if ( (_graphics is null) && hasGUI())
        {
            // Why is the IGraphics created lazily? This allows to load a plugin very quickly,
            // without opening its logical UI
            IGraphics graphics = createGraphics();

            // Don't forget to override the createGraphics method!
            assert(graphics !is null);

            _graphics = graphics;

            // Now that the UI is fully created, we enable the audio thread to use it
            atomicStore(_graphicsIsAvailable, true);
        }
    }
}

/// Should be called in Client class during compile time
/// to parse a `PluginInfo` from a supplied json file.
PluginInfo parsePluginInfo(string json)
{
    import std.json;
    import std.string;
    import std.conv;

    JSONValue j = parseJSON(json);

    static bool toBoolean(JSONValue value)
    {
        if (value.type == JSON_TYPE.TRUE)
            return true;
        if (value.type == JSON_TYPE.FALSE)
            return false;
        throw new Exception(format("Expected a boolean, got %s instead", value));
    }

    // Check that a string is "x.y.z"
    // FUTURE: support larger integers than 0 to 9 in the string
    static PluginVersion parsePluginVersion(string value)
    {
        bool isDigit(char ch)
        {
            return ch >= '0' && ch <= '9';
        }

        if ( value.length != 5  ||
             !isDigit(value[0]) ||
             value[1] != '.'    ||
             !isDigit(value[2]) ||
             value[3] != '.'    ||
             !isDigit(value[4]))
        {
            throw new Exception("\"publicVersion\" should follow the form x.y.z (eg: \"1.0.0\")");
        }

        PluginVersion ver;
        ver.major = value[0] - '0';
        ver.minor = value[2] - '0';
        ver.patch = value[4] - '0';
        return ver;
    }

    PluginInfo info;
    info.vendorName = j["vendorName"].str;
    info.vendorUniqueID = j["vendorUniqueID"].str;
    info.pluginName = j["pluginName"].str;
    info.pluginUniqueID = j["pluginUniqueID"].str;
    info.isSynth = toBoolean(j["isSynth"]);
    info.hasGUI = toBoolean(j["hasGUI"]);
    info.receivesMIDI = toBoolean(j["receivesMIDI"]);
    info.publicVersion = parsePluginVersion(j["publicVersion"].str);

    PluginCategory category = parsePluginCategory(j["category"].str);
    if (category == PluginCategory.invalid)
        throw new Exception("Invalid \"category\" in plugin.json. Check out dplug.client.daw for valid values (eg: \"effectDynamics\").");
    info.category = category;
    return info;
}