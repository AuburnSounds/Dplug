module derelict.x11.extensions.XInput;

version(linux):

public import
	derelict.x11.X,
    derelict.x11.Xlib,
    derelict.x11.extensions.XI;


extern(C):


enum _deviceKeyPress = 0;
enum _deviceKeyRelease = 1;

enum _deviceButtonPress = 0;
enum _deviceButtonRelease = 1;

enum _deviceMotionNotify = 0;

enum _deviceFocusIn = 0;
enum _deviceFocusOut = 1;

enum _proximityIn = 0;
enum _proximityOut = 1;

enum _deviceStateNotify = 0;
enum _deviceMappingNotify = 1;
enum _changeDeviceNotify = 2;
/* Space of 3 between is necessary! Reserved for DeviceKeyStateNotify,
   DeviceButtonStateNotify, DevicePresenceNotify (essentially unused). This
   code has to be in sync with FixExtensionEvents() in xserver/Xi/extinit.c */
enum _propertyNotify = 6;

auto FindTypeAndClass(A,B,C,D,E)(ref A d, ref B type, ref C _class, D classid, E offset){
    int _i;
    XInputClassInfo *_ip;
    type = 0;
    _class = 0;
    for(_i=0, _ip= (cast(XDevice *) d).classes; _i < (cast(XDevice *) d).num_classes; _i++, _ip++)
        if (_ip.input_class == classid){
            type =  _ip.event_type_base + offset;
            _class =  (cast(XDevice*)d).device_id << 8 | type;
        }
}

auto DeviceKeyPress(A,B,C)(ref A d, ref B type, ref C _class){
    FindTypeAndClass(d, type, _class, KeyClass, _deviceKeyPress);
}

auto DeviceKeyRelease(A,B,C)(ref A d, ref B type, ref C _class){
    FindTypeAndClass(d, type, _class, KeyClass, _deviceKeyRelease);
}

auto DeviceButtonPress(A,B,C)(ref A d, ref B type, ref C _class){
    FindTypeAndClass(d, type, _class, ButtonClass, _deviceButtonPress);
}

auto DeviceButtonRelease(A,B,C)(ref A d, ref B type, ref C _class){
    FindTypeAndClass(d, type, _class, ButtonClass, _deviceButtonRelease);
}

auto DeviceMotionNotify(A,B,C)(ref A d, ref B type, ref C _class){
    FindTypeAndClass(d, type, _class, ValuatorClass, _deviceMotionNotify);
}

auto DeviceFocusIn(A,B,C)(ref A d, ref B type, ref C _class){
    FindTypeAndClass(d, type, _class, FocusClass, _deviceFocusIn);
}

auto DeviceFocusOut(A,B,C)(ref A d, ref B type, ref C _class){
    FindTypeAndClass(d, type, _class, FocusClass, _deviceFocusOut);
}

auto ProximityIn(A,B,C)(ref A d, ref B type, ref C _class){
    FindTypeAndClass(d, type, _class, ProximityClass, _proximityIn);
}

auto ProximityOut(A,B,C)(ref A d, ref B type, ref C _class){
    FindTypeAndClass(d, type, _class, ProximityClass, _proximityOut);
}

auto DeviceStateNotify(A,B,C)(ref A d, ref B type, ref C _class){
    FindTypeAndClass(d, type, _class, OtherClass, _deviceStateNotify);
}

auto DeviceMappingNotify(A,B,C)(ref A d, ref B type, ref C _class){
    FindTypeAndClass(d, type, _class, OtherClass, _deviceMappingNotify);
}

auto ChangeDeviceNotify(A,B,C)(ref A d, ref B type, ref C _class){
    FindTypeAndClass(d, type, _class, OtherClass, _changeDeviceNotify);
}

auto DevicePropertyNotify(A,B,C)(ref A d, ref B type, ref C _class){
    FindTypeAndClass(d, type, _class, OtherClass, _propertyNotify);
}

