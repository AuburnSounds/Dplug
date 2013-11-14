//-------------------------------------------------------------------------------------------------------
// VST Plug-Ins SDK
// Version 2.4      $Date: 2006/06/20 17:22:55 $
//
// Category     : VST 2.x Interfaces
// Filename     : aeffect.d
// Created by   : Steinberg Media Technologies
// Description  : Definition of AEffect structure
//
// (c) 2006, Steinberg Media Technologies, All Rights Reserved
//-------------------------------------------------------------------------------------------------------

module dplug.vst.aeffect;

//import core.stdc.stdio; // for strncpy
import core.stdc.string; // for strncpy

/** Define SDK Version (you can generate different versions (from 2.0 to 2.4) of this SDK by unsetting the unwanted extensions). */

version = VST_2_1_EXTENSIONS; /// Version 2.1 extensions (08-06-2000)
version = VST_2_2_EXTENSIONS; /// Version 2.2 extensions (08-06-2001)
version = VST_2_3_EXTENSIONS; /// Version 2.3 extensions (20-05-2003)
version = VST_2_4_EXTENSIONS; /// Version 2.4 extensions (01-01-2006)

/** Current VST Version */
version(VST_2_4_EXTENSIONS)
    enum kVstVersion = 2400;
else version(VST_2_3_EXTENSIONS)
    enum kVstVersion = 2300;
else version(VST_2_2_EXTENSIONS)
    enum kVstVersion = 2200;
else version(VST_2_1_EXTENSIONS)
    enum kVstVersion = 2100;
else
    enum kVstVersion = 2;

/** Define for 64 Bit Platform. */
static if((void*).sizeof == 8) 
{
    version = VST_64BIT_PLATFORM;
}

//-------------------------------------------------------------------------------------------------------
// Integral Types
//-------------------------------------------------------------------------------------------------------
alias short VstInt16;
alias int VstInt32;
alias long VstInt64;
alias ptrdiff_t VstIntPtr;

alias extern(C) nothrow VstIntPtr function(AEffect* effect, VstInt32 opcode, VstInt32 index, VstIntPtr value, void* ptr, float opt) AEffectDispatcherProc;
alias extern(C) nothrow VstIntPtr function(AEffect* effect, VstInt32 opcode, VstInt32 index, VstIntPtr value, void* ptr, float opt) HostCallbackFunction;
alias extern(C) nothrow void function(AEffect* effect, float** inputs, float** outputs, VstInt32 sampleFrames) AEffectProcessProc;
alias extern(C) nothrow void function(AEffect* effect, double** inputs, double** outputs, VstInt32 sampleFrames) AEffectProcessDoubleProc;
alias extern(C) nothrow void function(AEffect* effect, VstInt32 index, float parameter) AEffectSetParameterProc;
alias extern(C) nothrow float function(AEffect* effect, VstInt32 index) AEffectGetParameterProc;

/** Four Character Constant (for AEffect->uniqueID) */
int CCONST(int a, int b, int c, int d)
{
    return (a << 24) | (b << 16) | (c << 8) | (d << 0);
 }

/** AEffect magic number */
enum kEffectMagic = CCONST('V', 's', 't', 'P');

