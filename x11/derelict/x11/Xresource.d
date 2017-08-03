module derelict.x11.Xresource;
import derelict.x11.Xlib;
version(linux):
extern (C) nothrow @nogc:

/****************************************************************
 ****************************************************************
 ***                                                          ***
 ***                                                          ***
 ***          X Resource Manager Intrinsics                   ***
 ***                                                          ***
 ***                                                          ***
 ****************************************************************
 ***************************************************************


/****************************************************************
 *
 * Memory Management
 *
 ****************************************************************/

extern char* Xpermalloc(
    uint                                                /* size                                                         */
);

/****************************************************************
 *
 * Quark Management
 *
 ****************************************************************/

alias int   XrmQuark;
alias int*  XrmQuarkList;
const XrmQuark NULLQUARK = 0;

alias char* XrmString;
const XrmString NULLSTRING = null;

                                                        /* find quark for string, create new quark if none already exists */
extern XrmQuark XrmStringToQuark(
    const char*                                         /* string                                                       */
);

extern XrmQuark XrmPermStringToQuark(
    const char*                                         /* string                                                       */
);

                                                        /* find string for quark                                        */
extern XrmString XrmQuarkToString(
    XrmQuark                                            /* quark                                                        */
);

extern XrmQuark XrmUniqueQuark( );

bool XrmStringsEqual(XrmString a1, XrmString a2){ return *a1 == *a2; }


/****************************************************************
 *
 * Conversion of Strings to Lists
 *
 ****************************************************************/

alias int XrmBinding;
enum {XrmBindTightly, XrmBindLoosely}
alias XrmBinding* XrmBindingList;

extern void XrmStringToQuarkList(
    const char*                                         /* string                                                       */,
    XrmQuarkList                                        /* quarks_return                                                */
);

extern void XrmStringToBindingQuarkList(
    const char*                                         /* string                                                       */,
    XrmBindingList                                      /* bindings_return                                              */,
    XrmQuarkList                                        /* quarks_return                                                */
);

/****************************************************************
 *
 * Name and Class lists.
 *
 ****************************************************************/

alias XrmQuark     XrmName;
alias XrmQuarkList XrmNameList;
XrmString   XrmNameToString(XrmName name)                       { return                    XrmQuarkToString( cast(XrmQuark) name );}
XrmName     XrmStringToName(XrmString string)                   { return cast(XrmName)      XrmStringToQuark(string);               }
void        XrmStringToNameList(XrmString str, XrmNameList name){                           XrmStringToQuarkList(str, name);        }

alias XrmQuark     XrmClass;
alias XrmQuarkList XrmClassList;
XrmString   XrmClassToString( XrmClass c_class )                        { return                    XrmQuarkToString( cast(XrmQuark) c_class);  }
XrmClass    XrmStringToClass( XrmString c_class )                       { return cast(XrmClass)     XrmStringToQuark(c_class);                  }
void        XrmStringToClassList( XrmString str, XrmClassList c_class)  {                           XrmStringToQuarkList(str, c_class);         }



/****************************************************************
 *
 * Resource Representation Types and Values
 *
 ****************************************************************/

alias XrmQuark     XrmRepresentation;
XrmRepresentation   XrmStringToRepresentation( XrmString string)        { return cast(XrmRepresentation)    XrmStringToQuark(string);   }
XrmString           XrmRepresentationToString( XrmRepresentation type)  { return                            XrmQuarkToString(type);     }

struct XrmValue{
    uint        size;
    XPointer    addr;
}
alias XrmValue* XrmValuePtr;


/****************************************************************
 *
 * Resource Manager Functions
 *
 ****************************************************************/
struct _XrmHashBucketRec{}
alias _XrmHashBucketRec* XrmHashBucket;
alias XrmHashBucket* XrmHashTable;
alias XrmHashTable[] XrmSearchList;
alias _XrmHashBucketRec* XrmDatabase;


extern void XrmDestroyDatabase(
    XrmDatabase                                         /* database                                                     */
);

extern void XrmQPutResource(
    XrmDatabase*                                        /* database                                                     */,
    XrmBindingList                                      /* bindings                                                     */,
    XrmQuarkList                                        /* quarks                                                       */,
    XrmRepresentation                                   /* type                                                         */,
    XrmValue*                                           /* value                                                        */
);

extern void XrmPutResource(
    XrmDatabase*                                        /* database                                                     */,
    const char*                                         /* specifier                                                    */,
    const char*                                         /* type                                                         */,
    XrmValue*                                           /* value                                                        */
);

extern void XrmQPutStringResource(
    XrmDatabase*                                        /* database                                                     */,
    XrmBindingList                                      /* bindings                                                     */,
    XrmQuarkList                                        /* quarks                                                       */,
    const char*                                         /* value                                                        */
);

extern void XrmPutStringResource(
    XrmDatabase*                                        /* database                                                     */,
    const char*                                         /* specifier                                                    */,
    const char*                                         /* value                                                        */
);