auto DevicePointerMotionHint(A,B,C)(ref A d, ref B type, ref C _class){
    _class =  (cast(XDevice *) d).device_id << 8 | _devicePointerMotionHint;
}

auto DeviceButton1Motion(A,B,C)(ref A d, ref B type, ref C _class){
    _class =  (cast(XDevice *) d).device_id << 8 | _deviceButton1Motion;
}

auto DeviceButton2Motion(A,B,C)(ref A d, ref B type, ref C _class){
    _class =  (cast(XDevice *) d).device_id << 8 | _deviceButton2Motion;
}

auto DeviceButton3Motion(A,B,C)(ref A d, ref B type, ref C _class){
    _class =  (cast(XDevice *) d).device_id << 8 | _deviceButton3Motion;
}

auto DeviceButton4Motion(A,B,C)(A d, B type, ref C _class){
    _class =  (cast(XDevice *) d).device_id << 8 | _deviceButton4Motion;
}

auto DeviceButton5Motion(A,B,C)(ref A d, ref B type, ref C _class){
    _class =  (cast(XDevice *) d).device_id << 8 | _deviceButton5Motion;
}

auto DeviceButtonMotion(A,B,C)(A d, B type, ref C _class){
    _class =  (cast(XDevice *) d).device_id << 8 | _deviceButtonMotion;
}

auto DeviceOwnerGrabButton(A,B,C)(ref A d, ref B type, ref C _class){
    _class =  (cast(XDevice *) d).device_id << 8 | _deviceOwnerGrabButton;
}

auto DeviceButtonPressGrab(A,B,C)(ref A d, ref B type, ref C _class){
    _class =  (cast(XDevice *) d).device_id << 8 | _deviceButtonGrab;
}

auto NoExtensionEvent(A,B,C)(ref A d, ref B type, ref C _class){
    _class =  (cast(XDevice *) d).device_id << 8 | _noExtensionEvent;
}


/* We need the declaration for DevicePresence. */
extern int _XiGetDevicePresenceNotifyEvent(Display *);
extern void _xibaddevice( Display *dpy, int *error);
extern void _xibadclass( Display *dpy, int *error);
extern void _xibadevent( Display *dpy, int *error);
extern void _xibadmode( Display *dpy, int *error);
extern void _xidevicebusy( Display *dpy, int *error);

auto DevicePresence(A,B,C)(A dpy, B type, C _class){
    type = _XiGetDevicePresenceNotifyEvent(dpy);
    _class =  (0x10000 | _devicePresence);
}

/* Errors */
auto BadDevice(A,B)(ref A dpy, ref B error){
    return _xibaddevice(dpy, &error);
}

auto BadClass(A,B)(ref A dpy, ref B error){
    return _xibadclass(dpy, &error);
}

auto BadEvent(A,B)(ref A dpy, ref B error){
    return _xibadevent(dpy, &error);
}

auto BadMode(A,B)(ref A dpy, ref B error){
    return _xibadmode(dpy, &error);
}

auto DeviceBusy(A,B)(ref A dpy, ref B error){
    return _xidevicebusy(dpy, &error);
}

/***************************************************************
 *
 * DeviceKey events.  These events are sent by input devices that
 * support input class Keys.
 * The location of the X pointer is reported in the coordinate
 * fields of the x,y and x_root,y_root fields.
 *
 */

struct XDeviceKeyEvent {
    int            type;         /* of event */
    ulong  serial;       /* # of last request processed */
    Bool           send_event;   /* true if from SendEvent request */
    Display        *display;     /* Display the event was read from */
    Window         window;       /* "event" window reported relative to */
    XID            deviceid;
    Window         root;         /* root window event occured on */
    Window         subwindow;    /* child window */
    Time           time;         /* milliseconds */
    int            x, y;         /* x, y coordinates in event window */
    int            x_root;       /* coordinates relative to root */
    int            y_root;       /* coordinates relative to root */
    uint   state;        /* key or button mask */
    uint   keycode;      /* detail */
    Bool           same_screen;  /* same screen flag */
    uint   device_state; /* device key or button mask */
    ubyte  axes_count;
    ubyte  first_axis;
    int[6] axis_data;
}

