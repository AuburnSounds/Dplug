module derelict.x11.extensions.XI2;

version(linux):

import std.string;

extern (C) nothrow @nogc:

/* Indices into the versions[] array (XExtInt.c). Used as a index to
 * retrieve the minimum version of XI from _XiCheckExtInit.
 * For indices 0 to 6 see XI.h */
const uint Dont_Check = 0;
const uint XInput_2_0 = 7;


const uint XI_2_Major = 2;
const uint XI_2_Minor = 0;

/* Property event flags */
enum {
    XIPropertyDeleted  = 0,
    XIPropertyCreated  = 1,
    XIPropertyModified = 2
}

/* Enter/Leave and Focus In/Out modes */
enum {
    XINotifyNormal        = 0,
    XINotifyGrab          = 1,
    XINotifyUngrab        = 2,
    XINotifyWhileGrabbed  = 3,
    XINotifyPassiveGrab   = 4,
    XINotifyPassiveUngrab = 5
}

/* Enter/Leave and focus In/out detail */
enum {
    XINotifyAncestor         = 0,
    XINotifyVirtual          = 1,
    XINotifyInferior         = 2,
    XINotifyNonlinear        = 3,
    XINotifyNonlinearVirtual = 4,
    XINotifyPointer          = 5,
    XINotifyPointerRoot      = 6,
    XINotifyDetailNone       = 7
}

/* Passive grab types */
enum {
    XIGrabtypeButton  = 0,
    XIGrabtypeKeycode = 1,
    XIGrabtypeEnter   = 2,
    XIGrabtypeFocusIn = 3
}

/* Passive grab modifier */
enum {
    XIAnyModifier  = 1U << 31,
    XIAnyButton    = 0,
    XIAnyKeycode   = 0
}

/* XIAllowEvents event-modes */
enum {
    XIAsyncDevice       = 0,
    XISyncDevice        = 1,
    XIReplayDevice      = 2,
    XIAsyncPairedDevice = 3,
    XIAsyncPair         = 4,
    XISyncPair          = 5
}

/* DeviceChangedEvent change reasons */
enum {
    XISlaveSwitch  = 1,
    XIDeviceChange = 2
}

/* Hierarchy flags */
enum {
    XIMasterAdded    = 1 << 0,
    XIMasterRemoved  = 1 << 1,
    XISlaveAdded     = 1 << 2,
    XISlaveRemoved   = 1 << 3,
    XISlaveAttached  = 1 << 4,
    XISlaveDetached  = 1 << 5,
    XIDeviceEnabled  = 1 << 6,
    XIDeviceDisabled = 1 << 7
}

/* ChangeHierarchy constants */
enum {
    XIAddMaster    = 1,
    XIRemoveMaster = 2,
    XIAttachSlave  = 3,
    XIDetachSlave  = 4
}

const int XIAttachToMaster = 1;
const int XIFloating       = 2;

/* Valuator modes */
enum {
    XIModeRelative = 0,
    XIModeAbsolute = 1
}

/* Device types */
enum {
    XIMasterPointer  = 1,
    XIMasterKeyboard = 2,
    XISlavePointer   = 3,
    XISlaveKeyboard  = 4,
    XIFloatingSlave  = 5
}

/* Device classes */
enum {
    XIKeyClass      = 0,
    XIButtonClass   = 1,
    XIValuatorClass = 2
}

/* Device event flags (common) */
/* Device event flags (key events only) */
const int XIKeyRepeat = 1 << 16;
/* Device event flags (pointer events only) */

/* XI2 event mask macros */
template XISetMask(string ptr, int event){
    const ubyte XISetMask = cast(ubyte)(ptr[(event)>>3] |=  (1 << ((event) & 7)));
}

template XIClearMask(string ptr, int event){
    const ubyte XIClearMask = cast(ubyte)(ptr[(event)>>3] &= ~(1 << ((event) & 7)));
}

template XIMaskIsSet(string ptr, int event){
    const ubyte XIMaskIsSet = cast(ubyte)(ptr[(event)>>3] &   (1 << ((event) & 7)));
}

template XIMaskLen(int event){
    const ubyte XIMaskLen = (((event) >> 3) + 1);
}

/* Fake device ID's for event selection */
enum {
    XIAllDevices       = 0,
    XIAllMasterDevices = 1
}

/* Event types */
enum {
    XI_DeviceChanged    = 1,
    XI_KeyPress         = 2,
    XI_KeyRelease       = 3,
    XI_ButtonPress      = 4,
    XI_ButtonRelease    = 5,
    XI_Motion           = 6,
    XI_Enter            = 7,
    XI_Leave            = 8,
    XI_FocusIn          = 9,
    XI_FocusOut         = 10,
    XI_HierarchyChanged = 11,
    XI_PropertyEvent    = 12,
    XI_RawKeyPress      = 13,
    XI_RawKeyRelease    = 14,
    XI_RawButtonPress   = 15,
    XI_RawButtonRelease = 16,
    XI_RawMotion        = 17,
    XI_LASTEVENT        = XI_RawMotion
}
/* NOTE: XI2LASTEVENT in xserver/include/inputstr.h must be the same value
 * as XI_LASTEVENT if the server is supposed to handle masks etc. for this
 * type of event. */

/* Event masks.
 * Note: the protocol spec defines a mask to be of (1 << type). Clients are
 * free to create masks by bitshifting instead of using these defines.
 */
 enum {
    XI_DeviceChangedMask    = (1 << XI_DeviceChanged),
    XI_KeyPressMask         = (1 << XI_KeyPress),
    XI_KeyReleaseMask       = (1 << XI_KeyRelease),
    XI_ButtonPressMask      = (1 << XI_ButtonPress),
    XI_ButtonReleaseMask    = (1 << XI_ButtonRelease),
    XI_MotionMask           = (1 << XI_Motion),
    XI_EnterMask            = (1 << XI_Enter),
    XI_LeaveMask            = (1 << XI_Leave),
    XI_FocusInMask          = (1 << XI_FocusIn),
    XI_FocusOutMask         = (1 << XI_FocusOut),
    XI_HierarchyChangedMask = (1 << XI_HierarchyChanged),
    XI_PropertyEventMask    = (1 << XI_PropertyEvent),
    XI_RawKeyPressMask      = (1 << XI_RawKeyPress),
    XI_RawKeyReleaseMask    = (1 << XI_RawKeyRelease),
    XI_RawButtonPressMask   = (1 << XI_RawButtonPress),
    XI_RawButtonReleaseMask = (1 << XI_RawButtonRelease),
    XI_RawMotionMask        = (1 << XI_RawMotion)
}
