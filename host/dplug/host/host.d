/**
 * Copyright: Copyright Auburn Sounds 2015 and later.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
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

    /// Sets a parameter's value.
    void setParameter(int paramIndex, float normalizedValue);

    /// Returns: Normalized value for parameter.
    float getParameter(int paramIndex);

    /// Loads a preset.
    void loadPreset(int presetIndex);

    /// Free all resources associated with the plugin host.
    void close();

    /// Get plugin information
    string getProductString();
    
    ///ditto
    string getEffectName();
    
    ///ditto
    string getVendorString();
}


