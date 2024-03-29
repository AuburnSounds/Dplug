/*
  LV2 UI Extension
  Copyright 2009-2016 David Robillard <d@drobilla.net>
  Copyright 2006-2011 Lars Luthman <lars.luthman@gmail.com>
  Copyright 2018 Ethan Reker <http://cutthroughrecordings.com>

  Permission to use, copy, modify, and/or distribute this software for any
  purpose with or without fee is hereby granted, provided that the above
  copyright notice and this permission notice appear in all copies.

  THIS SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
*/
module dplug.lv2.ui;

version(LV2):

/**
   @defgroup ui User Interfaces

   User interfaces of any type for plugins,
   <http://lv2plug.in/ns/extensions/ui> for details.

   @{
*/

import core.stdc.stdint;

import dplug.lv2.lv2;

enum LV2_UI_URI    = "http://lv2plug.in/ns/extensions/ui";  ///< http://lv2plug.in/ns/extensions/ui
enum LV2_UI_PREFIX = LV2_UI_URI ~ "#";                        ///< http://lv2plug.in/ns/extensions/ui#
enum LV2_UI__CocoaUI          = LV2_UI_PREFIX ~ "CocoaUI";           ///< http://lv2plug.in/ns/extensions/ui#CocoaUI
enum LV2_UI__Gtk3UI           = LV2_UI_PREFIX ~ "Gtk3UI";            ///< http://lv2plug.in/ns/extensions/ui#Gtk3UI
enum LV2_UI__GtkUI            = LV2_UI_PREFIX ~ "GtkUI";             ///< http://lv2plug.in/ns/extensions/ui#GtkUI
enum LV2_UI__PortNotification = LV2_UI_PREFIX ~ "PortNotification";  ///< http://lv2plug.in/ns/extensions/ui#PortNotification
enum LV2_UI__PortProtocol     = LV2_UI_PREFIX ~ "PortProtocol";      ///< http://lv2plug.in/ns/extensions/ui#PortProtocol
enum LV2_UI__Qt4UI            = LV2_UI_PREFIX ~ "Qt4UI";             ///< http://lv2plug.in/ns/extensions/ui#Qt4UI
enum LV2_UI__Qt5UI            = LV2_UI_PREFIX ~ "Qt5UI";             ///< http://lv2plug.in/ns/extensions/ui#Qt5UI
enum LV2_UI__UI               = LV2_UI_PREFIX ~ "UI";                ///< http://lv2plug.in/ns/extensions/ui#UI
enum LV2_UI__WindowsUI        = LV2_UI_PREFIX ~ "WindowsUI";         ///< http://lv2plug.in/ns/extensions/ui#WindowsUI
enum LV2_UI__X11UI            = LV2_UI_PREFIX ~ "X11UI";             ///< http://lv2plug.in/ns/extensions/ui#X11UI
enum LV2_UI__binary           = LV2_UI_PREFIX ~ "binary";            ///< http://lv2plug.in/ns/extensions/ui#binary
enum LV2_UI__fixedSize        = LV2_UI_PREFIX ~ "fixedSize";         ///< http://lv2plug.in/ns/extensions/ui#fixedSize
enum LV2_UI__idleInterface    = LV2_UI_PREFIX ~ "idleInterface";     ///< http://lv2plug.in/ns/extensions/ui#idleInterface
enum LV2_UI__noUserResize     = LV2_UI_PREFIX ~ "noUserResize";      ///< http://lv2plug.in/ns/extensions/ui#noUserResize
enum LV2_UI__notifyType       = LV2_UI_PREFIX ~ "notifyType";        ///< http://lv2plug.in/ns/extensions/ui#notifyType
enum LV2_UI__parent           = LV2_UI_PREFIX ~ "parent";            ///< http://lv2plug.in/ns/extensions/ui#parent
enum LV2_UI__plugin           = LV2_UI_PREFIX ~ "plugin";            ///< http://lv2plug.in/ns/extensions/ui#plugin
enum LV2_UI__portIndex        = LV2_UI_PREFIX ~ "portIndex";         ///< http://lv2plug.in/ns/extensions/ui#portIndex
enum LV2_UI__portMap          = LV2_UI_PREFIX ~ "portMap";           ///< http://lv2plug.in/ns/extensions/ui#portMap
enum LV2_UI__portNotification = LV2_UI_PREFIX ~ "portNotification";  ///< http://lv2plug.in/ns/extensions/ui#portNotification
enum LV2_UI__portSubscribe    = LV2_UI_PREFIX ~ "portSubscribe";     ///< http://lv2plug.in/ns/extensions/ui#portSubscribe
enum LV2_UI__protocol         = LV2_UI_PREFIX ~ "protocol";          ///< http://lv2plug.in/ns/extensions/ui#protocol
enum LV2_UI__floatProtocol    = LV2_UI_PREFIX ~ "floatProtocol";     ///< http://lv2plug.in/ns/extensions/ui#floatProtocol
enum LV2_UI__peakProtocol     = LV2_UI_PREFIX ~ "peakProtocol";      ///< http://lv2plug.in/ns/extensions/ui#peakProtocol
enum LV2_UI__resize           = LV2_UI_PREFIX ~ "resize";            ///< http://lv2plug.in/ns/extensions/ui#resize
enum LV2_UI__showInterface    = LV2_UI_PREFIX ~ "showInterface";     ///< http://lv2plug.in/ns/extensions/ui#showInterface
enum LV2_UI__touch            = LV2_UI_PREFIX ~ "touch";             ///< http://lv2plug.in/ns/extensions/ui#touch
enum LV2_UI__ui               = LV2_UI_PREFIX ~ "ui";                ///< http://lv2plug.in/ns/extensions/ui#ui
enum LV2_UI__updateRate       = LV2_UI_PREFIX ~ "updateRate";        ///< http://lv2plug.in/ns/extensions/ui#updateRate
enum LV2_UI__windowTitle      = LV2_UI_PREFIX ~ "windowTitle";       ///< http://lv2plug.in/ns/extensions/ui#windowTitle

