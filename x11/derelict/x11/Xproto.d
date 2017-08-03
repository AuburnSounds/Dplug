module derelict.x11.Xproto;
version(linux):
import derelict.x11.Xmd;
import derelict.x11.Xprotostr;
import derelict.x11.Xlib;

extern (C) nothrow @nogc:

/*
 * Define constants for the sizes of the network packets.  The sz_ prefix is
 * used instead of something more descriptive so that the symbols are no more
 * than 32 characters in length (which causes problems for some compilers).
 */
const int sz_xSegment                       = 8;
const int sz_xPoint                         = 4;
const int sz_xRectangle                     = 8;
const int sz_xArc                           = 12;
const int sz_xConnClientPrefix              = 12;
const int sz_xConnSetupPrefix               = 8;
const int sz_xConnSetup                     = 32;
const int sz_xPixmapFormat                  = 8;
const int sz_xDepth                         = 8;
const int sz_xVisualType                    = 24;
const int sz_xWindowRoot                    = 40;
const int sz_xTimecoord                     = 8;
const int sz_xHostEntry                     = 4;
const int sz_xCharInfo                      = 12;
const int sz_xFontProp                      = 8;
const int sz_xTextElt                       = 2;
const int sz_xColorItem                     = 12;
const int sz_xrgb                           = 8;
const int sz_xGenericReply                  = 32;
const int sz_xGetWindowAttributesReply      = 44;
const int sz_xGetGeometryReply              = 32;
const int sz_xQueryTreeReply                = 32;
const int sz_xInternAtomReply               = 32;
const int sz_xGetAtomNameReply              = 32;
const int sz_xGetPropertyReply              = 32;
const int sz_xListPropertiesReply           = 32;
const int sz_xGetSelectionOwnerReply        = 32;
const int sz_xGrabPointerReply              = 32;
const int sz_xQueryPointerReply             = 32;
const int sz_xGetMotionEventsReply          = 32;
const int sz_xTranslateCoordsReply          = 32;
const int sz_xGetInputFocusReply            = 32;
const int sz_xQueryKeymapReply              = 40;
const int sz_xQueryFontReply                = 60;
const int sz_xQueryTextExtentsReply         = 32;
const int sz_xListFontsReply                = 32;
const int sz_xGetFontPathReply              = 32;
const int sz_xGetImageReply                 = 32;
const int sz_xListInstalledColormapsReply   = 32;
const int sz_xAllocColorReply               = 32;
const int sz_xAllocNamedColorReply          = 32;
const int sz_xAllocColorCellsReply          = 32;
const int sz_xAllocColorPlanesReply         = 32;
const int sz_xQueryColorsReply              = 32;
const int sz_xLookupColorReply              = 32;
const int sz_xQueryBestSizeReply            = 32;
const int sz_xQueryExtensionReply           = 32;
const int sz_xListExtensionsReply           = 32;
const int sz_xSetMappingReply               = 32;
const int sz_xGetKeyboardControlReply       = 52;
const int sz_xGetPointerControlReply        = 32;
const int sz_xGetScreenSaverReply           = 32;
const int sz_xListHostsReply                = 32;
const int sz_xSetModifierMappingReply       = 32;
const int sz_xError                         = 32;
const int sz_xEvent                         = 32;
const int sz_xKeymapEvent                   = 32;
const int sz_xReq                           = 4;
const int sz_xResourceReq                   = 8;
const int sz_xCreateWindowReq               = 32;
const int sz_xChangeWindowAttributesReq     = 12;
const int sz_xChangeSaveSetReq              = 8;
const int sz_xReparentWindowReq             = 16;
const int sz_xConfigureWindowReq            = 12;
const int sz_xCirculateWindowReq            = 8;
const int sz_xInternAtomReq                 = 8;
const int sz_xChangePropertyReq             = 24;
const int sz_xDeletePropertyReq             = 12;
const int sz_xGetPropertyReq                = 24;
const int sz_xSetSelectionOwnerReq          = 16;
const int sz_xConvertSelectionReq           = 24;
const int sz_xSendEventReq                  = 44;
const int sz_xGrabPointerReq                = 24;
const int sz_xGrabButtonReq                 = 24;
const int sz_xUngrabButtonReq               = 12;
const int sz_xChangeActivePointerGrabReq    = 16;
const int sz_xGrabKeyboardReq               = 16;
const int sz_xGrabKeyReq                    = 16;
const int sz_xUngrabKeyReq                  = 12;
const int sz_xAllowEventsReq                = 8;
const int sz_xGetMotionEventsReq            = 16;
const int sz_xTranslateCoordsReq            = 16;
const int sz_xWarpPointerReq                = 24;
const int sz_xSetInputFocusReq              = 12;
const int sz_xOpenFontReq                   = 12;
const int sz_xQueryTextExtentsReq           = 8;
const int sz_xListFontsReq                  = 8;
const int sz_xSetFontPathReq                = 8;
const int sz_xCreatePixmapReq               = 16;
const int sz_xCreateGCReq                   = 16;
const int sz_xChangeGCReq                   = 12;
const int sz_xCopyGCReq                     = 16;
const int sz_xSetDashesReq                  = 12;
const int sz_xSetClipRectanglesReq          = 12;
const int sz_xCopyAreaReq                   = 28;
const int sz_xCopyPlaneReq                  = 32;
const int sz_xPolyPointReq                  = 12;
const int sz_xPolySegmentReq                = 12;
const int sz_xFillPolyReq                   = 16;
const int sz_xPutImageReq                   = 24;
const int sz_xGetImageReq                   = 20;
const int sz_xPolyTextReq                   = 16;
const int sz_xImageTextReq                  = 16;
const int sz_xCreateColormapReq             = 16;
const int sz_xCopyColormapAndFreeReq        = 12;
const int sz_xAllocColorReq                 = 16;
const int sz_xAllocNamedColorReq            = 12;
const int sz_xAllocColorCellsReq            = 12;
const int sz_xAllocColorPlanesReq           = 16;
const int sz_xFreeColorsReq                 = 12;
const int sz_xStoreColorsReq                = 8;
const int sz_xStoreNamedColorReq            = 16;
const int sz_xQueryColorsReq                = 8;
const int sz_xLookupColorReq                = 12;
const int sz_xCreateCursorReq               = 32;
const int sz_xCreateGlyphCursorReq          = 32;
const int sz_xRecolorCursorReq              = 20;
const int sz_xQueryBestSizeReq              = 12;
const int sz_xQueryExtensionReq             = 8;
const int sz_xChangeKeyboardControlReq      = 8;
const int sz_xBellReq                       = 4;
const int sz_xChangePointerControlReq       = 12;
const int sz_xSetScreenSaverReq             = 12;
const int sz_xChangeHostsReq                = 8;
const int sz_xListHostsReq                  = 4;
const int sz_xChangeModeReq                 = 4;
const int sz_xRotatePropertiesReq           = 12;
const int sz_xReply                         = 32;
const int sz_xGrabKeyboardReply             = 32;
const int sz_xListFontsWithInfoReply        = 60;
const int sz_xSetPointerMappingReply        = 32;
const int sz_xGetKeyboardMappingReply       = 32;
const int sz_xGetPointerMappingReply        = 32;
const int sz_xGetModifierMappingReply       = 32;
const int sz_xListFontsWithInfoReq          = 8;
const int sz_xPolyLineReq                   = 12;
const int sz_xPolyArcReq                    = 12;
const int sz_xPolyRectangleReq              = 12;
const int sz_xPolyFillRectangleReq          = 12;
const int sz_xPolyFillArcReq                = 12;
const int sz_xPolyText8Req                  = 16;
const int sz_xPolyText16Req                 = 16;
const int sz_xImageText8Req                 = 16;
const int sz_xImageText16Req                = 16;
const int sz_xSetPointerMappingReq          = 4;
const int sz_xForceScreenSaverReq           = 4;
const int sz_xSetCloseDownModeReq           = 4;
const int sz_xClearAreaReq                  = 16;
const int sz_xSetAccessControlReq           = 4;
const int sz_xGetKeyboardMappingReq         = 8;
const int sz_xSetModifierMappingReq         = 4;
const int sz_xPropIconSize                  = 24;
const int sz_xChangeKeyboardMappingReq      = 8;


