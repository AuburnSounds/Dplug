module derelict.x11.Xutil;
version(linux):
import core.stdc.config;
import derelict.x11.Xlib;
import derelict.x11.X;
import derelict.x11.Xregion;
import derelict.x11.Xresource : XrmStringToQuark;
import derelict.x11.keysym;

extern (C) nothrow @nogc:

/*
 * Bitmask returned by XParseGeometry().  Each bit tells if the corresponding
 * value (x, y, width, height) was found in the parsed string.
 */
const int NoValue     = 0x0000;
const int XValue      = 0x0001;
const int YValue      = 0x0002;
const int WidthValue  = 0x0004;
const int HeightValue = 0x0008;
const int AllValues   = 0x000F;
const int XNegative   = 0x0010;
const int YNegative   = 0x0020;

/*
 * new version containing base_width, base_height, and win_gravity fields;
 * used with WM_NORMAL_HINTS.
 */
struct XSizeHints {
    c_long flags;                                       /* marks which fields in this structure are defined             */
    int x, y;                                           /* obsolete for new window mgrs, but clients                    */
    int width, height;                                  /* should set so old wm's don't mess up                         */
    int min_width, min_height;
    int max_width, max_height;
    int width_inc, height_inc;
    struct aspect {
        int x;                                          /* numerator                                                    */
        int y;                                          /* denominator                                                  */
    }
    aspect min_aspect, max_aspect;
    int base_width, base_height;                        /* added by ICCCM version 1                                     */
    int win_gravity;                                    /* added by ICCCM version 1                                     */
}

/*
 * The next block of definitions are for window manager properties that
 * clients and applications use for communication.
 */

                                                        /* flags argument in size hints                                 */
enum {
    USPosition  = 1L << 0,                              /* user specified x, y                                          */
    USSize      = 1L << 1,                              /* user specified width, height                                 */

    PPosition   = 1L << 2,                              /* program specified position                                   */
    PSize       = 1L << 3,                              /* program specified size                                       */
    PMinSize    = 1L << 4,                              /* program specified minimum size                               */
    PMaxSize    = 1L << 5,                              /* program specified maximum size                               */
    PResizeInc  = 1L << 6,                              /* program specified resize increments                          */
    PAspect     = 1L << 7,                              /* program specified min and max aspect ratios                  */
    PBaseSize   = 1L << 8,                              /* program specified base for incrementing                      */
    PWinGravity = 1L << 9                               /* program specified window gravity                             */
}

/* obsolete */
c_long PAllHints = (PPosition|PSize|PMinSize|PMaxSize|PResizeInc|PAspect);



struct XWMHints{
    c_long  flags;                                      /* marks which fields in this structure are defined             */
    Bool    input;                                      /* does this application rely on the window manager to get keyboard input? */
    int     nitial_state;                               /* see below                                                    */
    Pixmap  icon_pixmap;                                /* pixmap to be used as icon                                    */
    Window  icon_window;                                /* window to be used as icon                                    */
    int     icon_x, icon_y;                             /* initial position of icon                                     */
    Pixmap  icon_mask;                                  /* icon mask bitmap                                             */
    XID     window_group;                               /* id of related window group                                   */
                                                        /* this structure may be extended in the future                 */
}

                                                        /* definition for flags of XWMHints                             */
enum {
    InputHint           = (1L << 0),
    StateHint           = (1L << 1),
    IconPixmapHint      = (1L << 2),
    IconWindowHint      = (1L << 3),
    IconPositionHint    = (1L << 4),
    IconMaskHint        = (1L << 5),
    WindowGroupHint     = (1L << 6),
    AllHints            = (InputHint|StateHint|IconPixmapHint|IconWindowHint|IconPositionHint|IconMaskHint|WindowGroupHint),
    XUrgencyHint        = (1L << 8)
}

                                                        /* definitions for initial window state                         */
enum {
    WithdrawnState  = 0,                                /* for windows that are not mapped                              */
    NormalState     = 1,                                /* most applications want to start this way                     */
    IconicState     = 3                                 /* application wants to start as an icon                        */
}

/*
 * Obsolete states no longer defined by ICCCM
 */
enum {
    DontCareState   = 0,                                /* don't know or care                                           */
    ZoomState       = 2,                                /* application wants to start zoomed                            */
    InactiveState   = 4                                 /* application believes it is seldom used;                      */
}
                                                        /* some wm's may put it on inactive menu                        */