alias XDeviceKeyPressedEvent = XDeviceKeyEvent;
alias XDeviceKeyReleasedEvent = XDeviceKeyEvent;

/*******************************************************************
 *
 * DeviceButton events.  These events are sent by extension devices
 * that support input class Buttons.
 *
 */

struct XDeviceButtonEvent {
    int           type;         /* of event */
    ulong serial;       /* # of last request processed by server */
    Bool          send_event;   /* true if from a SendEvent request */
    Display       *display;     /* Display the event was read from */
    Window        window;       /* "event" window reported relative to */
    XID           deviceid;
    Window        root;         /* root window that the event occured on */
    Window        subwindow;    /* child window */
    Time          time;         /* milliseconds */
    int           x, y;         /* x, y coordinates in event window */
    int           x_root;       /* coordinates relative to root */
    int           y_root;       /* coordinates relative to root */
    uint  state;        /* key or button mask */
    uint  button;       /* detail */
    Bool          same_screen;  /* same screen flag */
    uint  device_state; /* device key or button mask */
    ubyte axes_count;
    ubyte first_axis;
    int[6] axis_data;
}

alias XDeviceButtonPressedEvent = XDeviceButtonEvent;
alias XDeviceButtonReleasedEvent = XDeviceButtonEvent;

/*******************************************************************
 *
 * DeviceMotionNotify event.  These events are sent by extension devices
 * that support input class Valuators.
 *
 */

struct XDeviceMotionEvent {
    int           type;        /* of event */
    ulong serial;      /* # of last request processed by server */
    Bool          send_event;  /* true if from a SendEvent request */
    Display       *display;    /* Display the event was read from */
    Window        window;      /* "event" window reported relative to */
    XID           deviceid;
    Window        root;        /* root window that the event occured on */
    Window        subwindow;   /* child window */
    Time          time;        /* milliseconds */
    int           x, y;        /* x, y coordinates in event window */
    int           x_root;      /* coordinates relative to root */
    int           y_root;      /* coordinates relative to root */
    uint  state;       /* key or button mask */
    char          is_hint;     /* detail */
    Bool          same_screen; /* same screen flag */
    uint  device_state; /* device key or button mask */
    ubyte axes_count;
    ubyte first_axis;
    int[6] axis_data;
}

/*******************************************************************
 *
 * DeviceFocusChange events.  These events are sent when the focus
 * of an extension device that can be focused is changed.
 *
 */

struct XDeviceFocusChangeEvent {
    int           type;       /* of event */
    ulong serial;     /* # of last request processed by server */
    Bool          send_event; /* true if from a SendEvent request */
    Display       *display;   /* Display the event was read from */
    Window        window;     /* "event" window reported relative to */
    XID           deviceid;
    int           mode;       /* NotifyNormal, NotifyGrab, NotifyUngrab */
    int           detail;
	/*
	 * NotifyAncestor, NotifyVirtual, NotifyInferior, 
	 * NotifyNonLinear,NotifyNonLinearVirtual, NotifyPointer,
	 * NotifyPointerRoot, NotifyDetailNone 
	 */
    Time                time;
}

alias XDeviceFocusInEvent = XDeviceFocusChangeEvent;
alias XDeviceFocusOutEvent = XDeviceFocusChangeEvent;

/*******************************************************************
 *
 * ProximityNotify events.  These events are sent by those absolute
 * positioning devices that are capable of generating proximity information.
 *
 */

