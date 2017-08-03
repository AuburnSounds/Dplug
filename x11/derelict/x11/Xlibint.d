module derelict.x11.Xlibint;

version(linux):
/*
 *  Xlibint.h - Header definition and support file for the internal
 *  support routines used by the C subroutine interface
 *  library (Xlib) to the X Window System.
 *
 *  Warning, there be dragons here....
 */
import std.stdio;
import core.stdc.string : memcpy;
import core.stdc.config;
import core.stdc.stdio : fopen;
import core.stdc.stdlib : free, malloc, calloc, realloc;

import derelict.x11.X    : XID, GContext, KeySym, Font, VisualID, Window;
import derelict.x11.Xmd  : CARD32;
import derelict.x11.Xlib : _XrmHashBucketRec, Bool,Screen, ScreenFormat, Status, Visual, XChar2b, XCharStruct,
                    XConnectionWatchProc, XEvent, XErrorEvent, XExtCodes, XExtData, XFontStruct, XGCValues,
                    XGenericEventCookie, XModifierKeymap, XPointer, XRectangle, XSetWindowAttributes, XWindowAttributes;
import derelict.x11.Xtos;
import derelict.x11.Xproto;                                      /* to declare xEvent                                            */
import derelict.x11.XlibConf;                                    /* for configured options like XTHREADS                         */

extern (C) nothrow @nogc:

version( WIN32 )
    alias _XFlush _XFlushIt;


/*
 * If your BytesReadable correctly detects broken connections, then
 * you should NOT define XCONN_CHECK_FREQ.
 */
const uint XCONN_CHECK_FREQ = 256;

struct _XGC{
    XExtData*           ext_data;                       /* hook for extension to hang data                              */
    GContext            gid;                            /* protocol ID for graphics context                             */
    Bool                rects;                          /* boolean: TRUE if clipmask is list of rectangles              */
    Bool                dashes;                         /* boolean: TRUE if dash-list is really a list                  */
    c_ulong             dirty;                          /* cache dirty bits                                             */
    XGCValues           values;                         /* shadow structure of values                                   */
}
alias _XGC* GC;

struct _XLockInfo{}
struct _XDisplayAtoms{}
struct _XContextDB{}
struct _XIMFilter{}
struct _XkbInfoRec{}
struct _XtransConnInfo{}
struct _X11XCBPrivate{}
//~ struct _XLockPtrs{} -- define in version XTHREAD
struct _XKeytrans{}

struct _XDisplay{
    XExtData*           ext_data;                       /* hook for extension to hang data                              */
    _XFreeFuncs*        free_funcs;                     /* internal free functions                                      */
    int                 fd;                             /* Network socket.                                              */
    int                 conn_checker;                   /* ugly thing used by _XEventsQueued                            */
    int                 proto_major_version;            /* maj. version of server's X protocol                          */
    int                 proto_minor_version;            /* minor version of server's X protocol                         */
    char*               c_vendor;                       /* vendor of the server hardware                                */
    XID                 resource_base;                  /* resource ID base                                             */
    XID                 resource_mask;                  /* resource ID mask bits                                        */
    XID                 resource_id;                    /* allocator current ID                                         */
    int                 resource_shift;                 /* allocator shift to correct bits                              */
    extern (C) nothrow XID function( _XDisplay* )resource_alloc;/* allocator function                                           */
    int                 byte_order;                     /* screen byte order, LSBFirst, MSBFirst                        */
    int                 bitmap_unit;                    /* padding and data requirements                                */
    int                 bitmap_pad;                     /* padding requirements on bitmaps                              */
    int                 bitmap_bit_order;               /* LeastSignificant or MostSignificant                          */
    int                 nformats;                       /* number of pixmap formats in list                             */
    ScreenFormat*       pixmap_format;                  /* pixmap format list                                           */
    int                 vnumber;                        /* Xlib's X protocol version number.                            */
    int                 release;                        /* release of the server                                        */
    _XSQEvent*          head, tail;                     /* Input event queue.                                           */
    int                 qlen;                           /* Length of input event queue                                  */
    c_ulong             last_request_read;              /* seq number of last event read                                */
    c_ulong             request;                        /* sequence number of last request.                             */
    char*               last_req;                       /* beginning of last request, or dummy                          */
    char*               buffer;                         /* Output buffer starting address.                              */
    char*               bufptr;                         /* Output buffer index pointer.                                 */
    char*               bufmax;                         /* Output buffer maximum+1 address.                             */
    uint                max_request_size;               /* maximum number 32 bit words in request                       */
    _XrmHashBucketRec*  db;
    extern (C) nothrow int function( _XDisplay* ) synchandler;/* Synchronization handler                                      */
    char*               display_name;                   /* "host:display" string used on this connect                   */
    int                 default_screen;                 /* default screen for operations                                */
    int                 nscreens;                       /* number of screens on this server                             */
    Screen*             screens;                        /* pointer to list of screens                                   */
    c_ulong             motion_buffer;                  /* size of motion buffer                                        */
    c_ulong             flags;                          /* internal connection flags                                    */
    int                 min_keycode;                    /* minimum defined keycode                                      */
    int                 max_keycode;                    /* maximum defined keycode                                      */
    KeySym*             keysyms;                        /* This server's keysyms                                        */
    XModifierKeymap*    modifiermap;                    /* This server's modifier keymap                                */
    int                 keysyms_per_keycode;            /* number of rows                                               */
    char*               xdefaults;                      /* contents of defaults from server                             */
    char*               scratch_buffer;                 /* place to hang scratch buffer                                 */
    c_ulong             scratch_length;                 /* length of scratch buffer                                     */
    int                 ext_number;                     /* extension number on this display                             */
    _XExten*            ext_procs;                      /* extensions initialized on this display                       */
    /*
     * the following can be fixed size, as the protocol defines how
     * much address space is available.
     * While this could be done using the extension vector, there
     * may be MANY events processed, so a search through the extension
     * list to find the right procedure for each event might be
     * expensive if many extensions are being used.
     */
    extern (C) nothrow @nogc Bool function(                   /* vector for wire to event                                     */
                            Display*                    /* dpy                                                          */,
                            XEvent*                     /* re                                                           */,
                            xEvent*                     /* event                                                        */
    )[128] event_vec;
    extern (C) nothrow @nogc Status function(                 /* vector for event to wire                                     */
                            Display*                    /* dpy                                                          */,
                            XEvent*                     /* re                                                           */,
                            xEvent*                     /* event                                                        */
    )[128] wire_vec;
    KeySym                  lock_meaning;               /* for XLookupString                                            */
    _XLockInfo*             lock;                       /* multi-thread state, display lock                             */
    _XInternalAsync*        async_handlers;             /* for internal async                                           */
    c_ulong                 bigreq_size;                /* max size of big requests                                     */
    _XLockPtrs*             lock_fns;                   /* pointers to threads functions                                */
    extern (C) nothrow @nogc void function(                   /* XID list allocator function                                  */
                            Display*                    /* dpy                                                          */,
                            XID*                        /* ids                                                          */,
                            int                         /* count                                                        */
    ) idlist_alloc;
                                                        /* things above this line should not move, for binary compatibility */
    _XKeytrans*             key_bindings;               /* for XLookupString                                            */
    Font                    cursor_font;                /* for XCreateFontCursor                                        */
    _XDisplayAtoms*         atoms;                      /* for XInternAtom                                              */
    uint                    mode_switch;                /* keyboard group modifiers                                     */
    uint                    num_lock;                   /* keyboard numlock modifiers                                   */
    _XContextDB*            context_db;                 /* context database                                             */
    extern (C) nothrow @nogc Bool function(                   /* vector for wire to error                                     */
                            Display*                    /* display                                                      */,
                            XErrorEvent*                /* he                                                           */,
                            xError*                     /* we                                                           */
    ) *error_vec;
    /*
     * Xcms information
     */
    struct cms{
        XPointer            defaultCCCs;                /* pointer to an array of default XcmsCCC                       */
        XPointer            clientCmaps;                /* pointer to linked list of XcmsCmapRec                        */
        XPointer            perVisualIntensityMaps;
                                                        /* linked list of XcmsIntensityMap                              */
    };
    _XIMFilter*             im_filters;
    _XSQEvent*              qfree;                      /* unallocated event queue elements                             */
    c_ulong                 next_event_serial_num;      /* inserted into next queue elt                                 */
    _XExten*                flushes;                    /* Flush hooks                                                  */
    _XConnectionInfo*       im_fd_info;                 /* _XRegisterInternalConnection                                 */
    int                     im_fd_length;               /* number of im_fd_info                                         */
    _XConnWatchInfo*        conn_watchers;              /* XAddConnectionWatch                                          */
    int                     watcher_count;              /* number of conn_watchers                                      */
    XPointer                filedes;                    /* struct pollfd cache for _XWaitForReadable                    */
    extern (C) nothrow @nogc int function(                    /* user synchandler when Xlib usurps                            */
                            Display *                   /* dpy                                                          */
    ) savedsynchandler;
    XID                     resource_max;               /* allocator max ID                                             */
    int                     xcmisc_opcode;              /* major opcode for XC-MISC                                     */
    _XkbInfoRec*            xkb_info;                   /* XKB info                                                     */
    _XtransConnInfo*        trans_conn;                 /* transport connection object                                  */
    _X11XCBPrivate*         xcb;                        /* XCB glue private data                                        */