/*
 * new structure for manipulating TEXT properties; used with WM_NAME,
 * WM_ICON_NAME, WM_CLIENT_MACHINE, and WM_COMMAND.
 */
struct XTextProperty{
    ubyte*  value;                                      /* same as Property routines                                    */
    Atom    encoding;                                   /* prop type                                                    */
    int     format;                                     /* prop data format: 8, 16, or 32                               */
    c_ulong nitems;                                     /* number of data items in value                                */
}

const int XNoMemory             = -1;
const int XLocaleNotSupported   = -2;
const int XConverterNotFound    = -3;

alias int XICCEncodingStyle;
enum {
    XStringStyle,                                       /* STRING                                                       */
    XCompoundTextStyle,                                 /* COMPOUND_TEXT                                                */
    XTextStyle,                                         /* text in owner's encoding (current locale)                    */
    XStdICCTextStyle,                                   /* STRING, else COMPOUND_TEXT                                   */
                                                        /* The following is an XFree86 extension, introduced in November 2000 */
    XUTF8StringStyle                                    /* UTF8_STRING                                                  */
}

struct XIconSize{
    int min_width, min_height;
    int max_width, max_height;
    int width_inc, height_inc;
}

struct XClassHint{
    char* res_name;
    char* res_class;
} ;

version( XUTIL_DEFINE_FUNCTIONS ){
    extern int      XDestroyImage( XImage* ximage );
    extern c_ulong  XGetPixel( XImage *ximage, int x, int y );
    extern int      XPutPixel( XImage* ximage, int x, int y, c_ulong pixel );
    extern XImage*  XSubImage( XImage *ximage, int x, int y, uint width, uint height );
    extern int      XAddPixel( XImage *ximage, c_long value);
}
else{
    /*
     * These macros are used to give some sugar to the image routines so that
     * naive people are more comfortable with them.
     */
    /**
     * XDestroyImage
     * The XDestroyImage() function deallocates the memory associated with the XImage structure.
     * Note that when the image is created using XCreateImage(), XGetImage(), or XSubImage(), the destroy procedure that this macro calls frees both the image structure and the data pointed to by the image structure.
     * Params:
     *  ximage   = Specifies the image.
     * See_Also:
     *  XAddPixel(), XCreateImage(), XGetPixel(), XPutPixel(), XSubImage(), http://tronche.com/gui/x/xlib/utilities/manipulating-images.html
     */
    int XDestroyImage( XImage* ximage ){
        return ximage.f.destroy_image(ximage);
    }
    /**
     * XGetPixel
     * The XGetPixel() function returns the specified pixel from the named image. The pixel value is returned in normalized format (that is, the least-significant byte of the long is the least-significant byte of the pixel). The image must contain the x and y coordinates.
     * Params:
     *  ximage  = Specifies the image.
     *  x       = Specify the x coordinate.
     *  y       = Specify the y coordinate.
     * See_Also:
     *  XAddPixel(), XCreateImage(), XGetPixel(), XPutPixel(), XSubImage(), http://tronche.com/gui/x/xlib/utilities/manipulating-images.html
     */
    c_ulong XGetPixel( XImage* ximage, int x, int y ){
        return ximage.f.get_pixel(ximage, x, y);
    }
    /**
     * XPutPixel
     * The XPutPixel() function overwrites the pixel in the named image with the specified pixel value. The input pixel value must be in normalized format (that is, the least-significant byte of the long is the least-significant byte of the pixel). The image must contain the x and y coordinates.
     * Params:
     *  ximage  = Specifies the image.
     *  x       = Specify the x coordinate.
     *  y       = Specify the y coordinate.
     *  pixel   = Specifies the new pixel value.
     * See_Also:
     *  XAddPixel(), XCreateImage(), XGetPixel(), XPutPixel(), XSubImage(), http://tronche.com/gui/x/xlib/utilities/manipulating-images.html
     */
    int XPutPixel( XImage* ximage, int x, int y, c_ulong pixel ){
        return ximage.f.put_pixel(ximage, x, y, pixel);
    }
    /**
     * XSubImage
     * The XSubImage() function creates a new image that is a subsection of an existing one. It allocates the memory necessary for the new XImage structure and returns a pointer to the new image. The data is copied from the source image, and the image must contain the rectangle defined by x, y, subimage_width, and subimage_height.
     * Params:
     *  ximage          = Specifies the image.
     *  x               = Specify the x coordinate.
     *  y               = Specify the y coordinate.
     *  subimage_width  = Specifies the width of the new subimage, in pixels.
     *  subimage_height = Specifies the height of the new subimage, in pixels.
     * See_Also:
     *  XAddPixel(), XCreateImage(), XGetPixel(), XPutPixel(), XSubImage(), http://tronche.com/gui/x/xlib/utilities/manipulating-images.html
     */
    XImage XSubImage( XImage* ximage, int x, int y, uint width, uint height ){
        return ximage.f.sub_image(ximage, x, y, width, height);
    }
    /**
     * XAddPixel
     * The XAddPixel() function adds a constant value to every pixel in an image. It is useful when you have a base pixel value from allocating color resources and need to manipulate the image to that form.
     * Params:
     *  ximage          = Specifies the image.
     *  value           = Specifies the constant value that is to be added.
     * See_Also:
     *  XAddPixel(), XCreateImage(), XGetPixel(), XPutPixel(), XSubImage(), http://tronche.com/gui/x/xlib/utilities/manipulating-images.html
     */
    int XAddPixel( XImage* ximage, c_long value ){
        return ximage.f.add_pixel(ximage, value);
    }
}