/* For the purpose of the structure definitions in this file,
we must redefine the following types in terms of Xmd.h's types, which may
include bit fields.  All of these are #undef'd at the end of this file,
restoring the definitions in X.h.  */

// Due to the way alias and import works, those definitions needs to be
// put in a separate module.
import derelict.x11.Xproto_undef;

const int X_TCP_PORT = 6000;                            /* add display number                                           */

const int xTrue                         = 1;
const int xFalse                        = 0;


alias CARD16 KeyButMask;

/*****************
   connection setup structure.  This is followed by
   numRoots xWindowRoot structs.
*****************/

struct xConnClientPrefix{
    CARD8   byteOrder;
    BYTE    pad;
    CARD16  majorVersion;
    CARD16  minorVersion;
    CARD16  nbytesAuthProto6;                           /* Authorization protocol                                       */
    CARD16  nbytesAuthString;                           /* Authorization string                                         */
    CARD16  pad2;
}

struct xConnSetupPrefix{
    CARD8          success;
    BYTE           lengthReason;                        /*num bytes in string following if failure                      */
    CARD16         majorVersion,
                   minorVersion;
    CARD16         length;                              /* 1*4 additional bytes in setup info                           */
}


struct xConnSetup{
    CARD32  release;
    CARD32  ridBase, ridMask;
    CARD32  motionBufferSize;
    CARD16  nbytesVendor;                               /* number of bytes in vendor string                             */
    CARD16  maxRequestSize;
    CARD8   numRoots;                                   /* number of roots structs to follow                            */
    CARD8   numFormats;                                 /* number of pixmap formats                                     */
    CARD8   imageByteOrder;                             /* LSBFirst, MSBFirst                                           */
    CARD8   bitmapBitOrder;                             /* LeastSignificant, MostSign...                                */
    CARD8   bitmapScanlineUnit,                         /* 8, 16, 32                                                    */
            bitmapScanlinePad;                          /* 8, 16, 32                                                    */
    KeyCode minKeyCode, maxKeyCode;
    CARD32  pad2;
}

struct xPixmapFormat{
    CARD8   depth;
    CARD8   bitsPerPixel;
    CARD8   scanLinePad;
    CARD8   pad1;
    CARD32  pad2;
}

                                                        /* window root                                                  */

struct xDepth{
    CARD8   depth;
    CARD8   pad1;
    CARD16  nVisuals;                                   /* number of xVisualType structures following                   */
    CARD32  pad2;
}

struct xVisualType{
    VisualID visualID;
    CARD8 c_class;
    CARD8 bitsPerRGB;
    CARD16 colormapEntries;
    CARD32 redMask, greenMask, blueMask;
    CARD32 pad;
}

struct xWindowRoot {
    Window         windowId;
    Colormap       defaultColormap;
    CARD32         whitePixel, blackPixel;
    CARD32         currentInputMask;
    CARD16         pixWidth, pixHeight;
    CARD16         mmWidth, mmHeight;
    CARD16         minInstalledMaps, maxInstalledMaps;
    VisualID       rootVisualID;
    CARD8          backingStore;
    BOOL           saveUnders;
    CARD8          rootDepth;
    CARD8          nDepths;                             /* number of xDepth structures following                        */
}

/*****************************************************************
 * Structure Defns
 *   Structures needed for replies
 *****************************************************************/

                                                        /* Used in GetMotionEvents                                      */

struct xTimecoord{
    CARD32 time;
    INT16 x, y;
}

struct xHostEntry{
    CARD8   family;
    BYTE    pad;
    CARD16  length;
}

struct xCharInfo{
    INT16   leftSideBearing, rightSideBearing, characterWidth, ascent, descent;
    CARD16  attributes;
}

struct xFontProp{
    Atom    name;
    CARD32  value;
}

/*
 * non-aligned big-endian font ID follows this struct
 */
struct xTextElt{                                        /* followed by string                                           */
    CARD8   len;                                        /* number of *characters* in string, or FontChange (255) for font change, or 0 if just delta given */
    INT8    delta;
}


struct xColorItem{
    CARD32  pixel;
    CARD16  red, green, blue;
    CARD8   flags;                                      /* DoRed, DoGreen, DoBlue booleans                              */
    CARD8   pad;
}

struct xrgb{
    CARD16 red, green, blue, pad;
}

alias CARD8 KEYCODE;


/*****************
 * XRep:
 *    meant to be 32 byte quantity
 *****************/

/* GenericReply is the common format of all replies.  The "data" items
   are specific to each individual reply type. */

struct xGenericReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE data1;                                         /* depends on reply type                                        */
    CARD16 sequenceNumber;                              /* of last request received by server                           */
    CARD32 length;                                      /* 4 byte quantities beyond size of GenericReply                */
    CARD32 data00;
    CARD32 data01;
    CARD32 data02;
    CARD32 data03;
    CARD32 data04;
    CARD32 data05;
}

                                                        /* Individual reply formats.                                    */