/// Basic VST Effect "C" Interface.
align(8) struct AEffect
{
    VstInt32 magic;         ///< must be #kEffectMagic ('VstP')

    /** Host to Plug-in dispatcher @see AudioEffect::dispatcher */
    AEffectDispatcherProc dispatcher;
    
    /** \deprecated Accumulating process mode is deprecated in VST 2.4! Use AEffect::processReplacing instead! */
    AEffectProcessProc DEPRECATED_process;
    
    /** Set new value of automatable parameter @see AudioEffect::setParameter */
    AEffectSetParameterProc setParameter;

    /** Returns current value of automatable parameter @see AudioEffect::getParameter*/
    AEffectGetParameterProc getParameter;

    VstInt32 numPrograms;   ///< number of programs
    VstInt32 numParams;     ///< all programs are assumed to have numParams parameters
    VstInt32 numInputs;     ///< number of audio inputs
    VstInt32 numOutputs;    ///< number of audio outputs

    VstInt32 flags;         ///< @see VstAEffectFlags
    
    VstIntPtr resvd1;       ///< reserved for Host, must be 0
    VstIntPtr resvd2;       ///< reserved for Host, must be 0
    
    VstInt32 initialDelay;  ///< for algorithms which need input in the first place (Group delay or latency in Samples). This value should be initialized in a resume state.
    
    VstInt32 DEPRECATED_realQualities;    ///< \deprecated unused member
    VstInt32 DEPRECATED_offQualities;     ///< \deprecated unused member
    float    DEPRECATED_ioRatio;          ///< \deprecated unused member

    void* object;           ///< #AudioEffect class pointer
    void* user;             ///< user-defined pointer

    VstInt32 uniqueID;      ///< registered unique identifier (register it at Steinberg 3rd party support Web). This is used to identify a plug-in during save+load of preset and project.
    VstInt32 version_;       ///< plug-in version (example 1100 for version 1.1.0.0)

    /** Process audio samples in replacing mode @see AudioEffect::processReplacing */
    AEffectProcessProc processReplacing;

    version(VST_2_4_EXTENSIONS)
    {
        /** Process double-precision audio samples in replacing mode @see AudioEffect::processDoubleReplacing */
        AEffectProcessDoubleProc processDoubleReplacing;
        
        char[56] future;        ///< reserved for future use (please zero)
    }
    else
    {
        char[60] future;        ///< reserved for future use (please zero)
    }
}

/// AEffect flags
alias int VstAEffectFlags;
enum : VstAEffectFlags
{
    effFlagsHasEditor     = 1 << 0,         /// set if the plug-in provides a custom editor
    effFlagsCanReplacing  = 1 << 4,         /// supports replacing process mode (which should the default mode in VST 2.4)
    effFlagsProgramChunks = 1 << 5,         /// program data is handled in formatless chunks
    effFlagsIsSynth       = 1 << 8,         /// plug-in is a synth (VSTi), Host may assign mixer channels for its outputs
    effFlagsNoSoundInStop = 1 << 9,         /// plug-in does not produce sound when input is all silence

    DEPRECATED_effFlagsHasClip = 1 << 1,          /// deprecated in VST 2.4
    DEPRECATED_effFlagsHasVu   = 1 << 2,          /// deprecated in VST 2.4
    DEPRECATED_effFlagsCanMono = 1 << 3,          /// deprecated in VST 2.4
    DEPRECATED_effFlagsExtIsAsync   = 1 << 10,    /// deprecated in VST 2.4
    DEPRECATED_effFlagsExtHasBuffer = 1 << 11     /// deprecated in VST 2.4
}

version(VST_2_4_EXTENSIONS)
{
    enum : VstAEffectFlags
    {
        effFlagsCanDoubleReplacing = 1 << 12,   ///< plug-in supports double precision processing (VST 2.4)
    }
}


/// Basic dispatcher Opcodes (Host to Plug-in) */
alias int AEffectOpcodes;
enum : AEffectOpcodes
{
    effOpen = 0,        ///< no arguments  @see AudioEffect::open
    effClose,           ///< no arguments  @see AudioEffect::close

    effSetProgram,      ///< [value]: new program number  @see AudioEffect::setProgram
    effGetProgram,      ///< [return value]: current program number  @see AudioEffect::getProgram
    effSetProgramName,  ///< [ptr]: char* with new program name, limited to #kVstMaxProgNameLen  @see AudioEffect::setProgramName
    effGetProgramName,  ///< [ptr]: char buffer for current program name, limited to #kVstMaxProgNameLen  @see AudioEffect::getProgramName
    
    effGetParamLabel,   ///< [ptr]: char buffer for parameter label, limited to #kVstMaxParamStrLen  @see AudioEffect::getParameterLabel
    effGetParamDisplay, ///< [ptr]: char buffer for parameter display, limited to #kVstMaxParamStrLen  @see AudioEffect::getParameterDisplay
    effGetParamName,    ///< [ptr]: char buffer for parameter name, limited to #kVstMaxParamStrLen  @see AudioEffect::getParameterName
    
    DEPRECATED_effGetVu,  ///< \deprecated deprecated in VST 2.4

    effSetSampleRate,   ///< [opt]: new sample rate for audio processing  @see AudioEffect::setSampleRate
    effSetBlockSize,    ///< [value]: new maximum block size for audio processing  @see AudioEffect::setBlockSize
    effMainsChanged,    ///< [value]: 0 means "turn off", 1 means "turn on"  @see AudioEffect::suspend @see AudioEffect::resume

