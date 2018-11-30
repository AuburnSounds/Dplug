module dplug.lv2.client;

import std.string;

import  core.stdc.stdlib,
        core.stdc.string,
        core.stdc.stdio,
        core.stdc.math,
        core.stdc.stdint;

import std.algorithm.comparison;

import dplug.core.vec,
       dplug.core.nogc,
       dplug.core.math,
       dplug.core.lockedqueue,
       dplug.core.runtime,
       dplug.core.fpcontrol,
       dplug.core.thread,
       dplug.core.sync;

import dplug.client.client,
       dplug.client.daw,
       dplug.client.preset,
       dplug.client.graphics,
       dplug.client.midi,
       dplug.client.params;

import dplug.lv2.lv2,
       dplug.lv2.atom,
       dplug.lv2.atomutil,
       dplug.lv2.lv2util,
       dplug.lv2.midi,
       dplug.lv2.ui,
       dplug.lv2.urid;

enum PLUGIN_URI = "dplug:destructorizer";

static LV2Client* instancePtr;

/**
 * Main entry point for LV2 plugins.
 */
template LV2EntryPoint(alias ClientClass)
{
    enum importStdint = "import core.stdc.stdint;";
    enum entryPoint = "export extern(C) static LV2_Handle instantiate(const LV2_Descriptor* descriptor," ~
                      "                                               double rate," ~
                      "                                               const char* bundle_path," ~
                      "                                               const(LV2_Feature*)* features)" ~
                      "{" ~
                      "    return myLV2EntryPoint!" ~ ClientClass.stringof ~ "(descriptor, rate, bundle_path, features);" ~
                      "}\n";

    enum descriptor = "static const LV2_Descriptor descriptor = {" ~
                            "PLUGIN_URI," ~
                            "&instantiate," ~
                            "&connect_port," ~
                            "&activate," ~
                            "&run," ~
                            "&deactivate," ~
                            "&cleanup," ~
                            "&extension_data" ~
                        "};\n";
    enum descriptorUI = "static const LV2UI_Descriptor descriptorUI = " ~ 
                        "{" ~
                            "\"dplug:destructorizer#ui\"," ~
                            "&instantiateUI," ~
                            "&cleanupUI," ~
                            "&port_event," ~
                            "&extension_dataUI" ~
                        "};\n";

    enum lv2ui_descripor = "extern(C) const (LV2UI_Descriptor)* lv2ui_descriptor(uint32_t index)" ~ 
                            "{" ~
                            "    switch(index) {" ~
                            "        case 0: return &descriptorUI;" ~
                            "        default: return null;" ~
                            "    }" ~ 
                            "}\n";

    enum lv2_descriptor = "extern(C) const (LV2_Descriptor)*" ~ 
                            "lv2_descriptor(uint32_t index)" ~ 
                            "{" ~ 
                            "    switch (index) {" ~ 
                            "       case 0:  return &descriptor;" ~ 
                            "       default: return null;" ~ 
                            "    }" ~ 
                            "}\n";

    const char[] LV2EntryPoint = importStdint ~ entryPoint ~ descriptor ~ descriptorUI  ~ lv2ui_descripor ~ lv2_descriptor;
}

nothrow LV2_Handle myLV2EntryPoint(alias ClientClass)(const LV2_Descriptor* descriptor, double rate, const char* bundle_path, const(LV2_Feature*)* features)
{
    auto client = mallocNew!ClientClass();
    lv2client = mallocNew!LV2Client(client, descriptor, rate, bundle_path, features);
    instancePtr = &lv2client;
    return cast(LV2_Handle)&lv2client;
}

class LV2Client : IHostCommand
{
nothrow:
@nogc:

    Client _client;