                                                        /* Generic event cookie handling                                */
    uint                    next_cookie;                /* next event cookie                                            */
                                                        /* vector for wire to generic event, index is (extension - 128) */
    extern (C) nothrow @nogc Bool function(
                            Display*                    /* dpy                                                          */,
                            XGenericEventCookie*        /* Xlib event                                                   */,
                            xEvent*                     /* wire event                                                   */
    )[128] generic_event_vec;
                                                        /* vector for event copy, index is (extension - 128)            */
    extern (C) nothrow @nogc Bool function(
                            Display*                    /* dpy                                                          */,
                            XGenericEventCookie*        /* in                                                           */,
                            XGenericEventCookie*        /* out                                                          */
    )[128] generic_event_copy_vec;
    void*                   cookiejar;                  /* cookie events returned but not claimed                       */
};
alias _XDisplay Display;

void XAllocIDs( Display* dpy, XID* ids, int n){ dpy.idlist_alloc(dpy,ids,n); }

/*
 * define the following if you want the Data macro to be a procedure instead.
 */
enum bool DataRoutineIsProcedure = false;

/*
 * _QEvent datatype for use in input queueing.
 */
struct _XSQEvent{
    _XSQEvent*  next;
    XEvent      event;
    c_ulong     qserial_num;                            /* so multi-threaded code can find new ones                     */
}
alias _XSQEvent _XQEvent;
version( XTHREADS ){
    /* Author: Stephen Gildea, MIT X Consortium
     *
     * declarations for C Threads locking
     */
    struct _LockInfoRec{}
    alias _LockInfoRec* LockInfoPtr;

    version( XTHREADS_WARN ){
        struct _XLockPtrs {                             /* interfaces for locking.c                                     */
                                                        /* used by all, including extensions; do not move               */
            extern (C) nothrow void function(
                Display*    dpy,
                char*       file,
                int         line
            ) lock_display;
            extern (C) nothrow void function(
                Display*    dpy,
                char*       file,
                int         line
            ) unlock_display;
        }
    }
    else version( XTHREADS_FILE_LINE ){
        struct _XLockPtrs {                             /* interfaces for locking.c                                     */
                                                        /* used by all, including extensions; do not move               */
            extern (C) nothrow void function(
                Display*    dpy,
                char*       file,
                int         line
            ) lock_display;
            extern (C) nothrow void function(
                Display*    dpy,
                char*       file,
                int         line
            ) unlock_display;
        }
    }
    else{
        struct _XLockPtrs {                             /* interfaces for locking.c                                     */
                                                        /* used by all, including extensions; do not move               */
            extern (C) nothrow void function( Display* dpy ) lock_display;
            extern (C) nothrow void function( Display* dpy ) unlock_display;
        }
    }

    //~ template _XCreateMutex_fn{  const _XCreateMutex_fn  _XCreateMutex_fn  = _XCreateMutex_fn_p; }
    //~ template _XFreeMutex_fn{    const _XFreeMutex_fn    _XFreeMutex_fn    = _XFreeMutex_fn_p;   }
    //~ template _XLockMutex_fn{    const _XFreeMutex_fn    _XFreeMutex_fn    = _XLockMutex_fn_p;   }
    //~ template _XUnlockMutex_fn{  const _XUnlockMutex_fn  _XUnlockMutex_fn  = _XUnlockMutex_fn_p; }
    //~ template _Xglobal_lock{     const _Xglobal_lock     _Xglobal_lock     = Xglobal_lock_p;     }

                                                        /* in XlibInt.c                                                 */
    extern void function(
        LockInfoPtr                                     /* lock                                                         */
    ) _XCreateMutex_fn;
    extern void function(
        LockInfoPtr                                     /* lock                                                         */
    ) _XFreeMutex_fn;
    version( XTHREADS_WARN ){
        extern void function(
            LockInfoPtr                                 /* lock                                                         */
            , char*                                     /* file                                                         */
            , int                                       /* line                                                         */
        ) _XLockMutex_fn;
    }
    else version( XTHREADS_FILE_LINE ){
        extern void function(
            LockInfoPtr                                 /* lock                                                         */
            , char*                                     /* file                                                         */
            , int                                       /* line                                                         */
        ) _XLockMutex_fn;
    }
    else{
        extern void function(
            LockInfoPtr                                 /* lock                                                         */
            , char*                                     /* file                                                         */
            , int                                       /* line                                                         */
        ) _XLockMutex_fn;
    }
    version( XTHREADS_WARN ){
        extern void function(
            LockInfoPtr                                 /* lock                                                         */
            , char*                                     /* file                                                         */
            , int                                       /* line                                                         */
        ) _XUnlockMutex_fn;
    }
    else version( XTHREADS_FILE_LINE ){
        extern void function(
            LockInfoPtr                                 /* lock                                                         */
            , char*                                     /* file                                                         */
            , int                                       /* line                                                         */
        ) _XUnlockMutex_fn;
    }
    else{
        extern void function(
            LockInfoPtr                                 /* lock                                                         */
        ) _XUnlockMutex_fn;
    }

    extern LockInfoPtr _Xglobal_lock;

    version(XTHREADS_WARN){
        void LockDisplay(   Display*    d    ){ if (d.lock_fns)        d.lock_fns.lock_display(d,__FILE__,__LINE__);   }
        void UnlockDisplay( Display*    d    ){ if (d.lock_fns)        d.lock_fns.unlock_display(d,__FILE__,__LINE__); }
        void _XLockMutex(   LockInfoPtr lock ){ if (_XLockMutex_fn)    _XLockMutex_fn(lock,__FILE__,__LINE__);         }
        void _XUnlockMutex( LockInfoPtr lock ){ if (_XUnlockMutex_fn)  _XUnlockMutex_fn(lock,__FILE__,__LINE__);       }
    }
    else{
                                                            /* used everywhere, so must be fast if not using threads        */
        void LockDisplay(   Display*    d   ){ if (d.lock_fns) d.lock_fns.lock_display(d);      }
        void UnlockDisplay( Display*    d   ){ if (d.lock_fns) d.lock_fns.unlock_display(d);    }
        void _XLockMutex(   LockInfoPtr lock){ if (_XLockMutex_fn) _XLockMutex_fn(lock);        }
        void _XUnlockMutex( LockInfoPtr lock){ if (_XUnlockMutex_fn) _XUnlockMutex_fn(lock);    }
    }
    void _XCreateMutex( LockInfoPtr lock ){ if (_XCreateMutex_fn) (*_XCreateMutex_fn)(lock);}
    void _XFreeMutex( LockInfoPtr lock ){   if (_XFreeMutex_fn) (*_XFreeMutex_fn)(lock);}
}
else{                                                 /* !XTHREADS                                                     */
    extern LockInfoPtr _Xglobal_lock; // warn put here for skip build error
    struct _XLockPtrs{}
    struct _LockInfoRec{}
    alias _LockInfoRec* LockInfoPtr;
    void LockDisplay(   Display*    dis){}
    void _XLockMutex(   LockInfoPtr lock){}
    void _XUnlockMutex( LockInfoPtr lock){}
    void UnlockDisplay( Display*    dis){}
    void _XCreateMutex( LockInfoPtr lock){}
    void _XFreeMutex(   LockInfoPtr lock){}
}

