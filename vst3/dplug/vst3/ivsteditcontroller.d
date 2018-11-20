//------------------------------------------------------------------------
// Project     : VST SDK
//
// Category    : Interfaces
// Filename    : pluginterfaces/vst/ivsteditcontroller.h
// Created by  : Steinberg, 09/2005
// Description : VST Edit Controller Interfaces
//
//-----------------------------------------------------------------------------
// This file is part of a Steinberg SDK. It is subject to the license terms
// in the LICENSE file found in the top-level directory of this distribution
// and at www.steinberg.net/sdklicenses. 
// No part of the SDK, including this file, may be copied, modified, propagated,
// or distributed except according to the terms contained in the LICENSE file.
//-----------------------------------------------------------------------------
module dplug.vst3.ivsteditcontroller;

import dplug.vst3.ftypes;
import dplug.vst3.funknown;
import dplug.vst3.ipluginbase;
import dplug.vst3.ibstream;
import dplug.vst3.iplugview;

static immutable string kVstComponentControllerClass = "Component Controller Class";

struct ParameterInfo
{
//align(vst3Alignment):
    ParamID id;             ///< unique identifier of this parameter (named tag too)
    String128 title;        ///< parameter title (e.g. "Volume")
    String128 shortTitle;   ///< parameter shortTitle (e.g. "Vol")
    String128 units;        ///< parameter unit (e.g. "dB")
    int32 stepCount;        ///< number of discrete steps (0: continuous, 1: toggle, discrete value otherwise 
                            ///< (corresponding to max - min, for example: 127 for a min = 0 and a max = 127) - see \ref vst3parameterIntro)
    ParamValue defaultNormalizedValue;  ///< default normalized value [0,1] (in case of discrete value: defaultNormalizedValue = defDiscreteValue / stepCount)
    UnitID unitId;          ///< id of unit this parameter belongs to (see \ref vst3UnitsIntro)

    int32 flags;            ///< ParameterFlags (see below)
    enum ParameterFlags
    {
        kCanAutomate     = 1 << 0,  ///< parameter can be automated
        kIsReadOnly      = 1 << 1,  ///< parameter cannot be changed from outside (implies that kCanAutomate is false)
        kIsWrapAround    = 1 << 2,  ///< attempts to set the parameter value out of the limits will result in a wrap around [SDK 3.0.2]
        kIsList          = 1 << 3,  ///< parameter should be displayed as list in generic editor or automation editing [SDK 3.1.0]

        kIsProgramChange = 1 << 15, ///< parameter is a program change (unitId gives info about associated unit 
                                    ///< - see \ref vst3UnitPrograms)
        kIsBypass        = 1 << 16  ///< special bypass parameter (only one allowed): Plug-in can handle bypass
                                    ///< (highly recommended to export a bypass parameter for effect Plug-in)
    }
}

//------------------------------------------------------------------------
/** View Types used for IEditController::createView */
//------------------------------------------------------------------------
struct ViewType
{
    static immutable kEditor = "editor";
}

//------------------------------------------------------------------------
/** Flags used for IComponentHandler::restartComponent */
//------------------------------------------------------------------------
alias RestartFlags = int;
enum : RestartFlags
{
    kReloadComponent            = 1 << 0,   ///< The Component should be reloaded             [SDK 3.0.0]
    kIoChanged                  = 1 << 1,   ///< Input and/or Output Bus configuration has changed        [SDK 3.0.0]
    kParamValuesChanged         = 1 << 2,   ///< Multiple parameter values have changed 
                                            ///< (as result of a program change for example)  [SDK 3.0.0]
    kLatencyChanged             = 1 << 3,   ///< Latency has changed (IAudioProcessor.getLatencySamples)  [SDK 3.0.0]
    kParamTitlesChanged         = 1 << 4,   ///< Parameter titles or default values or flags have changed [SDK 3.0.0]
    kMidiCCAssignmentChanged    = 1 << 5,   ///< MIDI Controller Assignments have changed     [SDK 3.0.1]
    kNoteExpressionChanged      = 1 << 6,   ///< Note Expression has changed (info, count, PhysicalUIMapping, ...) [SDK 3.5.0]
    kIoTitlesChanged            = 1 << 7,   ///< Input and/or Output bus titles have changed  [SDK 3.5.0]
    kPrefetchableSupportChanged = 1 << 8,   ///< Prefetch support has changed (\see IPrefetchableSupport) [SDK 3.6.1]
    kRoutingInfoChanged         = 1 << 9    ///< RoutingInfo has changed (\see IComponent)    [SDK 3.6.6]
}