struct XProximityNotifyEvent {
    int             type;      /* ProximityIn or ProximityOut */        
    ulong   serial;    /* # of last request processed by server */
    Bool            send_event; /* true if this came from a SendEvent request */
    Display         *display;  /* Display the event was read from */
    Window          window;      
    XID	            deviceid;
    Window          root;            
    Window          subwindow;      
    Time            time;            
    int             x, y;            
    int             x_root, y_root;  
    uint    state;           
    Bool            same_screen;     
    uint    device_state; /* device key or button mask */
    ubyte   axes_count;
    ubyte   first_axis;
    int[6] axis_data;
}
alias XProximityInEvent = XProximityNotifyEvent;
alias XProximityOutEvent = XProximityNotifyEvent;

/*******************************************************************
 *
 * DeviceStateNotify events are generated on EnterWindow and FocusIn 
 * for those clients who have selected DeviceState.
 *
 */

struct XInputClass {
    ubyte	class_;
    ubyte	length;
}

struct XDeviceStateNotifyEvent {
    int           type;
    ulong serial;       /* # of last request processed by server */
    Bool          send_event;   /* true if this came from a SendEvent request */
    Display       *display;     /* Display the event was read from */
    Window        window;
    XID           deviceid;
    Time          time;
    int           num_classes;
    char[64] data;
}	

struct XValuatorStatus {
    ubyte	class_;
    ubyte	length;
    ubyte	num_valuators;
    ubyte	mode;
    int[6] valuators;
}

struct XKeyStatus {
    ubyte	class_;
    ubyte	length;
    short   num_keys;
    char[32] keys;
}

struct XButtonStatus {
    ubyte class_;
    ubyte length;
    short num_buttons;
    char[32] buttons;
}

/*******************************************************************
 *
 * DeviceMappingNotify event.  This event is sent when the key mapping,
 * modifier mapping, or button mapping of an extension device is changed.
 *
 */

struct XDeviceMappingEvent {
    int           type;
    ulong serial;       /* # of last request processed by server */
    Bool          send_event;   /* true if this came from a SendEvent request */
    Display       *display;     /* Display the event was read from */
    Window        window;       /* unused */
    XID           deviceid;
    Time          time;
    int           request;      /* one of MappingModifier, MappingKeyboard,
                                    MappingPointer */
    int           first_keycode;/* first keycode */
    int           count;        /* defines range of change w. first_keycode*/
}

/*******************************************************************
 *
 * ChangeDeviceNotify event.  This event is sent when an 
 * XChangeKeyboard or XChangePointer request is made.
 *
 */

struct XChangeDeviceNotifyEvent {
    int           type;
    ulong serial;       /* # of last request processed by server */
    Bool          send_event;   /* true if this came from a SendEvent request */
    Display       *display;     /* Display the event was read from */
    Window        window;       /* unused */
    XID           deviceid;
    Time          time;
    int           request;      /* NewPointer or NewKeyboard */
}

/*******************************************************************
 *
 * DevicePresenceNotify event.  This event is sent when the list of
 * input devices changes, in which case devchange will be false, and
 * no information about the change will be contained in the event;
 * the client should use XListInputDevices() to learn what has changed.
 *
 * If devchange is true, an attribute that the server believes is
 * important has changed on a device, and the client should use
 * XGetDeviceControl to examine the device.  If control is non-zero,
 * then that control has changed meaningfully.
 */

struct XDevicePresenceNotifyEvent {
    int           type;
    ulong serial;       /* # of last request processed by server */
    Bool          send_event;   /* true if this came from a SendEvent request */
    Display       *display;     /* Display the event was read from */
    Window        window;       /* unused */
    Time          time;
    Bool          devchange;
    XID           deviceid;
    XID           control;
}

/*
 * Notifies the client that a property on a device has changed value. The
 * client is expected to query the server for updated value of the property.
 */
struct XDevicePropertyNotifyEvent {
    int           type;
    ulong serial;       /* # of last request processed by server */
    Bool          send_event;   /* true if this came from a SendEvent request */
    Display       *display;     /* Display the event was read from */
    Window        window;       /* unused */
    Time          time;
    XID           deviceid;     /* id of the device that changed */
    Atom          atom;         /* the property that changed */
    int           state;        /* PropertyNewValue or PropertyDeleted */
}


