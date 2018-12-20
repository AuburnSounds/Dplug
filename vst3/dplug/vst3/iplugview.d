//-----------------------------------------------------------------------------
// LICENSE
// (c) 2007-2018, Steinberg Media Technologies GmbH, All Rights Reserved
// (c) 2018, Guillaume Piolat (contact@auburnsounds.com)
//-----------------------------------------------------------------------------
// 
// This Software Development Kit is licensed under the terms of the General 
// Public License (GPL) Version 3.
// 
// Details of that license can be found at: www.gnu.org/licenses/gpl-3.0.html
//-----------------------------------------------------------------------------
module dplug.vst3.iplugview;

import dplug.vst3.ftypes;

struct ViewRect
{
    int left = 0;
    int top = 0;
    int right = 0;
    int bottom = 0;

    int getWidth () const { return right - left; }
    int getHeight () const { return bottom - top; }
}

static assert(ViewRect.sizeof == 16);

/**  \defgroup platformUIType Platform UI Types
\ingroup pluginGUI
List of Platform UI types for IPlugView. This list is used to match the GUI-System between
the host and a Plug-in in case that an OS provides multiple GUI-APIs.
*/
/** The parent parameter in IPlugView::attached() is a HWND handle.
 *  You should attach a child window to it. */
static immutable kPlatformTypeHWND = "HWND"; ///< HWND handle. (Microsoft Windows)

/** The parent parameter in IPlugView::attached() is a WindowRef.
 *  You should attach a HIViewRef to the content view of the window. */
static immutable kPlatformTypeHIView = "HIView"; ///< HIViewRef. (Mac OS X)

/** The parent parameter in IPlugView::attached() is a NSView pointer.
 * You should attach a NSView to it. */
static immutable kPlatformTypeNSView = "NSView"; ///< NSView pointer. (Mac OS X)

/** The parent parameter in IPlugView::attached() is a UIView pointer.
 * You should attach an UIView to it. */
static immutable kPlatformTypeUIView = "UIView"; ///< UIView pointer. (iOS)

/** The parent parameter in IPlugView::attached() is a X11 Window supporting XEmbed.
 * You should attach a Window to it that supports the XEmbed extension. */
static immutable kPlatformTypeX11EmbedWindowID = "X11EmbedWindowID"; ///< X11 Window ID. (X11)

/**  Plug-in definition of a view.
\ingroup pluginGUI vstIPlug vst300
- [plug imp]
- [released: 3.0.0]

\par Sizing of a view
Usually the size of a Plug-in view is fixed. But both the host and the Plug-in can cause
a view to be resized:
\n
- <b> Host </b> : If IPlugView::canResize () returns kResultTrue the host will setup the window
  so that the user can resize it. While the user resizes the window
  IPlugView::checkSizeConstraint () is called, allowing the Plug-in to change the size to a valid
  rect. The host then resizes the window to this rect and has to call IPlugView::onSize ().
\n
\n
- <b> Plug-in </b> : The Plug-in can call IPlugFrame::resizeView () and cause the host to resize the
  window.
  Afterwards in the same callstack the host has to call IPlugView::onSize () if a resize is needed (size was changed).
  Note that if the host calls IPlugView::getSize () before calling IPlugView::onSize () (if needed),
  it will get the current (old) size not the wanted one!!
  Here the calling sequence:
    * plug-in->host: IPlugFrame::resizeView (newSize)
    * host->plug-in (optional): IPlugView::getSize () returns the currentSize (not the newSize)!
    * host->plug-in: if newSize is different from the current size: IPlugView::onSize (newSize)
    * host->plug-in (optional): IPlugView::getSize () returns the newSize
\n
<b>Please only resize the platform representation of the view when IPlugView::onSize () is
called.</b>

\par Keyboard handling
The Plug-in view receives keyboard events from the host. A view implementation must not handle
keyboard events by the means of platform callbacks, but let the host pass them to the view. The host
depends on a proper return value when IPlugView::onKeyDown is called, otherwise the Plug-in view may
cause a malfunction of the host's key command handling!

\see IPlugFrame, \ref platformUIType
*/
interface IPlugView : FUnknown
{
public:
nothrow:
@nogc:
    /** Is Platform UI Type supported
        \param type : IDString of \ref platformUIType */
    tresult isPlatformTypeSupported (FIDString type);

    /** The parent window of the view has been created, the (platform) representation of the view
        should now be created as well.
        Note that the parent is owned by the caller and you are not allowed to alter it in any way
        other than adding your own views.
        Note that in this call the Plug-in could call a IPlugFrame::resizeView ()!
        \param parent : platform handle of the parent window or view
        \param type : \ref platformUIType which should be created */
    tresult attached (void* parent, FIDString type);

    /** The parent window of the view is about to be destroyed.
        You have to remove all your own views from the parent window or view. */
    tresult removed ();

    /** Handling of mouse wheel. */
    tresult onWheel (float distance);

    /** Handling of keyboard events : Key Down.
        \param key : unicode code of key
        \param keyCode : virtual keycode for non ascii keys - see \ref VirtualKeyCodes in keycodes.h
        \param modifiers : any combination of modifiers - see \ref KeyModifier in keycodes.h
        \return kResultTrue if the key is handled, otherwise kResultFalse. \n
                <b> Please note that kResultTrue must only be returned if the key has really been
       handled. </b> Otherwise key command handling of the host might be blocked! */
    tresult onKeyDown (char16 key, int16 keyCode, int16 modifiers);

    /** Handling of keyboard events : Key Up.
        \param key : unicode code of key
        \param keyCode : virtual keycode for non ascii keys - see \ref VirtualKeyCodes in keycodes.h
        \param modifiers : any combination of KeyModifier - see \ref KeyModifier in keycodes.h
        \return kResultTrue if the key is handled, otherwise return kResultFalse. */
    tresult onKeyUp (char16 key, int16 keyCode, int16 modifiers);

    /** Returns the size of the platform representation of the view. */
    tresult getSize (ViewRect* size);

    /** Resizes the platform representation of the view to the given rect. Note that if the Plug-in
     *  requests a resize (IPlugFrame::resizeView ()) onSize has to be called afterward. */
    tresult onSize (ViewRect* newSize);

    /** Focus changed message. */
    tresult onFocus (TBool state);

    /** Sets IPlugFrame object to allow the Plug-in to inform the host about resizing. */
    tresult setFrame (IPlugFrame frame);

    /** Is view sizable by user. */
    tresult canResize ();

    /** On live resize this is called to check if the view can be resized to the given rect, if not
     *  adjust the rect to the allowed size. */
    tresult checkSizeConstraint (ViewRect* rect);

	immutable __gshared TUID iid = INLINE_UID(0x5BC32507, 0xD06049EA, 0xA6151B52, 0x2B755B29);
}

/** Callback interface passed to IPlugView.
\ingroup pluginGUI vstIHost vst300
- [host imp]
- [released: 3.0.0]

Enables a Plug-in to resize the view and cause the host to resize the window.
*/
interface IPlugFrame : FUnknown
{
public:
nothrow:
@nogc:
    /** Called to inform the host about the resize of a given view.
     *  Afterwards the host has to call IPlugView::onSize (). */
    tresult resizeView (IPlugView view, ViewRect* newSize);

    immutable __gshared TUID iid = INLINE_UID(0x367FAF01, 0xAFA94693, 0x8D4DA2A0, 0xED0882A3);
}