void Xfree(void* ptr){ free(ptr); }

/*
 * Note that some machines do not return a valid pointer for malloc(0), in
 * which case we provide an alternate under the control of the
 * define MALLOC_0_RETURNS_NULL.  This is necessary because some
 * Xlib code expects malloc(0) to return a valid pointer to storage.
 */
version(MALLOC_0_RETURNS_NULL){
    void* Xmalloc( size_t size )            { return malloc( size == 0 ? 1 : size );                        }
    void* Xrealloc( void* ptr, size_t size) { const void* Xrealloc = realloc(ptr, (size == 0 ? 1 : size));  }
    void* Xcalloc( int nelem, size_t elsize){ const void* calloc = ((nelem == 0 ? 1 : nelem), elsize);      }
}
else{
    void* Xmalloc( size_t size)             { return malloc(size);          }
    void* Xrealloc( void* ptr, size_t size) { return realloc(ptr, size);    }
    void* Xcalloc( int nelem, size_t elsize){ return calloc(nelem, elsize); }
}

const int       LOCKED          = 1;
const int       UNLOCKED        = 0;

const int       BUFSIZE         = 2048;                 /* X output buffer size.                                        */
const int       PTSPERBATCH     = 1024;                 /* point batching                                               */
const int       WLNSPERBATCH    = 50;                   /* wide line batching                                           */
const int       ZLNSPERBATCH    = 1024;                 /* thin line batching                                           */
const int       WRCTSPERBATCH   = 10;                   /* wide line rectangle batching                                 */
const int       ZRCTSPERBATCH   = 256;                  /* thin line rectangle batching                                 */
const int       FRCTSPERBATCH   = 256;                  /* filled rectangle batching                                    */
const int       FARCSPERBATCH   = 256;                  /* filled arc batching                                          */
const string    CURSORFONT      = "cursor";             /* standard cursor fonts                                        */


/*
 * Display flags
 */
enum {
    XlibDisplayIOError      = 1L << 0,
    XlibDisplayClosing      = 1L << 1,
    XlibDisplayNoXkb        = 1L << 2,
    XlibDisplayPrivSync     = 1L << 3,
    XlibDisplayProcConni    = 1L << 4,                  /* in _XProcessInternalConnection                               */
    XlibDisplayReadEvents   = 1L << 5,                  /* in _XReadEvents                                              */
    XlibDisplayReply        = 1L << 5,                  /* in _XReply                                                   */
    XlibDisplayWriting      = 1L << 6,                  /* in _XFlushInt, _XSend                                        */
    XlibDisplayDfltRMDB     = 1L << 7                   /* mark if RM db from XGetDefault                               */
}

/*
 * X Protocol packetizing macros.
 */

/*   Need to start requests on 64 bit word boundaries
 *   on a CRAY computer so add a NoOp (127) if needed.
 *   A character pointer on a CRAY computer will be non-zero
 *   after shifting right 61 bits of it is not pointing to
 *   a word boundary.
 */
//~ version( X86_64 ){
    //~ enum WORD64ALIGN = true;
    //~ if ( cast(c_long) dpy.bufptr >> 61){
        //~ dpy.last_req = dpy.bufptr;
        //~ dpy.bufptr   = X_NoOperation;
        //~ dpy.bufptr+1 =  0;
        //~ dpy.bufptr+2 =  0;
        //~ dpy.bufptr+3 =  1;
        //~ dpy.request++;
        //~ dpy.bufptr  += 4;
    //~ }
//~ }
//~ else                                                     /* else does not require alignment on 64-bit boundaries        */
    //~ enum WORD64ALIGN = true;
//~ }                                                       /* WORD64                                                       */


/*
 * GetReq - Get the next available X request packet in the buffer and
 * return it.
 *
 * "name" is the name of the request, e.g. CreatePixmap, OpenFont, etc.
 * "req" is the name of the request pointer.
 *
 */

