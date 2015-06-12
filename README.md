# dplug [![Build Status](https://travis-ci.org/p0nce/dplug.png?branch=master)](https://travis-ci.org/p0nce/dplug)

[![Join the chat at https://gitter.im/p0nce/dplug](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/p0nce/gfm?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

dplug is a library for creating audio plugins.
Additionally it comes with music DSP algorithms that might be useful for your next-generation MS converter plugin.
**Currently only support VST 2.x plugins on Windows.**

**Tested compilers:** ![dmd-2.067.1](https://img.shields.io/badge/DMD-2.067.1-brightgreen.svg) ![dmd-2.066.1](https://img.shields.io/badge/DMD-2.066.1-brightgreen.svg) ![LDC-0.15.1](https://img.shields.io/badge/LDC-0.15.1-brightgreen.svg) ![GDC-4.9.2](https://img.shields.io/badge/GDC-4.9.2-brightgreen.svg)


## Contents

### dplug:plugin
  * Abstract plugin client interface. Currently implemented once for VST

### dplug:vst
  * VST SDK D bindings
  * VST plugin client

### dplug:dsp
  * The basics for audio signal processing:
    - FFT and windowing function (include STFT with tunable overlap and zero-phase windowing)
    - FIR and IIR biquads
    - mipmapped wavetables
    - noise generation
    - various kinds of smoothers and envelopes
    - delay-line

### dplug:gui
   * For plugins that have an UI.
   * Toolkit including common widgets
   * Deferred renderer for real-time procedural UI (lazy updates)

### Examples
   * An example distortion VST plugin
   * A program that resample x2 through FFT padding


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

Files in the dsp/ folder falls under the Boost 1.0 license.
Before you use it, you need to agree with https://github.com/p0nce/dplug/licenses/Boost_1.0.txt

