//-----------------------------------------------------------------------------
// LICENSE
// (c) 2005, Steinberg Media Technologies GmbH, All Rights Reserved
// (c) 2018, Guillaume Piolat (contact@auburnsounds.com)
//-----------------------------------------------------------------------------
//
// This Software Development Kit is licensed under the terms of the General
// Public License (GPL) Version 3.
//
// This source is part of the "Auburn Sounds (Guillaume Piolat) extension to the 
// Steinberg VST 3 Plug-in SDK".
//
// Details of that license can be found at: www.gnu.org/licenses/gpl-3.0.html
//
// Dual-licence:
// 
// The "Auburn Sounds (Guillaume Piolat) extension to the Steinberg VST 3 Plug-in
// SDK", hereby referred to as DPLUG:VST3, is a language translation of the VST3 
// SDK suitable for usage in Dplug. Any Licensee of a currently valid Steinberg 
// VST 3 Plug-In SDK Licensing Agreement (version 2.2.4 or ulterior, hereby referred
// to as the AGREEMENT), is granted by Auburn Sounds (Guillaume Piolat) a non-exclusive, 
// worldwide, nontransferable license during the term the AGREEMENT to use parts
// of DPLUG:VST3 not covered by the AGREEMENT, as if they were originally 
// inside the Licensed Software Developer Kit mentionned in the AGREEMENT. 
// Under this licence all conditions that apply to the Licensed Software Developer 
// Kit also apply to DPLUG:VST3.
//
//-----------------------------------------------------------------------------
module dplug.vst3.ivstunit;

version(VST3):

import dplug.vst3.ftypes;
import dplug.vst3.ibstream;


enum UnitID kRootUnitId = 0;        ///< identifier for the top level unit (root)
enum UnitID kNoParentUnitId = -1;   ///< used for the root unit which doesn't have a parent.

/** Special ProgramListIDs for UnitInfo */
enum ProgramListID kNoProgramListId = -1;   ///< no programs are used in the unit.

/** Basic Unit Description.
\see IUnitInfo */
struct UnitInfo
{
    UnitID id;                      ///< unit identifier
    UnitID parentUnitId;            ///< identifier of parent unit (kNoParentUnitId: does not apply, this unit is the root)
    String128 name;                 ///< name, optional for the root component, required otherwise
    ProgramListID programListId;    ///< id of program list used in unit (kNoProgramListId = no programs used in this unit)
}

mixin SMTG_TYPE_SIZE_CHECK!(UnitInfo, 268, 268, 268);

/** Basic Program List Description.
\see IUnitInfo */
struct ProgramListInfo
{
    ProgramListID id;               ///< program list identifier
    String128 name;                 ///< name of program list
    int32 programCount;             ///< number of programs in this list
}

mixin SMTG_TYPE_SIZE_CHECK!(ProgramListInfo, 264, 264, 264);

/** Special programIndex value for IUnitHandler::notifyProgramListChange */
enum int32 kAllProgramInvalid = -1;     ///< all program information is invalid

/** Host callback for unit support.
\ingroup vstIHost vst300
- [host imp]
- [extends IComponentHandler]
- [released: 3.0.0]

Host callback interface, used with IUnitInfo.
Retrieve via queryInterface from IComponentHandler.

\see \ref vst3Units, IUnitInfo */
interface IUnitHandler: FUnknown
{
public:
nothrow:
@nogc:
    /** Notify host when a module is selected in Plug-in GUI. */
    tresult notifyUnitSelection (UnitID unitId);

    /** Tell host that the Plug-in controller changed a program list (rename, load, PitchName changes).
        \param listId is the specified program list ID to inform.
        \param programIndex : when kAllProgramInvalid, all program information is invalid, otherwise only the program of given index. */
    tresult notifyProgramListChange (ProgramListID listId, int32 programIndex);

    __gshared immutable TUID iid = INLINE_UID( 0x4B5147F8, 0x4654486B, 0x8DAB30BA, 0x163A3C56);
}


/** Edit controller extension to describe the Plug-in structure.
\ingroup vstIPlug vst300
- [plug imp]
- [extends IEditController]
- [released: 3.0.0]

IUnitInfo describes the internal structure of the Plug-in.
- The root unit is the component itself, so getUnitCount must return 1 at least.
- The root unit id has to be 0 (kRootUnitId).
- Each unit can reference one program list - this reference must not change.
- Each unit using a program list, references one program of the list.

\see \ref vst3Units, IUnitHandler */
interface IUnitInfo: FUnknown
{
public:
nothrow:
@nogc:
    /** Returns the flat count of units. */
    int32 getUnitCount ();