//~ #if !defined(UNIXCPP) || defined(ANSICPP)
//~ #define GetReq(name, req)
        //~ WORD64ALIGN\
    //~ if ((dpy.bufptr + SIZEOF(x##name##Req)) > dpy.bufmax)\
        //~ _XFlush(dpy);\
    //~ req = (x##name##Req *)(dpy.last_req = dpy.bufptr);\
    //~ req.reqType = X_##name;\
    //~ req.length = (SIZEOF(x##name##Req))>>2;\
    //~ dpy.bufptr += SIZEOF(x##name##Req);\
    //~ dpy.request++
//~
//~ #else                                                   /* non-ANSI C uses empty comment instead of "##" for token concatenation */
//~ #define GetReq(name, req)
        //~ WORD64ALIGN\
    //~ if ((dpy.bufptr + SIZEOF(x                          /*                                                              */name/*Req)) > dpy.bufmax)\
        //~ _XFlush(dpy);\
    //~ req = (x                                            /*                                                              */name/*Req *)(dpy.last_req = dpy.bufptr);\
    //~ req.reqType = X_                                    /*                                                              */name;\
    //~ req.length = (SIZEOF(x                              /*                                                              */name/*Req))>>2;\
    //~ dpy.bufptr += SIZEOF(x                              /*                                                              */name/*Req);\
    //~ dpy.request++
//~ #endif

/* GetReqExtra is the same as GetReq, but allocates "n" additional
   bytes after the request. "n" must be a multiple of 4!  */

//~ #if !defined(UNIXCPP) || defined(ANSICPP)
//~ #define GetReqExtra(name, n, req)
        //~ WORD64ALIGN\
    //~ if ((dpy.bufptr + SIZEOF(x##name##Req) + n) > dpy.bufmax)\
        //~ _XFlush(dpy);\
    //~ req = (x##name##Req *)(dpy.last_req = dpy.bufptr);\
    //~ req.reqType = X_##name;\
    //~ req.length = (SIZEOF(x##name##Req) + n)>>2;\
    //~ dpy.bufptr += SIZEOF(x##name##Req) + n;\
    //~ dpy.request++
//~ #else
//~ #define GetReqExtra(name, n, req)
        //~ WORD64ALIGN\
    //~ if ((dpy.bufptr + SIZEOF(x                          /*                                                              */name/*Req) + n) > dpy.bufmax)\
        //~ _XFlush(dpy);\
    //~ req = (x                                            /*                                                              */name/*Req *)(dpy.last_req = dpy.bufptr);\
    //~ req.reqType = X_                                    /*                                                              */name;\
    //~ req.length = (SIZEOF(x                              /*                                                              */name/*Req) + n)>>2;\
    //~ dpy.bufptr += SIZEOF(x                              /*                                                              */name/*Req) + n;\
    //~ dpy.request++
//~ #endif


/*
 * GetResReq is for those requests that have a resource ID
 * (Window, Pixmap, GContext, etc.) as their single argument.
 * "rid" is the name of the resource.
 */

//~ #if !defined(UNIXCPP) || defined(ANSICPP)
//~ #define GetResReq(name, rid, req)
        //~ WORD64ALIGN\
    //~ if ((dpy.bufptr + SIZEOF(xResourceReq)) > dpy.bufmax)\
        //~ _XFlush(dpy);\
    //~ req = (xResourceReq *) (dpy.last_req = dpy.bufptr);\
    //~ req.reqType = X_##name;\
    //~ req.length = 2;\
    //~ req.id = (rid);\
    //~ dpy.bufptr += SIZEOF(xResourceReq);\
    //~ dpy.request++
//~ #else
//~ #define GetResReq(name, rid, req)
        //~ WORD64ALIGN\
    //~ if ((dpy.bufptr + SIZEOF(xResourceReq)) > dpy.bufmax)\
        //~ _XFlush(dpy);\
    //~ req = (xResourceReq *) (dpy.last_req = dpy.bufptr);\
    //~ req.reqType = X_                                    /*                                                              */name;\
    //~ req.length = 2;\
    //~ req.id = (rid);\
    //~ dpy.bufptr += SIZEOF(xResourceReq);\
    //~ dpy.request++
//~ #endif

/*
 * GetEmptyReq is for those requests that have no arguments
 * at all.
 */
//~ #if !defined(UNIXCPP) || defined(ANSICPP)
//~ #define GetEmptyReq(name, req)
        //~ WORD64ALIGN\
    //~ if ((dpy.bufptr + SIZEOF(xReq)) > dpy.bufmax)\
        //~ _XFlush(dpy);\
    //~ req = (xReq *) (dpy.last_req = dpy.bufptr);\
    //~ req.reqType = X_##name;\
    //~ req.length = 1;\
    //~ dpy.bufptr += SIZEOF(xReq);\
    //~ dpy.request++
//~ #else
//~ #define GetEmptyReq(name, req)
        //~ WORD64ALIGN\
    //~ if ((dpy.bufptr + SIZEOF(xReq)) > dpy.bufmax)\
        //~ _XFlush(dpy);\
    //~ req = (xReq *) (dpy.last_req = dpy.bufptr);\
    //~ req.reqType = X_                                    /*                                                              */name;\
    //~ req.length = 1;\
    //~ dpy.bufptr += SIZEOF(xReq);\
    //~ dpy.request++
//~ #endif

//~ static if( WORD64 ){
    //~ template MakeBigReq(req,n){
        //~ char _BRdat[4];
        //~ c_ulong _BRlen  = req.length - 1;
        //~ req.length      = 0;
        //~ memcpy(_BRdat, cast(char)* req + (_BRlen << 2), 4);
        //~ memmove(cast(char)* req + 8, cast(char)* req + 4, _BRlen << 2);
        //~ memcpy(cast(char)* req + 4, _BRdat, 4);
        //~ Data32(dpy, cast(long)* &_BRdat, 4);
    //~ }
//~ }
//~ else{
    //~ static if( WORD64 ){
        //~ template MakeBigReq(req,n){
            //~ CARD64 _BRdat;
            //~ CARD32 _BRlen   = req.length - 1;
            //~ req.length      = 0;
            //~ _BRdat          = cast(CARD32)* req[_BRlen];
            //~ memmove(cast(char)* req + 8, cast(char)* req + 4, _BRlen << 2);
            //~ cast(CARD32)* req[1] = _BRlen + n + 2;
            //~ Data32(dpy, &_BRdat, 4);
        //~ }
    //~ }
    //~ else{
        //~ template MakeBigReq(req,n){
            //~ CARD32 _BRdat;
            //~ CARD32 _BRlen   = req.length - 1;
            //~ req.length      = 0;
            //~ _BRdat          = cast(CARD32)* req[_BRlen];
            //~ memmove(cast(char)* req + 8, cast(char)* req + 4, _BRlen << 2);
            //~ cast(CARD32)* req[1] = _BRlen + n + 2;
            //~ Data32(dpy, &_BRdat, 4);
        //~ }
    //~ }
