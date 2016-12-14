import std.file;
import std.stdio;
import dplug.gui;
import dplug.graphics;
import std.path;
import imageformats;

void main(string[] args)
{
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
    ImageRef!RGBA rendered = graphics.forceUpdate();

    writeln(rendered.pixels[0]);
    string resultPath = buildPath(appDir, "result.png");

    assert(4 * rendered.w == rendered.pitch); // no pitch supported
    ubyte[] png = write_png_to_mem(rendered.w, rendered.h, cast(ubyte[])( rendered.pixels[0..width*height] ), 3);
    writefln("Writing %s bytes", png.length);
    std.file.write(resultPath, png);
}


