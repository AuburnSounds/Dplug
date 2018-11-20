//-----------------------------------------------------------------------------
// Project     : VST SDK
//
// Category    : Interfaces
// Filename    : pluginterfaces/vst/ivstcomponent.h
// Created by  : Steinberg, 04/2005
// Description : Basic VST Interfaces
//
//-----------------------------------------------------------------------------
// This file is part of a Steinberg SDK. It is subject to the license terms
// in the LICENSE file found in the top-level directory of this distribution
// and at www.steinberg.net/sdklicenses. 
// No part of the SDK, including this file, may be copied, modified, propagated,
// or distributed except according to the terms contained in the LICENSE file.
//-----------------------------------------------------------------------------
module dplug.vst3.ivstcomponent;

import dplug.vst3.fplatform;
import dplug.vst3.ftypes;
import dplug.vst3.funknown;
import dplug.vst3.ipluginbase;
import dplug.vst3.ibstream;



/** \defgroup vstBus VST Buses
Bus Description

A bus can be understood as a "collection of data channels" belonging together.
It describes a data input or a data output of the Plug-in.
A VST component can define any desired number of buses, but this number must \b never change.
Dynamic usage of buses is handled in the host by activating and deactivating buses.
The component has to define the maximum number of supported buses and it has to
define which of them are active by default. A host that can handle multiple buses,
allows the user to activate buses that were initially inactive.

See also: IComponent::getBusInfo, IComponent::activateBus

@{*/

/** Bus media types */
alias MediaTypes = int;
enum : MediaTypes
{
    kAudio = 0,     ///< audio
    kEvent,         ///< events
    kNumMediaTypes
}

/** Bus directions */
enum : BusDirection
{
    kInput = 0,     ///< input bus
    kOutput         ///< output bus
}

/** Bus types */
alias BusTypes = int;
enum : BusTypes
{
    kMain = 0,      ///< main bus
    kAux            ///< auxiliary bus (sidechain)
}

/** BusInfo:
This is the structure used with getBusInfo, informing the host about what is a specific given bus.
\n See also: IComponent::getBusInfo */
struct BusInfo
{
nothrow:
@nogc:
//align(vst3Alignment):

    MediaType mediaType;    ///< Media type - has to be a value of \ref MediaTypes
    BusDirection direction; ///< input or output \ref BusDirections
    int32 channelCount;     ///< number of channels (if used then need to be recheck after \ref
                            /// IAudioProcessor::setBusArrangements is called).
                            /// For a bus of type MediaTypes::kEvent the channelCount corresponds
                            /// to the number of supported MIDI channels by this bus
    String128 name;         ///< name of the bus
    BusType busType;        ///< main or aux - has to be a value of \ref BusTypes
    uint32 flags;           ///< flags - a combination of \ref BusFlags
    enum BusFlags
    {
        kDefaultActive = 1 << 0 ///< bus active per default
    }

    void setName(wstring newName)
    {
        name[] = '\0';
        int len = cast(int)(newName.length);
        if (len > 127) len = 127;
        name[0..len] = newName[0..len];
    }
}

/** I/O modes */
alias IoModes = int;
enum : IoModes
{
    kSimple = 0,        ///< 1:1 Input / Output. Only used for Instruments. See \ref vst3IoMode
    kAdvanced,          ///< n:m Input / Output. Only used for Instruments.
    kOfflineProcessing  ///< Plug-in used in an offline processing context
}

/** Routing Information:
When the Plug-in supports multiple I/O buses, a host may want to know how the buses are related. The
relation of an event-input-channel to an audio-output-bus in particular is of interest to the host
(in order to relate MIDI-tracks to audio-channels)
\n See also: IComponent::getRoutingInfo, \ref vst3Routing */
struct RoutingInfo
{
//    align(vst3Alignment):

    MediaType mediaType;    ///< media type see \ref MediaTypes
    int32 busIndex;         ///< bus index
    int32 channel;          ///< channel (-1 for all channels)
};

// IComponent Interface
/** Component Base Interface
\ingroup vstIPlug vst300
- [plug imp]
- [released: 3.0.0]
- [mandatory]

This is the basic interface for a VST component and must always be supported.
It contains the common parts of any kind of processing class. The parts that
are specific to a media type are defined in a separate interface. An implementation
component must provide both the specific interface and IComponent.
*/
interface IComponent: IPluginBase
{
public:
nothrow:
@nogc:
    /** Called before initializing the component to get information about the controller class. */
    tresult getControllerClassId (TUID* classId);

    /** Called before 'initialize' to set the component usage (optional). See \ref IoModes */
    tresult setIoMode (IoMode mode);

    /** Called after the Plug-in is initialized. See \ref MediaTypes, BusDirections */
    int32 getBusCount (MediaType type, BusDirection dir);

    /** Called after the Plug-in is initialized. See \ref MediaTypes, BusDirections */
    tresult getBusInfo (MediaType type, BusDirection dir, int32 index, ref BusInfo bus /*out*/);

    /** Retrieves routing information (to be implemented when more than one regular input or output bus exists).
        The inInfo always refers to an input bus while the returned outInfo must refer to an output bus! */
    tresult getRoutingInfo (ref RoutingInfo inInfo, ref RoutingInfo outInfo /*out*/);

    /** Called upon (de-)activating a bus in the host application. The Plug-in should only processed an activated bus,
        the host could provide less see \ref AudioBusBuffers in the process call (see \ref IAudioProcessor::process) if last buses are not activated */
    tresult activateBus (MediaType type, BusDirection dir, int32 index, TBool state);

    /** Activates / deactivates the component. */
    tresult setActive (TBool state);

    /** Sets complete state of component. */
    tresult setState (IBStream state);

    /** Retrieves complete state of component. */
    tresult getState (IBStream state);

    __gshared immutable FUID iid = FUID(IComponent_iid);
}

static immutable TUID IComponent_iid = INLINE_UID(0xE831FF31, 0xF2D54301, 0x928EBBEE, 0x25697802);