//~ }

//~ void SetReqLen(req,n,badlen){
    //~ if ((req.length + n) > 65535u){
        //~ if (dpy.bigreq_size) {
            //~ MakeBigReq(req,n);
        //~ } else {
            //~ n = badlen;
            //~ req.length += n;
        //~ }
    //~ } else
        //~ req.length += n;
//~ }

//~ void SyncHandle(){
    //~ if (dpy.synchandler)
        //~ dpy.synchandler(dpy);
//~ }

extern void _XFlushGCCache(Display* dpy, GC gc);
void FlushGC(Display* dpy, GC gc){
    if (gc.dirty)
        _XFlushGCCache(dpy, gc);
}
/*
 * Data - Place data in the buffer and pad the end to provide
 * 32 bit word alignment.  Transmit if the buffer fills.
 *
 * "dpy" is a pointer to a Display.
 * "data" is a pinter to a data buffer.
 * "len" is the length of the data buffer.
 */
static if(!DataRoutineIsProcedure){
    void Data( Display* dpy, char* data, uint len) {
        if (dpy.bufptr + len <= dpy.bufmax){
            memcpy(dpy.bufptr, data, cast(int)len);
            dpy.bufptr += (len + 3) & ~3;
        } else
            _XSend(dpy, data, len);
    }
}                                                       /* DataRoutineIsProcedure                                       */


/* Allocate bytes from the buffer.  No padding is done, so if
 * the length is not a multiple of 4, the caller must be
 * careful to leave the buffer aligned after sending the
 * current request.
 *
 * "type" is the type of the pointer being assigned to.
 * "ptr" is the pointer being assigned to.
 * "n" is the number of bytes to allocate.
 *
 * Example:
 *    xTextElt* elt;
 *    BufAlloc (xTextElt *, elt, nbytes)
 */

//~ void BufAlloc(T)(ptr, size_t n){
    //~ if (dpy.bufptr + n > dpy.bufmax)
        //~ _XFlush (dpy);
    //~ ptr = cast(T) dpy.bufptr;
    //~ memset(ptr, '\0', n);
    //~ dpy.bufptr += n;
//~ }

static if( WORD64 ){
    void Data16( Display* dpy, short* data, uint len)   { _XData16(dpy, data, len); }
    void Data32( Display* dpy, c_long* data, uint len)  { _XData32(dpy, data, len); }
    extern int _XData16(
            Display*    dpy,
            short*      data,
            uint        len
    );
    extern int _XData32(
            Display*    dpy,
            c_long*     data,
            uint        len
    );
}
else{                                                   /* not WORD64                                                   */
    void Data16( Display* dpy, short* data, uint len)       { Data(dpy, cast(char *) data, len);         }
    void _XRead16Pad( Display* dpy, short* data, uint len)  { _XReadPad(dpy, cast(char *) data, len);    }
    void _XRead16( Display* dpy, short* data, uint len)     { _XRead(dpy, cast(char *) data, len);       }
    static if(LONG64){
        void Data32( Display* dpy, c_long* data, uint len){ _XData32(dpy, data, len); }
        extern int _XData32(
                Display*    dpy,
                c_long*     data,
                uint        len
        );
        extern void _XRead32(
                Display*    dpy,
                c_long*     data,
                c_long      len
        );
    }
    else{
        void Data32( Display* dpy, int* data, uint len)     { Data(dpy, cast(char *) data, len);     }
        void _XRead32( Display* dpy, int* data, uint len)   { _XRead(dpy, cast(char *) data, len);   }
    }
}

void PackData16( Display* dpy, short* data, uint len){ Data16(dpy, data, len); }
void PackData32( Display* dpy, c_long* data, uint len){ Data32(dpy, data, len); }

                                                        /* Xlib manual is bogus                                         */
void PackData( Display* dpy, short* data, uint len){ PackData16(dpy, data, len); }

int max(int a, int b) { return (a < b) ? b : a; }
int min(int a, int b) { return (a > b) ? b : a; }

bool CI_NONEXISTCHAR( XCharStruct* cs ){
   return ((cs.width == 0) && ((cs.rbearing|cs.lbearing|cs.ascent|cs.descent) == 0));
}
/*
 * CI_GET_CHAR_INFO_1D - return the charinfo struct for the indicated 8bit
 * character.  If the character is in the column and exists, then return the
 * appropriate metrics (note that fonts with common per-character metrics will
 * return min_bounds).  If none of these hold true, try again with the default
 * char.
 */
void CI_GET_CHAR_INFO_1D( XFontStruct* fs, uint col, XCharStruct* def, XCharStruct* cs){
    cs = def;
    if (col >= fs.min_char_or_char2 && col <= fs.max_char_or_char2) {
        if (fs.per_char == null)
            cs = &fs.min_bounds;
        else {
            cs = &fs.per_char[(col - fs.min_char_or_char2)];
            if ( CI_NONEXISTCHAR(cs) )
                cs = def;
        }
    }
}

void CI_GET_DEFAULT_INFO_1D( XFontStruct* fs, XCharStruct* cs){
    CI_GET_CHAR_INFO_1D (fs, fs.default_char, null, cs);
}



/*
 * CI_GET_CHAR_INFO_2D - return the charinfo struct for the indicated row and
 * column.  This is used for fonts that have more than row zero.
 */
void CI_GET_CHAR_INFO_2D( XFontStruct* fs, uint row, uint col, XCharStruct* def, XCharStruct* cs){
    cs = def;
    if (row >= fs.min_char1 && row <= fs.max_char1 && col >= fs.min_char_or_char2 && col <= fs.max_char_or_char2) {
        if (fs.per_char == null)
            cs = &fs.min_bounds;
        else{
            cs = &fs.per_char[((row - fs.min_char1) * (fs.max_char_or_char2 - fs.min_char_or_char2 + 1)) + (col - fs.min_char_or_char2)];
            if (CI_NONEXISTCHAR(cs))
                cs = def;
        }
    }
}

void CI_GET_DEFAULT_INFO_2D(XFontStruct* fs, XCharStruct* cs){
    uint r = (fs.default_char >> 8);
    uint c = (fs.default_char & 0xff);
    CI_GET_CHAR_INFO_2D (fs, r, c, null, cs);
}

version( MUSTCOPY ){
                                                        /* for when 32-bit alignment is not good enough                 */
    void OneDataCard32( Display* dpy, c_long* dstaddr, c_ulong srcvar ){
        dpy.bufptr -= 4;
        Data32(dpy, cast(char)* &(srcvar), 4);
    }
}
else{
                                                        /* srcvar must be a variable for large architecture version     */
    void OneDataCard32( Display* dpy, c_long* dstaddr, c_ulong srcvar){
        *dstaddr = cast(CARD32*)srcvar;
    }
}