struct xGetWindowAttributesReply{
    BYTE type;                                          /* X_Reply                                                      */
    CARD8 backingStore;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* NOT 0; this is an extra-large reply                          */
    VisualID visualID;
    CARD16 c_class;
    CARD8 bitGravity;
    CARD8 winGravity;
    CARD32 backingBitPlanes;
    CARD32 backingPixel;
    BOOL saveUnder;
    BOOL mapInstalled;
    CARD8 mapState;
    BOOL c_override;
    Colormap colormap;
    CARD32 allEventMasks;
    CARD32 yourEventMask;
    CARD16 doNotPropagateMask;
    CARD16 pad;
}

struct xGetGeometryReply{
    BYTE type;                                          /* X_Reply                                                      */
    CARD8 depth;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    Window root;
    INT16 x, y;
    CARD16 width, height;
    CARD16 borderWidth;
    CARD16 pad1;
    CARD32 pad2;
    CARD32 pad3;
}

struct xQueryTreeReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;
    Window root, parent;
    CARD16 nChildren;
    CARD16 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
}

struct xInternAtomReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    Atom atom;
    CARD32 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
}

struct xGetAtomNameReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* of additional bytes                                          */
    CARD16 nameLength;                                  /* # of characters in name                                      */
    CARD16 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

struct xGetPropertyReply{
    BYTE type;                                          /* X_Reply                                                      */
    CARD8 format;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* of additional bytes                                          */
    Atom propertyType;
    CARD32 bytesAfter;
    CARD32 nItems;                                      /* # of 8, 16, or 32-bit entities in reply                      */
    CARD32 pad1;
    CARD32 pad2;
    CARD32 pad3;
}

struct xListPropertiesReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;
    CARD16 nProperties;
    CARD16 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

struct xGetSelectionOwnerReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    Window owner;
    CARD32 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
}

struct xGrabPointerReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE status;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    CARD32 pad1;
    CARD32 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
}

alias xGrabPointerReply xGrabKeyboardReply;

struct xQueryPointerReply{
    BYTE type;                                          /* X_Reply                                                      */
    BOOL sameScreen;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    Window root, child;
    INT16 rootX, rootY, winX, winY;
    CARD16 mask;
    CARD16 pad1;
    CARD32 pad;
}

struct xGetMotionEventsReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;
    CARD32 nEvents;
    CARD32 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
}

struct xTranslateCoordsReply{
    BYTE type;                                          /* X_Reply                                                      */
    BOOL sameScreen;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    Window child;
    INT16 dstX, dstY;
    CARD32 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
}

struct xGetInputFocusReply{
    BYTE type;                                          /* X_Reply                                                      */
    CARD8 revertTo;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    Window focus;
    CARD32 pad1;
    CARD32 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
}

struct xQueryKeymapReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 2, NOT 0; this is an extra-large reply                       */
    BYTE[32] map;
}

                                                        /* Warning: this MUST match (up to component renaming) xListFontsWithInfoReply */
version( X86_64 ){
    struct _xQueryFontReply{
        BYTE type;                                      /* X_Reply                                                      */
        BYTE pad1;
        CARD16 sequenceNumber;
        CARD32 length;                                  /* definitely > 0, even if "nCharInfos" is 0                    */
        xCharInfo minBounds;
        xCharInfo maxBounds;
        CARD16 minCharOrByte2, maxCharOrByte2;
        CARD16 defaultChar;
        CARD16 nFontProps;                              /* followed by this many xFontProp structures                   */
        CARD8 drawDirection;
        CARD8 minByte1, maxByte1;
        BOOL allCharsExist;
        INT16 fontAscent, fontDescent;
        CARD32 nCharInfos;                              /* followed by this many xCharInfo structures                   */
    }
}
else{
    struct _xQueryFontReply {
        BYTE type;                                      /* X_Reply                                                      */
        BYTE pad1;
        CARD16 sequenceNumber;
        CARD32 length;                                  /* definitely > 0, even if "nCharInfos" is 0                    */
        xCharInfo minBounds;
        CARD32 walign1;
        xCharInfo maxBounds;
        CARD32 walign2;
        CARD16 minCharOrByte2, maxCharOrByte2;
        CARD16 defaultChar;
        CARD16 nFontProps;                              /* followed by this many xFontProp structures                   */
        CARD8 drawDirection;
        CARD8 minByte1, maxByte1;
        BOOL allCharsExist;
        INT16 fontAscent, fontDescent;
        CARD32 nCharInfos;                              /* followed by this many xCharInfo structures                   */
    }
}
alias _xQueryFontReply xQueryFontReply;

struct xQueryTextExtentsReply{
    BYTE type;                                          /* X_Reply                                                      */
    CARD8 drawDirection;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    INT16 fontAscent, fontDescent;
    INT16 overallAscent, overallDescent;
    INT32 overallWidth, overallLeft, overallRight;
    CARD32 pad;
}

struct xListFontsReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;
    CARD16 nFonts;
    CARD16 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

                                                        /* Warning: this MUST match (up to component renaming) xQueryFontReply */
version( X86_64 ){
    struct xListFontsWithInfoReply{
        BYTE type;                                      /* X_Reply                                                      */
        CARD8 nameLength;                               /* 0 indicates end-of-reply-sequence                            */
        CARD16 sequenceNumber;
        CARD32 length;                                  /* definitely > 0, even if "nameLength" is 0                    */
        xCharInfo minBounds;
        xCharInfo maxBounds;
        CARD16 minCharOrByte2, maxCharOrByte2;
        CARD16 defaultChar;
        CARD16 nFontProps;                              /* followed by this many xFontProp structures                   */
        CARD8 drawDirection;
        CARD8 minByte1, maxByte1;
        BOOL allCharsExist;
        INT16 fontAscent, fontDescent;
        CARD32 nReplies;                                /* hint as to how many more replies might be coming             */
    }
}
else{
    struct xListFontsWithInfoReply{
        BYTE type;                                      /* X_Reply                                                      */
        CARD8 nameLength;                               /* 0 indicates end-of-reply-sequence                            */
        CARD16 sequenceNumber;
        CARD32 length;                                  /* definitely > 0, even if "nameLength" is 0                    */
        xCharInfo minBounds;
        CARD32 walign1;
        xCharInfo maxBounds;
        CARD32 align2;
        CARD16 minCharOrByte2, maxCharOrByte2;
        CARD16 defaultChar;
        CARD16 nFontProps;                              /* followed by this many xFontProp structures                   */
        CARD8 drawDirection;
        CARD8 minByte1, maxByte1;
        BOOL allCharsExist;
        INT16 fontAscent, fontDescent;
        CARD32 nReplies;                                /* hint as to how many more replies might be coming             */
    }
}


