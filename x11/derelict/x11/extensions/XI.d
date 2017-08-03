module derelict.x11.extensions.XI;

version(linux):

import std.string : string;
import core.stdc.config;

/* Definitions used by the server, library and client */

const int sz_xGetExtensionVersionReq            = 8;
const int sz_xGetExtensionVersionReply          = 32;
const int sz_xListInputDevicesReq               = 4;
const int sz_xListInputDevicesReply             = 32;
const int sz_xOpenDeviceReq                     = 8;
const int sz_xOpenDeviceReply                   = 32;
const int sz_xCloseDeviceReq                    = 8;
const int sz_xSetDeviceModeReq                  = 8;
const int sz_xSetDeviceModeReply                = 32;
const int sz_xSelectExtensionEventReq           = 12;
const int sz_xGetSelectedExtensionEventsReq     = 8;
const int sz_xGetSelectedExtensionEventsReply   = 32;
const int sz_xChangeDeviceDontPropagateListReq  = 12;
const int sz_xGetDeviceDontPropagateListReq     = 8;
const int sz_xGetDeviceDontPropagateListReply   = 32;
const int sz_xGetDeviceMotionEventsReq          = 16;
const int sz_xGetDeviceMotionEventsReply        = 32;
const int sz_xChangeKeyboardDeviceReq           = 8;
const int sz_xChangeKeyboardDeviceReply         = 32;
const int sz_xChangePointerDeviceReq            = 8;
const int sz_xChangePointerDeviceReply          = 32;
const int sz_xGrabDeviceReq                     = 20;
const int sz_xGrabDeviceReply                   = 32;
const int sz_xUngrabDeviceReq                   = 12;
const int sz_xGrabDeviceKeyReq                  = 20;
const int sz_xGrabDeviceKeyReply                = 32;
const int sz_xUngrabDeviceKeyReq                = 16;
const int sz_xGrabDeviceButtonReq               = 20;
const int sz_xGrabDeviceButtonReply             = 32;
const int sz_xUngrabDeviceButtonReq             = 16;
const int sz_xAllowDeviceEventsReq              = 12;
const int sz_xGetDeviceFocusReq                 = 8;
const int sz_xGetDeviceFocusReply               = 32;
const int sz_xSetDeviceFocusReq                 = 16;
const int sz_xGetFeedbackControlReq             = 8;
const int sz_xGetFeedbackControlReply           = 32;
const int sz_xChangeFeedbackControlReq          = 12;
const int sz_xGetDeviceKeyMappingReq            = 8;
const int sz_xGetDeviceKeyMappingReply          = 32;
const int sz_xChangeDeviceKeyMappingReq         = 8;
const int sz_xGetDeviceModifierMappingReq       = 8;
const int sz_xSetDeviceModifierMappingReq       = 8;
const int sz_xSetDeviceModifierMappingReply     = 32;
const int sz_xGetDeviceButtonMappingReq         = 8;
const int sz_xGetDeviceButtonMappingReply       = 32;
const int sz_xSetDeviceButtonMappingReq         = 8;
const int sz_xSetDeviceButtonMappingReply       = 32;
const int sz_xQueryDeviceStateReq               = 8;
const int sz_xQueryDeviceStateReply             = 32;
const int sz_xSendExtensionEventReq             = 16;
const int sz_xDeviceBellReq                     = 8;
const int sz_xSetDeviceValuatorsReq             = 8;
const int sz_xSetDeviceValuatorsReply           = 32;
const int sz_xGetDeviceControlReq               = 8;
const int sz_xGetDeviceControlReply             = 32;
const int sz_xChangeDeviceControlReq            = 8;
const int sz_xChangeDeviceControlReply          = 32;
const int sz_xListDevicePropertiesReq           = 8;
const int sz_xListDevicePropertiesReply         = 32;
const int sz_xChangeDevicePropertyReq           = 20;
const int sz_xDeleteDevicePropertyReq           = 12;
const int sz_xGetDevicePropertyReq              = 24;
const int sz_xGetDevicePropertyReply            = 32;

const string INAME = "XInputExtension";

enum {
    XI_KEYBOARD                         = "KEYBOARD",
    XI_MOUSE                            = "MOUSE",
    XI_TABLET                           = "TABLET",
    XI_TOUCHSCREEN                      = "TOUCHSCREEN",
    XI_TOUCHPAD                         = "TOUCHPAD",
    XI_BARCODE                          = "BARCODE",
    XI_BUTTONBOX                        = "BUTTONBOX",
    XI_KNOB_BOX                         = "KNOB_BOX",
    XI_ONE_KNOB                         = "ONE_KNOB",
    XI_NINE_KNOB                        = "NINE_KNOB",
    XI_TRACKBALL                        = "TRACKBALL",
    XI_QUADRATURE                       = "QUADRATURE",
    XI_ID_MODULE                        = "ID_MODULE",
    XI_SPACEBALL                        = "SPACEBALL",
    XI_DATAGLOVE                        = "DATAGLOVE",
    XI_EYETRACKER                       = "EYETRACKER",
    XI_CURSORKEYS                       = "CURSORKEYS",
    XI_FOOTMOUSE                        = "FOOTMOUSE",
    XI_JOYSTICK                         = "JOYSTICK"
}

/* Indices into the versions[] array (XExtInt.c). Used as a index to
 * retrieve the minimum version of XI from _XiCheckExtInit */