extern void XrmPutLineResource(
    XrmDatabase*                                        /* database                                                     */,
    const char*                                         /* line                                                         */
);

extern Bool XrmQGetResource(
    XrmDatabase                                         /* database                                                     */,
    XrmNameList                                         /* quark_name                                                   */,
    XrmClassList                                        /* quark_class                                                  */,
    XrmRepresentation*                                  /* quark_type_return                                            */,
    XrmValue*                                           /* value_return                                                 */
);

extern Bool XrmGetResource(
    XrmDatabase                                         /* database                                                     */,
    const char*                                         /* str_name                                                     */,
    const char*                                         /* str_class                                                    */,
    char**                                              /* str_type_return                                              */,
    XrmValue*                                           /* value_return                                                 */
);

extern Bool XrmQGetSearchList(
    XrmDatabase                                         /* database                                                     */,
    XrmNameList                                         /* names                                                        */,
    XrmClassList                                        /* classes                                                      */,
    XrmSearchList                                       /* list_return                                                  */,
    int                                                 /* list_length                                                  */
);

extern Bool XrmQGetSearchResource(
    XrmSearchList                                       /* list                                                         */,
    XrmName                                             /* name                                                         */,
    XrmClass                                            /* class                                                        */,
    XrmRepresentation*                                  /* type_return                                                  */,
    XrmValue*                                           /* value_return                                                 */
);

/****************************************************************
 *
 * Resource Database Management
 *
 ****************************************************************/


extern void XrmSetDatabase(
    Display*                                            /* display                                                      */,
    XrmDatabase                                         /* database                                                     */
);

extern XrmDatabase XrmGetDatabase(
    Display*                                            /* display                                                      */
);


extern XrmDatabase XrmGetFileDatabase(
    const char*                                         /* filename                                                     */
);

extern Status XrmCombineFileDatabase(
    const char*                                         /* filename                                                     */,
    XrmDatabase*                                        /* target                                                       */,
    Bool                                                /* override                                                     */
);

extern XrmDatabase XrmGetStringDatabase(
    const char*                                         /* data null terminated string                                  */
);

extern void XrmPutFileDatabase(
    XrmDatabase                                         /* database                                                     */,
    const char*                                         /* filename                                                     */
);

extern void XrmMergeDatabases(
    XrmDatabase                                         /* source_db                                                    */,
    XrmDatabase*                                        /* target_db                                                    */
);

extern void XrmCombineDatabase(
    XrmDatabase                                         /* source_db                                                    */,
    XrmDatabase*                                        /* target_db                                                    */,
    Bool                                                /* override                                                     */
);

const uint XrmEnumAllLevels = 0;
const uint XrmEnumOneLevel  = 1;

extern Bool XrmEnumerateDatabase(
    XrmDatabase                                         /* db                                                           */,
    XrmNameList                                         /* name_prefix                                                  */,
    XrmClassList                                        /* class_prefix                                                 */,
    int                                                 /* mode                                                         */,
    Bool function(
         XrmDatabase*                                   /* db                                                           */,
         XrmBindingList                                 /* bindings                                                     */,
         XrmQuarkList                                   /* quarks                                                       */,
         XrmRepresentation*                             /* type                                                         */,
         XrmValue*                                      /* value                                                        */,
         XPointer                                       /* closure                                                      */
    )                                                   /* proc                                                         */,
    XPointer                                            /* closure                                                      */
);

extern char* XrmLocaleOfDatabase(
    XrmDatabase                                         /* database                                                     */
);


/****************************************************************
 *
 * Command line option mapping to resource entries
 *
 ****************************************************************/

alias int XrmOptionKind;
enum {
    XrmoptionNoArg,                                     /* Value is specified in OptionDescRec.value                    */
    XrmoptionIsArg,                                     /* Value is the option string itself                            */
    XrmoptionStickyArg,                                 /* Value is characters immediately following option             */
    XrmoptionSepArg,                                    /* Value is next argument in argv                               */
    XrmoptionResArg,                                    /* Resource and value in next argument in argv                  */
    XrmoptionSkipArg,                                   /* Ignore this option and the next argument in argv             */
    XrmoptionSkipLine,                                  /* Ignore this option and the rest of argv                      */
    XrmoptionSkipNArgs                                  /* Ignore this option and the next OptionDescRes.value arguments in argv */
}

struct XrmOptionDescRec{
    char*        option;                                /* Option abbreviation in argv                                  */
    char*        specifier;                             /* Resource specifier                                           */
    XrmOptionKind   argKind;                            /* Which style of option it is                                  */
    XPointer        value;                              /* Value to provide if XrmoptionNoArg                           */
}
alias XrmOptionDescRec* XrmOptionDescList;


extern void XrmParseCommand(
    XrmDatabase*                                        /* database                                                     */,
    XrmOptionDescList                                   /* table                                                        */,
    int                                                 /* table_count                                                  */,
    const char*                                         /* name                                                         */,
    int*                                                /* argc_in_out                                                  */,
    char**                                              /* argv_in_out                                                  */
);
