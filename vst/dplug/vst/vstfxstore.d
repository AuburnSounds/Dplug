/**
* Copyright: Steinberg.
* License:   To use this file you MUST agree with the Steinberg VST license included in the VST SDK.
* Authors:   D translation by Guillaume Piolat.
*/
module dplug.vst.vstfxstore;

import dplug.vst.aeffect;

/** Define SDK Version (you can generate different versions (from 2.0 to 2.4) of this SDK by unsetting the unwanted extensions). */

version = VST_2_4_EXTENSIONS; /// Version 2.4 extensions (01-01-2006)

//-------------------------------------------------------------------------------------------------------
/** Root chunk identifier for Programs (fxp) and Banks (fxb). */
enum VstInt32 cMagic = CCONST('C', 'c', 'n', 'K');

/** Regular Program (fxp) identifier. */
enum VstInt32 fMagic = CCONST('F', 'x', 'C', 'k');

/** Regular Bank (fxb) identifier. */
enum VstInt32 bankMagic = CCONST('F', 'x', 'B', 'k');

/** Program (fxp) identifier for opaque chunk data. */
enum VstInt32 chunkPresetMagic = CCONST('F', 'P', 'C', 'h');

/** Bank (fxb) identifier for opaque chunk data. */
enum VstInt32 chunkBankMagic = CCONST('F', 'B', 'C', 'h');

/*
    Note: The C data structures below are for illustration only. You can not read/write them directly.
    The byte order on disk of fxp and fxb files is Big Endian. You have to swap integer
    and floating-point values on Little Endian platforms (Windows, MacIntel)!
*/

//-------------------------------------------------------------------------------------------------------
/** Program (fxp) structure. */
//-------------------------------------------------------------------------------------------------------
struct fxProgram
{
//-------------------------------------------------------------------------------------------------------
    VstInt32 chunkMagic;                ///< 'CcnK'
    VstInt32 byteSize;                  ///< size of this chunk, excl. magic + byteSize

    VstInt32 fxMagic;                   ///< 'FxCk' (regular) or 'FPCh' (opaque chunk)
    VstInt32 version_;                  ///< format version (currently 1)
    VstInt32 fxID;                      ///< fx unique ID
    VstInt32 fxVersion;                 ///< fx version

    VstInt32 numParams;                 ///< number of parameters
    char[28] prgName;                   ///< program name (null-terminated ASCII string)

    union Content
    {
        float[1] params;                ///< variable sized array with parameter values

        struct Data
        {
            VstInt32 size;              ///< size of program data
            char[1] chunk;              ///< variable sized array with opaque program data
        }

        Data data;                      ///< program chunk data
    }

    Content content;                    ///< program content depending on fxMagic
//-------------------------------------------------------------------------------------------------------
}

//-------------------------------------------------------------------------------------------------------
/** Bank (fxb) structure. */
//-------------------------------------------------------------------------------------------------------
struct fxBank
{
//-------------------------------------------------------------------------------------------------------
    VstInt32 chunkMagic;                ///< 'CcnK'
    VstInt32 byteSize;                  ///< size of this chunk, excl. magic + byteSize

    VstInt32 fxMagic;                   ///< 'FxBk' (regular) or 'FBCh' (opaque chunk)
    VstInt32 version_;                  ///< format version (1 or 2)
    VstInt32 fxID;                      ///< fx unique ID
    VstInt32 fxVersion;                 ///< fx version

    VstInt32 numPrograms;               ///< number of programs

    version(VST_2_4_EXTENSIONS)
    {
        VstInt32 currentProgram;        ///< version 2: current program number
        char[124] future;               ///< reserved, should be zero
    }
    else
    {
        char[128] future;               ///< reserved, should be zero
    }

    union Content
    {
        fxProgram[1] programs;          ///< variable number of programs

        struct Data
        {
            VstInt32 size;              ///< size of bank data
            char[1] chunk;              ///< variable sized array with opaque bank data
        }

        Data data;                      ///< bank chunk data
    }

    Content content;                    ///< bank content depending on fxMagic
//-------------------------------------------------------------------------------------------------------
}
