// See licenses/WDL_license.txt
module dplug.plugin.iplug;


// TODO: define here a plugin interface that could support AU, VST

enum API
{
    VST,
    AUDIO_UNIT
}

abstract class IParameter
{
    void setFromFloat(float x);
    float getAsFloat();
}

/// Plugin format wrappers inherit from this base class.
abstract class IPlugin
{
public:
    // get number of parameters
    size_t getParamCount();

    // get parameter i
    IParameter getParam(size_t i);

protected:
}

