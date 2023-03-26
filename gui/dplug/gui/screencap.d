module dplug.gui.screencap;

import dplug.core.vec;
import dplug.core.nogc;
import dplug.core.binrange;
import dplug.graphics.image;
import dplug.window;

import core.stdc.stdio;
import core.stdc.string;

nothrow @nogc:


/// Create a 3D voxel file representing the whole UI.
/// Export to a .qb file, as used as input by Qubicle, Goxel, and https://drububu.com/miscellaneous/voxelizer/
/// Use https://drububu.com/miscellaneous/voxelizer/ if you want to convert to a MagicaVoxel .vox
/// Alternatively: https://github.com/mgerhardy/vengi
/// Free the result with `free(slice.ptr)`.
ubyte[] encodeScreenshotAsQB(ImageRef!RGBA colorMap, 
                             WindowPixelFormat pf, // input pixel format
                             ImageRef!L16 depthMap)
{
    int DEPTH = 16;
    int ADD_DEPTH = 10; // Additional depth voxels, so that the plugin is more tight.

    int W = colorMap.w;
    int H = colorMap.h;

    Vec!ubyte vox = makeVec!ubyte;

    vox.writeLE!ubyte(1); // .qb version
    vox.writeLE!ubyte(1);
    vox.writeLE!ubyte(0);
    vox.writeLE!ubyte(0);
    vox.writeLE!uint(0); // RGBA
    vox.writeLE!uint(0); // left handed
    vox.writeLE!uint(0); // uncompressed
    vox.writeLE!uint(0); // alpha is 0 or 255, tells visibility
    vox.writeLE!uint(1); // one matrice in file
    vox.writeLE!ubyte(1); // matrix name
    vox.writeLE!ubyte('0');

    // read matrix size 
    vox.writeLE(W);
    vox.writeLE(DEPTH + ADD_DEPTH);
    vox.writeLE(H);

    vox.writeLE(0); 
    vox.writeLE(0);
    vox.writeLE(0); // position

    for (int z = 0; z < H; z++)
    {
        // y inverted in .vox vs screen
        L16[] depthScan = depthMap.scanline(z);  

        for (int y = 0; y < DEPTH + ADD_DEPTH; y++)
        {
            for (int x = 0; x < W; x++)
            {
                L16 depthHere = depthScan[x];
                // note: in magickavoxel, increasing depth is NOT towards viewer
                int depth = ADD_DEPTH + (DEPTH * depthHere.l) / 65536;
                RGBA color = colorMap[x, z];
                vox.writeLE!ubyte(color.r);
                vox.writeLE!ubyte(color.g);
                vox.writeLE!ubyte(color.b);
                if (depth >= y)
                    vox.writeLE!ubyte(255);
                else
                    vox.writeLE!ubyte(0);
            }
        }
    }
    return vox.releaseData;
}

/// Create a PNG screenshot of the whole UI.
/// Free the result with `free(slice.ptr)`.
ubyte[] encodeScreenshotAsPNG(ImageRef!RGBA colorMap, WindowPixelFormat pf)
{
    import gamut;
    Image source;
    source.createViewFromImageRef!RGBA(colorMap);

    // make a clone to own the memory
    Image image = source.clone();

    assert(image.type == PixelType.rgba8);
    assert(image.hasData);

    static void swapByte(ref ubyte a, ref ubyte b)
    {
        ubyte tmp = a;
        a = b;
        b = tmp;
    }

    final switch(pf)
    {
        case WindowPixelFormat.RGBA8: break;
        case WindowPixelFormat.BGRA8: 
            for (int y = 0; y < image.height(); ++y)
            {
                ubyte* scan = cast(ubyte*) image.scanptr(y);
                for (int x = 0; x < image.width(); ++x)
                {
                    swapByte(scan[4*x + 0], scan[4*x + 2]);
                }
            }
            break;
        case WindowPixelFormat.ARGB8:
            for (int y = 0; y < image.height(); ++y)
            {
                ubyte* scan = cast(ubyte*) image.scanptr(y);
                for (int x = 0; x < image.width(); ++x)
                {
                    ubyte a = scan[4*x + 0];
                    ubyte r = scan[4*x + 1];
                    ubyte g = scan[4*x + 2];
                    ubyte b = scan[4*x + 3];
                    scan[4*x + 0] = r;
                    scan[4*x + 1] = g;
                    scan[4*x + 2] = b;
                    scan[4*x + 3] = a;
                }
            }
            break;
    }        

    ubyte[] png = image.saveToMemory(ImageFormat.PNG);
    scope(exit) freeEncodedImage(png);

    // Return a duped slice because of different freeing functions
    return mallocDup(png);
}