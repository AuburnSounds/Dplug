# dplug [![Build Status](https://travis-ci.org/p0nce/dplug.png?branch=master)](https://travis-ci.org/p0nce/dplug)

[![Join the chat at https://gitter.im/p0nce/dplug](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/p0nce/gfm?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

dplug is a library for creating audio plugins.
Additionally it comes with music DSP algorithms that might be useful for your next-generation MS converter plugin.
**Currently only support VST 2.x plugins on Windows.**

**Tested compilers:** ![dmd-2.067.1](https://img.shields.io/badge/DMD-2.067.1-brightgreen.svg) ![dmd-2.066.1](https://img.shields.io/badge/DMD-2.066.1-brightgreen.svg) ![LDC-0.15.1](https://img.shields.io/badge/LDC-0.15.1-brightgreen.svg) ![GDC-4.9.2](https://img.shields.io/badge/GDC-4.9.2-brightgreen.svg)

![Mandatory distortion example](screenshot.jpg "Mandatory distortion example")

## Contents

### dplug:plugin
  * Abstract plugin client interface. Currently implemented once for VST.

### dplug:vst
  * VST SDK D bindings
  * VST plugin client

### dplug:dsp
  * Basic support for audio processing:
    - FFT and windowing functions (include STFT with tunable overlap and zero-phase windowing)
    - FIR and RJB biquads (no higher order IIR sorry)
    - mipmapped wavetables for antialiased oscillators
    - noise generation including white/pink/demo noise
    - various kinds of smoothers and envelopes
    - delay-line and interpolation

### dplug:gui
   * Needed for plugins that do have an UI
   * Toolkit includes common widgets (knob/slider/switch)
   * Deferred renderer for a fully procedural UI (updates are lazy)

### Examples
   * Mandatory example: distortion VST plugin
   * Resampling x2 through FFT zero-padding


## Licenses

dplug has three different licenses depending on the part you need. 
For an audio plugin, you would typically need all three.

### dplug:plugin

Plugin wrapping is heavily inspired by the IPlug library (best represented here: https://github.com/olilarkin/wdl-ol).
Files in the plugin/ folder falls under the Cockos WDL license.
So before you wrap audio plugins with dplug, you need to agree with the following license: 
https://github.com/p0nce/dplug/blob/master/licenses/WDL_license.txt

A significant difference compared to IPlug/WDL wrapper is that no global plugin lock is ever taken.

### dplug:vst

This sub-package falls under the Steinberg VST license.

VST is a trademark of Steinberg Media Technologies GmbH.
Please register the SDK via the 3rd party developper license on Steinberg site.

Before you make VST plugins with dplug, you need to read and agree with the license for the VST3 SDK by Steinberg.
If you don't agree with the license, don't make plugins with dplug.
Find the VST3 SDK there: http://www.steinberg.net/en/company/developers.html

### dplug:gui, dplug:dsp

These sub-packages fall under the Boost 1.0 license.
Before you use it, you need to agree with https://github.com/p0nce/dplug/licenses/Boost_1.0.txt

