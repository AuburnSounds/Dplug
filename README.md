<img alt="logo" src="https://cdn.rawgit.com/AuburnSounds/dplug/master/logo.svg" width="200">

# Dplug [![Build Status](https://travis-ci.org/AuburnSounds/Dplug.svg?branch=master)](https://travis-ci.org/AuburnSounds/Dplug) <a href="https://code.dlang.org/packages/dplug" title="Go to dplug"><img src="https://img.shields.io/dub/v/dplug.svg" alt="Dub version"></a> ![Dplug Discord server](https://discordapp.com/api/guilds/242094594181955585/widget.png?style=shield)

`Dplug` is a library for creating audio plug-ins as simply as possible. 

[Auto-generated documentation...](http://dplug.dpldocs.info/dplug.html)

## Features

- Create VST 2.4 plug-ins for macOS, Windows, and Linux (to distribute VST2 plug-ins be sure to sign a VST2 Licence Agreement with Steinberg)
- Create Audio Unit v2 plug-ins for macOS
- Create AAX64 Native plug-ins for macOS and Windows
- Build plug-ins faster and with less pain: D language, plug-in bundling, color correction, performance tests...
- Small binaries with (optional) [rendering](http://www.auburnsounds.com/blog/2016-09-16_PBR-for-Audio-Software-Interfaces.html)
- Support [major DAWs](https://github.com/AuburnSounds/Dplug/wiki/Host-Support)
- Small, tight-knit community


### Community and ecosystem

These products use Dplug:

- [Couture](https://www.auburnsounds.com/products/Couture.html) by Auburn Sounds
- [Entropy](http://www.modernmetalproduction.com/product/entropy-ii-enhanced-stereo-delay-vst-au/) by Cut Through Recordings
- [Graillon](https://www.auburnsounds.com/products/Graillon.html) by Auburn Sounds
- [M4 Multiband Compressor](http://www.modernmetalproduction.com/product/m4-multiband-compressor-vst-au/) by Cut Through Recordings
- [Panagement](https://www.auburnsounds.com/products/Panagement.html) by Auburn Sounds
- [Tarabia Distortion](http://smaolab.org/product/tarabia-distortion/) by SMAOLAB

Increase quality and reduce time-to-market with commercial audio DSP in the [DSP Asset Store](DSP_Asset_Store.md).

Become one happy [Dplug contributor](https://github.com/AuburnSounds/Dplug/graphs/contributors) by submitting issues and pull-requests, and come talk with us on the [D Language Discord](https://discord.gg/QZtGZUw) to learn more and meet your peers Dplug users!



### Release notes

Keep up with major changes here: [Release Notes](https://github.com/AuburnSounds/Dplug/wiki/Release-notes)


## Tutorials

- [Getting Started](https://github.com/AuburnSounds/Dplug/wiki/Getting-Started)


## FAQ

- Does Dplug support the creation of synthesizer plug-ins?

Yes. See the [simple-mono-synth](examples/simple-mono-synth) and [Poly Alias](examples/poly-alias-synth) examples.

- Am I forced to use the PBR rendering system?

No. And if you don't use it, you don't pay for it.


- What is the oldest supported Windows version?

Windows Vista. 


- What is the oldest supported OS X version?

OS X 10.8+.

- What D compiler can possibly be used?

   See `.travis.yml` for supported compilers. The latest DMD or LDC should do.

- What D compilers are recommended?

   For releases it is highly recommended that you use LDC >= 1.8.
   When in development you can use DMD for faster compilation times. 

- Is Dplug stable?

Dplug has excellent stability.

Dplug documents all breaking changes in the [Changelog](https://github.com/AuburnSounds/Dplug/wiki/) and
issues major SemVer tags for breaking changes.

If you don't want breaking changes, you can pin Dplug to a major version in your `dub.json`.

But reality is complex, and bug fixes can be breaking too, (eg: "highpass FIR wasn't working").
In which case we have to make a judgment call as to whether it's a breaking fix, and whether the buggy feature was used.

Breaking commits, when they happen, are marked with BREAKING in the commit backlog.
They are discussed on Discord to assess the impact.

- Will you add feature X?

You have to understand that Dplug is a part-time operation, from people who spend much more time working on and releasing plug-ins.

**Dplug is there to support existing products and building commercial companies around them**, not to be beta software and make empty promises. 
Being stable and bug-free is much more important to us than implement every possible feature.

Politically, it's very often than enhancements get postponed in favour of product development, so please be patient!

We're looking for ways to improve governance as more contributors have appeared with contrasted agendas.


- Where do I start?

Be sure to read the [Wiki](https://github.com/AuburnSounds/Dplug/wiki/) in depth.


## Strengths of Dplug

  - As lightweight as possible
  - Public bugtracker
  - Well-defined scope: for professional plug-in developers
  - Maintained continuously, supported by sales for the foreseeable future
  - Price is free, no personal support must be expected though
  - PBR-style rendering lets you have a good visual quality with less disk space. If you don't use it, you don't pay for it.
  - No dealing with resource compilers: D can `import("filename.ext")` them
  - Easy to install and update
  - Constant push to fight complexity and minimize LOC


## Licenses

Dplug has different licenses depending on the sub-package you need.
Please check individual source files for license information.
**Please respect the individual licences when releasing a plug-in.**


### Plugin format wrapping

Plugin wrapping is inspired by the WDL library (best represented here: https://github.com/olilarkin/wdl-ol).

Some files falls under the Cockos WDL license.

Important contributors to WDL include:
- Cockos: http://www.cockos.com/
- Oliver Larkin: http://www.olilarkin.co.uk/



### VST SDK translation

VST is a trademark of Steinberg Media Technologies GmbH.
Please register the SDK via the 3rd party developer license on Steinberg site.

Before you make VST plugins with Dplug, you need to read and agree with the license for the VST3 SDK by Steinberg.

If you don't have the VST2 SDK, you can't _make_ plugins with Dplug.
Find the VST SDK there: http://www.steinberg.net/en/company/developers.html

**If you don't have a licensing agreement with Steinberg**, you can't _distribute_ VST2 or VST3 plug-ins.


### Misc

Other source files fall under the Boost 1.0 license.