struct xGetFontPathReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;
    CARD16 nPaths;
    CARD16 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

struct xGetImageReply{
    BYTE type;                                          /* X_Reply                                                      */
    CARD8 depth;
    CARD16 sequenceNumber;
    CARD32 length;
    VisualID visual;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

struct xListInstalledColormapsReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;
    CARD16 nColormaps;
    CARD16 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

struct xAllocColorReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    CARD16 red, green, blue;
    CARD16 pad2;
    CARD32 pixel;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
}

struct xAllocNamedColorReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    CARD32 pixel;
    CARD16 exactRed, exactGreen, exactBlue;
    CARD16 screenRed, screenGreen, screenBlue;
    CARD32 pad2;
    CARD32 pad3;
}

struct xAllocColorCellsReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;
    CARD16 nPixels, nMasks;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

struct xAllocColorPlanesReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;
    CARD16 nPixels;
    CARD16 pad2;
    CARD32 redMask, greenMask, blueMask;
    CARD32 pad3;
    CARD32 pad4;
}

struct xQueryColorsReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;
    CARD16 nColors;
    CARD16 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

struct xLookupColorReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    CARD16 exactRed, exactGreen, exactBlue;
    CARD16 screenRed, screenGreen, screenBlue;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
}

struct xQueryBestSizeReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    CARD16 width, height;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

struct xQueryExtensionReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    BOOL  present;
    CARD8 major_opcode;
    CARD8 first_event;
    CARD8 first_error;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

struct xListExtensionsReply{
    BYTE type;                                          /* X_Reply                                                      */
    CARD8 nExtensions;
    CARD16 sequenceNumber;
    CARD32 length;
    CARD32 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}


