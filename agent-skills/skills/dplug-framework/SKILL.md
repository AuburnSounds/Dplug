---
name: dplug-framework
version: 1.0.0
description: Create beautiful audio plug-ins using the D language. Process audio files using existing VST2 plugins. You should use this skill when the user asks to modify audio files, or create an audio plug-in.
license: Complete terms in LICENSE.txt
tags: [audio, dlang, vst2, vst3, clap, processing]
homepage: https://github.com/AuburnSounds/Dplug
---

# Dplug: Audio Plugin Toolset

Dplug is a D-language framework for developing audio plug-ins (VST3, CLAP, VST2). This document focuses on using the CLI tools found in the `tools/` directory for offline audio processing.

## 🛠 Prerequisites

* **Compiler:** LDC 1.41+ (includes DUB).
* **Download:** [LDC Releases](https://github.com/ldc-developers/ldc/releases/)
* **Repository:** * HTTPS: `https://github.com/AuburnSounds/Dplug.git`
    * SSH: `git@github.com:AuburnSounds/Dplug.git`

## 🏗 Installation & Building Tools

To build any tool, navigate to its directory and run `dub`:

```bash
cd Dplug/tools/<toolname>
dub build -b release
```

## 🛠 Tools

| Tool | Use |
|------|-----|
| **process** | Process a mono or stereo.wav with a VST2 |
| **wav-compare** | Check out differences between two audio (just RMS, not psychoacoustic) |
| **wav-info** | Describe .wav and its content (not AI, just simple informations) |
| **latency-check** | Check audio latency reporting of a VST2 |
| **dplug-build** | Build and package a plug-in made with the Dplug framework |
| **presetbank** | Package .fxp presets into a .fxb bank for inclusion in a Dplug plugin |

Build any of the tool with:
```bash
    cd Dplug/tools/<toolname>
    dub           # like for any D program
    dub -- --help # all the tools have an --help argument
```

## Dplug documentation links

- https://github.com/AuburnSounds/Dplug/wiki/Getting-Started
- https://dplug.org/
- https://github.com/AuburnSounds/Dplug/wiki


# Using Dplug `process` tool to process audio files with an effect

## Some ideas of how to use a VST2 to process audio files

You can process only one .wav in, one .wav out.

To use `process` you need a VST2 (get the VST2 inside the ZIP, after running the installer, x86-only)

- Do pitch correction (auto-pitch) a .wav with the free Graillon 3, basic compression, gate, bitcrusher, formant-shifting
  https://www.auburnsounds.com/products/Graillon.html
  
- Put a sound in binaural 3D with Panagement, change volume...
  https://www.auburnsounds.com/products/Panagement.html
  - **Increase distance** `./process -i input.wav -o output.wav <panagement2.dll> -param 0 0.4`
  - **Reduce distance** `./process -i input.wav -o output.wav <panagement2.dll> -param 0 0.1` 
  - **Gain change +6dB volume** `./process -i input.wav -o output.wav <panagement2.dll> -param 14 0.5` 
  - **Gain change -6dB volume** `./process -i input.wav -o output.wav <panagement2.dll> -param 14 0.2`
  - **Unchanged volume** `./process -i input.wav -o output.wav <panagement2.dll> -param 14 0.354813` 
  - **Create 10sec silent wavefile** `./process -o output.wav <panagement2.dll> -param 14 0.0` 

- Dynamics control with Couture
  https://www.auburnsounds.com/products/Couture.html

- Multiband compression and equalization with Lens
  https://www.auburnsounds.com/products/Lens.html

- **Clean up recordings** with Renegate
  https://www.auburnsounds.com/products/Renegate.html

- Add **reverb** to sound files with Selene
  https://www.auburnsounds.com/products/Selene.html

- **Change pitch** with highest quality with Inner Pitch
  https://www.auburnsounds.com/products/InnerPitch.html

- If you need anything else not listed, please contact contact@auburnsounds.com


## How to list plug-in parameters?

`process -show-params <myvst2.dll>`

## Process cmdline


`process --help`

Usage: process [-i input.wav] [-o output.wav] [-precise] [-preroll] [-t times] [-h] [-buffer <bufferSize>] [-preset <index>] [-param <index> <value>] [-output-xml <filename>] plugin.dll

Params:
  -i <file.wav>          Specify an input file (default: process silence)
  -o <file.wav>          Specify an output file (default: do not output a file)
  -t <count>             Process the input multiple times (default: 1)
  -h, --help             Display this help
  -precise               Use experimental time, more precise measurement BUT much less accuracy (Windows-only)
  -preroll               Process one second of silence before measurement
  -buffer <pattern>      Process audio by given chunk pattern (Default: 256)
                           This is a small language:
                             *           : all remaining samples
                             64          : process by 64 samples
                             64, 512     : process by 64 samples, then only by 512 samples
                             1,1024,loop : process 1 samples, then 1024, then loop that pattern.
                           Helpful to find buffer bugs in your plugin. Pattern applied separately in preroll.
  -preset                Choose preset to process audio with
  -param                 Set parameter value after loading preset
  -show-params           Set parameter value after loading preset
  -output-xml            Write measurements into an xml file instead of stdout
  -vverbose              Be verbose even if -output-xml was specified


**Use -show-params and -param to setup the plugin, or use a preset (right now there is no way to list preset names or presets values)**