/*******************************************************************
 *
 * Control structures for input devices that support input class
 * Feedback.  These are used by the XGetFeedbackControl and 
 * XChangeFeedbackControl functions.
 *
 */

struct XFeedbackState {
     XID            class_;
     int            length;
     XID            id;
}

struct XKbdFeedbackState {
    XID     class_;
    int     length;
    XID     id;
    int     click;
    int     percent;
    int     pitch;
    int     duration;
    int     led_mask;
    int     global_auto_repeat;
    char[32] auto_repeats;
}

struct XPtrFeedbackState {
    XID     class_;
    int     length;
    XID     id;
    int     accelNum;
    int     accelDenom;
    int     threshold;
}

struct XIntegerFeedbackState {
    XID     class_;
    int     length;
    XID     id;
    int     resolution;
    int     minVal;
    int     maxVal;
}

struct XStringFeedbackState {
    int     length;
    XID     id;
    int     max_symbols;
    int     num_syms_supported;
    KeySym  *syms_supported;
}

struct XBellFeedbackState {
    XID     class_;
    int     length;
    XID     id;
    int     percent;
    int     pitch;
    int     duration;
}

struct XLedFeedbackState {
    XID     class_;
    int     length;
    XID     id;
    int     led_values;
    int     led_mask;
}

struct XFeedbackControl {
     XID            class_;
     int            length;
     XID	    id;
}

struct XPtrFeedbackControl {
    XID     class_;
    int     length;
    XID     id;
    int     accelNum;
    int     accelDenom;
    int     threshold;
}

struct XKbdFeedbackControl {
    XID     class_;
    int     length;
    XID     id;
    int     click;
    int     percent;
    int     pitch;
    int     duration;
    int     led_mask;
    int     led_value;
    int     key;
    int     auto_repeat_mode;
}

struct XStringFeedbackControl {
    XID     class_;
    int     length;
    XID     id;
    int     num_keysyms;
    KeySym  *syms_to_display;
}

struct XIntegerFeedbackControl {
    XID     class_;
    int     length;
    XID     id;
    int     int_to_display;
}

struct XBellFeedbackControl {
    XID     class_;
    int     length;
    XID     id;
    int     percent;
    int     pitch;
    int     duration;
}

struct XLedFeedbackControl {
    XID     class_;
    int     length;
    XID     id;
    int     led_mask;
    int     led_values;
}

/*******************************************************************
 *
 * Device control structures.
 *
 */

struct XDeviceControl {
     XID            control;
     int            length;
}

struct XDeviceResolutionControl {
     XID            control;
     int            length;
     int            first_valuator;
     int            num_valuators;
     int            *resolutions;
}

struct XDeviceResolutionState {
     XID            control;
     int            length;
     int            num_valuators;
     int            *resolutions;
     int            *min_resolutions;
     int            *max_resolutions;
}

struct XDeviceAbsCalibControl {
    XID             control;
    int             length;
    int             min_x;
    int             max_x;
    int             min_y;
    int             max_y;
    int             flip_x;
    int             flip_y;
    int             rotation;
    int             button_threshold;
}

alias XDeviceAbsCalibState = XDeviceAbsCalibControl;

struct XDeviceAbsAreaControl {
    XID             control;
    int             length;
    int             offset_x;
    int             offset_y;
    int             width;
    int             height;
    int             screen;
    XID             following;
}

alias XDeviceAbsAreaState = XDeviceAbsAreaControl;

struct XDeviceCoreControl {
    XID             control;
    int             length;
    int             status;
}

struct XDeviceCoreState {
    XID             control;
    int             length;
    int             status;
    int             iscore;
}

struct XDeviceEnableControl {
    XID             control;
    int             length;
    int             enable;
}

alias XDeviceEnableState = XDeviceEnableControl;

