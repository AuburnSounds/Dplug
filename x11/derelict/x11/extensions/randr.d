module derelict.x11.extensions.randr;

version(linux):

/*
 * Copyright © 2000 Compaq Computer Corporation
 * Copyright © 2002 Hewlett Packard Company
 * Copyright © 2006 Intel Corporation
 * Copyright © 2008 Red Hat, Inc.
 *
 * Permission to use, copy, modify, distribute, and sell this software and its
 * documentation for any purpose is hereby granted without fee, provided that
 * the above copyright notice appear in all copies and that both that copyright
 * notice and this permission notice appear in supporting documentation, and
 * that the name of the copyright holders not be used in advertising or
 * publicity pertaining to distribution of the software without specific,
 * written prior permission.  The copyright holders make no representations
 * about the suitability of this software for any purpose.  It is provided "as
 * is" without express or implied warranty.
 *
 * THE COPYRIGHT HOLDERS DISCLAIM ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
 * INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS, IN NO
 * EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY SPECIAL, INDIRECT OR
 * CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE,
 * DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
 * TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
 * OF THIS SOFTWARE.
 *
 * Author:  Jim Gettys, HP Labs, Hewlett-Packard, Inc.
 *	    Keith Packard, Intel Corporation
 */

alias ushort Rotation;
alias ushort SizeID;
alias ushort SubpixelOrder;
alias ushort Connection;
alias ushort XRandrRotation;
alias ushort XRandrSizeID;
alias ushort XRandrSubpixelOrder;
alias ulong XRandrModeFlags;

enum RANDR_NAME			= "RANDR";
enum RANDR_MAJOR		= 1;
enum RANDR_MINOR		= 4;

enum RRNumberErrors		= 4;
enum RRNumberEvents		= 2;
enum RRNumberRequests	= 42;

enum X_RRQueryVersion	= 0;

enum X_RROldGetScreenInfo	= 1;
enum X_RR1_0SetScreenConfig	= 2;
enum X_RRSetScreenConfig	= 2;
enum X_RROldScreenChangeSelectInput	= 3;
enum X_RRSelectInput		= 4;
enum X_RRGetScreenInfo		= 5;
enum X_RRGetScreenSizeRange	= 6;
enum X_RRSetScreenSize		= 7;
enum X_RRGetScreenResources	= 8;
enum X_RRGetOutputInfo		= 9;
enum X_RRListOutputProperties = 10;
enum X_RRQueryOutputProperty = 11;
enum X_RRConfigureOutputProperty = 12;
enum X_RRChangeOutputProperty = 13;
enum X_RRDeleteOutputProperty = 14;
enum X_RRGetOutputProperty 	= 15;
enum X_RRCreateMode			= 16;
enum X_RRDestroyMode		= 17;
enum X_RRAddOutputMode		= 18;
enum X_RRDeleteOutputMode	= 19;
enum X_RRGetCrtcInfo		= 20;
enum X_RRSetCrtcConfig	    = 21;
enum X_RRGetCrtcGammaSize	= 22;
enum X_RRGetCrtcGamma		= 23;
enum X_RRSetCrtcGamma		= 24;
enum X_RRGetScreenResourcesCurrent = 25;
enum X_RRSetCrtcTransform	= 26;
enum X_RRGetCrtcTransform	= 27;
enum X_RRGetPanning			= 28;
enum X_RRSetPanning			= 29;
enum X_RRSetOutputPrimary	= 30;
enum X_RRGetOutputPrimary	= 31;
enum X_RRGetProviders		= 32;
enum X_RRGetProviderInfo	= 33;
enum X_RRSetProviderOffloadSink = 34;
enum X_RRSetProviderOutputSource = 35;
enum X_RRListProviderProperties = 36;
enum X_RRQueryProviderProperty = 37;
enum X_RRConfigureProviderProperty = 38;
enum X_RRChangeProviderProperty = 39;
enum X_RRDeleteProviderProperty = 40;
enum X_RRGetProviderProperty = 41;

enum RRTransformUnit		= (1L << 0);
enum RRTransformScaleUp	    = (1L << 1);
enum RRTransformScaleDown	= (1L << 2);
enum RRTransformProjective	= (1L << 3);

enum RRScreenChangeNotifyMask = (1L << 0);
enum RRCrtcChangeNotifyMask	= (1L << 1);
enum RROutputChangeNotifyMask = (1L << 2);
enum RROutputPropertyNotifyMask = (1L << 3);
enum RRProviderChangeNotifyMask = (1L << 4);
enum RRProviderPropertyNotifyMask = (1L << 5);
enum RRResourceChangeNotifyMask = (1L << 6);

enum RRScreenChangeNotify	= 0;
enum RRNotify				= 1;

enum  RRNotify_CrtcChange	= 0;
enum  RRNotify_OutputChange	= 1;
enum  RRNotify_OutputProperty = 2;
enum  RRNotify_ProviderChange = 3;
enum  RRNotify_ProviderProperty = 4;
enum  RRNotify_ResourceChange = 5;

enum RR_Rotate_0			= 1;
enum RR_Rotate_90			= 2;
enum RR_Rotate_180			= 4;
enum RR_Rotate_270			= 8;

enum RR_Reflect_X			= 16;
enum RR_Reflect_Y			= 32;

enum RRSetConfigSuccess		= 0;
enum RRSetConfigInvalidConfigTime = 1;
enum RRSetConfigInvalidTime	= 2;
enum RRSetConfigFailed		= 3;

enum RR_HSyncPositive		= 0x00000001;
enum RR_HSyncNegative		= 0x00000002;
enum RR_VSyncPositive		= 0x00000004;
enum RR_VSyncNegative		= 0x00000008;
enum RR_Interlace			= 0x00000010;
enum RR_DoubleScan			= 0x00000020;
enum RR_CSync				= 0x00000040;
enum RR_CSyncPositive		= 0x00000080;
enum RR_CSyncNegative		= 0x00000100;
enum RR_HSkewPresent		= 0x00000200;
enum RR_BCast				= 0x00000400;
enum RR_PixelMultiplex		= 0x00000800;
enum RR_DoubleClock			= 0x00001000;
enum RR_ClockDivideBy2		= 0x00002000;

enum RR_Connected			= 0;
enum RR_Disconnected		= 1;
enum RR_UnknownConnection	= 2;

enum BadRROutput			= 0;
enum BadRRCrtc				= 1;
enum BadRRMode				= 2;
enum BadRRProvider			= 3;

enum RR_PROPERTY_BACKLIGHT	= "Backlight";
enum RR_PROPERTY_RANDR_EDID	= "EDID";
enum RR_PROPERTY_SIGNAL_FORMAT = "SignalFormat";
enum RR_PROPERTY_SIGNAL_PROPERTIES = "SignalProperties";
enum RR_PROPERTY_CONNECTOR_TYPE	= "ConnectorType";
enum RR_PROPERTY_CONNECTOR_NUMBER = "ConnectorNumber";
enum RR_PROPERTY_COMPATIBILITY_LIST	= "CompatibilityList";
enum RR_PROPERTY_CLONE_LIST	= "CloneList";
enum RR_PROPERTY_BORDER		= "Border";
enum RR_PROPERTY_BORDER_DIMENSIONS = "BorderDimensions";

enum RR_Capability_None = 0;
enum RR_Capability_SourceOutput = 1;
enum RR_Capability_SinkOutput = 2;
enum RR_Capability_SourceOffload = 4;
enum RR_Capability_SinkOffload = 8;