/**
   The index returned by LV2UI_Port_Map::port_index() for unknown ports.
*/
enum LV2UI_INVALID_PORT_INDEX = cast(uint32_t)(-1);

extern(C):
nothrow:
@nogc:

/**
A pointer to some widget or other type of UI handle.

The actual type is defined by the type of the UI.
*/
alias LV2UI_Widget = void*;

/**
A pointer to UI instance internals.

The host may compare this to NULL, but otherwise MUST NOT interpret it.
*/
alias LV2UI_Handle = void*;

/**
A pointer to a controller provided by the host.

The UI may compare this to NULL, but otherwise MUST NOT interpret it.
*/
alias LV2UI_Controller = void*;

/**
A pointer to opaque data for a feature.
*/
alias LV2UI_Feature_Handle = void*;

/**
A host-provided function that sends data to a plugin's input ports.

@param controller The opaque controller pointer passed to
LV2UI_Descriptor::instantiate().

@param port_index Index of the port to update.

@param buffer Buffer containing `buffer_size` bytes of data.

@param buffer_size Size of `buffer` in bytes.

@param port_protocol Either 0 or the URID for a ui:PortProtocol.  If 0, the
protocol is implicitly ui:floatProtocol, the port MUST be an lv2:ControlPort
input, `buffer` MUST point to a single float value, and `buffer_size` MUST
be sizeof(float).  The UI SHOULD NOT use a protocol not supported by the
host, but the host MUST gracefully ignore any protocol it does not
understand.
*/
alias LV2UI_Write_Function = void function(LV2UI_Controller controller,
                                    uint32_t         port_index,
                                    uint32_t         buffer_size,
                                    uint32_t         port_protocol,
                                    const void*      buffer);

/**
A plugin UI.

A pointer to an object of this type is returned by the lv2ui_descriptor()
function.
*/
struct LV2UI_Descriptor 
{
nothrow:
@nogc:
extern(C):
    /**
    The URI for this UI (not for the plugin it controls).
    */
    char* URI;

