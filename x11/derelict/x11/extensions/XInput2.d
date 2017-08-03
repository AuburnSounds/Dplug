module derelict.x11.extensions.XInput2;

version(linux):

import derelict.x11.Xlib;
import derelict.x11.X;
import derelict.x11.extensions.XI2;
import derelict.x11.extensions.Xge;
import core.stdc.config;

extern (C) nothrow @nogc:

/*******************************************************************
 *
 */
struct XIAddMasterInfo{
    int                 type;
    char*               name;
    Bool                send_core;
    Bool                enable;
}

struct XIRemoveMasterInfo{
    int                 type;
    int                 deviceid;
    int                 return_mode; /* AttachToMaster, Floating */
    int                 return_pointer;
    int                 return_keyboard;
}

struct XIAttachSlaveInfo{
    int                 type;
    int                 deviceid;
    int                 new_master;
}

struct XIDetachSlaveInfo{
    int                 type;
    int                 deviceid;
}

union XIAnyHierarchyChangeInfo{
    int                   type; /* must be first element */
    XIAddMasterInfo       add;
    XIRemoveMasterInfo    remove;
    XIAttachSlaveInfo     attach;
    XIDetachSlaveInfo     detach;
}

struct XIModifierState{
    int    base;
    int    latched;
    int    locked;
    int    effective;
}

alias XIModifierState XIGroupState;

struct XIButtonState{
    int             mask_len;
    ubyte*          mask;
} 

struct XIValuatorState{
    int             mask_len;
    ubyte           mask;
    double*         values;
} 


struct XIEventMask{
    int                 deviceid;
    int                 mask_len;
    ubyte*              mask;
} 

struct XIAnyClassInfo{
    int         type;
    int         sourceid;
} 

struct XIButtonClassInfo{
    int             type;
    int             sourceid;
    int             num_buttons;
    Atom*           labels;
    XIButtonState   state;
} 

struct XIKeyClassInfo{
    int         type;
    int         sourceid;
    int         num_keycodes;
    int*        keycodes;
} 

struct XIValuatorClassInfo{
    int         type;
    int         sourceid;
    int         number;
    Atom        label;
    double      min;
    double      max;
    double      value;
    int         resolution;
    int         mode;
} 

struct XIDeviceInfo{
    int                 deviceid;
    char*               name;
    int                 use;
    int                 attachment;
    Bool                enabled;
    int                 num_classes;
    XIAnyClassInfo**    classes;
} 

struct XIGrabModifiers{
    int                 modifiers;
    int                 status;
} 

/**
 * Generic XI2 event. All XI2 events have the same header.
 */
struct XIEvent{
    int           type;         /* GenericEvent */
    c_ulong serial;             /* # of last request processed by server */
    Bool          send_event;   /* true if this came from a SendEvent request */
    Display*      display;      /* Display the event was read from */
    int           extension;    /* XI extension offset */
    int           evtype;
    Time          time;
} 


struct XIHierarchyInfo{
    int           deviceid;
    int           attachment;
    int           use;
    Bool          enabled;
    int           flags;
} 

/*
 * Notifies the client that the device hierarchy has been changed. The client
 * is expected to re-query the server for the device hierarchy.
 */
struct XIHierarchyEvent{
    int                 type;           /* GenericEvent */
    c_ulong             serial;         /* # of last request processed by server */
    Bool                send_event;     /* true if this came from a SendEvent request */
    Display*            display;        /* Display the event was read from */
    int                 extension;      /* XI extension offset */
    int                 evtype;         /* XI_HierarchyChanged */
    Time                time;
    int                 flags;
    int                 num_info;
    XIHierarchyInfo*    info;
}

/*
 * Notifies the client that the classes have been changed. This happens when
 * the slave device that sends through the master changes.
 */
struct XIDeviceChangedEvent{
    int                 type;         /* GenericEvent */
    c_ulong             serial;       /* # of last request processed by server */
    Bool                send_event;   /* true if this came from a SendEvent request */
    Display*            display;      /* Display the event was read from */
    int                 extension;    /* XI extension offset */
    int                 evtype;       /* XI_DeviceChanged */
    Time                time;
    int                 deviceid;     /* id of the device that changed */
    int                 sourceid;     /* Source for the new classes. */
    int                 reason;       /* Reason for the change */
    int                 num_classes;
    XIAnyClassInfo**    classes; /* same as in XIDeviceInfo */
}

