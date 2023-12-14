<img alt="logo" src="https://cdn.rawgit.com/AuburnSounds/dplug/master/tools/dplug-logos/logo-coloured-on-transparent.png" width="130">

# ![Build and Test](https://github.com/AuburnSounds/Dplug/workflows/ci/badge.svg) <a href="https://code.dlang.org/packages/dplug" title="Go to dplug"><img src="https://img.shields.io/dub/v/dplug.svg" alt="Dub version"></a>

`Dplug` lets you create professional audio plug-ins with minimal headaches and cost.

🏠 [Dplug.org](https://dplug.org/)  
📚 [DPlug Wiki](https://github.com/AuburnSounds/Dplug/wiki)  
💬 [Community Discord](https://discord.gg/7PdUvUbyJs)  
👩‍🏫 [Getting Started](https://github.com/AuburnSounds/Dplug/wiki/Getting-Started)  


## Features

|  Format | macOS arm64 | macOS amd64  | Windows 32-bit | Windows 64-bit | Linux x86-64 | 
|---------|-------------|--------------|----------------|----------------|--------------|
| VST2    | ✅         | ✅          | ✅            | ✅            | ✅          | 
| VST3    | ✅         | ✅          | ✅            | ✅            | ✅          | 
| AUv2    | ✅         | ✅          |                |                |              |
| AAX     | ✅          | ✅          | ✅             | ✅            |              |
| LV2     | ✅         | ✅          | ✅            | ✅            | ✅          | 
| FLP     | ❌         | ❌          | ❌            | ✅            |             | 


⚙️ Automated Mac and Windows installers, signing, notarization.  
⚙️ Build plug-ins with Dlang, a powerful, easy and fast native [language](https://dlang.org/orgs-using-d.html) with serious build times improvements over C++.  
⚙️ Package-based dependency management with DUB. Build any Dplug tool with the `$ dub` command.  
⚙️ With [PBR rendering](http://www.auburnsounds.com/blog/2016-09-16_PBR-for-Audio-Software-Interfaces.html), you can have video-game like skeuomorphism with a small distribution size.  
⚙️ DAW support list [here](https://github.com/AuburnSounds/Dplug/wiki/Host-Support).  
⚙️ Ask your question on the Discord!  
⚙️ Join the secretive Dplug Wasteland club for exclusive audio knowledge!  
⚙️ Free of charge!  


### Made with Dplug

- [Convergence](https://www.cutthroughrecordings.com/product/Convergence) by Cut Through Recordings
- [Couture](https://www.auburnsounds.com/products/Couture.html) by Auburn Sounds
- [Entropy 3](https://cutthroughrecordings.com/products/entropy-3-stereo-crossover-delay) by Cut Through Recordings
- [EpicPRESS](https://www.cutthroughrecordings.com/product/EpicPRESS) by Cut Through Recordings
- [Faradelay](https://cutthroughrecordings.com/products/faradelay) by Cut Through Recordings
- [Graillon](https://www.auburnsounds.com/products/Graillon.html) by Auburn Sounds
- [Inner Pitch](https://www.auburnsounds.com/products/InnerPitch.html) by Auburn Sounds
- [Lens](https://www.auburnsounds.com/products/Lens.html) by Auburn Sounds
- [M4 Multiband Compressor](https://www.cutthroughrecordings.com/product/M4_Multiband_Compressor) by Cut Through Recordings
- [Nu:Cat](https://lunafoxgirlvt.itch.io/nucat) by Kitsunebi Games
- [OneTrick Simian](https://punklabs.com/ot-simian) by Punk Labs 
- [Panagement](https://www.auburnsounds.com/products/Panagement.html) by Auburn Sounds
- [Renegate](https://www.auburnsounds.com/products/Renegate.html) by Auburn Sounds
- [Tarabia MK II](https://smaolab.org/product/tarabiamk2/) by SMAOLAB
- [Yamatube Pro](https://smaolab.org/yamatube/) by SMAOLAB


Come talk with us on the [Dplug Discord](https://discord.gg/QZtGZUw) to learn more and meet your peers!



### Release notes

Keep up with major changes with the [Dplug Release Notes](https://github.com/AuburnSounds/Dplug/wiki/Release-notes).   

_**Key concept:** Dplug uses SemVer. If you stay on the same Dplug major version tag (eg: `"~>13.0"`), your plug-in wont't break, and more importantly your **user sessions** won't break either._





## Governance

Dplug has a deep commitment to stability. All breaking changes are documented in the [Changelog](https://github.com/AuburnSounds/Dplug/wiki/) and issues major SemVer tags for breaking changes. If you don't want any breaking changes, you can pin Dplug to a major version in your `dub.json`. **Breaking changes only happen for major tags.**


**Dplug's goal is to support existing products and build commercial companies around them**. 
It is a part-time operation, **from people who release commercial plug-ins for a living.**

Being stable and relatively bug-free is deemed more important to us than implement every possible feature. It's often than enhancements get postponed in favour of product development, so please be patient!



## Strengths of Dplug

  - No interaction needed with `Xcode`, `CMake`, `C++`, `Obj-C` or `MSVC`.
  - Lovable D language, suitable from prototyping to production.
  - Same features for `VST2` / `VST3` / `AUv2` / `AAX` / `LV2` plug-in formats.
  - Same features for desktop OS: Windows / macOS / Linux.
  - [Faust](https://github.com/ctrecordings/dplug-faust-example) language integration.
  - Easy SIMD compatible with both `x86`, `x86_64`, and `arm64` with same codebase.
  - Fast 2D software rasterizer in `dplug:canvas`, no OpenGL headaches.
  - `Wren` scripting for faster UI authoring.
  - Optional Physically Based Rendering (PBR).
  - Image support: `PNG`, `JPEG`, `QOI`, and specially designed `QOIX` codec.
  - Easy to install and update.
  - State-of-the-Art [tutorials](https://dplug.org/#tutorials).


### VST3 SDK

If you don't have the VST3 SDK, you can't _make_ VST3 plugins with Dplug.
Find the VST3 SDK there: http://www.steinberg.net/en/company/developers.html

**If you don't have a licensing agreement with Steinberg**, you can't _distribute_ VST2 or VST3 plug-ins.


## Licenses

Dplug has many different licenses depending on the sub-package you need.
Please check individual source files for license information.
Please do your homework and respect the individual licences when releasing a plug-in.

In particular:
- [Dplug VST2 Guide](https://github.com/AuburnSounds/Dplug/wiki/Dplug-VST2-Guide)
- [Dplug AAX Guide](https://github.com/AuburnSounds/Dplug/wiki/Dplug-AAX-Guide)
- [Dplug VST3 Guide](https://github.com/AuburnSounds/Dplug/wiki/Dplug-VST3-Guide)