/*******************************************************************
 *
 * An array of XDeviceList structures is returned by the 
 * XListInputDevices function.  Each entry contains information
 * about one input device.  Among that information is an array of 
 * pointers to structures that describe the characteristics of 
 * the input device.
 *
 */

struct XAnyClassInfo {
    XID 	class_;
    int 	length;
}

alias XAnyClassPtr = XAnyClassInfo*;

struct XDeviceInfo {
    XID             id;        
    Atom            type;
    char            *name;
    int             num_classes;
    int             use;
    XAnyClassPtr 	inputclassinfo;
}

alias XDeviceInfoPtr = XDeviceInfo*;


struct XKeyInfo {
    XID			class_;
    int			length;
    ushort      min_keycode;
    ushort      max_keycode;
    ushort      num_keys;
}
alias XKeyInfoPtr = XKeyInfo*;

struct XButtonInfo {
    XID		class_;
    int		length;
    short 	num_buttons;
}

alias XButtonInfoPtr = XButtonInfo*;

alias XAxisInfoPtr = XAxisInfo*;

struct XAxisInfo {
    int 	resolution;
    int 	min_value;
    int 	max_value;
}

alias XValuatorInfoPtr = XValuatorInfo*;

struct XValuatorInfo {
    XID			class_;
    int			length;
    ubyte       num_axes;
    ubyte       mode;
    ulong       motion_buffer;
    XAxisInfoPtr        axes;
}

/*******************************************************************
 *
 * An XDevice structure is returned by the XOpenDevice function.  
 * It contains an array of pointers to XInputClassInfo structures.
 * Each contains information about a class of input supported by the
 * device, including a pointer to an array of data for each type of event
 * the device reports.
 *
 */


struct XInputClassInfo {
        ubyte   input_class;
        ubyte   event_type_base;
}

struct XDevice {
        XID                    device_id;
        int                    num_classes;
        XInputClassInfo        *classes;
}


/*******************************************************************
 *
 * The following structure is used to return information for the 
 * XGetSelectedExtensionEvents function.
 *
 */

struct XEventList {
        XEventClass     event_type;
        XID             device;
}

/*******************************************************************
 *
 * The following structure is used to return motion history data from 
 * an input device that supports the input class Valuators.
 * This information is returned by the XGetDeviceMotionEvents function.
 *
 */

struct XDeviceTimeCoord {
        Time   time;
        int    *data;
}


/*******************************************************************
 *
 * Device state structure.
 * This is returned by the XQueryDeviceState request.
 *
 */

struct XDeviceState {
        XID		device_id;
        int		num_classes;
        XInputClass	*data;
}

/*******************************************************************
 *
 * Note that the mode field is a bitfield that reports the Proximity
 * status of the device as well as the mode.  The mode field should
 * be OR'd with the mask DeviceMode and compared with the values
 * Absolute and Relative to determine the mode, and should be OR'd
 * with the mask ProximityState and compared with the values InProximity
 * and OutOfProximity to determine the proximity state.
 *
 */

struct XValuatorState {
    ubyte	class_;
    ubyte	length;
    ubyte	num_valuators;
    ubyte	mode;
    int        		*valuators;
}

struct XKeyState {
    ubyte	class_;
    ubyte	length;
    short num_keys;
    char[32] keys;
}

struct XButtonState {
    ubyte	class_;
    ubyte	length;
    short	num_buttons;
    char[32] buttons;
}



/*******************************************************************
 *
 * Function definitions.
 *
 */

extern int	XChangeKeyboardDevice(
    Display*		/* display */,
    XDevice*		/* device */
);

extern int	XChangePointerDevice(
    Display*		/* display */,
    XDevice*		/* device */,
    int			/* xaxis */,
    int			/* yaxis */
);

extern int	XGrabDevice(
    Display*		/* display */,
    XDevice*		/* device */,
    Window		/* grab_window */,
    Bool		/* ownerEvents */,
    int			/* event count */,
    XEventClass*	/* event_list */,
    int			/* this_device_mode */,
    int			/* other_devices_mode */,
    Time		/* time */
);