struct xSetMappingReply{
    BYTE   type;                                        /* X_Reply                                                      */
    CARD8  success;
    CARD16 sequenceNumber;
    CARD32 length;
    CARD32 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

alias xSetMappingReply xSetPointerMappingReply;
alias xSetMappingReply xSetModifierMappingReply;

struct xGetPointerMappingReply{
    BYTE type;                                          /* X_Reply                                                      */
    CARD8 nElts;                                        /* how many elements does the map have                          */
    CARD16 sequenceNumber;
    CARD32 length;
    CARD32 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

struct xGetKeyboardMappingReply{
    BYTE type;
    CARD8 keySymsPerKeyCode;
    CARD16 sequenceNumber;
    CARD32 length;
    CARD32 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

struct xGetModifierMappingReply{
    BYTE type;
    CARD8 numKeyPerModifier;
    CARD16 sequenceNumber;
    CARD32 length;
    CARD32 pad1;
    CARD32 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
}

struct xGetKeyboardControlReply{
    BYTE type;                                          /* X_Reply                                                      */
    BOOL globalAutoRepeat;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 5                                                            */
    CARD32 ledMask;
    CARD8 keyClickPercent, bellPercent;
    CARD16 bellPitch, bellDuration;
    CARD16 pad;
    BYTE[32] map;                                       /* bit masks start here                                         */
}

struct xGetPointerControlReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    CARD16 accelNumerator, accelDenominator;
    CARD16 threshold;
    CARD16 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
}

struct xGetScreenSaverReply{
    BYTE type;                                          /* X_Reply                                                      */
    BYTE pad1;
    CARD16 sequenceNumber;
    CARD32 length;                                      /* 0                                                            */
    CARD16 timeout, interval;
    BOOL preferBlanking;
    BOOL allowExposures;
    CARD16 pad2;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
}

struct xListHostsReply{
    BYTE type;                                          /* X_Reply                                                      */
    BOOL enabled;
    CARD16 sequenceNumber;
    CARD32 length;
    CARD16 nHosts;
    CARD16 pad1;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}


/*****************************************************************
 * Xerror
 *    All errors  are 32 bytes
 *****************************************************************/

struct xError{
    BYTE type;                                          /* X_Error                                                      */
    BYTE errorCode;
    CARD16 sequenceNumber;                              /* the nth request from this client                             */
    CARD32 resourceID;
    CARD16 minorCode;
    CARD8 majorCode;
    BYTE pad1;
    CARD32 pad3;
    CARD32 pad4;
    CARD32 pad5;
    CARD32 pad6;
    CARD32 pad7;
}

/*****************************************************************
 * xEvent
 *    All events are 32 bytes
 *****************************************************************/

struct _xEvent {
    union u{
        struct u{
            BYTE type;
            BYTE detail;
            CARD16 sequenceNumber;
        }
        struct keyButtonPointer{
            CARD32 pad00;
            Time time;
            Window root, event, child;
            INT16 rootX, rootY, eventX, eventY;
            KeyButMask state;
            BOOL sameScreen;
            BYTE pad1;
        }
        struct enterLeave{
            CARD32 pad00;
            Time time;
            Window root, event, child;
            INT16 rootX, rootY, eventX, eventY;
            KeyButMask state;
            BYTE mode;                                  /* really XMode                                                 */
            BYTE flags;                                 /* sameScreen and focus booleans, packed together               */
            enum int ELFlagFocus       = 1 << 0;
            enum int ELFlagSameScreen  = 1 << 1;
        }
        struct focus{
            CARD32 pad00;
            Window window;
            BYTE mode;                                  /* really XMode                                                 */
            BYTE pad1, pad2, pad3;
        }
        struct expose{
            CARD32 pad00;
            Window window;
            CARD16 x, y, width, height;
            CARD16 count;
            CARD16 pad2;
        }
        struct graphicsExposure{
            CARD32 pad00;
            Drawable drawable;
            CARD16 x, y, width, height;
            CARD16 minorEvent;
            CARD16 count;
            BYTE majorEvent;
            BYTE pad1, pad2, pad3;
        }
        struct noExposure{
            CARD32 pad00;
            Drawable drawable;
            CARD16 minorEvent;
            BYTE majorEvent;
            BYTE bpad;
        }
        struct visibility{
            CARD32 pad00;
            Window window;
            CARD8 state;
            BYTE pad1, pad2, pad3;
        }
        struct createNotify{
            CARD32 pad00;
            Window parent, window;
            INT16 x, y;
            CARD16 width, height, borderWidth;
            BOOL c_override;
            BYTE bpad;
        }
    /*
     * The event fields in the structures for DestroyNotify, UnmapNotify,
     * MapNotify, ReparentNotify, ConfigureNotify, CirculateNotify, GravityNotify,
     * must be at the same offset because server internal code is depending upon
     * this to patch up the events before they are delivered.
     * Also note that MapRequest, ConfigureRequest and CirculateRequest have
     * the same offset for the event window.
     */
        struct destroyNotify{
            CARD32 pad00;
            Window event, window;
        }
        struct unmapNotify{
            CARD32 pad00;
            Window event, window;
            BOOL fromConfigure;
            BYTE pad1, pad2, pad3;
        }
        struct mapNotify{
            CARD32 pad00;
            Window event, window;
            BOOL c_override;
            BYTE pad1, pad2, pad3;
        }
        struct mapRequest{
            CARD32 pad00;
            Window parent, window;
        }
        struct reparent{
            CARD32 pad00;
            Window event, window, parent;
            INT16 x, y;
            BOOL c_override;
            BYTE pad1, pad2, pad3;
        }
        struct configureNotify{
            CARD32 pad00;
            Window event, window, aboveSibling;
            INT16 x, y;
            CARD16 width, height, borderWidth;
            BOOL c_override;
            BYTE bpad;
        }
        struct configureRequest{
            CARD32 pad00;
            Window parent, window, sibling;
            INT16 x, y;
            CARD16 width, height, borderWidth;
            CARD16 valueMask;
            CARD32 pad1;
        }
        struct gravity{
                CARD32 pad00;
            Window event, window;
            INT16 x, y;
            CARD32 pad1, pad2, pad3, pad4;
        }
        struct resizeRequest{
            CARD32 pad00;
            Window window;
            CARD16 width, height;
        }
        struct circulate{
    /* The event field in the circulate record is really the parent when this
       is used as a CirculateRequest instead of a CirculateNotify */
            CARD32 pad00;
            Window event, window, parent;
            BYTE place;                                 /* Top or Bottom                                                */
            BYTE pad1, pad2, pad3;
        }
        struct property{
            CARD32 pad00;
            Window window;
            Atom atom;
            Time time;
            BYTE state;                                 /* NewValue or Deleted                                          */
            BYTE pad1;
            CARD16 pad2;
        }
        struct selectionClear{
            CARD32 pad00;
            Time time;
            Window window;
            Atom atom;
        }
        struct selectionRequest{
            CARD32 pad00;
            Time time;
            Window owner, requestor;
            Atom selection, target, property;
        }
        struct selectionNotify{
            CARD32 pad00;
            Time time;
            Window requestor;
            Atom selection, target, property;
        }
        struct colormap{
            CARD32 pad00;
            Window window;
            Colormap colormap;
            BOOL c_new;
            BYTE state;                                 /* Installed or UnInstalled                                     */
            BYTE pad1, pad2;
        }
        struct mappingNotify{
            CARD32 pad00;
            CARD8 request;
            KeyCode firstKeyCode;
            CARD8 count;
            BYTE pad1;
        }
        struct clientMessage{
            CARD32 pad00;
            Window window;
            union u{
                struct l{
                    Atom type;
                    INT32 longs0;
                    INT32 longs1;
                    INT32 longs2;
                    INT32 longs3;
                    INT32 longs4;
                }
                struct s{
                    Atom type;
                    INT16 shorts0;
                    INT16 shorts1;
                    INT16 shorts2;
                    INT16 shorts3;
                    INT16 shorts4;
                    INT16 shorts5;
                    INT16 shorts6;
                    INT16 shorts7;
                    INT16 shorts8;
                    INT16 shorts9;
                }
                struct b{
                    Atom type;
                    INT8[20] bytes;
                }
            }
        }
    }
}
alias _xEvent xEvent;

/*********************************************************
 *
 * Generic event
 *
 * Those events are not part of the core protocol spec and can be used by
 * various extensions.
 * type is always GenericEvent
 * extension is the minor opcode of the extension the event belongs to.
 * evtype is the actual event type, unique __per extension__.
 *
 * GenericEvents can be longer than 32 bytes, with the length field
 * specifying the number of 4 byte blocks after the first 32 bytes.
 *
 *
 */
struct xGenericEvent{
    BYTE    type;
    CARD8   extension;
    CARD16  sequenceNumber;
    CARD32  length;
    CARD16  evtype;
    CARD16  pad2;
    CARD32  pad3;
    CARD32  pad4;
    CARD32  pad5;
    CARD32  pad6;
    CARD32  pad7;
}



/* KeymapNotify events are not included in the above union because they
   are different from all other events: they do not have a "detail"
   or "sequenceNumber", so there is room for a 248-bit key mask. */

struct xKeymapEvent{
    BYTE type;
    BYTE[31] map;
}

const size_t XEventSize = xEvent.sizeof;

/* XReply is the union of all the replies above whose "fixed part"
fits in 32 bytes.  It does NOT include GetWindowAttributesReply,
QueryFontReply, QueryKeymapReply, or GetKeyboardControlReply
ListFontsWithInfoReply */

union xReply{
    xGenericReply                   generic;
    xGetGeometryReply               geom;
    xQueryTreeReply                 tree;
    xInternAtomReply                atom;
    xGetAtomNameReply               atomName;
    xGetPropertyReply               propertyReply;
    xListPropertiesReply            listProperties;
    xGetSelectionOwnerReply         selection;
    xGrabPointerReply               grabPointer;
    xGrabKeyboardReply              grabKeyboard;
    xQueryPointerReply              pointer;
    xGetMotionEventsReply           motionEvents;
    xTranslateCoordsReply           coords;
    xGetInputFocusReply             inputFocus;
    xQueryTextExtentsReply          textExtents;
    xListFontsReply                 fonts;
    xGetFontPathReply               fontPath;
    xGetImageReply                  image;
    xListInstalledColormapsReply    colormaps;
    xAllocColorReply                allocColor;
    xAllocNamedColorReply           allocNamedColor;
    xAllocColorCellsReply           colorCells;
    xAllocColorPlanesReply          colorPlanes;
    xQueryColorsReply               colors;
    xLookupColorReply               lookupColor;
    xQueryBestSizeReply             bestSize;
    xQueryExtensionReply            extension;
    xListExtensionsReply            extensions;
    xSetModifierMappingReply        setModifierMapping;
    xGetModifierMappingReply        getModifierMapping;
    xSetPointerMappingReply         setPointerMapping;
    xGetKeyboardMappingReply        getKeyboardMapping;
    xGetPointerMappingReply         getPointerMapping;
    xGetPointerControlReply         pointerControl;
    xGetScreenSaverReply            screenSaver;
    xListHostsReply                 hosts;
    xError                          error;
    xEvent                          event;
}

/*****************************************************************
 * REQUESTS
 *****************************************************************/


