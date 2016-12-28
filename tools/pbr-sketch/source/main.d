import std.file;
import std.stdio;
import std.path;
import std.conv;
import std.string;

import dplug.gui;
import dplug.graphics;

import imageformats;

/// Returns: Most precise clock ticks, in milliseconds.
long getTickUs() nothrow @nogc
{
    import core.time;
    return convClockFreq(MonoTime.currTime.ticks, MonoTime.ticksPerSecond, 1_000_000);
}


void main(string[] args)
{
    int timesRendering = 1;
    for (int i = 1; i < args.length; ++i)
    {
        string arg = args[i];
        if (arg == "-n")
            timesRendering = to!int(args[++i]);
        else 
            throw new Exception(format("Unknown parameter '%s'", arg));
    }

    string appDir = dirName(thisExePath());
    string basecolorName = buildPath(appDir, "basecolor.png");
    string materialName = buildPath(appDir, "material.png");
    string emissiveName = buildPath(appDir, "emissive.png");
    string physicalName = buildPath(appDir, "physical.png");
    string depthName = buildPath(appDir, "depth.png");

    OwnedImage!RGBA diffuse = loadImageSeparateAlpha(std.file.read(basecolorName), std.file.read(emissiveName));
    scope(exit) diffuse.destroy();
    OwnedImage!RGBA material = loadImageSeparateAlpha(std.file.read(materialName), std.file.read(physicalName));
    scope(exit) material.destroy();
    OwnedImage!RGBA depth = loadOwnedImage(std.file.read(depthName));
    scope(exit) depth.destroy();

    string diffuseCopy = buildPath(appDir, "diffuse-copy.png");

    string skyboxPath = buildPath(appDir, "skybox.jpg");
    OwnedImage!RGBA skybox = loadOwnedImage(std.file.read(skyboxPath));

    assert(diffuse.w == material.w);
    assert(diffuse.h == material.h);
    assert(diffuse.w == depth.w);
    assert(diffuse.h == depth.h);
    int width = diffuse.w;
    int height = diffuse.h;

    writefln("width = %s  height = %s", width, height);

    class CustomGraphics : GUIGraphics
    {
        this()
        {
            super(width, height);
        }

        override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
        {
            diffuse.blitTo(diffuseMap);
            material.blitTo(materialMap);

            for (int j = 0; j < height; ++j)
            {
                L16[] depthScan = depthMap.scanline(j);
                RGBA[] depthInp = depth.scanline(j);
                for (int i = 0; i < width; ++i)
                {
                    depthScan[i].l = cast(ushort)(0.5 + 257 * (depthInp[i].g + depthInp[i].r + depthInp[i].b) / 3);
                }
            }
        }

        ImageRef!RGBA forceUpdate()
        {
            auto result = _windowListener.onResized(width, height);
            setDirtyWhole();
            _windowListener.recomputeDirtyAreas();
            _windowListener.onDraw(WindowPixelFormat.RGBA8);
            return result;
        }
    }

    CustomGraphics graphics = new CustomGraphics();
    scope(exit) graphics.destroy();
    graphics.context().setSkybox(skybox);

    ImageRef!RGBA rendered;
    
    // render one time for warming-up
    rendered = graphics.forceUpdate();

    long[] timeSamples = new long[timesRendering];
    long totalTime = 0;
    long minTime = long.max;
    
    foreach(time; 0..timesRendering)
    {
        long before = getTickUs();
        rendered = graphics.forceUpdate();
        long timeElapsed = getTickUs() - before;


        totalTime += timeElapsed;
        if (minTime > timeElapsed)
            minTime = timeElapsed;

        timeSamples[time] = timeElapsed;
    }

    writefln("Rendered %s times in %s sec", timesRendering, totalTime * 0.000001);
    writefln("Time samples: %s", timeSamples);
    writefln("Min  = %s ms", minTime / 1000.0);
    writefln("Mean = %s ms per render", (totalTime / 1000.0) / timesRendering );    

    string resultPath = buildPath(appDir, "result.png");

    assert(4 * rendered.w == rendered.pitch); // no pitch supported
    ubyte[] png = write_png_to_mem(rendered.w, rendered.h, cast(ubyte[])( rendered.pixels[0..width*height] ), 3);
    writefln("Writing %s bytes", png.length);
    std.file.write(resultPath, png);
}