    /**
    Create a new UI and return a handle to it.  This function works
    similarly to LV2_Descriptor::instantiate().

    @param descriptor The descriptor for the UI to instantiate.

    @param plugin_uri The URI of the plugin that this UI will control.

    @param bundle_path The path to the bundle containing this UI, including
    the trailing directory separator.

    @param write_function A function that the UI can use to send data to the
    plugin's input ports.

    @param controller A handle for the UI instance to be passed as the
    first parameter of UI methods.

    @param widget (output) widget pointer.  The UI points this at its main
    widget, which has the type defined by the UI type in the data file.

    @param features An array of LV2_Feature pointers.  The host must pass
    all feature URIs that it and the UI supports and any additional data, as
    in LV2_Descriptor::instantiate().  Note that UI features and plugin
    features are not necessarily the same.

    */
    LV2UI_Handle function(const LV2UI_Descriptor* descriptor,
                                const char*                     plugin_uri,
                                const char*                     bundle_path,
                                LV2UI_Write_Function            write_function,
                                LV2UI_Controller                controller,
                                LV2UI_Widget*                   widget,
                                const (LV2_Feature*)*       features) instantiate;


    /**
    Destroy the UI.  The host must not try to access the widget after
    calling this function.
    */
    void function(LV2UI_Handle ui) cleanup;

    /**
    Tell the UI that something interesting has happened at a plugin port.

    What is "interesting" and how it is written to `buffer` is defined by
    `format`, which has the same meaning as in LV2UI_Write_Function().
    Format 0 is a special case for lv2:ControlPort, where this function
    should be called when the port value changes (but not necessarily for
    every change), `buffer_size` must be sizeof(float), and `buffer`
    points to a single IEEE-754 float.

    By default, the host should only call this function for lv2:ControlPort
    inputs.  However, the UI can request updates for other ports statically
    with ui:portNotification or dynamicaly with ui:portSubscribe.

    The UI MUST NOT retain any reference to `buffer` after this function
    returns, it is only valid for the duration of the call.

    This member may be NULL if the UI is not interested in any port events.
    */
    void function(LV2UI_Handle ui,
                    uint32_t     port_index,
                    uint32_t     buffer_size,
                    uint32_t     format,
                    const void*  buffer) port_event;

    /**
    Return a data structure associated with an extension URI, typically an
    interface struct with additional function pointers

    This member may be set to NULL if the UI is not interested in supporting
    any extensions. This is similar to LV2_Descriptor::extension_data().

    */
    const (void)* function(const char* uri) extension_data;
}

/**
Feature/interface for resizable UIs (LV2_UI__resize).

This structure is used in two ways: as a feature passed by the host via
LV2UI_Descriptor::instantiate(), or as an interface provided by a UI via
LV2UI_Descriptor::extension_data()).
*/
struct LV2UI_Resize 
{
nothrow:
@nogc:
extern(C):

    /**
    Pointer to opaque data which must be passed to ui_resize().
    */
    LV2UI_Feature_Handle handle;

    /**
    Request/advertise a size change.

    When provided by the host, the UI may call this function to inform the
    host about the size of the UI.

    When provided by the UI, the host may call this function to notify the
    UI that it should change its size accordingly.  In this case, the host
    must pass the LV2UI_Handle to provide access to the UI instance.

    @return 0 on success.
    */
    int function(LV2UI_Feature_Handle handle, int width, int height) ui_resize;
}

/**
Feature to map port symbols to UIs.

This can be used by the UI to get the index for a port with the given
symbol.  This makes it possible to implement and distribute a UI separately
from the plugin (since symbol, unlike index, is a stable port identifier).
*/
struct LV2UI_Port_Map 
{
nothrow:
@nogc:
extern(C):
    /**
    Pointer to opaque data which must be passed to port_index().
    */
    LV2UI_Feature_Handle handle;

    /**
    Get the index for the port with the given `symbol`.

    @return The index of the port, or LV2UI_INVALID_PORT_INDEX if no such
    port is found.
    */
    uint32_t function(LV2UI_Feature_Handle handle, const char* symbol) port_index;
}

/**
Feature to subscribe to port updates (LV2_UI__portSubscribe).
*/
struct LV2UI_Port_Subscribe 
{
extern(C):
nothrow:
@nogc:
    /**
    Pointer to opaque data which must be passed to subscribe() and
    unsubscribe().
    */
    LV2UI_Feature_Handle handle;

    /**
    Subscribe to updates for a port.

    This means that the host will call the UI's port_event() function when
    the port value changes (as defined by protocol).

    Calling this function with the same `port_index` and `port_protocol`
    as an already active subscription has no effect.

    @param handle The handle field of this struct.
    @param port_index The index of the port.
    @param port_protocol The URID of the ui:PortProtocol.
    @param features Features for this subscription.
    @return 0 on success.
    */
    uint32_t function(LV2UI_Feature_Handle      handle,
                        uint32_t                  port_index,
                        uint32_t                  port_protocol,
                        const (LV2_Feature*)* features) subscribe;

