/**
* PBR rendering, custom rendering.
*
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.compositor;

import gfm.math.box;

import dplug.core.vec;
import dplug.core.nogc;

import dplug.graphics.mipmap;
import dplug.graphics.drawex;
import dplug.graphics.image;
import dplug.graphics.view;

import dplug.gui.ransac;

import dplug.window.window;


import inteli.math;


/// Only deals with rendering tiles.
/// If you don't like Dplug default compositing, just make another Compositor
/// and assign the 'compositor' field in GUIGraphics.
/// However for now mipmaps are not negotiable, they will get generated outside this compositor.
interface ICompositor
{
nothrow:
@nogc:
    /// Setup the compositor to output a particular output size.
    ///
    /// Params:
    ///     width      The width of the given input mipmaps, and the width of the output image.
    ///     height     The height of the given input mipmaps, and the height of the output image.
    ///     areaMaxWidth  The maximum width of the `area` passed in `compositeTile`. This is useful to allocate smaller thread-local buffers.
    ///     areaMaxHeight The maximum height of the `area` passed in `compositeTile`. This is useful to allocate smaller thread-local buffers.
    ///
    /// Note: this call is always called before `compositeTile` is called, and never simultaneously.
    ///
    void resizeBuffers(int width, 
                       int height,
                       int areaMaxWidth,
                       int areaMaxHeight);

    /// From given input mipmaps, write output image into `wfb` with pixel format `pf`, for the output area `area`.
    ///
    /// Params:
    ///     threadIndex index of the thread 0 to `numThreads` - 1 that is tasked with repainting the area
    ///                 The number of threads is passed out of band, in the Compositor constructor.
    ///     wfb         Image to write the output pixels to.
    ///     diffuseMap  Diffuse input.  Basecolor + Emissive, the Compositor decides how it uses these channels.
    ///     materialMap Material input. Roughness + Metalness + Specular + Unused, the Compositor decides how it uses these channels.
    ///     depthMap    Depth input. A different of `FACTOR_Z` in the Z direction has a similar size as a displacement of one pixels.
    ///                 As such, the range of possible simulated depth is (ushort.max / FACTOR_Z) pixels.
    ///                 But ultimately, the Compositor decides how it uses these channels.
    ///     skybox      Environment texture. Cheap and dirty reflections, to simulate metals.
    ///
    /// Note: several threads will call this function concurrently. 
    ///       It is important to only deal with `area` to avoid clashing writes.
    ///
    void compositeTile(int threadIndex,
                       ImageRef!RGBA wfb, 
                       box2i area,
                       Mipmap!RGBA diffuseMap,
                       Mipmap!RGBA materialMap,
                       Mipmap!L16 depthMap,
                       Mipmap!RGBA skybox);
}

/// Customizable compositor. This owns an arbitrary number of passes.
class Compositor : ICompositor
{
public:
nothrow:
@nogc:

    this(int numThreads)
    {
        // override and add passes here. They will be `destroyFree` on exit.
    }

    ~this()
    {
        foreach(pass; _passes[])
        {
            destroyFree(pass);
        }
    }

    override void resizeBuffers(int width, 
                                int height,
                                int areaMaxWidth,
                                int areaMaxHeight)
    {
        foreach(pass; _passes)
        {
            pass.resizeBuffers(width, height, areaMaxWidth, areaMaxHeight);
        }
    }

    override void compositeTile(int threadIndex,
                                ImageRef!RGBA wfb, 
                                box2i area,
                                Mipmap!RGBA diffuseMap,
                                Mipmap!RGBA materialMap,
                                Mipmap!L16 depthMap,
                                Mipmap!RGBA skybox)
    {
        // Note: if you want to customize rendering further, you can add new buffers to a struct extending
        // CompositorPassBuffers, override `compositeTile` and you will still be able to use the legacy passes.
        CompositorPassBuffers buffers;
        buffers.outputBuf = &wfb;
        buffers.diffuseMap = diffuseMap;
        buffers.materialMap = materialMap;
        buffers.depthMap = depthMap;
        buffers.skybox = skybox;
        foreach(pass; _passes)
        {
            pass.renderIfActive(threadIndex, area, &buffers);
        }

        // final pass copy pixels into the `wfb` buffer
    }

private:
    // Implements ICompositor
    Vec!CompositorPass _passes;
}

struct CompositorPassBuffers
{
    ImageRef!RGBA* outputBuf;
    Mipmap!RGBA diffuseMap;
    Mipmap!RGBA materialMap;
    Mipmap!L16 depthMap;
    Mipmap!RGBA skybox; // TODO: this should be internal to the SkyboxPass instead    
}

interface ICompositorPass
{
nothrow:
@nogc:
    void resizeBuffers(int width, 
                       int height,
                       int areaMaxWidth,
                       int areaMaxHeight);
}


class CompositorPass : ICompositorPass
{
public:
nothrow:
@nogc:

    this(int numThreads)
    {
        _numThreads = numThreads;
        _active = true;
    }

    void setActive(bool active)
    {
        _active = active;
    }

    void renderIfActive(int threadIndex, const(box2i) area, CompositorPassBuffers* buffers)
    {
        if (_active)
            render(threadIndex, area, buffers);
    }

    abstract void render(int threadIndex, const(box2i) area, CompositorPassBuffers* buffers);

private:

    /// Whether the pass should execute on render. This breaks dirtiness if you change it.
    bool _active;

    /// Cached number of threads.
    int _numThreads;
}