    /** Gets UnitInfo for a given index in the flat list of unit. */
    tresult getUnitInfo (int32 unitIndex, ref UnitInfo info /*out*/);

    /** Component intern program structure. */
    /** Gets the count of Program List. */
    int32 getProgramListCount ();

    /** Gets for a given index the Program List Info. */
    tresult getProgramListInfo (int32 listIndex, ref ProgramListInfo info /*out*/);

    /** Gets for a given program list ID and program index its program name. */
    tresult getProgramName (ProgramListID listId, int32 programIndex, String128* name /*out*/);

    /** Gets for a given program list ID, program index and attributeId the associated attribute value. */
    tresult getProgramInfo (ProgramListID listId, int32 programIndex,
        const(wchar)* attributeId /*in*/, String128* attributeValue /*out*/);

    /** Returns kResultTrue if the given program index of a given program list ID supports PitchNames. */
    tresult hasProgramPitchNames (ProgramListID listId, int32 programIndex);

    /** Gets the PitchName for a given program list ID, program index and pitch.
        If PitchNames are changed the Plug-in should inform the host with IUnitHandler::notifyProgramListChange. */
    tresult getProgramPitchName (ProgramListID listId, int32 programIndex,
        int16 midiPitch, String128* name /*out*/);

    // units selection --------------------
    /** Gets the current selected unit. */
    UnitID getSelectedUnit ();

    /** Sets a new selected unit. */
    tresult selectUnit (UnitID unitId);

    /** Gets the according unit if there is an unambiguous relation between a channel or a bus and a unit.
        This method mainly is intended to find out which unit is related to a given MIDI input channel. */
    tresult getUnitByBus (MediaType type, BusDirection dir, int32 busIndex,
        int32 channel, ref UnitID unitId /*out*/);

    /** Receives a preset data stream.
        - If the component supports program list data (IProgramListData), the destination of the data
          stream is the program specified by list-Id and program index (first and second parameter)
        - If the component supports unit data (IUnitData), the destination is the unit specified by the first
          parameter - in this case parameter programIndex is < 0). */
    tresult setUnitProgramData (int32 listOrUnitId, int32 programIndex, IBStream data);


    __gshared immutable TUID iid = INLINE_UID( 0x3D4BD6B5, 0x913A4FD2, 0xA886E768, 0xA5EB92C1);
}

/+

/** Component extension to access program list data.
\ingroup vstIPlug vst300
- [plug imp]
- [extends IComponent]
- [released: 3.0.0]

A component can either support program list data via this interface or
unit preset data (IUnitData), but not both!

\see \ref vst3UnitPrograms */

class IProgramListData: public FUnknown
{
public:

    /** Returns kResultTrue if the given Program List ID supports Program Data. */
    virtual tresult PLUGIN_API programDataSupported (ProgramListID listId) = 0;

    /** Gets for a given program list ID and program index the program Data. */
    virtual tresult PLUGIN_API getProgramData (ProgramListID listId, int32 programIndex, IBStream* data) = 0;

    /** Sets for a given program list ID and program index a program Data. */
    virtual tresult PLUGIN_API setProgramData (ProgramListID listId, int32 programIndex, IBStream* data) = 0;


    static const FUID iid;
};

DECLARE_CLASS_IID (IProgramListData, 0x8683B01F, 0x7B354F70, 0xA2651DEC, 0x353AF4FF)


/** Component extension to access unit data.
\ingroup vstIPlug vst300
- [plug imp]
- [extends IComponent]
- [released: 3.0.0]

A component can either support unit preset data via this interface or
program list data (IProgramListData), but not both!

\see \ref vst3UnitPrograms */

class IUnitData: public FUnknown
{
public:

    /** Returns kResultTrue if the specified unit supports export and import of preset data. */
    virtual tresult PLUGIN_API unitDataSupported (UnitID unitID) = 0;

    /** Gets the preset data for the specified unit. */
    virtual tresult PLUGIN_API getUnitData (UnitID unitId, IBStream* data) = 0;

    /** Sets the preset data for the specified unit. */
    virtual tresult PLUGIN_API setUnitData (UnitID unitId, IBStream* data) = 0;


    static const FUID iid;
};

DECLARE_CLASS_IID (IUnitData, 0x6C389611, 0xD391455D, 0xB870B833, 0x94A0EFDD)

+/