    /**
    Unsubscribe from updates for a port.

    This means that the host will cease calling calling port_event() when
    the port value changes.

    Calling this function with a `port_index` and `port_protocol` that
    does not refer to an active port subscription has no effect.

    @param handle The handle field of this struct.
    @param port_index The index of the port.
    @param port_protocol The URID of the ui:PortProtocol.
    @param features Features for this subscription.
    @return 0 on success.
    */
    uint32_t function(LV2UI_Feature_Handle      handle,
                            uint32_t                  port_index,
                            uint32_t                  port_protocol,
                            const (LV2_Feature*)* features) unsubscribe;
}

/**
A feature to notify the host that the user has grabbed a UI control.
*/
struct LV2UI_Touch 
{
nothrow:
@nogc:
extern(C):

    /**
    Pointer to opaque data which must be passed to ui_resize().
    */
    LV2UI_Feature_Handle handle;

    /**
    Notify the host that a control has been grabbed or released.

    The host should cease automating the port or otherwise manipulating the
    port value until the control has been ungrabbed.

    @param handle The handle field of this struct.
    @param port_index The index of the port associated with the control.
    @param grabbed If true, the control has been grabbed, otherwise the
    control has been released.
    */
    void function(LV2UI_Feature_Handle handle,
                  uint32_t             port_index,
                  bool                 grabbed) touch;
}

/**
UI Idle Interface (LV2_UI__idleInterface)

UIs can provide this interface to have an idle() callback called by the host
rapidly to update the UI.
*/
struct LV2UI_Idle_Interface 
{
nothrow:
@nogc:
extern(C):
    /**
    Run a single iteration of the UI's idle loop.

    This will be called rapidly in the UI thread at a rate appropriate
    for a toolkit main loop.  There are no precise timing guarantees, but
    the host should attempt to call idle() at a high enough rate for smooth
    animation, at least 30Hz.

    @return non-zero if the UI has been closed, in which case the host
    should stop calling idle(), and can either completely destroy the UI, or
    re-show it and resume calling idle().
    */
    int function(LV2UI_Handle ui) idle;
}

/**
UI Show Interface (LV2_UI__showInterface)

UIs can provide this interface to show and hide a window, which allows them
to function in hosts unable to embed their widget.  This allows any UI to
provide a fallback for embedding that works in any host.

If used:
- The host MUST use LV2UI_Idle_Interface to drive the UI.
- The UI MUST return non-zero from LV2UI_Idle_Interface::idle() when it has been closed.
- If idle() returns non-zero, the host MUST call hide() and stop calling
    idle().  It MAY later call show() then resume calling idle().
*/
struct LV2UI_Show_Interface 
{
nothrow:
@nogc:
extern(C):
    /**
    Show a window for this UI.

    The window title MAY have been passed by the host to
    LV2UI_Descriptor::instantiate() as an LV2_Options_Option with key
    LV2_UI__windowTitle.

    @return 0 on success, or anything else to stop being called.
    */
    int function(LV2UI_Handle ui) show;

    /**
    Hide the window for this UI.

    @return 0 on success, or anything else to stop being called.
    */
    int function(LV2UI_Handle ui) hide;
}

/**
Peak data for a slice of time, the update format for ui:peakProtocol.
*/
struct LV2UI_Peak_Data 
{
    /**
    The start of the measurement period.  This is just a running counter
    that is only meaningful in comparison to previous values and must not be
    interpreted as an absolute time.
    */
    uint32_t period_start;

    /**
    The size of the measurement period, in the same units as period_start.
    */
    uint32_t period_size;

    /**
    The peak value for the measurement period. This should be the maximal
    value for abs(sample) over all the samples in the period.
    */
    float peak;
}

/**
The type of the lv2ui_descriptor() function.
*/
// typedef const LV2UI_Descriptor* (*LV2UI_DescriptorFunction)(uint32_t index);
alias LV2UI_DescriptorFunction = const LV2UI_Descriptor function(uint32_t index);
