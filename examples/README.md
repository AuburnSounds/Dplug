### Examples
   * `example/template`: Template to make a new plug-in.
   * `examples/clipit`: Another distortion plugin, with a flat UI. 
     This one explains how to build an UI using `dplug:flat-widgets`.
   * `examples/distort`: A distortion plugin, with a PBR UI.
     This one explains how to use `TimedFIFO` for UI feedback, `Canvas`, `ImageKnob`, Wren scripting, custom widgets that draw to both Raw and PBR layer.
   * `examples/faust-example`: A FreeVerb example using Faust.


### Other Examples

**Beware!** Those examples are less authoritative/maintained than `clipit`, `distort`, and `template`:
   * `examples/ms-encode`: simplest plugin for tutorial purpose, without UI.
   * `examples/simple-mono-synth`: very basic sine-wave generator, without UI.
   * `examples/poly-alias-synth`: simple polyphonic wave generator, without UI.
   * `examples/arpejoe`: simple MIDI output plug-in, without UI.


### How to run

- `dplug-build` will build a VST3 plug-in (you can't distribute that plug-in without signing the VST3 Steinberg Agreement!)

- `dplug-build -c <format>` to choose a format.

- `dplug-build --final -c <format>` for an optimized final build.


