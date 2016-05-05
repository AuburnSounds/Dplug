#define PLUG_MFR "WittyAudio"


// TODO: this should be set by release tool by reading the plugin.json keys (from CT)
#define PLUG_IS_INST 0
#define PLUG_DOES_MIDI 0

#define UseExtendedThingResource 1
#include <CoreServices/CoreServices.r>


// this is a define used to indicate that a component has no static data that would mean
// that no more than one instance could be open at a time - never been true for AUs
#ifndef cmpThreadSafeOnMac
#define cmpThreadSafeOnMac  0x10000000
#endif

#undef  TARGET_REZ_MAC_X86
#if defined(__i386__) || defined(i386_YES)
  #define TARGET_REZ_MAC_X86        1
#else
  #define TARGET_REZ_MAC_X86        0
#endif

#undef  TARGET_REZ_MAC_X86_64
#if defined(__x86_64__) || defined(x86_64_YES)
  #define TARGET_REZ_MAC_X86_64     1
#else
  #define TARGET_REZ_MAC_X86_64     0
#endif

#if TARGET_OS_MAC
  #if TARGET_REZ_MAC_X86 && TARGET_REZ_MAC_X86_64
    #define TARGET_REZ_FAT_COMPONENTS_2 1
    #define Target_PlatformType     platformIA32NativeEntryPoint
    #define Target_SecondPlatformType platformX86_64NativeEntryPoint
  #elif TARGET_REZ_MAC_X86
    #define Target_PlatformType     platformIA32NativeEntryPoint
  #elif TARGET_REZ_MAC_X86_64
    #define Target_PlatformType     platformX86_64NativeEntryPoint
  #else
    #error you gotta target something
  #endif
  #define Target_CodeResType    'dlle'
  #define TARGET_REZ_USE_DLLE   1
#else
  #error get a real platform type
#endif // not TARGET_OS_MAC

#ifndef TARGET_REZ_FAT_COMPONENTS_2
  #define TARGET_REZ_FAT_COMPONENTS_2   0
#endif

enum
{
  kAudioUnitType_MusicDevice        = 'aumu',
  kAudioUnitType_MusicEffect        = 'aumf',
  kAudioUnitType_Effect             = 'aufx',
  kAudioUnitCarbonViewComponentType = 'auvw',
};

#define componentDoAutoVersion             0x01
#define componentHasMultiplePlatforms      0x08

#define RES_NAME PLUG_MFR ": " PLUG_NAME

resource 'STR ' (1000, purgeable) {
  RES_NAME
};

resource 'STR ' (1000 + 1, purgeable) {
  PLUG_NAME " AU"
};

resource 'dlle' (1000) {
  "dplugAUEntryPoint"
};

resource 'thng' (1000, RES_NAME) {
#if PLUG_IS_INST
kAudioUnitType_MusicDevice,
#elif PLUG_DOES_MIDI
kAudioUnitType_MusicEffect,
#else
kAudioUnitType_Effect,
#endif
  PLUG_UNIQUE_ID,
  PLUG_MFR_ID,
  0, 0, 0, 0,               //  no 68K
  'STR ', 1000,
  'STR ', 1000 + 1,
  0,  0,      // icon
  PLUG_VER,
  componentHasMultiplePlatforms | componentDoAutoVersion,
  0,
  {
    cmpThreadSafeOnMac,
    Target_CodeResType, 1000,
    Target_PlatformType,

#if TARGET_REZ_FAT_COMPONENTS_2
    cmpThreadSafeOnMac,
    Target_CodeResType, 1000,
    Target_SecondPlatformType,
#endif
  }
};

#if TARGET_REZ_MAC_X86

#define RES_ID 2000

#undef RES_NAME
#define RES_NAME PLUG_MFR ": " PLUG_NAME " Carbon View"


resource 'STR ' (2000, purgeable) {
  RES_NAME
};

resource 'STR ' (2000 + 1, purgeable) {
  PLUG_NAME " AU Carbon View"
};

resource 'dlle' (2000) {
  "dplugAUCarbonViewEntryPoint"
};

resource 'thng' (2000, RES_NAME) {
  kAudioUnitCarbonViewComponentType,
  PLUG_UNIQUE_ID,
  PLUG_MFR_ID,
  0, 0, 0, 0,               //  no 68K
  'STR ', 2000,
  'STR ', 2000 + 1,
  0,  0,      // icon
  PLUG_VER,
  componentHasMultiplePlatforms | componentDoAutoVersion,
  0,
  {
    cmpThreadSafeOnMac,
    Target_CodeResType, 2000,
    Target_PlatformType,

#if TARGET_REZ_FAT_COMPONENTS_2
    cmpThreadSafeOnMac,
    Target_CodeResType, 2000,
    Target_SecondPlatformType,
#endif
  }
};

#endif // TARGET_REZ_MAC_X86

