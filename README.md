# What's this?

dplug is an audio package that aims to allow the creation of audio plugins. 
Currently very alpha.


## License

VST is a trademark of Steinberg Media Technologies GmbH. Please register the SDK via the 3rd party developper license on Steinberg site.

Before you code with dplug, you need to read and agree with the license for the original SDK by Steinberg. If you don't agree with the license, don't make plugins with dplug.



## Contents

### plugin/
  * **iplug.d.d** base plugin interface, format agnostic
  * **dllmain.d** shared library entry point

### vst/
  * **aeffect.d** VST SDK translation of aeffect.h
  * **aeffectx.d** VST SDK translation of aeffectx.h
  * **plugin.d** VST wrapper
