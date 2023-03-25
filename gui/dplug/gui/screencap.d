module dplug.gui.screencap;

import dplug.core.vec;
import dplug.core.binrange;
import dplug.graphics.image;
import dplug.window;

import core.stdc.stdio;
import core.stdc.string;

nothrow @nogc:


/// Create a 3D voxel file representing the whole UI.
/// Export to a .qb file, as used as input by Qubicle, Goxel, and https://drububu.com/miscellaneous/voxelizer/
/// Use https://drububu.com/miscellaneous/voxelizer/ if you want to convert to a MagicaVoxel .vox
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