extern int	XUngrabDevice(
    Display*		/* display */,
    XDevice*		/* device */,
    Time 		/* time */
);

extern int	XGrabDeviceKey(
    Display*		/* display */,
    XDevice*		/* device */,
    uint	/* key */,
    uint	/* modifiers */,
    XDevice*		/* modifier_device */,
    Window		/* grab_window */,
    Bool		/* owner_events */,
    uint	/* event_count */,
    XEventClass*	/* event_list */,
    int			/* this_device_mode */,
    int			/* other_devices_mode */
);

extern int	XUngrabDeviceKey(
    Display*		/* display */,
    XDevice*		/* device */,
    uint	/* key */,
    uint	/* modifiers */,
    XDevice*		/* modifier_dev */,
    Window		/* grab_window */
);

extern int	XGrabDeviceButton(
    Display*		/* display */,
    XDevice*		/* device */,
    uint	/* button */,
    uint	/* modifiers */,
    XDevice*		/* modifier_device */,
    Window		/* grab_window */,
    Bool		/* owner_events */,
    uint	/* event_count */,
    XEventClass*	/* event_list */,
    int			/* this_device_mode */,
    int			/* other_devices_mode */
);

extern int	XUngrabDeviceButton(
    Display*		/* display */,
    XDevice*		/* device */,
    uint	/* button */,
    uint	/* modifiers */,
    XDevice*		/* modifier_dev */,
    Window		/* grab_window */
);

extern int	XAllowDeviceEvents(
    Display*		/* display */,
    XDevice*		/* device */,
    int			/* event_mode */,
    Time		/* time */
);

extern int	XGetDeviceFocus(
    Display*		/* display */,
    XDevice*		/* device */,
    Window*		/* focus */,
    int*		/* revert_to */,
    Time*		/* time */
);

extern int	XSetDeviceFocus(
    Display*		/* display */,
    XDevice*		/* device */,
    Window		/* focus */,
    int			/* revert_to */,
    Time		/* time */
);

extern XFeedbackState	*XGetFeedbackControl(
    Display*		/* display */,
    XDevice*		/* device */,
    int*		/* num_feedbacks */
);

extern void	XFreeFeedbackList(
    XFeedbackState*	/* list */
);

extern int	XChangeFeedbackControl(
    Display*		/* display */,
    XDevice*		/* device */,
    ulong	/* mask */,
    XFeedbackControl*	/* f */
);

extern int	XDeviceBell(
    Display*		/* display */,
    XDevice*		/* device */,
    XID			/* feedbackclass */,
    XID			/* feedbackid */,
    int			/* percent */
);

extern KeySym	*XGetDeviceKeyMapping(
    Display*		/* display */,
    XDevice*		/* device */,
/+
#if NeedWidePrototypes
    uint	/* first */,
#else
+/
    KeyCode		/* first */,
//#endif
    int			/* keycount */,
    int*		/* syms_per_code */
);

extern int	XChangeDeviceKeyMapping(
    Display*		/* display */,
    XDevice*		/* device */,
    int			/* first */,
    int			/* syms_per_code */,
    KeySym*		/* keysyms */,
    int			/* count */
);

extern XModifierKeymap	*XGetDeviceModifierMapping(
    Display*		/* display */,
    XDevice*		/* device */
);

extern int	XSetDeviceModifierMapping(
    Display*		/* display */,
    XDevice*		/* device */,
    XModifierKeymap*	/* modmap */
);

extern int	XSetDeviceButtonMapping(
    Display*		/* display */,
    XDevice*		/* device */,
    ubyte*	/* map[] */,
    int			/* nmap */
);

extern int	XGetDeviceButtonMapping(
    Display*		/* display */,
    XDevice*		/* device */,
    ubyte*	/* map[] */,
    uint	/* nmap */
);

