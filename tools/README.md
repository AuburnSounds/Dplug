### Tools
   * `tools/dplug-build`: DUB frontend to build plug-ins
   * `tools/process`: plugin host for testing audio processing speed/reproducibility
   * `tools/wav-compare`: comparison of WAV files, difference spectrogram
   * `tools/wav-info`: show information about a single WAV file
   * `tools/abtest`: helps performing A/B testing of two similar audio files (needs SDL and SDL_mixer)
   * `tools/bench`: perform quality and performance measurements to validate optimizations and find regressions. Uses `wav-compare` and `process`
   * `tools/latency-check`: report errors for wrong latencies
   * `tools/stress-plugin`: makes multiple load of plugins while processing audio mainly to test GUI opening speed
   * `tools/presetbank`: Synthesize a FXB file out of a number of individual FXP files.
   * `tools/color-correction`: Choose color correction curves for a finished UI