struct XIDeviceEvent{
    int                 type;           /* GenericEvent */
    c_ulong             serial;         /* # of last request processed by server */
    Bool                send_event;     /* true if this came from a SendEvent request */
    Display*            display;        /* Display the event was read from */
    int                 extension;      /* XI extension offset */
    int                 evtype;
    Time                time;
    int                 deviceid;
    int                 sourceid;
    int                 detail;
    Window              root;
    Window              event;
    Window              child;
    double              root_x;
    double              root_y;
    double              event_x;
    double              event_y;
    int                 flags;
    XIButtonState       buttons;
    XIValuatorState     valuators;
    XIModifierState     mods;
    XIGroupState        group;
}

struct XIRawEvent{
    int             type;         /* GenericEvent */
    c_ulong         serial;       /* # of last request processed by server */
    Bool            send_event;   /* true if this came from a SendEvent request */
    Display*        display;      /* Display the event was read from */
    int             extension;    /* XI extension offset */
    int             evtype;       /* XI_RawKeyPress, XI_RawKeyRelease, etc. */
    Time            time;
    int             deviceid;
    int             sourceid;     /* Bug: Always 0. https://bugs.freedesktop.org//show_bug.cgi?id=34240 */
    int             detail;
    int             flags;
    XIValuatorState valuators;
    double*         raw_values;
}

struct XIEnterEvent{
    int                 type;           /* GenericEvent */
    c_ulong             serial;         /* # of last request processed by server */
    Bool                send_event;     /* true if this came from a SendEvent request */
    Display*            display;        /* Display the event was read from */
    int                 extension;      /* XI extension offset */
    int                 evtype;
    Time                time;
    int                 deviceid;
    int                 sourceid;
    int                 detail;
    Window              root;
    Window              event;
    Window              child;
    double              root_x;
    double              root_y;
    double              event_x;
    double              event_y;
    int                 mode;
    Bool                focus;
    Bool                same_screen;
    XIButtonState       buttons;
    XIModifierState     mods;
    XIGroupState        group;
}

alias XIEnterEvent XILeaveEvent;
alias XIEnterEvent XIFocusInEvent;
alias XIEnterEvent XIFocusOutEvent;

struct XIPropertyEvent{
    int             type;           /* GenericEvent */
    c_ulong         serial;         /* # of last request processed by server */
    Bool            send_event;     /* true if this came from a SendEvent request */
    Display*        display;        /* Display the event was read from */
    int             extension;      /* XI extension offset */
    int             evtype;         /* XI_PropertyEvent */
    Time            time;
    int             deviceid;       /* id of the device that changed */
    Atom            property;
    int             what;
}

extern Bool     XIQueryPointer(
    Display*            display,
    int                 deviceid,
    Window              win,
    Window*             root,
    Window*             child,
    double*             root_x,
    double*             root_y,
    double*             win_x,
    double*             win_y,
    XIButtonState*      buttons,
    XIModifierState*    mods,
    XIGroupState*       group
);

extern Bool     XIWarpPointer(
    Display*            display,
    int                 deviceid,
    Window              src_win,
    Window              dst_win,
    double              src_x,
    double              src_y,
    uint                src_width,
    uint                src_height,
    double              dst_x,
    double              dst_y
);

extern Status   XIDefineCursor(
    Display*            display,
    int                 deviceid,
    Window              win,
    Cursor              cursor
);

extern Status   XIUndefineCursor(
    Display*            display,
    int                 deviceid,
    Window              win
);

extern Status   XIChangeHierarchy(
    Display*                    display,
    XIAnyHierarchyChangeInfo*   changes,
    int                         num_changes
);

extern Status   XISetClientPointer(
    Display*            dpy,
    Window              win,
    int                 deviceid
);

extern Bool     XIGetClientPointer(
    Display*            dpy,
    Window              win,
    int*                deviceid
);

