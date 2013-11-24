// See Steinberg VST license here: http://www.gersic.com/vstsdk/html/plug/intro.html#licence
module dplug.vst.host;

import core.stdc.string;

import dplug.vst.aeffectx;


struct VSTHost
{
public:
    
    void init(HostCallbackFunction hostCallback, AEffect* effect) pure nothrow
    {
        _hostCallback = hostCallback;
        _effect = effect;
    }

    /**
     * Returns:
     * 	  input latency in frames
     */
    int inputLatency() nothrow 
    {
        return cast(int)_hostCallback(_effect, audioMasterGetInputLatency, 0, 0, null, 0);
    }

    /**
     * Returns:
     * 	  output latency in frames
     */
    int outputLatency() nothrow 
    {
        return cast(int)_hostCallback(_effect, audioMasterGetOutputLatency, 0, 0, null, 0);
    }

    /**
     * Deprecated: This call is deprecated, but was added to support older hosts (like MaxMSP).
     * Plugins (VSTi2.0 thru VSTi2.3) call this to tell the host that the plugin is an instrument.
     */
    void wantEvents() nothrow
    {
        _hostCallback(_effect, DEPRECATED_audioMasterWantMidi, 0, 1, null, 0);
    }

    /**
     * Returns:
     *    current sampling rate of host.
     */
    float samplingRate() nothrow
    {
        float *f = cast(float *) _hostCallback(_effect, audioMasterGetSampleRate, 0, 0, null, 0);
        return *f;
    }

    /**
     * Returns:
     *    current block size of host.
     */
    int blockSize() nothrow
    {
        return cast(int)_hostCallback(_effect, audioMasterGetBlockSize, 0, 0, null, 0.0f);
    }

    /// Request plugin window resize.
    bool requestResize(int width, int height) nothrow
    {
        return (_hostCallback(_effect, audioMasterSizeWindow, width, height, null, 0.0f) != 0);
    }

    const(char)* vendorString() nothrow
    {
        int res = cast(int)_hostCallback(_effect, audioMasterGetVendorString, 0, 0, _vendorStringBuf.ptr, 0.0f);
        if (res == 1)
        {
            //size_t len = strlen(_vendorStringBuf.ptr);
            return _vendorStringBuf.ptr;
        }
        else
            return "unknown";
    }

    const(char)* productString() nothrow
    {
        int res = cast(int)_hostCallback(_effect, audioMasterGetProductString, 0, 0, _productStringBuf.ptr, 0.0f);
        if (res == 1)
        {
            //size_t len = strlen(_productStringBuf.ptr);
            return _productStringBuf.ptr;
        }
        else
            return "unknown";
    }

    /// Capabilities

    enum HostCaps
    {
        SEND_VST_EVENTS,                      // Host supports send of Vst events to plug-in.
        SEND_VST_MIDI_EVENTS,                 // Host supports send of MIDI events to plug-in.
        SEND_VST_TIME_INFO,                   // Host supports send of VstTimeInfo to plug-in.
        RECEIVE_VST_EVENTS,                   // Host can receive Vst events from plug-in.
        RECEIVE_VST_MIDI_EVENTS,              // Host can receive MIDI events from plug-in.
        REPORT_CONNECTION_CHANGES,            // Host will indicates the plug-in when something change in plug-in´s routing/connections with suspend()/resume()/setSpeakerArrangement().
        ACCEPT_IO_CHANGES,                    // Host supports ioChanged().
        SIZE_WINDOW,                          // used by VSTGUI
        OFFLINE,                              // Host supports offline feature.
        OPEN_FILE_SELECTOR,                   // Host supports function openFileSelector().
        CLOSE_FILE_SELECTOR,                  // Host supports function closeFileSelector().
        START_STOP_PROCESS,                   // Host supports functions startProcess() and stopProcess().
        SHELL_CATEGORY,                       // 'shell' handling via uniqueID. If supported by the Host and the Plug-in has the category kPlugCategShell
        SEND_VST_MIDI_EVENT_FLAG_IS_REALTIME, // Host supports flags for VstMidiEvent.
        SUPPLY_IDLE                           // ???

    }

    bool canDo(HostCaps caps) nothrow
    {
        const(char)* capsString = hostCapsString(caps);
        assert(capsString !is null);

        // note: const is casted away here
        return _hostCallback(_effect, audioMasterCanDo, 0, 0, cast(void*)capsString, 0.0f) == 1;
    }


private:
    AEffect* _effect;
    HostCallbackFunction _hostCallback;
    char[65] _vendorStringBuf;
    char[96] _productStringBuf;
    int _vendorVersion;

    static const(char)* hostCapsString(HostCaps caps) pure nothrow
    {
        switch (caps)
        {
        case HostCaps.SEND_VST_EVENTS: return "sendVstEvents";
        case HostCaps.SEND_VST_MIDI_EVENTS: return "sendVstMidiEvent";
        case HostCaps.SEND_VST_TIME_INFO: return "sendVstTimeInfo";
        case HostCaps.RECEIVE_VST_EVENTS: return "receiveVstEvents";
        case HostCaps.RECEIVE_VST_MIDI_EVENTS: return "receiveVstMidiEvent";
        case HostCaps.REPORT_CONNECTION_CHANGES: return "reportConnectionChanges";
        case HostCaps.ACCEPT_IO_CHANGES: return "acceptIOChanges";
        case HostCaps.SIZE_WINDOW: return "sizeWindow";
        case HostCaps.OFFLINE: return "offline";
        case HostCaps.OPEN_FILE_SELECTOR: return "openFileSelector";
        case HostCaps.CLOSE_FILE_SELECTOR: return "closeFileSelector";
        case HostCaps.START_STOP_PROCESS: return "startStopProcess";
        case HostCaps.SHELL_CATEGORY: return "shellCategory";
        case HostCaps.SEND_VST_MIDI_EVENT_FLAG_IS_REALTIME: return "sendVstMidiEventFlagIsRealtime";
        case HostCaps.SUPPLY_IDLE: return "supplyIdle";
        default:
            assert(false);
        }
    }
}