struct _XInternalAsync {
    _XInternalAsync* next;
    /*
     * handler arguments:
     * rep is the generic reply that caused this handler
     * to be invoked.  It must also be passed to _XGetAsyncReply.
     * buf and len are opaque values that must be passed to
     * _XGetAsyncReply or _XGetAsyncData.
     * data is the closure stored in this struct.
     * The handler returns True iff it handled this reply.
     */
    extern (C) nothrow Bool function(
        Display*                                        /* dpy                                                          */,
        xReply*                                         /* rep                                                          */,
        char*                                           /* buf                                                          */,
        int                                             /* len                                                          */,
        XPointer                                        /* data                                                         */
    ) handler;
    XPointer data;
}
alias _XInternalAsync _XAsyncHandler;

struct _XAsyncEState {
    c_ulong min_sequence_number;
    c_ulong max_sequence_number;
    ubyte   error_code;
    ubyte   major_opcode;
    ushort  minor_opcode;
    ubyte   last_error_received;
    int     error_count;
}
alias _XAsyncEState _XAsyncErrorState;

extern void _XDeqAsyncHandler(Display* dpy, _XAsyncHandler* handler);

void DeqAsyncHandler( Display* dpy, _XAsyncHandler* handler ){
    if (dpy.async_handlers == handler)
        dpy.async_handlers = handler.next;
    else
        _XDeqAsyncHandler(dpy, handler);
}

alias void function(
    Display*                                            /* display                                                      */
) FreeFuncType;

alias int function(
    XModifierKeymap*                                    /* modmap                                                       */
) FreeModmapType;

/*
 * This structure is private to the library.
 */
struct _XFreeFuncs {
    FreeFuncType atoms;                                 /* _XFreeAtomTable                                              */
    FreeModmapType modifiermap;                         /* XFreeModifierMap                                             */
    FreeFuncType key_bindings;                          /* _XFreeKeyBindings                                            */
    FreeFuncType context_db;                            /* _XFreeContextDB                                              */
    FreeFuncType defaultCCCs;                           /* _XcmsFreeDefaultCCCs                                         */
    FreeFuncType clientCmaps;                           /* _XcmsFreeClientCmaps                                         */
    FreeFuncType intensityMaps;                         /* _XcmsFreeIntensityMaps                                       */
    FreeFuncType im_filters;                            /* _XFreeIMFilters                                              */
    FreeFuncType xkb;                                   /* _XkbFreeInfo                                                 */
}
alias _XFreeFuncs _XFreeFuncRec;

                                                        /* types for InitExt.c                                          */
alias int function (
    Display*                                            /* display                                                      */,
    GC                                                  /* gc                                                           */,
    XExtCodes*                                          /* codes                                                        */
) CreateGCType;

alias int function(
    Display*                                            /* display                                                      */,
    GC                                                  /* gc                                                           */,
    XExtCodes*                                          /* codes                                                        */
) CopyGCType;

alias int function (
    Display*                                            /* display                                                      */,
    GC                                                  /* gc                                                           */,
    XExtCodes*                                          /* codes                                                        */
) FlushGCType;

alias int function (
    Display*                                            /* display                                                      */,
    GC                                                  /* gc                                                           */,
    XExtCodes*                                          /* codes                                                        */
) FreeGCType;

alias int function (
    Display*                                            /* display                                                      */,
    XFontStruct*                                        /* fs                                                           */,
    XExtCodes*                                          /* codes                                                        */
) CreateFontType;

alias int function(
    Display*                                            /* display                                                      */,
    XFontStruct*                                        /* fs                                                           */,
    XExtCodes*                                          /* codes                                                        */
) FreeFontType;

alias int function(
    Display*                                            /* display                                                      */,
    XExtCodes*                                          /* codes                                                        */
) CloseDisplayType;

alias int function(
    Display*                                            /* display                                                      */,
    xError*                                             /* err                                                          */,
    XExtCodes*                                          /* codes                                                        */,
    int*                                                /* ret_code                                                     */
) ErrorType;

alias char* function(
    Display*                                            /* display                                                      */,
    int                                                 /* code                                                         */,
    XExtCodes*                                          /* codes                                                        */,
    char*                                               /* buffer                                                       */,
    int                                                 /* nbytes                                                       */
) ErrorStringType;

alias void function(
    Display*                                            /* display                                                      */,
    XErrorEvent*                                        /* ev                                                           */,
    void*                                               /* fp                                                           */
) PrintErrorType;

alias void function(
    Display*                                            /* display                                                      */,
    XExtCodes*                                          /* codes                                                        */,
    const char*                                         /* data                                                         */,
   c_long                                               /* len                                                          */
) BeforeFlushType;

/*
 * This structure is private to the library.
 */
struct _XExten {                                        /* private to extension mechanism                               */
    _XExten*            next;                           /* next in list                                                 */
    XExtCodes           codes;                          /* public information, all extension told                       */
    CreateGCType        create_GC;                      /* routine to call when GC created                              */
    CopyGCType          copy_GC;                        /* routine to call when GC copied                               */
    FlushGCType         flush_GC;                       /* routine to call when GC flushed                              */
    FreeGCType          free_GC;                        /* routine to call when GC freed                                */
    CreateFontType      create_Font;                    /* routine to call when Font created                            */
    FreeFontType        free_Font;                      /* routine to call when Font freed                              */
    CloseDisplayType    close_display;                  /* routine to call when connection closed                       */
    ErrorType           error;                          /* who to call when an error occurs                             */
    ErrorStringType     error_string;                   /* routine to supply error string                               */
    char*               name;                           /* name of this extension                                       */
    PrintErrorType      error_values;                   /* routine to supply error values                               */
    BeforeFlushType     before_flush;                   /* routine to call when sending data                            */
    _XExten*            next_flush;                     /* next in list of those with flushes                           */
}
alias _XExten _XExtension;

                                                        /* extension hooks                                              */
static if (DataRoutineIsProcedure)
{
    extern void Data(Display* dpy, char* data, c_long len);
}

