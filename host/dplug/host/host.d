/**
Generic host commands.
Copyright: Auburn Sounds 2015-2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.host.host;

nothrow @nogc:

interface IPluginHost
{
nothrow @nogc:

    /// Process some audio.
    /// `setSampleRate` and `setMaxBufferSize` must be called before use.
    /// samples must <= the maximum buffer size asked in 
    void processAudioFloat(float** inputs, float** ouputs, int samples);

    /// Sets the desired sampleRate
    void setSampleRate(float sampleRate);

    /// Sets the maximum buffer size
    void setMaxBufferSize(int samples);

    /// Sets I/O arrangement (simple right now).
    bool setIO(int numInputs, int numOutputs);

    /// Sets a parameter's value.
    void setParameter(int paramIndex, float normalizedValue);

    /// Returns: Normalized value for parameter.
    float getParameter(int paramIndex);

    /// Returns: Full name for parameter.
    /// Lifetime of return value is same as IPluginHost.
    const(char)[] getParameterName(int paramIndex);

    /// Returns: Number of parameters.
    int getParameterCount();

    /// Loads a preset.
    void loadPreset(int presetIndex);

    /// Serialize state of the plugin, to restore with `restoreState`.
    ///
    /// Returns: `null` in case of error, else a state chunk.
    ///           The lifetime of this returned chunk is the same as the `IPluginHost`, or until 
    ///           another call to `saveState` is done.
    const(ubyte)[] saveState();

    /// Restore state of the plugin, saved with `saveState`.
    /// Returns: `true` on success.
    bool restoreState(const(ubyte)[] chunk);

    /// Gets current "program" index.
    /// Note: not all presets are exposed to the host. In many plug-ins they aren't.
    int getCurrentProgram();

    /// Get plugin information.
    /// Lifetime of return value is same as IPluginHost.
    const(char)[] getProductString();
    
    ///ditto
    /// Lifetime of return value is same as IPluginHost.
    const(char)[] getEffectName();
    
    ///ditto
    /// Lifetime of return value is same as IPluginHost.
    const(char)[] getVendorString();

    /// Opens the editor window.
    /// On Windows, pass a HWND
    /// On Mac, a NSView    
    void openUI(void* windowHandle);

    /// Closes the editor.
    void closeUI();

    /// Gets the UI size.
    int[2] getUISize();

    /// Switch on the plugin. Call it before processing.
    void beginAudioProcessing();

    /// Switch off the plugin. Call it after processing.
    void endAudioProcessing();

    /// Get current plug-in latency in samples.
    /// Because of VST2 limitations, this number of only valid between a 
    /// `beginAudioProcessing` and `endAudioProcessing` call, and won't move while
    /// processing.
    int getLatencySamples();

    /// Get tail size in seconds. Precise semantics TBD.
    double getTailSizeInSeconds();
}


