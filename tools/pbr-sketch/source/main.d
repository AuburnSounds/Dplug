import std.file;
import std.stdio;
import dplug.gui;
import ae.utils.graphics;
import gfm.image;
import std.path;

void main(string[] args)
{
    string appDir = dirName(thisExePath());
    string basecolorName = buildPath(appDir, "basecolor.png");
    string materialName = buildPath(appDir, "material.png");
    string emissiveName = buildPath(appDir, "emissive.png");
    string physicalName = buildPath(appDir, "physical.png");
    string depthName = buildPath(appDir, "depth.png");

    Image!RGBA diffuse = loadImageSeparateAlpha(std.file.read(basecolorName), std.file.read(emissiveName));
    Image!RGBA material = loadImageSeparateAlpha(std.file.read(materialName), std.file.read(physicalName));
    Image!RGBA depth = loadImage(std.file.read(depthName));

    string diffuseCopy = buildPath(appDir, "diffuse-copy.png");

    string skyboxPath = buildPath(appDir, "skybox.jpg");
    Image!RGBA skybox = loadImage(std.file.read(skyboxPath));

    assert(diffuse.w == material.w);
    assert(diffuse.h == material.h);
    assert(diffuse.w == depth.w);
    assert(diffuse.h == depth.h);
    int width = diffuse.w;
    int height = diffuse.h;

    writefln("width = %s  height = %s", width, height);
    Image!RGBA result;
    result.size(width, height);

    class CustomGraphics : GUIGraphics
    {
        this()
        {
            super(width, height);
        }

        override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
        {
            diffuse.blitTo(diffuseMap);
            material.blitTo(materialMap);

            for (int j = 0; j < height; ++j)
                for (int i = 0; i < width; ++i)
                    depthMap[i, j].l = cast(ushort)(0.5 + 257 * (depth[i, j].g + depth[i, j].r + depth[i, j].b) / 3);
        }

        void forceUpdate()
        {
            _windowListener.onResized(width, height);
            setDirty();
            _windowListener.recomputeDirtyAreas();
            _windowListener.onDraw(result.toRef, WindowPixelFormat.RGBA8);
        }
    }


    CustomGraphics graphics = new CustomGraphics();
    graphics.context().setSkybox(skybox);
    graphics.forceUpdate();
    graphics.destroy();

    string resultPath = buildPath(appDir, "result.png");
    auto png = result.toPNG();
    writefln("Writing %s bytes", png.length);
    std.file.write(resultPath, png);
}