/*
 * Compose sequence status structure, used in calling XLookupString.
 */
struct XComposeStatus {
    XPointer compose_ptr;                               /* state table pointer                                          */
    int chars_matched;                                  /* match state                                                  */
}

/*
 * Keysym macros, used on Keysyms to test for classes of symbols
 */
template IsKeypadKey(KeySym keysym){
  const bool IsKeypadKey = (( keysym >= XK_KP_Space )       && ( keysym <= XK_KP_Equal));
}

template IsPrivateKeypadKey(KeySym keysym){
  const bool IsPrivateKeypadKey = (( keysym >= 0x11000000 ) && ( keysym <= 0x1100FFFF));
}

template IsCursorKey(KeySym keysym){
  const bool IsCursorKey = (( keysym >= XK_Home )           && ( keysym <  XK_Select));
}

template IsPFKey(KeySym keysym){
  const bool IsPFKey = (( keysym >= XK_KP_F1 )              && ( keysym <= XK_KP_F4));
}

template IsFunctionKey(KeySym keysym){
  const bool IsFunctionKey = (( keysym >= XK_F1 )           && (keysym <= XK_F35));
}

template IsMiscFunctionKey(KeySym keysym){
  const bool IsMiscFunctionKey = (( keysym >= XK_Select )   && ( keysym <= XK_Break));
}

static if( XK_XKB_KEYS ){
    template IsModifierKey(KeySym keysym){
        const bool IsModifierKey = (  ( (keysym >= XK_Shift_L) && (keysym <= XK_Hyper_R) )
                                       || ( (keysym >= XK_ISO_Lock) && (keysym <= XK_ISO_Last_Group_Lock) )
                                       || ( keysym == XK_Mode_switch)
                                       || ( keysym == XK_Num_Lock)
                                   );
    }
}
else{
    template IsModifierKey(keysym){
        const bool IsModifierKey = (((keysym >= XK_Shift_L) && (keysym <= XK_Hyper_R))
                                       || (keysym == XK_Mode_switch)
                                       || (keysym == XK_Num_Lock)
                                   );
    }
}
/*
 * opaque reference to Region data type
 */
alias _XRegion* Region;

/* Return values from XRectInRegion() */
enum {
    RectangleOut    = 0,
    RectangleIn     = 1,
    RectanglePart   = 2
}


/*
 * Information used by the visual utility routines to find desired visual
 * type from the many visuals a display may support.
 */

struct XVisualInfo{
    Visual*   visual;
    VisualID  visualid;
    int       screen;
    int       depth;
    int       c_class;                                  /* C++                                                          */;
    c_ulong   red_mask;
    c_ulong   green_mask;
    c_ulong   blue_mask;
    int       colormap_size;
    int       bits_per_rgb;
}

enum {
    VisualNoMask            = 0x0,
    VisualIDMask            = 0x1,
    VisualScreenMask        = 0x2,
    VisualDepthMask         = 0x4,
    VisualClassMask         = 0x8,
    VisualRedMaskMask       = 0x10,
    VisualGreenMaskMask     = 0x20,
    VisualBlueMaskMask      = 0x40,
    VisualColormapSizeMask  = 0x80,
    VisualBitsPerRGBMask    = 0x100,
    VisualAllMask           = 0x1FF
}