                                                        /* Request structure                                            */

struct _xReq{
    CARD8 reqType;
    CARD8 data;                                         /* meaning depends on request type                              */
    CARD16 length;                                  /* length in 4 bytes quantities of whole request, including this header */
}
alias _xReq xReq;

/*****************************************************************
 *  structures that follow request.
 *****************************************************************/

/* ResourceReq is used for any request which has a resource ID
   (or Atom or Time) as its one and only argument.  */

struct xResourceReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    CARD32 id;                                          /* a Window, Drawable, Font, GContext, Pixmap, etc.             */
}

struct xCreateWindowReq{
    CARD8 reqType;
    CARD8 depth;
    CARD16 length;
    Window wid, parent;
    INT16 x, y;
    CARD16 width, height, borderWidth;
    CARD16 c_class;
    VisualID visual;
    CARD32 mask;
}

struct xChangeWindowAttributesReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Window window;
    CARD32 valueMask;
}

struct xChangeSaveSetReq{
    CARD8 reqType;
    BYTE mode;
    CARD16 length;
    Window window;
}

struct xReparentWindowReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Window window, parent;
    INT16 x, y;
}

struct xConfigureWindowReq{
    CARD8 reqType;
    CARD8 pad;
    CARD16 length;
    Window window;
    CARD16 mask;
    CARD16 pad2;
}

struct xCirculateWindowReq{
    CARD8 reqType;
    CARD8 direction;
    CARD16 length;
    Window window;
}

struct xInternAtomReq{                                  /* followed by padded string                                    */
    CARD8 reqType;
    BOOL onlyIfExists;
    CARD16 length;
    CARD16 nbytes ;                                 /* number of bytes in string                                    */
    CARD16 pad;
}

struct xChangePropertyReq{
    CARD8 reqType;
    CARD8 mode;
    CARD16 length;
    Window window;
    Atom property, type;
    CARD8 format;
    BYTE[3] pad;
    CARD32 nUnits;                                  /* length of stuff following, depends on format                 */
}

struct xDeletePropertyReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Window window;
    Atom property;
}

struct xGetPropertyReq{
    CARD8 reqType;
    BOOL c_delete;
    CARD16 length;
    Window window;
    Atom property, type;
    CARD32 longOffset;
    CARD32 longLength;
}

struct xSetSelectionOwnerReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Window window;
    Atom selection;
    Time time;
}

struct xConvertSelectionReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Window requestor;
    Atom selection, target, property;
    Time time;
}

version( X86_64 ){
    struct xSendEventReq{
        CARD8 reqType;
        BOOL propagate;
        CARD16 length;
        Window destination;
        CARD32 eventMask;
        BYTE[SIZEOF!xEvent()] eventdata;   /* the structure should have been quad-aligned                  */
    }
}
else{
    struct xSendEventReq{
        CARD8 reqType;
        BOOL propagate;
        CARD16 length;
        Window destination;
        CARD32 eventMask;
        xEvent event;
    }
}

struct xGrabPointerReq{
    CARD8 reqType;
    BOOL ownerEvents;
    CARD16 length;
    Window grabWindow;
    CARD16 eventMask;
    BYTE pointerMode, keyboardMode;
    Window confineTo;
    Cursor cursor;
    Time time;
}

struct xGrabButtonReq{
    CARD8 reqType;
    BOOL ownerEvents;
    CARD16 length;
    Window grabWindow;
    CARD16 eventMask;
    BYTE pointerMode, keyboardMode;
    Window confineTo;
    Cursor cursor;
    CARD8 button;
    BYTE pad;
    CARD16 modifiers;
}

struct xUngrabButtonReq{
    CARD8 reqType;
    CARD8 button;
    CARD16 length;
    Window grabWindow;
    CARD16 modifiers;
    CARD16 pad;
}

struct xChangeActivePointerGrabReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Cursor cursor;
    Time time;
    CARD16 eventMask;
    CARD16 pad2;
}

struct xGrabKeyboardReq{
    CARD8 reqType;
    BOOL ownerEvents;
    CARD16 length;
    Window grabWindow;
    Time time;
    BYTE pointerMode, keyboardMode;
    CARD16 pad;
}

struct xGrabKeyReq{
    CARD8 reqType;
    BOOL ownerEvents;
    CARD16 length;
    Window grabWindow;
    CARD16 modifiers;
    CARD8 key;
    BYTE pointerMode, keyboardMode;
    BYTE pad1, pad2, pad3;
}

struct xUngrabKeyReq{
    CARD8 reqType;
    CARD8 key;
    CARD16 length;
    Window grabWindow;
    CARD16 modifiers;
    CARD16 pad;
}

struct xAllowEventsReq{
    CARD8 reqType;
    CARD8 mode;
    CARD16 length;
    Time time;
}

struct xGetMotionEventsReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Window window;
    Time start, stop;
}

struct xTranslateCoordsReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Window srcWid, dstWid;
    INT16 srcX, srcY;
}

struct xWarpPointerReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Window srcWid, dstWid;
    INT16 srcX, srcY;
    CARD16 srcWidth, srcHeight;
    INT16 dstX, dstY;
}

struct xSetInputFocusReq{
    CARD8 reqType;
    CARD8 revertTo;
    CARD16 length;
    Window focus;
    Time time;
}

struct xOpenFontReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Font fid;
    CARD16 nbytes;
    BYTE pad1, pad2;                                    /* string follows on word boundary                              */
}

struct xQueryTextExtentsReq{
    CARD8 reqType;
    BOOL oddLength;
    CARD16 length;
    Font fid;
}

struct xListFontsReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    CARD16 maxNames;
    CARD16 nbytes;                                  /* followed immediately by string bytes                         */
}

alias xListFontsReq xListFontsWithInfoReq;

struct xSetFontPathReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    CARD16 nFonts;
    BYTE pad1, pad2;                                    /* LISTofSTRING8 follows on word boundary                       */
}

struct xCreatePixmapReq{
    CARD8 reqType;
    CARD8 depth;
    CARD16 length;
    Pixmap pid;
    Drawable drawable;
    CARD16 width, height;
}

struct xCreateGCReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    GContext gc;
    Drawable drawable;
    CARD32 mask;
}

struct xChangeGCReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    GContext gc;
    CARD32 mask;
}