    this(Client client, const LV2_Descriptor* descriptor, double rate, const char* bundle_path, const(LV2_Feature*)* features)
    {
        _client = client;
        _client.setHostCommand(this);
        _maxInputs = _client.maxInputs();
        _maxOutputs = _client.maxOutputs();
        _numParams = cast(uint)_client.params().length;
        _sampleRate = cast(float)rate;

        _lv2Ports = makeVec!LV2Port();
        foreach(param; _client.params)
        {
            LV2ParamPort port = mallocNew!LV2ParamPort();
            if(cast(FloatParameter)param)
                port.paramType = Float;
            else if(cast(BoolParameter)param)
                port.paramType = Bool;
            else if(cast(EnumParameter)param)
                port.paramType = Enum;
            else if(cast(IntegerParameter)param)
                port.paramType = Integer;
            else
                assert(false, "Unsupported param type");

            _lv2Ports.pushBack(port);
        }

        foreach(input; 0..cast(uint)(_maxInputs))
        {
            LV2InputPort port = mallocNew!LV2InputPort();
            _lv2Ports.pushBack(port);
        }

        foreach(output; 0..cast(uint)(_maxOutputs))
        {
            LV2OutputPort port = mallocNew!LV2OutputPort();
            _lv2Ports.pushBack(port);
        }
    }

    void cleanup()
    {
        foreach(port; _lv2Ports)
            port.destroyFree();
    }

    void updateParamFromHost(uint32_t port_index)
    {
        LV2ParamPort port = cast(LV2ParamPort)_lv2Ports[port_index];
        float paramValue = *(port.data);
        switch(port.paramType)
        {
            case Bool:
                _client.setParameterFromHost(port_index, paramValue > 0 ? true : false);
                break;
            case Enum:
                _client.setParameterFromHost(port_index, cast(int)paramValue);
                break;
            case Integer:
                _client.setParameterFromHost(port_index, cast(int)paramValue);
                break;
            case Float:
                _client.setParameterFromHost(port_index, paramValue);
                break;
            default:
                assert(false, "Unsupported param type");
        }
    }

    void updatePortFromClient(uint32_t port_index, float value)
    {
        LV2ParamPort port = cast(LV2ParamPort)_lv2Ports[port_index];
        *port.data = value;
    }

    void connect_port(uint32_t port, void* data)
    {
        LV2Port lv2Port = _lv2Ports[port];
        switch(cast(LV2PortType)lv2Port.lv2PortType)
        {
            case Param:
                (cast(LV2ParamPort)lv2Port).data = cast(float*)data;
                break;
            case InputPort:
                (cast(LV2InputPort)lv2Port).data = cast(float*)data;
                break;
            case OutputPort:
                (cast(LV2OutputPort)lv2Port).data = cast(float*) data;
                break;
            default:
                break;
        }
    }

    void activate()
    {
        _client.reset(_sampleRate, 0, _maxInputs, _maxOutputs);
    }

    void run(uint32_t n_samples)
    {
        TimeInfo timeInfo;
        Vec!(float*) inputs = makeVec!(float*)();
        Vec!(float*) outputs = makeVec!(float*)();
        foreach(port; _lv2Ports)
        {
            switch(port.lv2PortType)
            {
                case InputPort:
                    inputs.pushBack((cast(LV2InputPort)port).data);
                    break;
                case OutputPort:
                    outputs.pushBack((cast(LV2OutputPort)port).data);
                    break;
                default:
                    break;
            }
        }

        _client.processAudioFromHost(inputs.releaseData(), outputs.releaseData(), n_samples, timeInfo);
    }

    void deactivate()
    {

    }

    void instantiateUI(const LV2UI_Descriptor* descriptor,
									const char*                     plugin_uri,
									const char*                     bundle_path,
									LV2UI_Write_Function            write_function,
									LV2UI_Controller                controller,
									LV2UI_Widget*                   widget,
									const (LV2_Feature*)*       features)
    {
        // _graphicsMutex.lock();
        *widget = cast(LV2UI_Widget)_client.openGUI(null, null, GraphicsBackend.x11);
        // _graphicsMutex.unlock();
    }