/*
 * This defines a window manager property that clients may use to
 * share standard color maps of type RGB_COLOR_MAP:
 */
struct XStandardColormap{
    Colormap colormap;
    c_ulong     red_max;
    c_ulong     red_mult;
    c_ulong     green_max;
    c_ulong     green_mult;
    c_ulong     blue_max;
    c_ulong     blue_mult;
    c_ulong     base_pixel;
    VisualID    visualid;                               /* added by ICCCM version 1                                     */
    XID         killid;                                 /* added by ICCCM version 1                                     */
}

const XID ReleaseByFreeingColormap = 1L;                /* for killid field above                                       */


/*
 * return codes for XReadBitmapFile and XWriteBitmapFile
 */
enum {
    BitmapSuccess       = 0,
    BitmapOpenFailed    = 1,
    BitmapFileInvalid   = 2,
    BitmapNoMemory      = 3
}

/*****************************************************************
 *
 * Context Management
 *
 ****************************************************************/


                                                        /* Associative lookup table return codes                        */
enum {
    XCSUCCESS = 0,                                      /* No error.                                                    */
    XCNOMEM   = 1,                                      /* Out of memory                                                */
    XCNOENT   = 2,                                      /* No entry in table                                            */
}

alias int XContext;

template XUniqueContext(){
    const XContext XUniqueContext = XrmUniqueQuark();
}

XContext XStringToContext(char* statement){
    return XrmStringToQuark(statement);
}

                                                        /* The following declarations are alphabetized.                 */

extern XClassHint* XAllocClassHint ( );

extern XIconSize* XAllocIconSize ( );

extern XSizeHints* XAllocSizeHints ( );

extern XStandardColormap* XAllocStandardColormap ( );

extern XWMHints* XAllocWMHints ( );

extern int XClipBox(
    Region                                              /* r                                                            */,
    XRectangle*                                         /* rect_return                                                  */
);

extern Region XCreateRegion( );

extern char* XDefaultString ( );

extern int XDeleteContext(
    Display*                                            /* display                                                      */,
    XID                                                 /* rid                                                          */,
    XContext                                            /* context                                                      */
);

extern int XDestroyRegion(
    Region                                              /* r                                                            */
);

extern int XEmptyRegion(
    Region                                              /* r                                                            */
);

extern int XEqualRegion(
    Region                                              /* r1                                                           */,
    Region                                              /* r2                                                           */
);

extern int XFindContext(
    Display*                                            /* display                                                      */,
    XID                                                 /* rid                                                          */,
    XContext                                            /* context                                                      */,
    XPointer*                                           /* data_return                                                  */
);

extern Status XGetClassHint(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XClassHint*                                         /* class_hints_return                                           */
);

extern Status XGetIconSizes(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XIconSize**                                         /* size_list_return                                             */,
    int*                                                /* count_return                                                 */
);

extern Status XGetNormalHints(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XSizeHints*                                         /* hints_return                                                 */
);

extern Status XGetRGBColormaps(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XStandardColormap**                                 /* stdcmap_return                                               */,
    int*                                                /* count_return                                                 */,
    Atom                                                /* property                                                     */
);

extern Status XGetSizeHints(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XSizeHints*                                         /* hints_return                                                 */,
    Atom                                                /* property                                                     */
);

extern Status XGetStandardColormap(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XStandardColormap*                                  /* colormap_return                                              */,
    Atom                                                /* property                                                     */
);

extern Status XGetTextProperty(
    Display*                                            /* display                                                      */,
    Window                                              /* window                                                       */,
    XTextProperty*                                      /* text_prop_return                                             */,
    Atom                                                /* property                                                     */
);

extern XVisualInfo* XGetVisualInfo(
    Display*                                            /* display                                                      */,
    long                                                /* vinfo_mask                                                   */,
    XVisualInfo*                                        /* vinfo_template                                               */,
    int*                                                /* nitems_return                                                */
);

extern Status XGetWMClientMachine(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XTextProperty*                                      /* text_prop_return                                             */
);

extern XWMHints *XGetWMHints(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */
);

extern Status XGetWMIconName(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XTextProperty*                                      /* text_prop_return                                             */
);