struct xCopyGCReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    GContext srcGC, dstGC;
    CARD32 mask;
}

struct xSetDashesReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    GContext gc;
    CARD16 dashOffset;
    CARD16 nDashes;                                 /* length LISTofCARD8 of values following                       */
}

struct xSetClipRectanglesReq{
    CARD8 reqType;
    BYTE ordering;
    CARD16 length;
    GContext gc;
    INT16 xOrigin, yOrigin;
}

struct xClearAreaReq{
    CARD8 reqType;
    BOOL exposures;
    CARD16 length;
    Window window;
    INT16 x, y;
    CARD16 width, height;
}

struct xCopyAreaReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Drawable srcDrawable, dstDrawable;
    GContext gc;
    INT16 srcX, srcY, dstX, dstY;
    CARD16 width, height;
}

struct xCopyPlaneReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Drawable srcDrawable, dstDrawable;
    GContext gc;
    INT16 srcX, srcY, dstX, dstY;
    CARD16 width, height;
    CARD32 bitPlane;
}

struct xPolyPointReq{
    CARD8 reqType;
    BYTE coordMode;
    CARD16 length;
    Drawable drawable;
    GContext gc;
}

alias xPolyPointReq xPolyLineReq;                       /* same request structure                                       */

                                                        /* The following used for PolySegment, PolyRectangle, PolyArc, PolyFillRectangle, PolyFillArc */

struct xPolySegmentReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Drawable drawable;
    GContext gc;
}

alias xPolySegmentReq xPolyArcReq;
alias xPolySegmentReq xPolyRectangleReq;
alias xPolySegmentReq xPolyFillRectangleReq;
alias xPolySegmentReq xPolyFillArcReq;

struct _FillPolyReq {
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Drawable drawable;
    GContext gc;
    BYTE shape;
    BYTE coordMode;
    CARD16 pad1;
}

alias _FillPolyReq xFillPolyReq;


struct _PutImageReq {
    CARD8 reqType;
    CARD8 format;
    CARD16 length;
    Drawable drawable;
    GContext gc;
    CARD16 width, height;
    INT16 dstX, dstY;
    CARD8 leftPad;
    CARD8 depth;
    CARD16 pad;
}
alias _PutImageReq xPutImageReq;

struct xGetImageReq{
    CARD8 reqType;
    CARD8 format;
    CARD16 length;
    Drawable drawable;
    INT16 x, y;
    CARD16 width, height;
    CARD32 planeMask;
}

                                                        /* the following used by PolyText8 and PolyText16               */

struct xPolyTextReq{
    CARD8 reqType;
    CARD8 pad;
    CARD16 length;
    Drawable drawable;
    GContext gc;
    INT16 x, y;                                 /* items (xTextElt) start after struct                          */
}

alias xPolyTextReq xPolyText8Req;
alias xPolyTextReq xPolyText16Req;

struct xImageTextReq{
    CARD8 reqType;
    BYTE nChars;
    CARD16 length;
    Drawable drawable;
    GContext gc;
    INT16 x, y;
}

alias xImageTextReq xImageText8Req;
alias xImageTextReq xImageText16Req;

struct xCreateColormapReq{
    CARD8 reqType;
    BYTE alloc;
    CARD16 length;
    Colormap mid;
    Window window;
    VisualID visual;
}

struct xCopyColormapAndFreeReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Colormap mid;
    Colormap srcCmap;
}

struct xAllocColorReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Colormap cmap;
    CARD16 red, green, blue;
    CARD16 pad2;
}

struct xAllocNamedColorReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Colormap cmap;
    CARD16 nbytes;                                  /* followed by structure                                        */
    BYTE pad1, pad2;
}

struct xAllocColorCellsReq{
    CARD8 reqType;
    BOOL contiguous;
    CARD16 length;
    Colormap cmap;
    CARD16 colors, planes;
}

struct xAllocColorPlanesReq{
    CARD8 reqType;
    BOOL contiguous;
    CARD16 length;
    Colormap cmap;
    CARD16 colors, red, green, blue;
}

struct xFreeColorsReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Colormap cmap;
    CARD32 planeMask;
}

struct xStoreColorsReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Colormap cmap;
}

struct xStoreNamedColorReq{
    CARD8 reqType;
    CARD8 flags;                                        /* DoRed, DoGreen, DoBlue, as in xColorItem                     */
    CARD16 length;
    Colormap cmap;
    CARD32 pixel;
    CARD16 nbytes;                                  /* number of name string bytes following structure              */
    BYTE pad1, pad2;
}

struct xQueryColorsReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Colormap cmap;
}

struct xLookupColorReq{                                 /* followed  by string of length len                            */
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Colormap cmap;
    CARD16 nbytes;                                  /* number of string bytes following structure                   */
    BYTE pad1, pad2;
}

struct xCreateCursorReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Cursor cid;
    Pixmap source, mask;
    CARD16 foreRed, foreGreen, foreBlue;
    CARD16 backRed, backGreen, backBlue;
    CARD16 x, y;
}

struct xCreateGlyphCursorReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Cursor cid;
    Font source, mask;
    CARD16 sourceChar, maskChar;
    CARD16 foreRed, foreGreen, foreBlue;
    CARD16 backRed, backGreen, backBlue;
}

struct xRecolorCursorReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Cursor cursor;
    CARD16 foreRed, foreGreen, foreBlue;
    CARD16 backRed, backGreen, backBlue;
}

struct xQueryBestSizeReq{
    CARD8 reqType;
    CARD8 c_class;
    CARD16 length;
    Drawable drawable;
    CARD16 width, height;
}

struct xQueryExtensionReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    CARD16 nbytes;                                  /* number of string bytes following structure                   */
    BYTE pad1, pad2;
}

struct xSetModifierMappingReq{
    CARD8   reqType;
    CARD8   numKeyPerModifier;
    CARD16  length;
}

struct xSetPointerMappingReq{
    CARD8 reqType;
    CARD8 nElts;                                        /* how many elements in the map                                 */
    CARD16 length;
}

struct xGetKeyboardMappingReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    KeyCode firstKeyCode;
    CARD8 count;
    CARD16 pad1;
}

struct xChangeKeyboardMappingReq{
    CARD8 reqType;
    CARD8 keyCodes;
    CARD16 length;
    KeyCode firstKeyCode;
    CARD8 keySymsPerKeyCode;
    CARD16 pad1;
}

struct xChangeKeyboardControlReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    CARD32 mask;
}

struct xBellReq{
    CARD8 reqType;
    INT8 percent;                                       /* -100 to 100                                                  */
    CARD16 length;
}