enum {
    Dont_Check                          = 0,
    XInput_Initial_Release              = 1,
    XInput_Add_XDeviceBell              = 2,
    XInput_Add_XSetDeviceValuators      = 3,
    XInput_Add_XChangeDeviceControl     = 4,
    XInput_Add_DevicePresenceNotify     = 5,
    XInput_Add_DeviceProperties         = 6
}
/* DO NOT ADD TO HERE -> XI2 */

enum {
    XI_Absent                           = 0,
    XI_Present                          = 1
}

enum {
    XI_Initial_Release_Major            = 1,
    XI_Initial_Release_Minor            = 0
}

enum {
    XI_Add_XDeviceBell_Major            = 1,
    XI_Add_XDeviceBell_Minor            = 1
}

enum {
    XI_Add_XSetDeviceValuators_Major    = 1,
    XI_Add_XSetDeviceValuators_Minor    = 2
}

enum {
    XI_Add_XChangeDeviceControl_Major   = 1,
    XI_Add_XChangeDeviceControl_Minor   = 3
}

enum {
    XI_Add_DevicePresenceNotify_Major   = 1,
    XI_Add_DevicePresenceNotify_Minor   = 4
}

enum {
    XI_Add_DeviceProperties_Major       = 1,
    XI_Add_DeviceProperties_Minor       = 5
}

enum {
    DEVICE_RESOLUTION                   = 1,
    DEVICE_ABS_CALIB                    = 2,
    DEVICE_CORE                         = 3,
    DEVICE_ENABLE                       = 4,
    DEVICE_ABS_AREA                     = 5
}

const int NoSuchExtension           = 1;

const int COUNT                     = 0;
const int CREATE                    = 1;

const int NewPointer                = 0;
const int NewKeyboard               = 1;

const int XPOINTER                  = 0;
const int XKEYBOARD                 = 1;

const int UseXKeyboard              = 0xFF;

enum {
    IsXPointer                          = 0,
    IsXKeyboard                         = 1,
    IsXExtensionDevice                  = 2,
    IsXExtensionKeyboard                = 3,
    IsXExtensionPointer                 = 4
}

enum {
    AsyncThisDevice                     = 0,
    SyncThisDevice                      = 1,
    ReplayThisDevice                    = 2,
    AsyncOtherDevices                   = 3,
    AsyncAll                            = 4,
    SyncAll                             = 5
}

    const int FollowKeyboard            = 3;
    const int RevertToFollowKeyboard    = 3;

    const c_long DvAccelNum             = (1L << 0);
    const c_long DvAccelDenom           = (1L << 1);
    const c_long DvThreshold            = (1L << 2);

    const c_long DvKeyClickPercent      = (1L<<0);
    const c_long DvPercent              = (1L<<1);
    const c_long DvPitch                = (1L<<2);
    const c_long DvDuration             = (1L<<3);
    const c_long DvLed                  = (1L<<4);
    const c_long DvLedMode              = (1L<<5);
    const c_long DvKey                  = (1L<<6);
    const c_long DvAutoRepeatMode       = (1L<<7);

    const c_long DvString               = (1L << 0);

    const c_long DvInteger              = (1L << 0);

enum {
    DeviceMode                          = (1L << 0),
    Relative                            = 0,
    Absolute                            = 1
}

enum {
    ProximityState                      = (1L << 1),
    InProximity                         = (0L << 1),
    OutOfProximity                      = (1L << 1)
}

const int AddToList                 = 0;
const int DeleteFromList            = 1;

enum {
    KeyClass                            = 0,
    ButtonClass                         = 1,
    ValuatorClass                       = 2,
    FeedbackClass                       = 3,
    ProximityClass                      = 4,
    FocusClass                          = 5,
    OtherClass                          = 6,
    AttachClass                         = 7
}

enum {
    KbdFeedbackClass                    = 0,
    PtrFeedbackClass                    = 1,
    StringFeedbackClass                 = 2,
    IntegerFeedbackClass                = 3,
    LedFeedbackClass                    = 4,
    BellFeedbackClass                   = 5
}

enum {
    _devicePointerMotionHint            = 0,
    _deviceButton1Motion                = 1,
    _deviceButton2Motion                = 2,
    _deviceButton3Motion                = 3,
    _deviceButton4Motion                = 4,
    _deviceButton5Motion                = 5,
    _deviceButtonMotion                 = 6,
    _deviceButtonGrab                   = 7,
    _deviceOwnerGrabButton              = 8,
    _noExtensionEvent                   = 9
}

const int _devicePresence           = 0;

const int _deviceEnter              = 0;
const int _deviceLeave              = 1;

/* Device presence notify states */
enum {
    DeviceAdded                         = 0,
    DeviceRemoved                       = 1,
    DeviceEnabled                       = 2,
    DeviceDisabled                      = 3,
    DeviceUnrecoverable                 = 4,
    DeviceControlChanged                = 5
}

/* XI Errors */
enum {
    XI_BadDevice                        = 0,
    XI_BadEvent                         = 1,
    XI_BadMode                          = 2,
    XI_DeviceBusy                       = 3,
    XI_BadClass                         = 4
}

/*
 * Make XEventClass be a CARD32 for 64 bit servers.  Don't affect client
 * definition of XEventClass since that would be a library interface change.
 * See the top of X.h for more _XSERVER64 magic.
 *
 * But, don't actually use the CARD32 type.  We can't get it defined here
 * without polluting the namespace.
 */
version(_XSERVER64){
    alias XEventClass = uint;
}else{
    alias XEventClass = c_ulong;
}

/*******************************************************************
 *
 * Extension version structure.
 *
 */

struct XExtensionVersion{
    int     present;
    short   major_version;
    short   minor_version;
}
