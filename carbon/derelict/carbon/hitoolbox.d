/*
* Copyright (c) 2015 Guillaume Piolat
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without
* modification, are permitted provided that the following conditions are
* met:
*
* * Redistributions of source code must retain the above copyright
*   notice, this list of conditions and the following disclaimer.
*
* * Redistributions in binary form must reproduce the above copyright
*   notice, this list of conditions and the following disclaimer in the
*   documentation and/or other materials provided with the distribution.
*
* * Neither the names 'Derelict', 'DerelictSDL', nor the names of its contributors
*   may be used to endorse or promote products derived from this software
*   without specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
* "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
* TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
* PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
* CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
* EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
* PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
* PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
* LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
* NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
* SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
module derelict.carbon.hitoolbox;

version(OSX):


import derelict.carbon.corefoundation;
import derelict.carbon.coregraphics;


alias WindowRef = void*; // TODO: this actually belongs to QD framework

// <HIToolbox/CarbonEventsCore.h.h>

alias EventRef = void*;
alias EventLoopRef = void*;
alias EventLoopTimerRef = void*;
alias EventHandlerRef = void*;
alias EventHandlerCallRef = void*;
alias EventTargetRef = void*;

alias EventParamName = OSType;
alias EventParamType = OSType;
alias EventTime = double;
alias EventTimeout = EventTime;
alias EventTimerInterval = EventTime;

enum EventTime kEventDurationSecond = 1.0;

enum : int
{
    eventAlreadyPostedErr         = -9860,
    eventTargetBusyErr            = -9861,
    eventClassInvalidErr          = -9862,
    eventClassIncorrectErr        = -9864,
    eventDeferAccessibilityEventErr = -9865,
    eventHandlerAlreadyInstalledErr = -9866,
    eventInternalErr              = -9868,
    eventKindIncorrectErr         = -9869,
    eventParameterNotFoundErr     = -9870,
    eventNotHandledErr            = -9874,
    eventLoopTimedOutErr          = -9875,
    eventLoopQuitErr              = -9876,
    eventNotInQueueErr            = -9877,
    eventHotKeyExistsErr          = -9878,
    eventHotKeyInvalidErr         = -9879,
    eventPassToNextTargetErr      = -9880
}


struct EventTypeSpec
{
    OSType eventClass;
    UInt32 eventKind;
}

extern (C) nothrow @nogc
{
    alias da_GetMainEventLoop = EventLoopRef function();
    alias da_InstallEventHandler = OSStatus function(EventTargetRef, EventHandlerUPP, ItemCount, const(EventTypeSpec)*, void*, EventHandlerRef*);
    alias da_GetEventClass = OSType function(EventRef inEvent);
    alias da_GetEventKind = UInt32 function(EventRef inEvent);
    alias da_GetEventParameter = OSStatus function(EventRef, EventParamName, EventParamType, EventParamType*, ByteCount, ByteCount*, void*);
    alias da_InstallEventLoopTimer = OSStatus function(EventLoopRef, EventTimerInterval, EventTimerInterval,
                                                       EventLoopTimerUPP, void*, EventLoopTimerRef*);

    alias da_RemoveEventHandler = OSStatus function(EventHandlerRef);
    alias da_RemoveEventLoopTimer = OSStatus function(EventLoopTimerRef);
}

__gshared
{
    da_GetMainEventLoop GetMainEventLoop;
    da_InstallEventHandler InstallEventHandler;
    da_GetEventClass GetEventClass;
    da_GetEventKind GetEventKind;
    da_GetEventParameter GetEventParameter;
    da_InstallEventLoopTimer InstallEventLoopTimer;
    da_RemoveEventLoopTimer RemoveEventLoopTimer;
    da_RemoveEventHandler RemoveEventHandler;
}


extern(C) nothrow
{
    alias EventHandlerProcPtr = OSStatus function(EventHandlerCallRef inHandlerCallRef, EventRef inEvent, void *inUserData);
    alias EventHandlerUPP = EventHandlerProcPtr;
    alias EventLoopTimerUPP = void function(EventLoopTimerRef inTimer, void* inUserData);
}



// <HIToolbox/CarbonEvents.h>

enum : int
{
  kEventClassMouse              = CCONST('m', 'o', 'u', 's'),
  kEventClassKeyboard           = CCONST('k', 'e', 'y', 'b'),
  kEventClassTextInput          = CCONST('t', 'e', 'x', 't'),
  kEventClassApplication        = CCONST('a', 'p', 'p', 'l'),
  kEventClassAppleEvent         = CCONST('e', 'p', 'p', 'c'),
  kEventClassMenu               = CCONST('m', 'e', 'n', 'u'),
  kEventClassWindow             = CCONST('w', 'i', 'n', 'd'),
  kEventClassControl            = CCONST('c', 'n', 't', 'l'),
  kEventClassCommand            = CCONST('c', 'm', 'd', 's'),
  kEventClassTablet             = CCONST('t', 'b', 'l', 't'),
  kEventClassVolume             = CCONST('v', 'o', 'l', ' '),
  kEventClassAppearance         = CCONST('a', 'p', 'p', 'm'),
  kEventClassService            = CCONST('s', 'e', 'r', 'v'),
  kEventClassToolbar            = CCONST('t', 'b', 'a', 'r'),
  kEventClassToolbarItem        = CCONST('t', 'b', 'i', 't'),
  kEventClassToolbarItemView    = CCONST('t', 'b', 'i', 'v'),
  kEventClassAccessibility      = CCONST('a', 'c', 'c', 'e'),
  kEventClassSystem             = CCONST('m', 'a', 'c', 's'),
  kEventClassInk                = CCONST('i', 'n', 'k', ' '),
  kEventClassTSMDocumentAccess  = CCONST('t', 'd', 'a', 'c'),
  kEventClassGesture            = CCONST('g', 'e', 's', 't')
}

enum : int
{
    kEventControlInitialize                     = 1000,
    kEventControlDispose                        = 1001,
    kEventControlGetOptimalBounds               = 1003,
    kEventControlOptimalBoundsChanged           = 1004,
    kEventControlDefInitialize                  = kEventControlInitialize,
    kEventControlDefDispose                     = kEventControlDispose,
    kEventControlHit                            = 1,
    kEventControlSimulateHit                    = 2,
    kEventControlHitTest                        = 3,
    kEventControlDraw                           = 4,
    kEventControlApplyBackground                = 5,
    kEventControlApplyTextColor                 = 6,
    kEventControlSetFocusPart                   = 7,
    kEventControlGetFocusPart                   = 8,
    kEventControlActivate                       = 9,
    kEventControlDeactivate                     = 10,
    kEventControlSetCursor                      = 11,
    kEventControlContextualMenuClick            = 12,
    kEventControlClick                          = 13,
    kEventControlGetNextFocusCandidate          = 14,
    kEventControlGetAutoToggleValue             = 15,
    kEventControlInterceptSubviewClick          = 16,
    kEventControlGetClickActivation             = 17,
    kEventControlDragEnter                      = 18,
    kEventControlDragWithin                     = 19,
    kEventControlDragLeave                      = 20,
    kEventControlDragReceive                    = 21,
    kEventControlInvalidateForSizeChange        = 22,
    kEventControlTrackingAreaEntered            = 23,
    kEventControlTrackingAreaExited             = 24,
    kEventControlTrack                          = 51,
    kEventControlGetScrollToHereStartPoint      = 52,
    kEventControlGetIndicatorDragConstraint     = 53,
    kEventControlIndicatorMoved                 = 54,
    kEventControlGhostingFinished               = 55,
    kEventControlGetActionProcPart              = 56,
    kEventControlGetPartRegion                  = 101,
    kEventControlGetPartBounds                  = 102,
    kEventControlSetData                        = 103,
    kEventControlGetData                        = 104,
    kEventControlGetSizeConstraints             = 105,
    kEventControlGetFrameMetrics                = 106,
    kEventControlValueFieldChanged              = 151,
    kEventControlAddedSubControl                = 152,
    kEventControlRemovingSubControl             = 153,
    kEventControlBoundsChanged                  = 154,
    kEventControlVisibilityChanged              = 157,
    kEventControlTitleChanged                   = 158,
    kEventControlOwningWindowChanged            = 159,
    kEventControlHiliteChanged                  = 160,
    kEventControlEnabledStateChanged            = 161,
    kEventControlLayoutInfoChanged              = 162,
    kEventControlFocusPartChanged               = 164,
    kEventControlArbitraryMessage               = 201
}

enum : int
{
    kEventMouseDown                 = 1,
    kEventMouseUp                   = 2,
    kEventMouseMoved                = 5,
    kEventMouseDragged              = 6,
    kEventMouseEntered              = 8,
    kEventMouseExited               = 9,
    kEventMouseWheelMoved           = 10,
    kEventMouseScroll               = 11
}

alias EventMouseWheelAxis = UInt16;
enum : EventMouseWheelAxis
{
    kEventMouseWheelAxisX         = 0,
    kEventMouseWheelAxisY         = 1
}


enum : int
{
    kEventRawKeyDown                = 1,
    kEventRawKeyRepeat              = 2,
    kEventRawKeyUp                  = 3,
    kEventRawKeyModifiersChanged    = 4,
    kEventHotKeyPressed             = 5,
    kEventHotKeyReleased            = 6
}

enum : int
{
    kEventWindowUpdate                  = 1,
    kEventWindowDrawContent             = 2,
    kEventWindowActivated               = 5,
    kEventWindowDeactivated             = 6,
    kEventWindowHandleActivate          = 91,
    kEventWindowHandleDeactivate        = 92,
    kEventWindowGetClickActivation      = 7,
    kEventWindowGetClickModality        = 8,
    kEventWindowShowing                 = 22,
    kEventWindowHiding                  = 23,
    kEventWindowShown                   = 24,
    kEventWindowHidden                  = 25,
    kEventWindowCollapsing              = 86,
    kEventWindowExpanding               = 87,
    kEventWindowExpanded                = 70,
    kEventWindowZoomed                  = 76,
    kEventWindowBoundsChanging          = 26,
    kEventWindowBoundsChanged           = 27,
    kEventWindowResizeStarted           = 28,
    kEventWindowResizeCompleted         = 29,
    kEventWindowDragStarted             = 30,
    kEventWindowDragCompleted           = 31,
    kEventWindowClosed                  = 73,
    kEventWindowTransitionStarted       = 88,
    kEventWindowTransitionCompleted     = 89,
    kEventWindowClickDragRgn            = 32,
    kEventWindowClickResizeRgn          = 33,
    kEventWindowClickCollapseRgn        = 34,
    kEventWindowClickCloseRgn           = 35,
    kEventWindowClickZoomRgn            = 36,
    kEventWindowClickContentRgn         = 37,
    kEventWindowClickProxyIconRgn       = 38,
    kEventWindowClickToolbarButtonRgn   = 41,
    kEventWindowClickStructureRgn       = 42,
    kEventWindowCursorChange            = 40,
    kEventWindowCollapse                = 66,
    kEventWindowCollapsed               = 67,
    kEventWindowCollapseAll             = 68,
    kEventWindowExpand                  = 69,
    kEventWindowExpandAll               = 71,
    kEventWindowClose                   = 72,
    kEventWindowCloseAll                = 74,
    kEventWindowZoom                    = 75,
    kEventWindowZoomAll                 = 77,
    kEventWindowContextualMenuSelect    = 78,
    kEventWindowPathSelect              = 79,
    kEventWindowGetIdealSize            = 80,
    kEventWindowGetMinimumSize          = 81,
    kEventWindowGetMaximumSize          = 82,
    kEventWindowConstrain               = 83,
    kEventWindowRestoreFromDock         = 84,
    kEventWindowHandleContentClick      = 85,
    kEventWindowGetDockTileMenu         = 90,
    kEventWindowGetIdealStandardState   = 93,
    kEventWindowUpdateDockTile          = 94,
    kEventWindowColorSpaceChanged       = 95,
    kEventWindowRestoredAfterRelaunch   = 96,
    kEventWindowProxyBeginDrag          = 128,
    kEventWindowProxyEndDrag            = 129,
    kEventWindowToolbarSwitchMode       = 150,
    kEventWindowFocusAcquired           = 200,
    kEventWindowFocusRelinquish         = 201,
    kEventWindowFocusContent            = 202,
    kEventWindowFocusToolbar            = 203,
    kEventWindowFocusDrawer             = 204,
    kEventWindowFocusLost               = 205,
    kEventWindowFocusRestored           = 206,
    kEventWindowSheetOpening            = 210,
    kEventWindowSheetOpened             = 211,
    kEventWindowSheetClosing            = 212,
    kEventWindowSheetClosed             = 213,
    kEventWindowDrawerOpening           = 220,
    kEventWindowDrawerOpened            = 221,
    kEventWindowDrawerClosing           = 222,
    kEventWindowDrawerClosed            = 223,
    kEventWindowGetFullScreenContentSize    = 240,
    kEventWindowFullScreenEnterStarted      = 241,
    kEventWindowFullScreenEnterCompleted    = 242,
    kEventWindowFullScreenExitStarted       = 243,
    kEventWindowFullScreenExitCompleted     = 244,
    kEventWindowDrawFrame               = 1000,
    kEventWindowDrawPart                = 1001,
    kEventWindowGetRegion               = 1002,
    kEventWindowHitTest                 = 1003,
    kEventWindowInit                    = 1004,
    kEventWindowDispose                 = 1005,
    kEventWindowDragHilite              = 1006,
    kEventWindowModified                = 1007,
    kEventWindowSetupProxyDragImage     = 1008,
    kEventWindowStateChanged            = 1009,
    kEventWindowMeasureTitle            = 1010,
    kEventWindowDrawGrowBox             = 1011,
    kEventWindowGetGrowImageRegion      = 1012,
    kEventWindowPaint                   = 1013,
    kEventWindowAttributesChanged       = 1019,
    kEventWindowTitleChanged            = 1020
}

enum : int
{
    kEventParamMouseLocation      = CCONST('m', 'l', 'o', 'c'),
    kEventParamWindowMouseLocation = CCONST('w', 'm', 'o', 'u'),
    kEventParamMouseButton        = CCONST('m', 'b', 't', 'n'),
    kEventParamClickCount         = CCONST('c', 'c', 'n', 't'),
    kEventParamMouseWheelAxis     = CCONST('m', 'w', 'a', 'x'),
    kEventParamMouseWheelDelta    = CCONST('m', 'w', 'd', 'l'),
    kEventParamMouseWheelSmoothVerticalDelta = CCONST('s', 'a', 'x', 'y'),
    kEventParamMouseWheelSmoothHorizontalDelta = CCONST('s', 'a', 'x', 'x'),
    kEventParamDirectionInverted  = CCONST('d', 'i', 'r', 'i'),
    kEventParamMouseDelta         = CCONST('m', 'd', 't', 'a'),
    kEventParamMouseChord         = CCONST('c', 'h', 'o', 'r'),
    kEventParamTabletEventType    = CCONST('t', 'b', 'l', 't'),
    kEventParamMouseTrackingRef   = CCONST('m', 't', 'r', 'f'),
    typeMouseButton               = CCONST('m', 'b', 't', 'n'),
    typeMouseWheelAxis            = CCONST('m', 'w', 'a', 'x'),
    typeMouseTrackingRef          = CCONST('m', 't', 'r', 'f')
}

enum : int
{
    kEventParamWindowRef          = CCONST('w', 'i', 'n', 'd'),
    kEventParamGrafPort           = CCONST('g', 'r', 'a', 'f'),
    kEventParamMenuRef            = CCONST('m', 'e', 'n', 'u'),
    kEventParamEventRef           = CCONST('e', 'v', 'n', 't'),
    kEventParamControlRef         = CCONST('c', 't', 'r', 'l'),
    kEventParamRgnHandle          = CCONST('r', 'g', 'n', 'h'),
    kEventParamEnabled            = CCONST('e', 'n', 'a', 'b'),
    kEventParamDimensions         = CCONST('d', 'i', 'm', 's'),
    kEventParamBounds             = CCONST('b', 'o', 'u', 'n'),
    kEventParamAvailableBounds    = CCONST('a', 'v', 'l', 'b'),
//    kEventParamAEEventID          = keyAEEventID,
//    kEventParamAEEventClass       = keyAEEventClass,
    kEventParamCGContextRef       = CCONST('c', 'n', 't', 'x'),
    kEventParamCGImageRef         = CCONST('c', 'g', 'i', 'm'),
    kEventParamDeviceDepth        = CCONST('d', 'e', 'v', 'd'),
    kEventParamDeviceColor        = CCONST('d', 'e', 'v', 'c'),
    kEventParamMutableArray       = CCONST('m', 'a', 'r', 'r'),
    kEventParamResult             = CCONST('a', 'n', 's', 'r'),
    kEventParamMinimumSize        = CCONST('m', 'n', 's', 'z'),
    kEventParamMaximumSize        = CCONST('m', 'x', 's', 'z'),
    kEventParamAttributes         = CCONST('a', 't', 't', 'r'),
    kEventParamReason             = CCONST('w', 'h', 'y', '?'),
    kEventParamTransactionID      = CCONST('t', 'r', 'n', 's'),
    kEventParamDisplayDevice      = CCONST('g', 'd', 'e', 'v'),
//    kEventParamGDevice            = kEventParamDisplayDevice,
    kEventParamIndex              = CCONST('i', 'n', 'd', 'x'),
    kEventParamUserData           = CCONST('u', 's', 'r', 'd'),
    kEventParamShape              = CCONST('s', 'h', 'a', 'p'),
    typeWindowRef                 = CCONST('w', 'i', 'n', 'd'),
    typeGrafPtr                   = CCONST('g', 'r', 'a', 'f'),
    typeGWorldPtr                 = CCONST('g', 'w', 'l', 'd'),
    typeMenuRef                   = CCONST('m', 'e', 'n', 'u'),
    typeControlRef                = CCONST('c', 't', 'r', 'l'),
    typeCollection                = CCONST('c', 'l', 't', 'n'),
    typeQDRgnHandle               = CCONST('r', 'g', 'n', 'h'),
    typeOSStatus                  = CCONST('o', 's', 's', 't'),
    typeCFIndex                   = CCONST('c', 'f', 'i', 'x'),
    typeCGContextRef              = CCONST('c', 'n', 't', 'x'),
    typeCGImageRef                = CCONST('c', 'g', 'i', 'm'),
    typeHIPoint                   = CCONST('h', 'i', 'p', 't'),
    typeHISize                    = CCONST('h', 'i', 's', 'z'),
    typeHIRect                    = CCONST('h', 'i', 'r', 'c'),
    typeHIShapeRef                = CCONST('s', 'h', 'a', 'p'),
    typeVoidPtr                   = CCONST('v', 'o', 'i', 'd'),
    typeGDHandle                  = CCONST('g', 'd', 'e', 'v'),
    typeCGDisplayID               = CCONST('c', 'g', 'i', 'd'),
    typeCGFloat                   = CCONST('c', 'g', 'f', 'l'),
    typeHIPoint72DPIGlobal        = CCONST('h', 'i', 'p', 'g'),
    typeHIPointScreenPixel        = CCONST('h', 'i', 'p', 's'),
    typeHISize72DPIGlobal         = CCONST('h', 'i', 's', 'g'),
    typeHISizeScreenPixel         = CCONST('h', 'i', 's', 's'),
    typeHIRect72DPIGlobal         = CCONST('h', 'i', 'r', 'g'),
    typeHIRectScreenPixel         = CCONST('h', 'i', 'r', 's'),
    typeCGFloat72DPIGlobal        = CCONST('h', 'i', 'f', 'g'),
    typeCGFloatScreenPixel        = CCONST('h', 'i', 'f', 's'),
    kEventParamDisplayChangeFlags = CCONST('c', 'g', 'd', 'p'),
    typeCGDisplayChangeFlags      = CCONST('c', 'g', 'd', 'f')
}

enum : int
{
    kEventParamKeyCode            = CCONST('k', 'c', 'o', 'd'),
    kEventParamKeyMacCharCodes    = CCONST('k', 'c', 'h', 'r'),
    kEventParamKeyModifiers       = CCONST('k', 'm', 'o', 'd'),
    kEventParamKeyUnicodes        = CCONST('k', 'u', 'n', 'i'),
    kEventParamKeyboardType       = CCONST('k', 'b', 'd', 't'),
    typeEventHotKeyID             = CCONST('h', 'k', 'i', 'd')
}

alias EventMouseButton = UInt16;
enum : EventMouseButton
{
    kEventMouseButtonPrimary      = 1,
    kEventMouseButtonSecondary    = 2,
    kEventMouseButtonTertiary     = 3
}

OSStatus InstallControlEventHandler(ControlRef target, EventHandlerUPP handler, ItemCount numTypes,
                                    const(EventTypeSpec)* list, void* userData, EventHandlerRef* outHandlerRef)
{
    return InstallEventHandler(GetControlEventTarget(target), handler, numTypes, list, userData, outHandlerRef);
}

OSStatus InstallWindowEventHandler(WindowRef target, EventHandlerUPP handler, ItemCount numTypes,
                                   const(EventTypeSpec)* list, void* userData, EventHandlerRef* outHandlerRef)
{
    return InstallEventHandler(GetWindowEventTarget(target), handler, numTypes, list, userData, outHandlerRef);
}





extern (C) nothrow @nogc
{
    alias da_GetControlEventTarget = EventTargetRef function(ControlRef);
    alias da_GetWindowEventTarget = EventTargetRef function(WindowRef);
}

__gshared
{
    da_GetControlEventTarget GetControlEventTarget;
    da_GetWindowEventTarget GetWindowEventTarget;
}


// <HIToolbox/Controls.h>

enum : int
{
  kControlSupportsGhosting      = 1 << 0,
  kControlSupportsEmbedding     = 1 << 1,
  kControlSupportsFocus         = 1 << 2,
  kControlWantsIdle             = 1 << 3,
  kControlWantsActivate         = 1 << 4,
  kControlHandlesTracking       = 1 << 5,
  kControlSupportsDataAccess    = 1 << 6,
  kControlHasSpecialBackground  = 1 << 7,
  kControlGetsFocusOnClick      = 1 << 8,
  kControlSupportsCalcBestRect  = 1 << 9,
  kControlSupportsLiveFeedback  = 1 << 10,
  kControlHasRadioBehavior      = 1 << 11,
  kControlSupportsDragAndDrop   = 1 << 12,
  kControlAutoToggles           = 1 << 14,
  kControlSupportsGetRegion     = 1 << 17,
  kControlSupportsFlattening    = 1 << 19,
  kControlSupportsSetCursor     = 1 << 20,
  kControlSupportsContextualMenus = 1 << 21,
  kControlSupportsClickActivation = 1 << 22,
  kControlIdlesWithTimer        = 1 << 23,
  kControlInvertsUpDownValueMeaning = 1 << 24
}

struct ControlID
{
    OSType              signature;
    SInt32              id;
}

extern (C) nothrow @nogc
{
    alias da_GetRootControl = OSErr function(WindowRef, ControlRef*);
    alias da_CreateRootControl = OSErr function(WindowRef inWindow, ControlRef* outControl);
    alias da_EmbedControl = OSErr function(ControlRef inControl, ControlRef inContainer);
    alias da_SizeControl = void function(ControlRef theControl, SInt16 w, SInt16 h);
}

__gshared
{
    da_GetRootControl GetRootControl;
    da_CreateRootControl CreateRootControl;
    da_EmbedControl EmbedControl;
    da_SizeControl SizeControl;
}


// <HIToolbox/Events.h>

alias EventModifiers = ushort;
enum
{
  activeFlagBit                 = 0,
  btnStateBit                   = 7,
  cmdKeyBit                     = 8,
  shiftKeyBit                   = 9,
  alphaLockBit                  = 10,
  optionKeyBit                  = 11,
  controlKeyBit                 = 12,
}

enum : EventModifiers
{
  activeFlag                    = 1 << activeFlagBit,
  btnState                      = 1 << btnStateBit,
  cmdKey                        = 1 << cmdKeyBit,
  shiftKey                      = 1 << shiftKeyBit,
  alphaLock                     = 1 << alphaLockBit,
  optionKey                     = 1 << optionKeyBit,
  controlKey                    = 1 << controlKeyBit
}


// <HIToolbox/HIContainerViews.h>

extern (C) nothrow @nogc
{
    alias da_CreateUserPaneControl = OSStatus function(WindowRef, const(Rect)*, UInt32, ControlRef*);
}

__gshared
{
    da_CreateUserPaneControl CreateUserPaneControl;
}


// <HIToolbox/HIGeometry.h>

alias HIRect = CGRect;
alias HIPoint = CGPoint;

alias HICoordinateSpace = UInt32;
enum : HICoordinateSpace
{
  kHICoordSpace72DPIGlobal      = 1,
  kHICoordSpaceScreenPixel      = 2,
  kHICoordSpaceWindow           = 3,
  kHICoordSpaceView             = 4
}

extern (C) nothrow @nogc
{
    alias da_HIPointConvert = void function(HIPoint*, HICoordinateSpace, void*, HICoordinateSpace, void*);
}

__gshared
{
    da_HIPointConvert HIPointConvert;
}



// <HIToolbox/HIObject.h>

alias ControlRef = void*;
alias HIViewRef = ControlRef;
alias HIViewID = ControlID;


// <HIToolbox/HIView.h>

enum : int
{
  kHIViewFeatureSupportsGhosting = 1 << 0,
  kHIViewFeatureAllowsSubviews  = 1 << 1,
  kHIViewFeatureGetsFocusOnClick = 1 << 8,
  kHIViewFeatureSupportsLiveFeedback = 1 << 10,
  kHIViewFeatureSupportsRadioBehavior = 1 << 11,
  kHIViewFeatureAutoToggles     = 1 << 14,
  kHIViewFeatureIdlesWithTimer  = 1 << 23,
  kHIViewFeatureInvertsUpDownValueMeaning = 1 << 24,
  kHIViewFeatureIsOpaque        = 1 << 25,
  kHIViewFeatureDoesNotDraw     = 1 << 27,
  kHIViewFeatureDoesNotUseSpecialParts = 1 << 28,
  kHIViewFeatureIgnoresClicks   = 1 << 29
}

extern (C) nothrow @nogc
{
    alias da_HIViewGetRoot = HIViewRef function(WindowRef inWindow);
    alias da_HIViewFindByID = OSStatus function(HIViewRef inStartView, HIViewID inID, HIViewRef* outView);
    alias da_HIViewAddSubview = OSStatus function(HIViewRef inParent, HIViewRef inNewChild);
    alias da_HIViewSetNeedsDisplayInRect = OSStatus function(HIViewRef, const(HIRect)*, Boolean);
    alias da_HIViewGetBounds = OSStatus function(HIViewRef, HIRect* outRect);
}

__gshared
{
    da_HIViewGetRoot HIViewGetRoot;
    da_HIViewFindByID HIViewFindByID;
    da_HIViewAddSubview HIViewAddSubview;
    da_HIViewSetNeedsDisplayInRect HIViewSetNeedsDisplayInRect;
    da_HIViewGetBounds HIViewGetBounds;
}


// <HIToolbox/HIWindowViews.h>

static immutable HIViewID kHIViewWindowContentID = HIViewID(CCONST('w', 'i', 'n', 'd'), 1); // TODO: is it portable across OSX versions?

// <HIToolbox/MacWindows.h>

alias WindowClass = int;
alias WindowAttributes = OptionBits;

enum : int
{
    kHIWindowBitCloseBox          = 1,
    kHIWindowBitZoomBox           = 2,
    kHIWindowBitCollapseBox       = 4,
    kHIWindowBitResizable         = 5,
    kHIWindowBitSideTitlebar      = 6,
    kHIWindowBitToolbarButton     = 7,
    kHIWindowBitUnifiedTitleAndToolbar = 8,
    kHIWindowBitTextured          = 9,
    kHIWindowBitNoTitleBar        = 10,
    kHIWindowBitTexturedSquareCorners = 11,
    kHIWindowBitNoTexturedContentSeparator = 12,
    kHIWindowBitRoundBottomBarCorners = 13,
    kHIWindowBitDoesNotCycle      = 16,
    kHIWindowBitNoUpdates         = 17,
    kHIWindowBitNoActivates       = 18,
    kHIWindowBitOpaqueForEvents   = 19,
    kHIWindowBitCompositing       = 20,
    kHIWindowBitFrameworkScaled   = 21,
    kHIWindowBitNoShadow          = 22,
    kHIWindowBitCanBeVisibleWithoutLogin = 23,
    kHIWindowBitAsyncDrag         = 24,
    kHIWindowBitHideOnSuspend     = 25,
    kHIWindowBitStandardHandler   = 26,
    kHIWindowBitHideOnFullScreen  = 27,
    kHIWindowBitInWindowMenu      = 28,
    kHIWindowBitLiveResize        = 29,
    kHIWindowBitIgnoreClicks      = 30,
    kHIWindowBitNoConstrain       = 32,
    kHIWindowBitDoesNotHide       = 33,
    kHIWindowBitAutoViewDragTracking = 34
}

enum : int
{
    kWindowNoAttributes           = 0,
    kWindowCloseBoxAttribute      = (1 << (kHIWindowBitCloseBox - 1)),
    kWindowHorizontalZoomAttribute = (1 << (kHIWindowBitZoomBox - 1)),
    kWindowVerticalZoomAttribute  = (1 << kHIWindowBitZoomBox),
    kWindowFullZoomAttribute      = (kWindowVerticalZoomAttribute | kWindowHorizontalZoomAttribute),
    kWindowCollapseBoxAttribute   = (1 << (kHIWindowBitCollapseBox - 1)),
    kWindowResizableAttribute     = (1 << (kHIWindowBitResizable - 1)),
    kWindowSideTitlebarAttribute  = (1 << (kHIWindowBitSideTitlebar - 1)),
    kWindowToolbarButtonAttribute = (1 << (kHIWindowBitToolbarButton - 1)),
    kWindowUnifiedTitleAndToolbarAttribute = (1 << (kHIWindowBitUnifiedTitleAndToolbar - 1)),
    kWindowMetalAttribute         = (1 << (kHIWindowBitTextured - 1)),
    kWindowNoTitleBarAttribute    = (1 << (kHIWindowBitNoTitleBar - 1)),
    kWindowTexturedSquareCornersAttribute = (1 << (kHIWindowBitTexturedSquareCorners - 1)),
    kWindowMetalNoContentSeparatorAttribute = (1 << (kHIWindowBitNoTexturedContentSeparator - 1)),
    kWindowHasRoundBottomBarCornersAttribute = (1 << (kHIWindowBitRoundBottomBarCorners - 1)),
    kWindowDoesNotCycleAttribute  = (1 << (kHIWindowBitDoesNotCycle - 1)),
    kWindowNoUpdatesAttribute     = (1 << (kHIWindowBitNoUpdates - 1)),
    kWindowNoActivatesAttribute   = (1 << (kHIWindowBitNoActivates - 1)),
    kWindowOpaqueForEventsAttribute = (1 << (kHIWindowBitOpaqueForEvents - 1)),
    kWindowCompositingAttribute   = (1 << (kHIWindowBitCompositing - 1)),
    kWindowNoShadowAttribute      = (1 << (kHIWindowBitNoShadow - 1)),
    kWindowCanBeVisibleWithoutLoginAttribute = (1 << (kHIWindowBitCanBeVisibleWithoutLogin - 1)),
    kWindowHideOnSuspendAttribute = (1 << (kHIWindowBitHideOnSuspend - 1)),
    kWindowAsyncDragAttribute     = (1 << (kHIWindowBitAsyncDrag - 1)),
    kWindowStandardHandlerAttribute = (1 << (kHIWindowBitStandardHandler - 1)),
    kWindowHideOnFullScreenAttribute = (1 << (kHIWindowBitHideOnFullScreen - 1)),
    kWindowInWindowMenuAttribute  = (1 << (kHIWindowBitInWindowMenu - 1)),
    kWindowLiveResizeAttribute    = (1 << (kHIWindowBitLiveResize - 1)),
    kWindowIgnoreClicksAttribute  = (1 << (kHIWindowBitIgnoreClicks - 1)),
    kWindowFrameworkScaledAttribute = (1 << (kHIWindowBitFrameworkScaled - 1)),
    kWindowStandardDocumentAttributes = (kWindowCloseBoxAttribute | kWindowFullZoomAttribute | kWindowCollapseBoxAttribute | kWindowResizableAttribute),
    kWindowStandardFloatingAttributes = (kWindowCloseBoxAttribute | kWindowCollapseBoxAttribute)
}


extern (C) nothrow @nogc
{
    alias da_GetWindowAttributes = OSStatus function(WindowRef window, WindowAttributes* outAttributes);
}

__gshared
{
    da_GetWindowAttributes GetWindowAttributes;
}

