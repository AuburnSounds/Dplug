<img alt="logo" src="https://cdn.rawgit.com/AuburnSounds/dplug/master/logo.svg" width="200">

# Dplug [![Build Status](https://travis-ci.org/AuburnSounds/dplug.png?branch=master)](https://travis-ci.org/AuburnSounds/dplug) <a href="https://code.dlang.org/packages/dplug" title="Go to dplug"><img src="https://img.shields.io/dub/v/dplug.svg" alt="Dub version"></a> 

`Dplug` is a library for crafting audio plugins as simply as possible. [Come talk with us!](https://discord.gg/QZtGZUw) if you want to learn more.


## Current features

- Creating VST 2.4 plugins on Windows Vista or later, and Mac OS X 10.7 or later, 32-bit and 64-bit
- Creating Audio Unit v2 plugins for Mac OS X, 32-bit and 64-bit
- Comes with basic music DSP algorithms
- Comes with a number of `tools` to make plugin creation faster (bundling, color correction, regression tests, performance tests)
- Dplug is using Physically Based Rendering to keep installers small: http://www.auburnsounds.com/blog/2016-09-16_PBR-for-Audio-Software-Interfaces.html

### Products made with Dplug

- [Panagement](https://www.auburnsounds.com/products/Panagement.html)
- [Graillon](https://www.auburnsounds.com/products/Graillon.html)


### Release notes

- v4.x.y (2nd Nov 2016)
  * macOS Sierra support fixed.
  * To allow that, the D runtime is now linked with but disabled. No GC, no TLS, no global ctor/dtor.

- v3.x.y (9th May 2016):
  * Audio Unit compatibility added, with both Cocoa and Carbon UI. What is still missing from AU: Audio Component API, sandboxing, v3. In other words it's on parity with IPlug but not JUCE.
  * The `release` tool is now much more friendly to use.
  * Special keys in `dub.json` are now expected in a `plugin.json` file next to dub.json. In the future it will be the place of autority for information about a plugin, for now this has to be duplicated in `buildPluginInfo()` override. An empty `plugin.json` is OK, defaults are in place. This file is consumed by the `release` tool.
  * The Wiki became a place to visit.

- v2.x.y: (6th January 2016)
  * `release` tool now expects a VST or AU configuration, see the `distort` example for details
  * special `dub.json` key `CFBundleIdentifier` became `CFBundleIdentifierPrefix`, see how `distort` works to update your plugins dub.json
  * 10.6 compatibility dropped.

- v1.x.y: (26th May 2015)
  * initial release, VST support for 32-bit and 64-bit, Windows and Mac



## Tutorial

https://auburnsounds.com/blog/2016-02-08_Making-a-Windows-VST-plugin-with-D.html (This tutorial is a bit outdated)



## How to build plugins

### For Windows:
- Use DMD >= v2.070 or LDC >= v1.0.0-b2
- Install DUB, the D package manager: http://code.dlang.org/download
- Go into an example directory
- Type `dub --compiler=dmd` or `dub --compiler=ldc2` depending on the compiler used.

### For OS X:
- Use DMD >= v2.070 or LDC >= v1.0.0-b2
- Install DUB, the D package manager: http://code.dlang.org/download
- Build and use the `release` tool which is in the `tools/release/` directory.
- Go into an example directory
- Type `release --compiler dmd` or `release --compiler ldc` depending on the compiler used.
- This tool is needed to create the whole bundle.


## FAQ

- Am I forced to use the PBR graphics system?

No. There are people making plugins with Dplug without using PBR. How it works is that the physical channel is just filled with 0. Doing that requires a set of custom widgets.

- How do I build plugins for OS X?

You need to use the `release` program in the `tools`directory.
This tool create a bundle and Universal Binaries as needed.
Like most D programs, you can build it by typing `dub`.

- What is the oldest supported Windows version?

Windows Vista. Users report plugins made with both DMD and LDC work on Windows XP. But XP isn't officially supported by D compilers.

- What is the oldest supported OS X version?

OS X 10.7+.

- What D compiler can possibly be used?

   See `.travis.yml` for supported compilers. The latest DMD or LDC should do. However, it is recommended that you use LDC-1.0.0-b2 for final binaries as no other LDC version has been as well tested with Dplug.

- Is Dplug stable?

Starting with v4 we'll issue major or minor version tag for breaking changes.
If you don't want breaking change, you can pin Dplug to a specific version in your `dub.json`.
Breaking commits are marked with BREAKING in the commit backlog.

- How are `TODO`, `FUTURE` and `MAYDO` comments defined?

`TODO` represent a bug a user could possibly bump into.
`FUTURE` represent an future enhancement that could concern speed, maintainability or correctness but doesn't affect the experience much, if any.
`MAYDO` represent things that we could want to do given enough time.


## Comparison vs IPlug

Pros:
  - No dispatcher-wide mutex lock. All locks are of a short duration, to avoid blocking the audio thread.
  - Buffer splitting: ensure your plugin never receive a buffer larger than N samples, and the corresponding MIDI input.
  - Plugin parameters implement the Observer pattern.
  - Float parameters can have user-defined mapping.
  - PBR-style rendering lets you have a good visual quality with less disk space.
  - No need to deal with resource compilers: D can `import("filename.ext")` them.
  - No need to maintain IDE project files, they are generated by DUB.
    eg: `dub generate visuald` or `dub generate sublimetext`
  - No need to make Info.plist files, they are generated instead.
  - No need to use Xcode whatsoever.
  - No need to use a macOS SDK.
  - Easy to install: DUB will download the library itself when building, a <= 2mb archive.  
  - 10x less lines of code than the next larger alternative.

Cons:
  - **AAX and VST3 unimplemented.**
  - No resizeable UI
  - No HDPI support
  - No modal windows

## Licenses

Dplug has three different licenses depending on the part you need.
For an audio plugin, you would typically need all three.
I recommend that you check individual source files for license information.

### Plugin format wrapping

Plugin wrapping is heavily inspired by the WDL library (best represented here: https://github.com/olilarkin/wdl-ol).

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
If you don't agree with the license, don't make plugins with Dplug.
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
   * implements windowing for Win32, Cocoa and Carbon

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

### Examples
   * `examples/distort`: mandatory distortion plugin
   * `examples/ms-encode`: simplest plugin for tutorial purpose

### Tools
   * `tools/pbr-sketch`: playground for creating plugin background textures
   * `tools/release`: DUB frontend to build Mac bundles and use LDC with proper envvars
   * `tools/process`: plugin host for testing audio processing speed/reproducibility
   * `tools/wav-compare`: comparison of WAV files
   * `tools/stress-plugin`: makes multiple load of plugins while processing audio mainly to test GUI opening speed
   * `Lift-Gamma-Gain-Contrast`: adjust color correction curves on a finished UI http://www.gamesfrommars.fr/lift-gamma-gain-contrast/