extern int _XError(
    Display*                                            /* dpy                                                          */,
    xError*                                             /* rep                                                          */
);
extern int _XIOError(
    Display*                                            /* dpy                                                          */
);
extern int function(
    Display*                                            /* dpy                                                          */
) _XIOErrorFunction;
extern int function(
    Display*                                            /* dpy                                                          */,
    XErrorEvent*                                        /* error_event                                                  */
) _XErrorFunction;
extern void _XEatData(
    Display*                                            /* dpy                                                          */,
    c_ulong                                             /* n                                                            */
);
extern char* _XAllocScratch(
    Display*                                            /* dpy                                                          */,
    c_ulong                                             /* nbytes                                                       */
);
extern char* _XAllocTemp(
    Display*                                            /* dpy                                                          */,
    c_ulong                                             /* nbytes                                                       */
);
extern void _XFreeTemp(
    Display*                                            /* dpy                                                          */,
    char*                                               /* buf                                                          */,
    c_ulong                                             /* nbytes                                                       */
);
extern Visual* _XVIDtoVisual(
    Display*                                            /* dpy                                                          */,
    VisualID                                            /* id                                                           */
);
extern c_ulong _XSetLastRequestRead(
    Display*                                            /* dpy                                                          */,
    xGenericReply*                                      /* rep                                                          */
);
extern int _XGetHostname(
    char*                                               /* buf                                                          */,
    int                                                 /* maxlen                                                       */
);
extern Screen* _XScreenOfWindow(
    Display*                                            /* dpy                                                          */,
    Window                                              /* w                                                            */
);
extern Bool _XAsyncErrorHandler(
    Display*                                            /* dpy                                                          */,
    xReply*                                             /* rep                                                          */,
    char*                                               /* buf                                                          */,
    int                                                 /* len                                                          */,
    XPointer                                            /* data                                                         */
);
extern char* _XGetAsyncReply(
    Display*                                            /* dpy                                                          */,
    char*                                               /* replbuf                                                      */,
    xReply*                                             /* rep                                                          */,
    char*                                               /* buf                                                          */,
    int                                                 /* len                                                          */,
    int                                                 /* extra                                                        */,
    Bool                                                /* discard                                                      */
);
extern void _XGetAsyncData(
    Display*                                            /* dpy                                                          */,
    char *                                              /* data                                                         */,
    char *                                              /* buf                                                          */,
    int                                                 /* len                                                          */,
    int                                                 /* skip                                                         */,
    int                                                 /* datalen                                                      */,
    int                                                 /* discardtotal                                                 */
);
extern void _XFlush(
    Display*                                            /* dpy                                                          */
);
extern int _XEventsQueued(
    Display*                                            /* dpy                                                          */,
    int                                                 /* mode                                                         */
);
extern void _XReadEvents(
    Display*                                            /* dpy                                                          */
);
extern int _XRead(
    Display*                                            /* dpy                                                          */,
    char*                                               /* data                                                         */,
   c_long                                               /* size                                                         */
);
extern void _XReadPad(
    Display*                                            /* dpy                                                          */,
    char*                                               /* data                                                         */,
   c_long                                               /* size                                                         */
);
extern void _XSend(
    Display*                                            /* dpy                                                          */,
    const char*                                         /* data                                                         */,
   c_long                                               /* size                                                         */
);
extern Status _XReply(
    Display*                                            /* dpy                                                          */,
    xReply*                                             /* rep                                                          */,
    int                                                 /* extra                                                        */,
    Bool                                                /* discard                                                      */
);
extern void _XEnq(
    Display*                                            /* dpy                                                          */,
    xEvent*                                             /* event                                                        */
);
extern void _XDeq(
    Display*                                            /* dpy                                                          */,
    _XQEvent*                                           /* prev                                                         */,
    _XQEvent*                                           /* qelt                                                         */
);

extern Bool _XUnknownWireEvent(
    Display*                                            /* dpy                                                          */,
    XEvent*                                             /* re                                                           */,
    xEvent*                                             /* event                                                        */
);

extern Bool _XUnknownWireEventCookie(
    Display*                                            /* dpy                                                          */,
    XGenericEventCookie*                                /* re                                                           */,
    xEvent*                                             /* event                                                        */
);

extern Bool _XUnknownCopyEventCookie(
    Display*                                            /* dpy                                                          */,
    XGenericEventCookie*                                /* in                                                           */,
    XGenericEventCookie*                                /* out                                                          */
);

extern Status _XUnknownNativeEvent(
    Display*                                            /* dpy                                                          */,
    XEvent*                                             /* re                                                           */,
    xEvent*                                             /* event                                                        */
);

extern Bool _XWireToEvent(Display* dpy, XEvent* re, xEvent* event);
extern Bool _XDefaultWireError(Display* display, XErrorEvent* he, xError* we);
extern Bool _XPollfdCacheInit(Display* dpy);
extern void _XPollfdCacheAdd(Display* dpy, int fd);
extern void _XPollfdCacheDel(Display* dpy, int fd);
extern XID _XAllocID(Display* dpy);
extern void _XAllocIDs(Display* dpy, XID* ids, int count);

extern int _XFreeExtData(
    XExtData*                                           /* extension                                                    */
);

extern int function( Display*, GC, XExtCodes* ) XESetCreateGC(
    Display*                                            /* display                                                      */,
    int                                                 /* extension                                                    */,
    int function (
        Display*                                        /* display                                                      */,
        GC                                              /* gc                                                           */,
        XExtCodes*                                      /* codes                                                        */
    )                                                   /* proc                                                         */
);

extern int function( Display*, GC, XExtCodes* ) XESetCopyGC(
    Display*                                            /* display                                                      */,
    int                                                 /* extension                                                    */,
    int function (
        Display*                                        /* display                                                      */,
        GC                                              /* gc                                                           */,
        XExtCodes*                                      /* codes                                                        */
    )                                                   /* proc                                                         */
);

extern int function( Display*, GC, XExtCodes* ) XESetFlushGC(
    Display*                                            /* display                                                      */,
    int                                                 /* extension                                                    */,
    int function (
        Display*                                        /* display                                                      */,
        GC                                              /* gc                                                           */,
        XExtCodes*                                      /* codes                                                        */
    )                                                   /* proc                                                         */
);

extern int function (Display*, GC, XExtCodes* ) XESetFreeGC(
    Display*                                            /* display                                                      */,
    int                                                 /* extension                                                    */,
    int function (
        Display*                                        /* display                                                      */,
        GC                                              /* gc                                                           */,
        XExtCodes*                                      /* codes                                                        */
    )                                                   /* proc                                                         */
);

extern int function( Display*, XFontStruct*, XExtCodes* ) XESetCreateFont(
    Display*                                            /* display                                                      */,
    int                                                 /* extension                                                    */,
    int function (
        Display*                                        /* display                                                      */,
        XFontStruct*                                    /* fs                                                           */,
        XExtCodes*                                      /* codes                                                        */
    )                                                   /* proc                                                         */
);

extern int function(Display*, XFontStruct*, XExtCodes* ) XESetFreeFont(
    Display*                                            /* display                                                      */,
    int                                                 /* extension                                                    */,
    int function (
        Display*                                        /* display                                                      */,
        XFontStruct*                                    /* fs                                                           */,
        XExtCodes*                                      /* codes                                                        */
    )                                                   /* proc                                                         */
);

extern int function( Display*, XExtCodes* ) XESetCloseDisplay(
    Display*                                            /* display                                                      */,
    int                                                 /* extension                                                    */,
    int function (
        Display*                                        /* display                                                      */,
        XExtCodes*                                      /* codes                                                        */
    )                                                   /* proc                                                         */
);