    void port_event(uint32_t     port_index,
						uint32_t     buffer_size,
						uint32_t     format,
						const void*  buffer)
    {
        updateParamFromHost(port_index);
    }

    void cleanupUI()
    {
        _client.closeGUI();
    }

    override void beginParamEdit(int paramIndex)
    {
        
    }

    override void paramAutomate(int paramIndex, float value)
    {
        updatePortFromClient(paramIndex, value);
    }

    override void endParamEdit(int paramIndex)
    {

    }

    override bool requestResize(int width, int height)
    {
        return false;
    }

    // Not properly implemented yet. LV2 should have an extension to get DAW information.
    override DAW getDAW()
    {
        return DAW.Unknown;
    }

private:

    uint _maxInputs;
    uint _maxOutputs;
    uint _numParams;

    float _sampleRate;

    Vec!LV2Port _lv2Ports;
}

alias LV2PortType = int;
enum
{
    Param = 0,
    InputPort = 1,
    OutputPort = 2
}

class LV2Port
{
public:
    LV2PortType lv2PortType;
}

alias ParamType = int;
enum : int
{
    Bool = 0,
    Enum = 1,
    Integer = 2,
    Float = 3
}
class LV2ParamPort : LV2Port
{
    this() nothrow @nogc
    {
        lv2PortType = Param;
    }
    float* data;
    ParamType paramType;
}

class LV2InputPort : LV2Port
{
    this() nothrow @nogc
    {
        lv2PortType = InputPort;
    }
    float* data;
}

class LV2OutputPort : LV2Port
{
    this() nothrow @nogc
    {
        lv2PortType = OutputPort;
    }
    float* data;
}

static LV2Client lv2client;

/*
    LV2 Callback funtion implementations
    note that instatiate is a template mixin. 
*/
extern(C)
{
    static void
    connect_port(LV2_Handle instance,
                uint32_t   port,
                void*      data)
    {
        LV2Client lv2client = *cast(LV2Client*)instance;
        lv2client.connect_port(port, data);
    }

    static void
    activate(LV2_Handle instance)
    {
        LV2Client lv2client = *cast(LV2Client*)instance;
        lv2client.activate();
    }

    static void
    run(LV2_Handle instance, uint32_t n_samples)
    {
        LV2Client lv2client = *cast(LV2Client*)instance;
        lv2client.run(n_samples);
    }

    static void
    deactivate(LV2_Handle instance)
    {
        LV2Client lv2client = *cast(LV2Client*)instance;
        lv2client.deactivate();
    }

    static void
    cleanup(LV2_Handle instance)
    {
        // free(cast(LV2Client*)instance);
        LV2Client lv2client = *cast(LV2Client*)instance;
        lv2client.cleanup();
        lv2client.destroyFree();
    }

    static const (void)*
    extension_data(const char* uri)
    {
        return null;
    }

    LV2UI_Handle instantiateUI(const LV2UI_Descriptor* descriptor,
									const char*                     plugin_uri,
									const char*                     bundle_path,
									LV2UI_Write_Function            write_function,
									LV2UI_Controller                controller,
									LV2UI_Widget*                   widget,
									const (LV2_Feature*)*       features)
    {
        instancePtr.instantiateUI(descriptor, plugin_uri, bundle_path, write_function, controller, widget, features);
        return cast(LV2UI_Handle)instancePtr;
    }

    void write_function(LV2UI_Controller controller,
										uint32_t         port_index,
										uint32_t         buffer_size,
										uint32_t         port_protocol,
										const void*      buffer)
    {
        
    }

    void cleanupUI(LV2UI_Handle ui)
    {
        instancePtr.cleanupUI();
    }

    void port_event(LV2UI_Handle ui,
						uint32_t     port_index,
						uint32_t     buffer_size,
						uint32_t     format,
						const void*  buffer)
    {
        instancePtr.port_event(port_index, buffer_size, format, buffer);
    }

    const (void)* extension_dataUI(const char* uri)
    {
        return null;
    }
}