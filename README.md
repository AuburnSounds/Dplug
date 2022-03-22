<img alt="logo" src="https://cdn.rawgit.com/AuburnSounds/dplug/master/tools/dplug-logos/logo-coloured-on-transparent.png" width="130">

![Build and Test](https://github.com/AuburnSounds/Dplug/workflows/ci/badge.svg)
# [![Build Status](https://travis-ci.com/AuburnSounds/Dplug.svg?branch=master)](https://travis-ci.com/AuburnSounds/Dplug) <a href="https://code.dlang.org/packages/dplug" title="Go to dplug"><img src="https://img.shields.io/dub/v/dplug.svg" alt="Dub version"></a>

`Dplug` lets you create audio plug-ins with unmatched simplicity and speed, using the D language.

- Homepage: [https://dplug.org/](https://dplug.org/)
- Wiki: https://github.com/AuburnSounds/Dplug/wiki
- Discord: https://discord.gg/KsUUj39Q

## Features

|  Format | macOS arm64 | macOS amd64  | Windows 32-bit | Windows 64-bit | Linux x86-64 | Raspberry ARM32 |
|---------|-------------|--------------|----------------|----------------|--------------|-----------------|
| VST2    | Yes         | Yes          | Yes            | Yes            | Yes          | Yes             |
| VST3    | Yes         | Yes          | Yes            | Yes            | Yes          | Yes             |
| AUv2    | Yes         | Yes          |                |                |              |                 |
| AAX     | No          | Yes          | No             | Yes            |              |                 |
| LV2     | Yes         | Yes          | Yes            | Yes            | Yes          | Yes             |


- Automated Mac and Windows installers
- Raspberry Pi support
- Build plug-ins with less pain using the D language, possibly the most [powerful](https://dlang.org/orgs-using-d.html) native language available today
- Live-coding of the UI with [Wren](https://wren.io/)
- Leverage package-based dependencies using DUB, the D language's package manager
- Small binaries with (optional) [rendering](http://www.auburnsounds.com/blog/2016-09-16_PBR-for-Audio-Software-Interfaces.html)
- Static link with the MSCRT runtime libraries to distribute only one single file
- Support [major DAWs](https://github.com/AuburnSounds/Dplug/wiki/Host-Support)
- Small, tight-knit community


### Community and ecosystem

The following commercial products are known to use Dplug:

- [Convergence](https://www.cutthroughrecordings.com/product/Convergence) by Cut Through Recordings
- [Couture](https://www.auburnsounds.com/products/Couture.html) by Auburn Sounds
- [Entropy](https://www.cutthroughrecordings.com/product/Entropy_II_-_Enhanced_Stereo_Delay) by Cut Through Recordings
- [EpicPRESS](https://www.cutthroughrecordings.com/product/EpicPRESS) by Cut Through Recordings
- [Graillon](https://www.auburnsounds.com/products/Graillon.html) by Auburn Sounds
- [M4 Multiband Compressor](https://www.cutthroughrecordings.com/product/M4_Multiband_Compressor) by Cut Through Recordings
- [Panagement](https://www.auburnsounds.com/products/Panagement.html) by Auburn Sounds
- [Renegate](https://www.auburnsounds.com/products/Renegate.html) by Auburn Sounds

Looking for DSP algorithms? Reduce time-to-market with the [DSP Asset Store](DSP_Asset_Store.md).

Become one happy [Dplug contributor](https://github.com/AuburnSounds/Dplug/graphs/contributors) by submitting issues and pull-requests, and come talk with us on the [D Language Discord](https://discord.gg/QZtGZUw) to learn more and meet other Dplug users!



### Release notes

Keep up with major changes here: [Release Notes](https://github.com/AuburnSounds/Dplug/wiki/Release-notes)


## Tutorials

- [Getting Started](https://github.com/AuburnSounds/Dplug/wiki/Getting-Started)


## Governance

Dplug has a deep commitment to stability. All breaking changes are documented in the [Changelog](https://github.com/AuburnSounds/Dplug/wiki/) and issues major SemVer tags for breaking changes. If you don't want any breaking changes, you can pin Dplug to a major version in your `dub.json`. **Breaking changes only happen for major tags.**


**Dplug's goal is to support existing products and building commercial companies around them**. 
It is a part-time operation, from people who release commercial plug-ins.

Being stable and relatively bug-free is deemed more important to us than implement every possible feature. It's often than enhancements get postponed in favour of product development, so please be patient!


- Where do I start?

Be sure to read the [Wiki](https://github.com/AuburnSounds/Dplug/wiki/) in depth.


## Strengths of Dplug

  - As lightweight as possible
  - Public bugtracker
  - Well-defined scope: for professional plug-in developers
  - Maintained continuously, supported by sales for the foreseeable future
  - Price is free, no personal support must be expected though
  - Intel intrinsics compatible with Apple Silicon
  - Fast 2D software rasterizer in `dplug:canvas`
  - Scriptable UI for faster authoring
  - PBR-style rendering lets you have a good visual quality with less disk space. If you don't use it, you don't pay for it.
  - No dealing with resource compilers: D can `import("filename.ext")` them
  - Easy to install and update
  - Constant push to fight complexity


### VST SDK

If you don't have the VST SDK, you can't _make_ VST plugins with Dplug.
Find the VST SDK there: http://www.steinberg.net/en/company/developers.html

**If you don't have a licensing agreement with Steinberg**, you can't _distribute_ VST2 or VST3 plug-ins.


## Licenses

Dplug has many different licenses depending on the sub-package you need.
Please check individual source files for license information.
Please do your homework and respect the individual licences when releasing a plug-in.

- [Dplug VST2 Guide](https://github.com/AuburnSounds/Dplug/wiki/Dplug-VST2-Guide)
- [Dplug AAX Guide](https://github.com/AuburnSounds/Dplug/wiki/Dplug-AAX-Guide)
- [Dplug VST3 Guide](https://github.com/AuburnSounds/Dplug/wiki/Dplug-VST3-Guide)

