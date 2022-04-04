### Examples
   * `examples/distort`: mandatory distortion plugin, with a PBR UI. Fork this for your own plug-in.
     This one explains how to use `TimedFIFO` for UI feedback, `Canvas`, `ImageKnob`, Wren scripting, custom widgets that draw to both Raw and PBR layer.
   * `examples/clipit`: mandatory distortion plugin, with a flat UI. Fork this for your own plug-in.
     This one explains how to use flag-widgets.



### Alt. Examples

**Beware!** Those examples are less authoritative/maintained than `examples/clipit` and `examples/distort`:
   * `examples/ms-encode`: simplest plugin for tutorial purpose, without UI.
   * `examples/simple-mono-synth`: very basic sine-wave generator, without UI.
   * `examples/poly-alias-synth`: simple polyphonic wave generator, without UI.
   * `examples/arpejoe`: simple MIDI output plug-in, without UI.


### How to run

- `dplug-build` will build a VST3 plug-in (you can't distribute that plug-in without signing the VST3 Steinberg Agreement!)

- `dplug-build -c <format>` to choose a format.

- `dplug-build --final -c <format>` for an optimized final build.


