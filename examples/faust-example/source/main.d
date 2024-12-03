/**
Copyright: Ethan Reker 2023.
License: MIT
*/
module main;

import std.math;
import std.algorithm;

import dplug.core,
       dplug.client;

import gui;

import freeverb;

mixin(pluginEntryPoints!ExampleClient);

enum : int
{
    paramDamp,
    paramRoomSize,
    paramStereoSpread,
    paramWet
}


final class ExampleClient : FaustClient
{
public:
nothrow:
@nogc:

    this()
    {
        super();
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info)
    {
        assert(frames <= 512);
        super.processAudio(inputs, outputs, frames, info);

        if (ExampleGUI gui = cast(ExampleGUI) graphicsAcquire())
        {
            graphicsRelease();
        }
    }

    override IGraphics createGraphics()
    {
        return mallocNew!ExampleGUI(this);
    }
}