extern int function( Display*, xError*, XExtCodes*, int* ) XESetError(
    Display*                                            /* display                                                      */,
    int                                                 /* extension                                                    */,
    int function (
        Display*                                        /* display                                                      */,
        xError*                                         /* err                                                          */,
        XExtCodes*                                      /* codes                                                        */,
        int*                                            /* ret_code                                                     */
    )                                                   /* proc                                                         */
);

extern char* function( Display*, int, XExtCodes*, char*, int ) XESetErrorString(
    Display*                                            /* display                                                      */,
    int                                                 /* extension                                                    */,
    char* function (
        Display*                                        /* display                                                      */,
        int                                             /* code                                                         */,
        XExtCodes*                                      /* codes                                                        */,
        char*                                           /* buffer                                                       */,
        int                                             /* nbytes                                                       */
    )                                                   /* proc                                                         */
);

extern void function( Display*, XErrorEvent*, void* ) XESetPrintErrorValues(
    Display*                                            /* display                                                      */,
    int                                                 /* extension                                                    */,
    void function(
        Display*                                        /* display                                                      */,
        XErrorEvent*                                    /* ev                                                           */,
        void*                                           /* fp                                                           */
    )                                                   /* proc                                                         */
);

extern Bool function( Display*, XEvent*, xEvent* )XESetWireToEvent(
    Display*                                            /* display                                                      */,
    int                                                 /* event_number                                                 */,
    Bool function (
        Display*                                        /* display                                                      */,
        XEvent*                                         /* re                                                           */,
        xEvent*                                         /* event                                                        */
    )                                                   /* proc                                                         */
);

extern Bool function( Display*, XGenericEventCookie*, xEvent* )XESetWireToEventCookie(
    Display*                                            /* display                                                      */,
    int                                                 /* extension                                                    */,
    Bool function (
        Display*                                        /* display                                                      */,
        XGenericEventCookie*                            /* re                                                           */,
        xEvent*                                         /* event                                                        */
    )                                                   /* proc                                                         */
);

extern Bool function( Display*, XGenericEventCookie*, XGenericEventCookie* )XESetCopyEventCookie(
    Display*                                            /* display                                                      */,
    int                                                 /* extension                                                    */,
    Bool function (
        Display*                                        /* display                                                      */,
        XGenericEventCookie*                            /* in                                                           */,
        XGenericEventCookie*                            /* out                                                          */
    )                                                   /* proc                                                         */
);


extern Status function( Display*, XEvent*, xEvent* ) XESetEventToWire(
    Display*                                            /* display                                                      */,
    int                                                 /* event_number                                                 */,
    Status function (
        Display*                                        /* display                                                      */,
        XEvent*                                         /* re                                                           */,
        xEvent*                                         /* event                                                        */
    )                                                    /* proc                                                         */
);

extern Bool function( Display*, XErrorEvent*, xError* ) XESetWireToError(
    Display*                                            /* display                                                      */,
    int                                                 /* error_number                                                 */,
    Bool function (
        Display*                                        /* display                                                      */,
        XErrorEvent*                                    /* he                                                           */,
        xError*                                         /* we                                                           */
    )                                                   /* proc                                                         */
);

extern void function( Display*, XExtCodes*, const char*, c_long ) XESetBeforeFlush(
    Display*                                            /* display                                                      */,
    int                                                 /* error_number                                                 */,
    void function (
        Display*                                        /* display                                                      */,
        XExtCodes*                                      /* codes                                                        */,
        const char*                                     /* data                                                         */,
        c_long                                          /* len                                                          */
    )                                                   /* proc                                                         */
);

                                                        /* internal connections for IMs                                 */

alias void function(
    Display*                                            /* dpy                                                          */,
    int                                                 /* fd                                                           */,
    XPointer                                            /* call_data                                                    */
) _XInternalConnectionProc;


extern Status _XRegisterInternalConnection(
    Display*                                            /* dpy                                                          */,
    int                                                 /* fd                                                           */,
    _XInternalConnectionProc                            /* callback                                                     */,
    XPointer                                            /* call_data                                                    */
);

extern void _XUnregisterInternalConnection(
    Display*                                            /* dpy                                                          */,
    int                                                 /* fd                                                           */
);

extern void _XProcessInternalConnection(
    Display*                                            /* dpy                                                          */,
    _XConnectionInfo*                                   /* conn_info                                                    */
);

                                                        /* Display structure has pointers to these                      */

struct _XConnectionInfo {                               /* info from _XRegisterInternalConnection                       */
    int fd;
    _XInternalConnectionProc read_callback;
    XPointer call_data;
    XPointer* watch_data;                               /* set/used by XConnectionWatchProc                             */
    _XConnectionInfo* next;
};

struct _XConnWatchInfo {                                /* info from XAddConnectionWatch                                */
    XConnectionWatchProc fn;
    XPointer client_data;
    _XConnWatchInfo* next;
};

version( Posix ){
    extern char* __XOS2RedirRoot( char* );
}

extern int _XTextHeight(
    XFontStruct*                                        /* font_struct                                                  */,
    const char*                                         /* string                                                       */,
    int                                                 /* count                                                        */
);

extern int _XTextHeight16(
    XFontStruct*                                        /* font_struct                                                  */,
    const XChar2b*                                      /* string                                                       */,
    int                                                 /* count                                                        */
);

alias std.stdio.File.open   _XOpenFile;
alias fopen _XFopenFile;

                                                        /* EvToWire.c                                                   */
extern Status _XEventToWire(Display* dpy, XEvent* re, xEvent* event);

extern int _XF86LoadQueryLocaleFont(
    Display*                                            /* dpy                                                          */,
    const char*                                         /* name                                                         */,
    XFontStruct**                                       /* xfp                                                          */,
    Font*                                               /* fidp                                                         */
);

extern void _XProcessWindowAttributes( Display* dpy, xChangeWindowAttributesReq* req, c_ulong valuemask, XSetWindowAttributes* attributes);

extern int _XDefaultError( Display* dpy, XErrorEvent* event);

extern int _XDefaultIOError( Display* dpy);

extern void _XSetClipRectangles( Display* dpy, GC gc, int clip_x_origin, int clip_y_origin, XRectangle* rectangles, int n, int ordering );

Status _XGetWindowAttributes( Display* dpy, Window w, XWindowAttributes* attr);

int _XPutBackEvent( Display* dpy, XEvent* event);

extern Bool _XIsEventCookie( Display* dpy, XEvent* ev );

extern void _XFreeEventCookies( Display* dpy );

extern void _XStoreEventCookie( Display* dpy, XEvent* ev );

extern Bool _XFetchEventCookie( Display* dpy, XGenericEventCookie* ev );

extern Bool _XCopyEventCookie( Display* dpy, XGenericEventCookie* inEvent, XGenericEventCookie* outEvent );

                                                        /* lcFile.c                                                     */

extern void xlocaledir( char* buf, int buf_len );