/** Host callback interface for an edit controller.
\ingroup vstIHost vst300
- [host imp]
- [released: 3.0.0]

Allow transfer of parameter editing to component (processor) via host and support automation.
Cause the host to react on configuration changes (restartComponent)

\see IEditController */
interface IComponentHandler: FUnknown
{
public:
nothrow:
@nogc:

    /** To be called before calling a performEdit (e.g. on mouse-click-down event). */
    tresult beginEdit (ParamID id);

    /** Called between beginEdit and endEdit to inform the handler that a given parameter has a new value. */
    tresult performEdit (ParamID id, ParamValue valueNormalized);

    /** To be called after calling a performEdit (e.g. on mouse-click-up event). */
    tresult endEdit (ParamID id);

    /** Instructs host to restart the component. This should be called in the UI-Thread context!
    \param flags is a combination of RestartFlags */
    tresult restartComponent (int32 flags);

    __gshared immutable FUID iid = FUID(IComponentHandler_iid);
}

static immutable TUID IComponentHandler_iid = INLINE_UID(0x93A0BEA3, 0x0BD045DB, 0x8E890B0C, 0xC1E46AC6);


/** Edit controller component interface.
\ingroup vstIPlug vst300
- [plug imp]
- [released: 3.0.0]

The Controller part of an effect or instrument with parameter handling (export, definition, conversion...).
\see IComponent::getControllerClassId, IMidiMapping */
interface IEditController: IPluginBase
{
public:
nothrow:
@nogc:

    /** Receives the component state. */
    tresult setComponentState (IBStream* state);

    /** Sets the controller state. */
    tresult setState (IBStream* state);

    /** Gets the controller state. */
    tresult getState (IBStream* state);

    // parameters -------------------------
    /** Returns the number of parameters exported. */
    int32 getParameterCount ();

    /** Gets for a given index the parameter information. */
    tresult getParameterInfo (int32 paramIndex, ref ParameterInfo info /*out*/);

    /** Gets for a given paramID and normalized value its associated string representation. */
    tresult getParamStringByValue (ParamID id, ParamValue valueNormalized /*in*/, String128 string /*out*/);

    /** Gets for a given paramID and string its normalized value. */
    tresult getParamValueByString (ParamID id, TChar* string_ /*in*/, ref ParamValue valueNormalized /*out*/);

    /** Returns for a given paramID and a normalized value its plain representation
        (for example 90 for 90db - see \ref vst3AutomationIntro). */
    ParamValue normalizedParamToPlain (ParamID id, ParamValue valueNormalized);

    /** Returns for a given paramID and a plain value its normalized value. (see \ref vst3AutomationIntro) */
    ParamValue plainParamToNormalized (ParamID id, ParamValue plainValue);

    /** Returns the normalized value of the parameter associated to the paramID. */
    ParamValue getParamNormalized (ParamID id);

    /** Sets the normalized value to the parameter associated to the paramID. The controller must never
        pass this value-change back to the host via the IComponentHandler. It should update the according
        GUI element(s) only!*/
    tresult setParamNormalized (ParamID id, ParamValue value);

    // handler ----------------------------
    /** Gets from host a handler. */
    tresult setComponentHandler (IComponentHandler* handler);

    // view -------------------------------
    /** Creates the editor view of the Plug-in, currently only "editor" is supported, see \ref ViewType.
        The life time of the editor view will never exceed the life time of this controller instance. */
    IPlugView createView (FIDString name);

    __gshared immutable FUID iid = FUID(IEditController_iid);
}

static immutable TUID IEditController_iid = INLINE_UID(0xDCD7BBE3, 0x7742448D, 0xA874AACC, 0x979C759E);

//------------------------------------------------------------------------
/** Knob Mode */
//------------------------------------------------------------------------
alias KnobModes = int;
enum : KnobModes
{
    kCircularMode = 0,      ///< Circular with jump to clicked position
    kRelativCircularMode,   ///< Circular without jump to clicked position
    kLinearMode             ///< Linear: depending on vertical movement
}

alias KnobMode = int;     ///< Knob Mode