    effEditGetRect,     ///< [ptr]: #ERect** receiving pointer to editor size  @see ERect @see AEffEditor::getRect
    effEditOpen,        ///< [ptr]: system dependent Window pointer, e.g. HWND on Windows  @see AEffEditor::open
    effEditClose,       ///< no arguments @see AEffEditor::close

    DEPRECATED_effEditDraw,   ///< \deprecated deprecated in VST 2.4
    DEPRECATED_effEditMouse,  ///< \deprecated deprecated in VST 2.4
    DEPRECATED_effEditKey,    ///< \deprecated deprecated in VST 2.4

    effEditIdle,        ///< no arguments @see AEffEditor::idle
    
    DEPRECATED_effEditTop,    ///< \deprecated deprecated in VST 2.4
    DEPRECATED_effEditSleep,  ///< \deprecated deprecated in VST 2.4
    DEPRECATED_effIdentify,   ///< \deprecated deprecated in VST 2.4
    
    effGetChunk,        ///< [ptr]: void** for chunk data address [index]: 0 for bank, 1 for program  @see AudioEffect::getChunk
    effSetChunk,        ///< [ptr]: chunk data [value]: byte size [index]: 0 for bank, 1 for program  @see AudioEffect::setChunk
 
    effNumOpcodes       
}

/// Basic dispatcher Opcodes (Plug-in to Host)
alias int AudioMasterOpcodes;
enum : AudioMasterOpcodes
{
    audioMasterAutomate = 0,    ///< [index]: parameter index [opt]: parameter value  @see AudioEffect::setParameterAutomated
    audioMasterVersion,         ///< [return value]: Host VST version (for example 2400 for VST 2.4) @see AudioEffect::getMasterVersion
    audioMasterCurrentId,       ///< [return value]: current unique identifier on shell plug-in  @see AudioEffect::getCurrentUniqueId
    audioMasterIdle,            ///< no arguments  @see AudioEffect::masterIdle
    DEPRECATED_audioMasterPinConnected ///< \deprecated deprecated in VST 2.4 r2
}

/// String length limits (in characters excl. 0 byte)
enum VstStringConstants
{
    kVstMaxProgNameLen   = 24,  ///< used for #effGetProgramName, #effSetProgramName, #effGetProgramNameIndexed
    kVstMaxParamStrLen   = 8,   ///< used for #effGetParamLabel, #effGetParamDisplay, #effGetParamName
    kVstMaxVendorStrLen  = 64,  ///< used for #effGetVendorString, #audioMasterGetVendorString
    kVstMaxProductStrLen = 64,  ///< used for #effGetProductString, #audioMasterGetProductString
    kVstMaxEffectNameLen = 32   ///< used for #effGetEffectName
}


/// String copy taking care of null terminator.
char* vst_strncpy (char* dst, const char* src, size_t maxLen)
{
    char* result = strncpy (dst, src, maxLen);
    dst[maxLen] = 0;
    return result;
}

//-------------------------------------------------------------------------------------------------------
/** String concatenation taking care of null terminator. */
//-------------------------------------------------------------------------------------------------------
char* vst_strncat (char* dst, const char* src, size_t maxLen)
{
    char* result = strncat (dst, src, maxLen);
    dst[maxLen] = 0;
    return result;
}

//-------------------------------------------------------------------------------------------------------
/** Cast #VstIntPtr to pointer. */
//-------------------------------------------------------------------------------------------------------
T* FromVstPtr(T)(VstIntPtr arg)
{
    T** address = cast(T**)&arg;
    return *address;
}

//-------------------------------------------------------------------------------------------------------
/** Cast pointer to #VstIntPtr. */
//-------------------------------------------------------------------------------------------------------
VstIntPtr ToVstPtr(T)(T* ptr)
{
    VstIntPtr* address = cast(VstIntPtr*)&ptr;
    return *address;
}

/// Structure used for #effEditGetRect.
struct ERect
{
    VstInt16 top;       ///< top coordinate
    VstInt16 left;      ///< left coordinate
    VstInt16 bottom;    ///< bottom coordinate
    VstInt16 right;     ///< right coordinate
}