extern Status XGetWMName(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XTextProperty*                                      /* text_prop_return                                             */
);

extern Status XGetWMNormalHints(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XSizeHints*                                         /* hints_return                                                 */,
    long*                                               /* supplied_return                                              */
);

extern Status XGetWMSizeHints(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XSizeHints*                                         /* hints_return                                                 */,
    long*                                               /* supplied_return                                              */,
    Atom                                                /* property                                                     */
);

extern Status XGetZoomHints(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XSizeHints*                                         /* zhints_return                                                */
);

extern int XIntersectRegion(
    Region                                              /* sra                                                          */,
    Region                                              /* srb                                                          */,
    Region                                              /* dr_return                                                    */
);

extern void XConvertCase(
    KeySym                                              /* sym                                                          */,
    KeySym*                                             /* lower                                                        */,
    KeySym*                                             /* upper                                                        */
);

extern int XLookupString(
    XKeyEvent*                                          /* event_struct                                                 */,
    char*                                               /* buffer_return                                                */,
    int                                                 /* bytes_buffer                                                 */,
    KeySym*                                             /* keysym_return                                                */,
    XComposeStatus*                                     /* status_in_out                                                */
);

extern Status XMatchVisualInfo(
    Display*                                            /* display                                                      */,
    int                                                 /* screen                                                       */,
    int                                                 /* depth                                                        */,
    int                                                 /* class                                                        */,
    XVisualInfo*                                        /* vinfo_return                                                 */
);

extern int XOffsetRegion(
    Region                                              /* r                                                            */,
    int                                                 /* dx                                                           */,
    int                                                 /* dy                                                           */
);

extern Bool XPointInRegion(
    Region                                              /* r                                                            */,
    int                                                 /* x                                                            */,
    int                                                 /* y                                                            */
);

extern Region XPolygonRegion(
    XPoint*                                 /* points                                                       */,
    int                                                 /* n                                                            */,
    int                                                 /* fill_rule                                                    */
);

extern int XRectInRegion(
    Region                                              /* r                                                            */,
    int                                                 /* x                                                            */,
    int                                                 /* y                                                            */,
    uint                                                /* width                                                        */,
    uint                                                /* height                                                       */
);

extern int XSaveContext(
    Display*                                            /* display                                                      */,
    XID                                                 /* rid                                                          */,
    XContext                                            /* context                                                      */,
    char*                                               /* data                                                         */
);

extern int XSetClassHint(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XClassHint*                                         /* class_hints                                                  */
);

extern int XSetIconSizes(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XIconSize*                                          /* size_list                                                    */,
    int                                                 /* count                                                        */
);

extern int XSetNormalHints(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XSizeHints*                                         /* hints                                                        */
);

extern void XSetRGBColormaps(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XStandardColormap*                                  /* stdcmaps                                                     */,
    int                                                 /* count                                                        */,
    Atom                                                /* property                                                     */
);

extern int XSetSizeHints(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XSizeHints*                                         /* hints                                                        */,
    Atom                                                /* property                                                     */
);

extern int XSetStandardProperties(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    char*                                               /* window_name                                                  */,
    char*                                               /* icon_name                                                    */,
    Pixmap                                              /* icon_pixmap                                                  */,
    char**                                              /* argv                                                         */,
    int                                                 /* argc                                                         */,
    XSizeHints*                                         /* hints                                                        */
);

extern void XSetTextProperty(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XTextProperty*                                      /* text_prop                                                    */,
    Atom                                                /* property                                                     */
);

extern void XSetWMClientMachine(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XTextProperty*                                      /* text_prop                                                    */
);

extern int XSetWMHints(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XWMHints*                                           /* wm_hints                                                     */
);

extern void XSetWMIconName(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XTextProperty*                                      /* text_prop                                                    */
);

extern void XSetWMName(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XTextProperty*                                      /* text_prop                                                    */
);

extern void XSetWMNormalHints(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XSizeHints*                                         /* hints                                                        */
);

extern void XSetWMProperties(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XTextProperty*                                      /* window_name                                                  */,
    XTextProperty*                                      /* icon_name                                                    */,
    char**                                              /* argv                                                         */,
    int                                                 /* argc                                                         */,
    XSizeHints*                                         /* normal_hints                                                 */,
    XWMHints*                                           /* wm_hints                                                     */,
    XClassHint*                                         /* class_hints                                                  */
);