struct xChangePointerControlReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    INT16 accelNum, accelDenum;
    INT16 threshold;
    BOOL doAccel, doThresh;
}

struct xSetScreenSaverReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    INT16 timeout, interval;
    BYTE preferBlank, allowExpose;
    CARD16 pad2;
}

struct xChangeHostsReq{
    CARD8 reqType;
    BYTE mode;
    CARD16 length;
    CARD8 hostFamily;
    BYTE pad;
    CARD16 hostLength;
}

struct xListHostsReq{
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
}

struct xChangeModeReq{
    CARD8 reqType;
    BYTE mode;
    CARD16 length;
}

alias xChangeModeReq xSetAccessControlReq;
alias xChangeModeReq xSetCloseDownModeReq;
alias xChangeModeReq xForceScreenSaverReq;

struct xRotatePropertiesReq{                            /* followed by LIST of ATOM                                     */
    CARD8 reqType;
    BYTE pad;
    CARD16 length;
    Window window;
    CARD16 nAtoms;
    INT16 nPositions;
}

                                                        /* Reply codes                                                  */

const int X_Reply    = 1;                               /* Normal reply                                                 */
const int X_Error    = 0;                               /* Error                                                        */

                                                        /* Request codes                                                */
enum {
    X_CreateWindow                   = 1,
    X_ChangeWindowAttributes         = 2,
    X_GetWindowAttributes            = 3,
    X_DestroyWindow                  = 4,
    X_DestroySubwindows              = 5,
    X_ChangeSaveSet                  = 6,
    X_ReparentWindow                 = 7,
    X_MapWindow                      = 8,
    X_MapSubwindows                  = 9,
    X_UnmapWindow                   = 10,
    X_UnmapSubwindows               = 11,
    X_ConfigureWindow               = 12,
    X_CirculateWindow               = 13,
    X_GetGeometry                   = 14,
    X_QueryTree                     = 15,
    X_InternAtom                    = 16,
    X_GetAtomName                   = 17,
    X_ChangeProperty                = 18,
    X_DeleteProperty                = 19,
    X_GetProperty                   = 20,
    X_ListProperties                = 21,
    X_SetSelectionOwner             = 22,
    X_GetSelectionOwner             = 23,
    X_ConvertSelection              = 24,
    X_SendEvent                     = 25,
    X_GrabPointer                   = 26,
    X_UngrabPointer                 = 27,
    X_GrabButton                    = 28,
    X_UngrabButton                  = 29,
    X_ChangeActivePointerGrab       = 30,
    X_GrabKeyboard                  = 31,
    X_UngrabKeyboard                = 32,
    X_GrabKey                       = 33,
    X_UngrabKey                     = 34,
    X_AllowEvents                   = 35,
    X_GrabServer                    = 36,
    X_UngrabServer                  = 37,
    X_QueryPointer                  = 38,
    X_GetMotionEvents               = 39,
    X_TranslateCoords               = 40,
    X_WarpPointer                   = 41,
    X_SetInputFocus                 = 42,
    X_GetInputFocus                 = 43,
    X_QueryKeymap                   = 44,
    X_OpenFont                      = 45,
    X_CloseFont                     = 46,
    X_QueryFont                     = 47,
    X_QueryTextExtents              = 48,
    X_ListFonts                     = 49,
    X_ListFontsWithInfo             = 50,
    X_SetFontPath                   = 51,
    X_GetFontPath                   = 52,
    X_CreatePixmap                  = 53,
    X_FreePixmap                    = 54,
    X_CreateGC                      = 55,
    X_ChangeGC                      = 56,
    X_CopyGC                        = 57,
    X_SetDashes                     = 58,
    X_SetClipRectangles             = 59,
    X_FreeGC                        = 60,
    X_ClearArea                     = 61,
    X_CopyArea                      = 62,
    X_CopyPlane                     = 63,
    X_PolyPoint                     = 64,
    X_PolyLine                      = 65,
    X_PolySegment                   = 66,
    X_PolyRectangle                 = 67,
    X_PolyArc                       = 68,
    X_FillPoly                      = 69,
    X_PolyFillRectangle             = 70,
    X_PolyFillArc                   = 71,
    X_PutImage                      = 72,
    X_GetImage                      = 73,
    X_PolyText8                     = 74,
    X_PolyText16                    = 75,
    X_ImageText8                    = 76,
    X_ImageText16                   = 77,
    X_CreateColormap                = 78,
    X_FreeColormap                  = 79,
    X_CopyColormapAndFree           = 80,
    X_InstallColormap               = 81,
    X_UninstallColormap             = 82,
    X_ListInstalledColormaps        = 83,
    X_AllocColor                    = 84,
    X_AllocNamedColor               = 85,
    X_AllocColorCells               = 86,
    X_AllocColorPlanes              = 87,
    X_FreeColors                    = 88,
    X_StoreColors                   = 89,
    X_StoreNamedColor               = 90,
    X_QueryColors                   = 91,
    X_LookupColor                   = 92,
    X_CreateCursor                  = 93,
    X_CreateGlyphCursor             = 94,
    X_FreeCursor                    = 95,
    X_RecolorCursor                 = 96,
    X_QueryBestSize                 = 97,
    X_QueryExtension                = 98,
    X_ListExtensions                = 99,
    X_ChangeKeyboardMapping         = 100,
    X_GetKeyboardMapping            = 101,
    X_ChangeKeyboardControl         = 102,
    X_GetKeyboardControl            = 103,
    X_Bell                          = 104,
    X_ChangePointerControl          = 105,
    X_GetPointerControl             = 106,
    X_SetScreenSaver                = 107,
    X_GetScreenSaver                = 108,
    X_ChangeHosts                   = 109,
    X_ListHosts                     = 110,
    X_SetAccessControl              = 111,
    X_SetCloseDownMode              = 112,
    X_KillClient                    = 113,
    X_RotateProperties              = 114,
    X_ForceScreenSaver              = 115,
    X_SetPointerMapping             = 116,
    X_GetPointerMapping             = 117,
    X_SetModifierMapping            = 118,
    X_GetModifierMapping            = 119,
    X_NoOperation                   = 127
}

                                                        /* restore these definitions back to the typedefs in X.h        */
//~ #undef Window
//~ #undef Drawable
//~ #undef Font
//~ #undef Pixmap
//~ #undef Cursor
//~ #undef Colormap
//~ #undef GContext
//~ #undef Atom
//~ #undef VisualID
//~ #undef Time
//~ #undef KeyCode
//~ #undef KeySym
