# What's this?

dplug is an audio package that aims to allow the creation of audio plugins. 
Currently very alpha.


## License

VST is a trademark of Steinberg Media Technologies GmbH. Please register the SDK via the 3rd party developper license on Steinberg site.

Before you code with dplug, you need to read and agree with the license for the original SDK by Steinberg. If you don't agree with the license, don't make plugins with dplug.



## Contents

### plugin/
  * **iplug.d.d** base plugin interface, format agnostic (not done yet)
  * **dllmain.d** shared library entry point

### vst/
  * **aeffect.d** VST SDK translation of aeffect.h
  * **aeffectx.d** VST SDK translation of aeffectx.h
  * **plugin.d** VST wrapper (not done yet)

### dsp/
  * **funcs.d** useful audio DSP functions
  * **fft.d** FFT and short term FFT analyzer with tunable overlap and zero-phase windowing
  * **fir.d** dealing with impulses
  * **wavetable.d** basic anti-aliased waveform generation through mipmapped wavetables
  * **iir.d** biquad filters  
  * **noise.d** white noise, demo noise, 1D perlin noise
  * **smooth.d** different kinds of smoothers, including non-linear ones
  * **envelope.d** power and amplitude estimators
  * **window.d** typical windowing functions
