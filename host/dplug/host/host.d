/**
 * Copyright: Copyright Auburn Sounds 2015 and later.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.host.host;

interface IPluginHost
{
    /// Process some audio.
    void processAudioFloat(float** inputs, float** ouputs, int samples);

    /// Sets a parameter's value.
    void setParameter(int paramIndex, float normalizedValue);

    /// Returns: Normalized value for parameter.
    float getParameter(int paramIndex);

    /// Free all resources associated with the plugin host.
    void close();

    /// Get plugin information
    string getProductString();
    
    ///ditto
    string getEffectName();
    
    ///ditto
    string getVendorString();
}