extern int      XISelectEvents(
     Display*            dpy,
     Window              win,
     XIEventMask*        masks,
     int                 num_masks
);

extern XIEventMask *XIGetSelectedEvents(
     Display*            dpy,
     Window              win,
     int*                num_masks_return
);

extern Status XIQueryVersion(
     Display*           dpy,
     int*               major_version_inout,
     int*               minor_version_inout
);

extern XIDeviceInfo* XIQueryDevice(
     Display*           dpy,
     int                deviceid,
     int*               ndevices_return
);

extern Status XISetFocus(
     Display*           dpy,
     int                deviceid,
     Window             focus,
     Time               time
);

extern Status XIGetFocus(
     Display*           dpy,
     int                deviceid,
     Window*            focus_return);

extern Status XIGrabDevice(
     Display*           dpy,
     int                deviceid,
     Window             grab_window,
     Time               time,
     Cursor             cursor,
     int                grab_mode,
     int                paired_device_mode,
     Bool               owner_events,
     XIEventMask*       mask
);

extern Status XIUngrabDevice(
     Display*           dpy,
     int                deviceid,
     Time               time
);

extern Status XIAllowEvents(
    Display*            display,
    int                 deviceid,
    int                 event_mode,
    Time                time
);

extern int XIGrabButton(
    Display*            display,
    int                 deviceid,
    int                 button,
    Window              grab_window,
    Cursor              cursor,
    int                 grab_mode,
    int                 paired_device_mode,
    int                 owner_events,
    XIEventMask*        mask,
    int                 num_modifiers,
    XIGrabModifiers*    modifiers_inout
);

extern int XIGrabKeycode(
    Display*            display,
    int                 deviceid,
    int                 keycode,
    Window              grab_window,
    int                 grab_mode,
    int                 paired_device_mode,
    int                 owner_events,
    XIEventMask*        mask,
    int                 num_modifiers,
    XIGrabModifiers*    modifiers_inout
);

extern int XIGrabEnter(
    Display*            display,
    int                 deviceid,
    Window              grab_window,
    Cursor              cursor,
    int                 grab_mode,
    int                 paired_device_mode,
    int                 owner_events,
    XIEventMask*        mask,
    int                 num_modifiers,
    XIGrabModifiers*    modifiers_inout
);

extern int XIGrabFocusIn(
    Display*            display,
    int                 deviceid,
    Window              grab_window,
    int                 grab_mode,
    int                 paired_device_mode,
    int                 owner_events,
    XIEventMask*        mask,
    int                 num_modifiers,
    XIGrabModifiers*    modifiers_inout
);
extern Status XIUngrabButton(
    Display*            display,
    int                 deviceid,
    int                 button,
    Window              grab_window,
    int                 num_modifiers,
    XIGrabModifiers*    modifiers
);

extern Status XIUngrabKeycode(
    Display*            display,
    int                 deviceid,
    int                 keycode,
    Window              grab_window,
    int                 num_modifiers,
    XIGrabModifiers*    modifiers
);

extern Status XIUngrabEnter(
    Display*            display,
    int                 deviceid,
    Window              grab_window,
    int                 num_modifiers,
    XIGrabModifiers*    modifiers
);

extern Status XIUngrabFocusIn(
    Display*            display,
    int                 deviceid,
    Window              grab_window,
    int                 num_modifiers,
    XIGrabModifiers*    modifiers
);


extern Atom *XIListProperties(
    Display*            display,
    int                 deviceid,
    int*                num_props_return
);

extern void XIChangeProperty(
    Display*            display,
    int                 deviceid,
    Atom                property,
    Atom                type,
    int                 format,
    int                 mode,
    ubyte*              data,
    int                 num_items
);

extern void
XIDeleteProperty(
    Display*            display,
    int                 deviceid,
    Atom                property
);

extern Status
XIGetProperty(
    Display*            display,
    int                 deviceid,
    Atom                property,
    long                offset,
    long                length,
    Bool                delete_property,
    Atom                type,
    Atom*               type_return,
    int*                format_return,
    c_ulong*            num_items_return,
    c_ulong*            bytes_after_return,
    ubyte**             data
);

extern void XIFreeDeviceInfo(XIDeviceInfo* info);
