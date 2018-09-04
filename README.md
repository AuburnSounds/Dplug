<img alt="logo" src="https://cdn.rawgit.com/AuburnSounds/dplug/master/logo.svg" width="200">

# Dplug [![Build Status](https://travis-ci.org/AuburnSounds/Dplug.svg?branch=master)](https://travis-ci.org/AuburnSounds/Dplug) <a href="https://code.dlang.org/packages/dplug" title="Go to dplug"><img src="https://img.shields.io/dub/v/dplug.svg" alt="Dub version"></a> ![Dplug Discord server](https://discordapp.com/api/guilds/242094594181955585/widget.png?style=shield)

`Dplug` is a library for creating audio plug-ins as simply as possible. 

[Auto-generated documentation...](http://dplug.dpldocs.info/dplug.html)

**IMPORTANT To distribute VST2 plug-ins be sure to sign a VST2 Licence Agreement with Steinberg before October 2018.**

## Current features

- Creating VST 2.4 plug-ins for Windows, macOS, and Linux, for 32-bit and 64-bit
- Creating Audio Unit v2 plug-ins for Mac OS X, 32-bit and 64-bit
- Creating AAX Native plug-ins for Windows and Mac OS X, 64-bit only
- Comes with basic music DSP algorithms
- Comes with a number of `tools` to make plug-in authoring faster (bundling, color correction, regression tests, performance tests)
- Dplug is using (optional) [rendering](http://www.auburnsounds.com/blog/2016-09-16_PBR-for-Audio-Software-Interfaces.html) to keep installers small
- See the [list of supported hosts...](https://github.com/AuburnSounds/Dplug/wiki/Host-Support)


### Community and ecosystem

DPlug was successfully leveraged to build the following products:

- [Couture](https://www.auburnsounds.com/products/Couture.html) by Auburn Sounds
- [Entropy](http://www.modernmetalproduction.com/product/entropy-ii-enhanced-stereo-delay-vst-au/) by Cut Through Recordings
- [Graillon](https://www.auburnsounds.com/products/Graillon.html) by Auburn Sounds
- [M4 Multiband Compressor](http://www.modernmetalproduction.com/product/m4-multiband-compressor-vst-au/) by Cut Through Recordings
- [Panagement](https://www.auburnsounds.com/products/Panagement.html) by Auburn Sounds
- [Tarabia Distortion](http://smaolab.org/product/tarabia-distortion/) by SMAOLAB

Become one happy [DPlug contributor](https://github.com/AuburnSounds/Dplug/graphs/contributors) by submitting issues and pull-requests, and come talk with us on the [D Language Discord](https://discord.gg/QZtGZUw) to learn more and meet your peers DPlug users!

### Release notes

Keep up with major changes here: [Release Notes](https://github.com/AuburnSounds/Dplug/wiki/Release-notes)


## Tutorials

- [Getting Started](https://github.com/AuburnSounds/Dplug/wiki/Getting-Started)
- [Making a Windows VST plugin with D](https://auburnsounds.com/blog/2016-02-08_Making-a-Windows-VST-plugin-with-D.html) (outdated)


## FAQ

- Does Dplug support the creation of synthesizer plug-ins?

Yes. See simple-mono-synth example.

- Am I forced to use the PBR rendering system?

No. You can make [plug-ins with Dplug without using PBR](http://www.modernmetalproduction.com/product/m4-multiband-compressor-vst-au/). How it works is that the physical channel is just filled with 0. Doing that requires a set of custom widgets, which you can find in `dplug:flat-widgets`.


- What is the oldest supported Windows version?

Windows Vista. Windows XP isn't officially supported by D compilers.


- What is the oldest supported OS X version?

OS X 10.8+.

- What D compiler can possibly be used?

   See `.travis.yml` for supported compilers. The latest DMD or LDC should do.

- What D compilers are recommended?

   For releases it is highly recommended that you use LDC >= 1.8.
   When in development you can use DMD for faster compilation times. 

- Is Dplug stable?

Dplug now has excellent stability.

Dplug documents its breaking changes in the [Changelog](https://github.com/AuburnSounds/Dplug/wiki/) and
issues major SemVer tags for breaking changes.

If you don't want breaking changes, you can pin Dplug to a major version in your `dub.json`.

But reality is complex, and bug fixes can be breaking too, (eg: "highpass FIR wasn't working").
In which case we have to make a judgment call as to whether it's a breaking fix, and whether the buggy feature was used.

Breaking commits, when they happen, are marked with BREAKING in the commit backlog.
They are always discussed on Discord.

- Will you add feature X?

You have to understand that Dplug is a part-time operation, from people who spend much more time working on and releasing plug-ins.

Dplug is there to support existing products and building companies around them, not to be beta software and make empty promises. 
Being stable and bug-free is much more important to us than implementing every possible feature.

Politically, it's very often than enhancements get postponed in favour of product development, so please be patient!

We're looking for ways to improve governance as more contributors have appeared with contrasted agendas.


- Where do I start?

Be sure to read the [Wiki](https://github.com/AuburnSounds/Dplug/wiki/) in depth.


## Comparison vs IPlug

Pros:
  - No dispatcher-wide mutex lock. All locks are of a short duration, to avoid blocking the audio thread.
  - Plugin parameters implement the Observer pattern.
  - Float parameters can have user-defined mapping.
  - PBR-style rendering lets you have a good visual quality with less disk space.
  - No need to deal with resource compilers: D can `import("filename.ext")` them.
  - No need to maintain IDE project files, they are generated by DUB.
    eg: `dub generate visuald` or `dub generate sublimetext`
  - No need to make Info.plist files, they are generated by `dplug-build`.
  - No need to use Xcode whatsoever.
  - No need to use a macOS SDK.
  - Easy to install: DUB will download the library itself when building, a <= 3mb archive.
  - 10x less lines of code than the next larger alternative.

Cons:
  - VST3 not yet implemented
  - No resizeable UI
  - No HDPI support
  - No modal windows
  - Latest IPlug has separated graphics from windowing

## Licenses

Dplug has different licenses depending on the sub-package you need.
Please check individual source files for license information.

### Plugin format wrapping

Plugin wrapping is inspired by the WDL library (best represented here: https://github.com/olilarkin/wdl-ol).

Some files falls under the Cockos WDL license.

Important contributors to WDL include:
- Cockos: http://www.cockos.com/
- Oliver Larkin: http://www.olilarkin.co.uk/


### VST SDK translation

This sub-package falls under the Steinberg VST license.

VST is a trademark of Steinberg Media Technologies GmbH.
Please register the SDK via the 3rd party developer license on Steinberg site.

Before you make VST plugins with Dplug, you need to read and agree with the license for the VST3 SDK by Steinberg.
**If you don't agree with the VST SDK license, you can't make plugins with Dplug.**
Find the VST3 SDK there: http://www.steinberg.net/en/company/developers.html

### Misc

Other source files fall under the Boost 1.0 license.


## Contents of the tree

### dplug:client
  * Abstract plugin client interface. Currently implemented for VST and AU.

### dplug:host
  * Abstract plugin host interface. Basic support for VST hosting.

### dplug:vst
  * VST 2.4 plugin client implementation

### dplug:au
  * Audio Unit v2 plugin client implementation

### dplug:window
  * implements windowing for Win32, X11, Cocoa and Carbon

### dplug:gui
   * Needed for plugins that do have an UI
   * Toolkit includes common widgets (knob, slider, switch, logo, level, label...)
   * Physically Based Renderer for a fully procedural UI

### dplug:dsp
  * Basic support for audio processing:
    - Real and Complex FFT, windowing functions (STFT with overlap and zero-phase windowing)
    - FIR, 1st order IIR filters and RBJ biquads
    - mipmapped wavetables for antialiased oscillators
    - noise generation including white/pink/demo noise
    - various kinds of smoothers and envelopes
    - delay-line and interpolation

### dplug:derelict-nogc
   * Enables dynamic library loading without using the D runtime

### dplug:carbon
   * Dynamic Carbon bindings

### dplug:cocoa
   * Dynamic Cocoa bindings

### dplug:x11
   * Static X11 bindings

### dplug-aax (external repositery, see Wiki)
   * AAX Native and AAX AudioSuite plugin client implementation