extern XDeviceState	*XQueryDeviceState(
    Display*		/* display */,
    XDevice*		/* device */
);

extern void	XFreeDeviceState(
    XDeviceState*	/* list */
);

extern XExtensionVersion	*XGetExtensionVersion(
    Display*		/* display */,
    const(char)*	/* name */
);

extern XDeviceInfo	*XListInputDevices(
    Display*		/* display */,
    int*		/* ndevices */
);

extern void	XFreeDeviceList(
    XDeviceInfo*	/* list */
);

extern XDevice	*XOpenDevice(
    Display*		/* display */,
    XID			/* id */
);

extern int	XCloseDevice(
    Display*		/* display */,
    XDevice*		/* device */
);

extern int	XSetDeviceMode(
    Display*		/* display */,
    XDevice*		/* device */,
    int			/* mode */
);

extern int	XSetDeviceValuators(
    Display*		/* display */,
    XDevice*		/* device */,
    int*		/* valuators */,
    int			/* first_valuator */,
    int			/* num_valuators */
);

extern XDeviceControl	*XGetDeviceControl(
    Display*		/* display */,
    XDevice*		/* device */,
    int			/* control */
);

extern int	XChangeDeviceControl(
    Display*		/* display */,
    XDevice*		/* device */,
    int			/* control */,
    XDeviceControl*	/* d */
);

extern int	XSelectExtensionEvent(
    Display*		/* display */,
    Window		/* w */,
    XEventClass*	/* event_list */,
    int			/* count */
);

extern int XGetSelectedExtensionEvents(
    Display*		/* display */,
    Window		/* w */,
    int*		/* this_client_count */,
    XEventClass**	/* this_client_list */,
    int*		/* all_clients_count */,
    XEventClass**	/* all_clients_list */
);

extern int	XChangeDeviceDontPropagateList(
    Display*		/* display */,
    Window		/* window */,
    int			/* count */,
    XEventClass*	/* events */,
    int			/* mode */
);

extern XEventClass	*XGetDeviceDontPropagateList(
    Display*		/* display */,
    Window		/* window */,
    int*		/* count */
);

extern Status	XSendExtensionEvent(
    Display*		/* display */,
    XDevice*		/* device */,
    Window		/* dest */,
    Bool		/* prop */,
    int			/* count */,
    XEventClass*	/* list */,
    XEvent*		/* event */
);

extern XDeviceTimeCoord	*XGetDeviceMotionEvents(
    Display*		/* display */,
    XDevice*		/* device */,
    Time		/* start */,
    Time		/* stop */,
    int*		/* nEvents */,
    int*		/* mode */,
    int*		/* axis_count */
);

extern void	XFreeDeviceMotionEvents(
    XDeviceTimeCoord*	/* events */
);

extern void	XFreeDeviceControl(
    XDeviceControl*	/* control */
);

extern Atom*   XListDeviceProperties(
    Display*            /* dpy */,
    XDevice*            /* dev */,
    int*                /* nprops_return */
);

extern void XChangeDeviceProperty(
    Display*            /* dpy */,
    XDevice*            /* dev */,
    Atom                /* property */,
    Atom                /* type */,
    int                 /* format */,
    int                 /* mode */,
    const(ubyte)*		/*data */,
    int                 /* nelements */
);

extern void
XDeleteDeviceProperty(
    Display*            /* dpy */,
    XDevice*            /* dev */,
    Atom                /* property */
);

extern Status
XGetDeviceProperty(
     Display*           /* dpy*/,
     XDevice*           /* dev*/,
     Atom               /* property*/,
     long               /* offset*/,
     long               /* length*/,
     Bool               /* delete*/,
     Atom               /* req_type*/,
     Atom*              /* actual_type*/,
     int*               /* actual_format*/,
     ulong*     /* nitems*/,
     ulong*     /* bytes_after*/,
     ubyte**    /* prop*/
);

