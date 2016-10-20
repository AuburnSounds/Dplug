#!/bin/sh

dub test dplug:core
dub test dplug:client
dub test dplug:host
dub test dplug:vst
dub test dplug:au
dub test dplug:graphics
dub test dplug:gui
dub test dplug:cocoa
dub test dplug:carbon
dub test dplug:derelict-nogc

dub test -a x86 --compiler=ldc2 dplug:core
dub test -a x86 --compiler=ldc2 dplug:client
dub test -a x86 --compiler=ldc2 dplug:host
dub test -a x86 --compiler=ldc2 dplug:vst
dub test -a x86 --compiler=ldc2 dplug:au
dub test -a x86 --compiler=ldc2 dplug:graphics
dub test -a x86 --compiler=ldc2 dplug:gui
dub test -a x86 --compiler=ldc2 dplug:cocoa
dub test -a x86 --compiler=ldc2 dplug:carbon
dub test -a x86 --compiler=ldc2 dplug:derelict-nogc