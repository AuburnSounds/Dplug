<img alt="logo" src="https://cdn.rawgit.com/AuburnSounds/dplug/master/logo.svg" width="200">

# Dplug [![Build Status](https://travis-ci.org/AuburnSounds/Dplug.svg?branch=master)](https://travis-ci.org/AuburnSounds/Dplug) <a href="https://code.dlang.org/packages/dplug" title="Go to dplug"><img src="https://img.shields.io/dub/v/dplug.svg" alt="Dub version"></a>

`Dplug` is a library for creating audio plug-ins as simply as possible. [Come talk with us!](https://discord.gg/QZtGZUw) if you want to learn more.


## Current features

- Creating VST 2.4 plug-ins for Windows, macOS, and Linux, for 32-bit and 64-bit
- Creating Audio Unit v2 plug-ins for Mac OS X, 32-bit and 64-bit
- Creating AAX Native plug-ins for Windows and Mac OS X, 32-bit and 64-bit
- Comes with basic music DSP algorithms
- Comes with a number of `tools` to make plug-in authoring faster (bundling, color correction, regression tests, performance tests)
- Dplug is using (optional) rendering to keep installers small: http://www.auburnsounds.com/blog/2016-09-16_PBR-for-Audio-Software-Interfaces.html though you're not forced to use it.

### Products made with Dplug

- [Entropy by Cut Through Recordings](http://www.modernmetalproduction.com/product/entropy-ii-enhanced-stereo-delay-vst-au/)
- [Graillon by Auburn Sounds](https://www.auburnsounds.com/products/Graillon.html)
- [M4 Multiband Compressor by Cut Through Recordings](http://www.modernmetalproduction.com/product/m4-multiband-compressor-vst-au/)
- [Panagement by Auburn Sounds](https://www.auburnsounds.com/products/Panagement.html)


### Release notes

Read about major changes here: https://github.com/AuburnSounds/dplug/wiki/Release-notes


## Tutorials

- https://github.com/AuburnSounds/dplug/wiki/Getting-Started
- https://auburnsounds.com/blog/2016-02-08_Making-a-Windows-VST-plugin-with-D.html (outdated)



## How to build plug-ins

### For Windows:
- Install DMD or LDC.
- (optional) Install DUB, the D package manager: http://code.dlang.org/download
- Go into an example directory
- Type `dub --compiler=dmd` or `dub --compiler=ldc2` depending on the desired compiler.

### For OS X:
- Install DMD or LDC.
- (optional) Install DUB, the D package manager: http://code.dlang.org/download
- Build and use the `dplug-build` tool which is in the `tools/dplug-build/` directory.
- `sudo ln -s /path/to/Dplug/tools/dplug-build/dplug-build /usr/local/bin/dplug-build`
- Go into an example directory
- Type `dplug-build --compiler dmd` or `dplug-build --compiler ldc` depending on the desired compiler.


## FAQ

- Does Dplug support the creation of synthesizer plug-ins?

Yes. See simple-mono-synth example.

- Am I forced to use the PBR graphics system?

No. There are people making [plug-ins with Dplug without using PBR](http://www.modernmetalproduction.com/product/m4-multiband-compressor-vst-au/). How it works is that the physical channel is just filled with 0. Doing that requires a set of custom widgets, which you can find in `dplug:flat-widgets`.

- How do I build plugins for OS X?

You need to use the `dplug-build` program in the `tools`directory.
This tool creates Mac bundles and Universal Binaries as needed.
Like most D programs, you can build it by typing `dub`.

- What is the oldest supported Windows version?

Windows Vista. Users report plug-ins made with both DMD and LDC work on Windows XP. But XP isn't officially supported by D compilers.

- What is the oldest supported OS X version?

OS X 10.8+.

- What D compiler can possibly be used?

   See `.travis.yml` for supported compilers. The latest DMD or LDC should do.

- What D compilers are recommended?

   For both macOS and Windows it is recommended that you use LDC 1.2 or later.

- Is Dplug stable?

Starting with v5 we'll have issue major or minor version tag for breaking changes.
If you don't want breaking change, you can pin Dplug to a specific version in your `dub.json`.
Breaking commits are marked with BREAKING in the commit backlog.
They are always discussed on Discord before-hand.

- Will you add feature X?

You have to understand that Dplug is a part-time operation, from people who spend much more time working on and releasing plug-ins.

Dplug is there to support existing products and building companies around them, not to be beta software. Being stable and bug-free is much more important to us than implementing every possible feature.

If you have money to sponsor some sanctionned feature it can definately help though.

- Where do I start?

Be sure to read the [Wiki](https://github.com/AuburnSounds/dplug/wiki/) in depth.


## Comparison vs IPlug

Pros:
  - No dispatcher-wide mutex lock. All locks are of a short duration, to avoid blocking the audio thread.
  - Buffer splitting: ensure your plugin never receive a buffer larger than N samples, and the corresponding MIDI input. This helps with memory consumption for the largest buffer sizes.
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

## Licenses

Dplug has three different licenses depending on the part you need.
For an audio plugin, you would typically need all three.
I recommend that you check individual source files for license information.

### Plugin format wrapping

Plugin wrapping is inspired by the WDL library (best represented here: https://github.com/olilarkin/wdl-ol).

Some files falls under the Cockos WDL license.

Important contributors to WDL include:
- Cockos: http://www.cockos.com/
- Oliver Larkin: http://www.olilarkin.co.uk/

However Dplug is **far** from a translation of WDL (see FAQ).


### VST SDK translation

This sub-package falls under the Steinberg VST license.

VST is a trademark of Steinberg Media Technologies GmbH.
Please register the SDK via the 3rd party developper license on Steinberg site.

Before you make VST plugins with Dplug, you need to read and agree with the license for the VST3 SDK by Steinberg.
**If you don't agree with the VST SDK license, don't make plugins with Dplug.**
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

