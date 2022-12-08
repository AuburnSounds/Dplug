/**
Generic host commands.
Copyright: Auburn Sounds 2015-2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.host.host;

interface IPluginHost
{
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
    const(char)[] getParameterName(int paramIndex);

    /// Returns: Number of parameters.
    int getParameterCount();

    /// Loads a preset.
    void loadPreset(int presetIndex);

    /// Serialize state of the plugin.
    ubyte[] saveState();

    /// Restore state of the plugin.
    void restoreState(ubyte[] chunk);

    /// Gets current "program" index.
    int getCurrentProgram();

    /// Free all resources associated with the plugin host.
    void close();

    /// Get plugin information
    string getProductString();
    
    ///ditto
    string getEffectName();
    
    ///ditto
    string getVendorString();

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


