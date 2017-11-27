module derelict.x11.Xtos;
version(linux):
//~ #define ALLOCATE_LOCAL_FALLBACK(_size) XtMalloc((unsigned long)(_size))
//~ #define DEALLOCATE_LOCAL_FALLBACK(_ptr) XtFree((XtPointer)(_ptr))
//~ #include <X11/Xalloca.h>

enum bool WORD64 = false;

version( X86_64 ){
    enum bool LONG64 = true;
}
else{
    enum bool LONG64 = false;
}
/* DON'T ADD STUFF AFTER THIS #endif */
