# Task template

Task file contains single xml node `<bench> </bench>`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<bench>
  <baseline>baseline.dll</baseline> // 1
  <challenger>challenger.dll</challenger> // 0 or more. If not set, processors that consume 2 sources will not be called.
  <preset>1</preset> // 0 or more. If no presets were specified uses preset 0.
  <source>source.wav</source> // 0 or more. If no sources were specified uses all sources from source_dir.
  <quality-compare/> // 0 or 1. Runs comparison of outputs in addition to process tool.
  <speed-measure/> // 0 or 1. Measures the time it took to process source file and compares the measurements between baseline and each challenger.
  <source-dir>C:\samples</source-dir> // 0 or 1. Overrides setting of global config
  <output-dir>bench</output-dir> // 0 or 1. Overrides setting of global config
</bench>
```

Plugins specified with `<baseline>` and `<challenger>` nodes can have optional parameter values. See `example1.xml` below.

Source paths are always relative to `<source_dir>`, unless they are absolute.

Plugin paths are always relative to `<task_dir>`, unless they are absolute.

# Caching

The results of process step are cached and are recalculated when cache is invalidated or when -force flag is passed.
Cache is invalidated when plugin modification date changes, or when plugin parameters change.

# Config template

Tool looks for `config.xml` in the same directory as executable.

`config.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<bench>
  <source_dir>C:\samples</source_dir> // 0 or 1. If not set than source directory equals <task_dir>/samples
  <output_dir>C:\output</output_dir> // 0 or 1. If not set than output directory equals <task_dir>/output
</bench>
```

# Execution process:

```
Read global config
    Read source directory. If not set than source directory equals <task directory>/samples
    Read output directory. If not set than output directory equals <task directory>/output

Read task file
    Read baseline plugin
    Read competitor plugins
    Read sources. If no sources were specified uses all sources from source_dir
    Read presets. If no presets were specified uses preset 0
    Read optional source directory that will override one from global config
    Read optional output directory that will override one from global config
    Read zero or more processors that will be run after 'process' step
For each combination of source and preset
    for each plugin
        run 'process' tool passing it source, output path, plugin and preset
    if quality-compare tag is specified run comparison on every pair of baseline output and challenger output (see example3 below)
    if speed-measure tag is specified run comparison on every pair of baseline output and challenger output (see example4 below)

```

# Examples:
`config.xml` contents:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<bench>
  <source_dir>C:\samples</source_dir>
  <output_dir>C:\output</output_dir>
</bench>
```

---

Will process bass.wav with baseline.dll and challenger.dll plugins and output two wav files in output folder.

`example1.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<bench>
  <baseline>
    baseline.dll
    <parameter index="1" value="0.5" />
    <parameter index="5" value="0.1" />
  </baseline>
  <challenger>
    challenger.dll
    <parameter index="1" value="0.7" />
  </challenger>
  <preset>1</preset>
  <source>bass.wav</source>
</bench>
```
Tool will produce following calls:

```
process -i C:\samples\bass.wav -o C:\Samples\output\bass-1-baseline.wav -preset 1 -param 1 0.5 -param 5 0.1 baseline.dll
process -i C:\samples\bass.wav -o C:\Samples\output\bass-1-challenger.wav -preset 1 -param 1 0.7 challenger.dll
```

---

`example2.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<bench>
  <baseline>baseline.dll</baseline>
  <challenger>challenger.dll</challenger>

  <preset>1</preset>
  <preset>2</preset>

  <source>various.wav</source>
  <source>various-voices.wav</source>

  <quality-compare/>
</bench>
```

Tool will produce following calls:
```
process -i C:\samples\various.wav -o C:\Samples\output\various-1-baseline.wav -preset 1 baseline.dll
process -i C:\samples\various.wav -o C:\Samples\output\various-1-challenger.wav -preset 1 challenger.dll
wav-compare C:\Samples\output\various-1-baseline.wav C:\Samples\output\various-1-challenger.wav

process -i C:\samples\various.wav -o C:\Samples\output\various-2-baseline.wav -preset 2 baseline.dll
process -i C:\samples\various.wav -o C:\Samples\output\various-2-challenger.wav -preset 2 challenger.dll
wav-compare C:\Samples\output\various-2-baseline.wav C:\Samples\output\various-2-challenger.wav

process -i C:\samples\various-voices.wav -o C:\Samples\output\various-voices-1-baseline.wav -preset 1 baseline.dll
process -i C:\samples\various-voices.wav -o C:\Samples\output\various-voices-1-challenger.wav -preset 1 challenger.dll
wav-compare C:\Samples\output\various-voices-1-baseline.wav C:\Samples\output\various-voices-1-challenger.wav

process -i C:\samples\various-voices.wav -o C:\Samples\output\various-voices-2-baseline.wav -preset 2 baseline.dll
process -i C:\samples\various-voices.wav -o C:\Samples\output\various-voices-2-challenger.wav -preset 2 challenger.dll
wav-compare C:\Samples\output\various-voices-2-baseline.wav C:\Samples\output\various-voices-2-challenger.wav
```

---

quality-compare is run for each pair of outputs for baseline and challenger
`example3.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<bench>
  <baseline>baseline.dll</baseline>
  <challenger>challenger1.dll</challenger>
  <challenger>challenger2.dll</challenger>
  <preset>1</preset>
  <source>source.wav</source>
  <quality-compare/>
</bench>
```

does:

```
process -i C:\samples\source.wav -o C:\Samples\output\source-1-baseline.wav -preset 1 baseline.dll
process -i C:\samples\source.wav -o C:\Samples\output\source-1-challenger1.wav -preset 1 challenger1.dll
process -i C:\samples\source.wav -o C:\Samples\output\source-1-challenger2.wav -preset 1 challenger2.dll

wav-compare C:\Samples\output\source-1-baseline.wav C:\Samples\output\source-1-challenger1.wav
wav-compare C:\Samples\output\source-1-baseline.wav C:\Samples\output\source-1-challenger2.wav
```

---

`example4.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<bench>
  <baseline>baseline.dll</baseline>
  <challenger>challenger1.dll</challenger>
  <challenger>challenger2.dll</challenger>
  <source>source.wav</source>
  <speed-measure/>
</bench>
```

does:

```
Speed measure against baseline 0.33216s
  challenger1 0.340568s ratio 1.02531
  challenger2 0.456 ratio 1.372
```