extern void XmbSetWMProperties(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    char*                                               /* window_name                                                  */,
    char*                                               /* icon_name                                                    */,
    char**                                              /* argv                                                         */,
    int                                                 /* argc                                                         */,
    XSizeHints*                                         /* normal_hints                                                 */,
    XWMHints*                                           /* wm_hints                                                     */,
    XClassHint*                                         /* class_hints                                                  */
);

extern void Xutf8SetWMProperties(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    char*                                               /* window_name                                                  */,
    char*                                               /* icon_name                                                    */,
    char**                                              /* argv                                                         */,
    int                                                 /* argc                                                         */,
    XSizeHints*                                         /* normal_hints                                                 */,
    XWMHints*                                           /* wm_hints                                                     */,
    XClassHint*                                         /* class_hints                                                  */
);

extern void XSetWMSizeHints(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XSizeHints*                                         /* hints                                                        */,
    Atom                                                /* property                                                     */
);

extern int XSetRegion(
    Display*                                            /* display                                                      */,
    GC                                                  /* gc                                                           */,
    Region                                              /* r                                                            */
);

extern void XSetStandardColormap(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XStandardColormap*                                  /* colormap                                                     */,
    Atom                                                /* property                                                     */
);

extern int XSetZoomHints(
    Display*                                            /* display                                                      */,
    Window                                              /* w                                                            */,
    XSizeHints*                                         /* zhints                                                       */
);

extern int XShrinkRegion(
    Region                                              /* r                                                            */,
    int                                                 /* dx                                                           */,
    int                                                 /* dy                                                           */
);

extern Status XStringListToTextProperty(
    char**                                              /* list                                                         */,
    int                                                 /* count                                                        */,
    XTextProperty*                                      /* text_prop_return                                             */
);

extern int XSubtractRegion(
    Region                                              /* sra                                                          */,
    Region                                              /* srb                                                          */,
    Region                                              /* dr_return                                                    */
);

extern int XmbTextListToTextProperty(
    Display*        display,
    char**      list,
    int         count,
    XICCEncodingStyle   style,
    XTextProperty*  text_prop_return
);

extern int XwcTextListToTextProperty(
    Display*            display,
    wchar**             list,
    int                 count,
    XICCEncodingStyle   style,
    XTextProperty*      text_prop_return
);

extern int Xutf8TextListToTextProperty(
    Display*            display,
    char**              list,
    int                 count,
    XICCEncodingStyle   style,
    XTextProperty*      text_prop_return
);

extern void XwcFreeStringList(
    wchar**             list
);

extern Status XTextPropertyToStringList(
    XTextProperty*                                      /* text_prop                                                    */,
    char***                                             /* list_return                                                  */,
    int*                                                /* count_return                                                 */
);

extern int XmbTextPropertyToTextList(
    Display*                display,
    const XTextProperty*    text_prop,
    char***                 list_return,
    int*                    count_return
);

extern int XwcTextPropertyToTextList(
    Display*                display,
    const XTextProperty*    text_prop,
    wchar***                list_return,
    int*                    count_return
);

extern int Xutf8TextPropertyToTextList(
    Display*                display,
    const XTextProperty*    text_prop,
    char***                 list_return,
    int*                    count_return
);

extern int XUnionRectWithRegion(
    XRectangle*                                         /* rectangle                                                    */,
    Region                                              /* src_region                                                   */,
    Region                                              /* dest_region_return                                           */
);

extern int XUnionRegion(
    Region                                              /* sra                                                          */,
    Region                                              /* srb                                                          */,
    Region                                              /* dr_return                                                    */
);

extern int XWMGeometry(
    Display*                                            /* display                                                      */,
    int                                                 /* screen_number                                                */,
    char*                                               /* user_geometry                                                */,
    char*                                               /* default_geometry                                             */,
    uint                                                /* border_width                                                 */,
    XSizeHints*                                         /* hints                                                        */,
    int*                                                /* x_return                                                     */,
    int*                                                /* y_return                                                     */,
    int*                                                /* width_return                                                 */,
    int*                                                /* height_return                                                */,
    int*                                                /* gravity_return                                               */
);

extern int XXorRegion(
    Region                                              /* sra                                                          */,
    Region                                              /* srb                                                          */,
    Region                                              /* dr_return                                                    */
);
