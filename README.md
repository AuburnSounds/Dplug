# What's this?

dplug is a library that allow the creation of audio plugins. 
Additionally it comes with music DSP algorithms that might be useful for your next-generation MS converter plugin.
**Currently only support VST 2.4 plugins without GUI.**

## Contents

### plugin/
  * **client.d.d** client plugin interface, used by client wrappers.
  * **dllmain.d** shared library entry point.
  * **spinlock.d** spinlock, spinlock protected value, spinlock protected queue.
  * **daw.d** known plugin hosts.

### vst/
  * **aeffect.d** VST SDK translation of aeffect.h.
  * **aeffectx.d** VST SDK translation of aeffectx.h.
  * **vstfxstore.d** VST SDK translation of vstfxstore.h.
  * **client.d** VST plugin client.

### dsp/
  * **funcs.d** useful audio DSP functions.
  * **fft.d** FFT and short term FFT analyzer with tunable overlap and zero-phase windowing.
  * **fir.d** dealing with impulses.
  * **wavetable.d** basic anti-aliased waveform generation through mipmapped wavetables.
  * **iir.d** biquad filters.
  * **noise.d** white noise, demo noise, 1D perlin noise.
  * **smooth.d** different kinds of smoothers, including non-linear ones.
  * **envelope.d** power and amplitude estimators.
  * **window.d** typical windowing functions.
  * **goldrabiner.d** low-latency speech pitch estimation.
  * **delayline.d** interpolated delay-line.

## Licenses

dplug has 3 different licenses depending on the part you need.

### Plugin wrapper

Plugin wrapping is heavily inspired by the IPlug library (best represented here: https://github.com/olilarkin/wdl-ol).
Files in the plugin/ folder falls under the Cockos WDL license.
So before you wrap audio plugins with dplug, you need to agree with https://github.com/p0nce/dplug/licenses/WDL_license.txt

### VST interface

Files in the vst/ folder falls under the Steinberg VST license.

VST is a trademark of Steinberg Media Technologies GmbH. 
Please register the SDK via the 3rd party developper license on Steinberg site.

Before you make VST plugins with dplug, you need to read and agree with the license for the original SDK by Steinberg. 
A copy is available here: http://www.gersic.com/vstsdk/html/plug/intro.html#licence
If you don't agree with the license, don't make plugins with dplug.

### Audio DSP algorithms

Files in the dsp/ folder falls under the Unlicense license (public domain).
You can do whatever you want with it.
