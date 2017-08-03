module derelict.x11.Xmd;

version(linux):
//~ import std.string;
import std.conv;
import core.stdc.config;

import derelict.x11.Xtos;

extern (C) nothrow @nogc:
/*
 *  Xmd.d: MACHINE DEPENDENT DECLARATIONS.
 */

/*
 * Special per-machine configuration flags.
 */
version( X86_64 ){
    enum bool LONG64 = true; /* 32/64-bit architecture */
    /*
     * Stuff to handle large architecture machines; the constants were generated
     * on a 32-bit machine and must correspond to the protocol.
     */
    enum bool MUSTCOPY = true;
}
else{
    enum bool LONG64 = false;
    enum bool MUSTCOPY = false;
}



/*
 * Definition of macro used to set constants for size of network structures;
 * machines with preprocessors that can't handle all of the sz_ symbols
 * can define this macro to be sizeof(x) if and only if their compiler doesn't
 * pad out structures (esp. the xTextElt structure which contains only two
 * one-byte fields).  Network structures should always define sz_symbols.
 *
 * The sz_ prefix is used instead of something more descriptive so that the
 * symbols are no more than 32 characters long (which causes problems for some
 * compilers and preprocessors).
 *
 * The extra indirection is to get macro arguments to expand correctly before
 * the concatenation, rather than afterward.
 */
//~ template _SIZEOF(T){ size_t _SIZEOF = T.sizeof; }
size_t _SIZEOF(T)(){ return T.sizeof; }
alias _SIZEOF SIZEOF;

/*
 * Bitfield suffixes for the protocol structure elements, if you
 * need them.  Note that bitfields are not guaranteed to be signed
 * (or even unsigned) according to ANSI C.
 */
version( X86_64 ){
    alias long INT64;
    //~ #  define B32 :32
    //~ #  define B16 :16
    alias uint INT32;
    alias uint INT16;
}
else{
    //~ #  define B32
    //~ #  define B16
    static if( LONG64 ){
        alias c_long INT64;
        alias int INT32;
    }
    else
        alias c_long INT32;
    alias short INT16;
}

alias byte    INT8;

static if( LONG64 ){
    alias c_ulong CARD64;
    alias uint CARD32;
}
else
    alias c_ulong CARD32;

static if( !WORD64 && !LONG64 )
    alias ulong CARD64;

alias ushort    CARD16;
alias byte      CARD8;

alias CARD32    BITS32;
alias CARD16    BITS16;

alias CARD8     BYTE;
alias CARD8     BOOL;

/*
 * definitions for sign-extending bitfields on 64-bit architectures
 */
static if( WORD64 ){
    template cvtINT8toInt(INT8 val)     {   const int       cvtINT8toInt    = cast(int)     (val & 0x00000080) ? (val | 0xffffffffffffff00) : val; }
    template cvtINT16toInt(INT16 val)   {   const int       cvtINT16toInt   = cast(int)     (val & 0x00008000) ? (val | 0xffffffffffff0000) : val; }
    template cvtINT32toInt(INT32 val)   {   const int       cvtINT32toInt   = cast(int)     (val & 0x80000000) ? (val | 0xffffffff00000000) : val; }
    template cvtINT8toShort(INT8 val)   {   const short     cvtINT8toShort  = cast(short)   cvtINT8toInt(val); }
    template cvtINT16toShort(INT16 val) {   const short     cvtINT16toShort = cast(short)   cvtINT16toInt(val); }
    template cvtINT32toShort(INT32 val) {   const short     cvtINT32toShort = cast(short)   cvtINT32toInt(val); }
    template cvtINT8toLong(INT8 val)    {   const c_long    cvtINT8toLong   = cast(c_long)  cvtINT8toInt(val); }
    template cvtINT16toLong(INT16 val)  {   const c_long    cvtINT16toLong  = cast(c_long)  cvtINT16toInt(val); }
    template cvtINT32toLong(INT32 val)  {   const c_long    cvtINT32toLong  = cast(c_long)  cvtINT32toInt(val); }
}
else{ /* WORD64 and UNSIGNEDBITFIELDS */
    template cvtINT8toInt(INT8 val)     {   const int       cvtINT8toInt    = cast(int)     val; }
    template cvtINT16toInt(INT16 val)   {   const int       cvtINT16toInt   = cast(int)     val; }
    template cvtINT32toInt(INT32 val)   {   const int       cvtINT32toInt   = cast(int)     val; }
    template cvtINT8toShort(INT8 val)   {   const short     cvtINT8toShort  = cast(short)   val; }
    template cvtINT16toShort(INT16 val) {   const short     cvtINT16toShort = cast(short)   val; }
    template cvtINT32toShort(INT32 val) {   const short     cvtINT32toShort = cast(short)   val; }
    template cvtINT8toLong(INT8 val)    {   const c_long    cvtINT8toLong   = cast(c_long)  val; }
    template cvtINT16toLong(INT16 val)  {   const c_long    cvtINT16toLong  = cast(c_long)  val; }
    template cvtINT32toLong(INT32 val)  {   const c_long    cvtINT32toLong  = cast(c_long)  val; }
}



static if( MUSTCOPY ){
    /*
     * This macro must not cast or else pointers will get aligned and be wrong
     */
    T NEXTPTR(T)(T p){ const T NEXTPTR = p + SIZEOF!(T); }
}
else{/* else not MUSTCOPY, this is used for 32-bit machines */
    /*
     * this version should leave result of type (t *), but that should only be
     * used when not in MUSTCOPY
     */
    T NEXTPTR(T)(T p){ const T NEXTPTR = p + 1; }
}/* MUSTCOPY - used machines whose C structs don't line up with proto */
