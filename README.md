# What's this?

dplug is an audio package that aims to allow the creation of audio plugins. 
Currently very alpha.


## License

The VST SDK translation follow the original Steinberg VST license. 
If using the VST wrapper, you must agree to this license.

The rest of the repositery is public domain (Unlicense).


## Contents

### plugin/
  * **iplug.d.d** base plugin interface, format agnostic
  * **dllmain.d** shared library entry point

### vst/
  * **aeffect.d** VST SDK translation of aeffect.h
  * **aeffectx.d** VST SDK translation of aeffectx.h
  * **plugin.d** VST wrapper
