module dplug.gui.voxexport;

import dplug.core.vec;
import dplug.core.binrange;
import dplug.graphics.image;
import dplug.window;

nothrow @nogc:

/// Export a .vox format used by MagicaVoxel
/// This can be useful for post-hoc 3D renders of existing PBR plugins.
/// Params:
///    color RGB image, alpha is ignored.
///    depth depth image
/// Note that actual voxel depth is rounded in order not to make a 65535-high voxel mesh.
/// Return value must be free with `free`.
ubyte[] encodePBRBuffersToVOX(ImageRef!RGBA colorMap, 
                              WindowPixelFormat pf, // input pixel format
                              ImageRef!L16 depthMap)
{
    int DEPTH = 16;

    // limitation of today
    int W = colorMap.w;
    if (W > 256) W = 256;
    int H = colorMap.h;
    if (H > 256) H = 256;

    Vec!ubyte vox = makeVec!ubyte;
    vox.writeBE!uint(RIFFChunkId!"VOX ");
    vox.writeLE!uint(150); // version
    
    vox.writeBE!uint(RIFFChunkId!"MAIN");
    vox.writeLE!uint(0); // temporary chunk size

    size_t mainChildrenSizeIndex = vox.length;
    vox.writeLE!uint(0); // temporary children chunk size

    // TODO: several objects for each 256x256 slices
    
    vox.writeBE!uint(RIFFChunkId!"SIZE");
    vox.writeLE!uint(12); // SIZE chunk size
    vox.writeLE!uint(0);  // no children
    vox.writeLE!uint(W); // width
    vox.writeLE!uint(DEPTH); // depth
    vox.writeLE!uint(H); // height

    vox.writeBE!uint(RIFFChunkId!"XYZI");
    size_t xyziSizeIndex = vox.length;
    vox.writeLE!uint(0); // XYZI chunk size // will be = 4 + 4 * numVoxels
    vox.writeLE!uint(0);  // no children

    size_t xyziNumIndex = vox.length;
    vox.writeLE!uint(0);  // unknown number of voxels, for now

    uint numVoxels = 0;

    for (int y = 0; y < H; ++y)
    {
        RGBA[] scan = colorMap.scanline(H-1-y); // y inverted in .vox vs screen
        for (int x = 0; x < W; ++x)
        {
            L16 depthHere = depthMap[x, H-1-y];
            int depth = (DEPTH * (65535 - depthHere.l)) / 65536; // note: in magickavoxel, increasing depth is NOT towards viewer
            assert(depth >= 0 && depth < DEPTH);
            RGBA color = scan[x];
            final switch (pf)
            {
                case WindowPixelFormat.RGBA8:
                    break;
                case WindowPixelFormat.BGRA8:
                    ubyte tmp = color.r;
                    color.r = color.b;
                    color.b = tmp;
                    break;
                case WindowPixelFormat.ARGB8:
                    ubyte tmp = color.r;
                    color.r = color.a;
                    color.a = color.b;
                    color.b = color.g;
                    color.g = tmp;
                    break;
            }

            ubyte colIndex = findNearestColor(color);

            // A column of dots
            
            for (int d = depth; d < DEPTH; ++d)
            {
                vox.put(cast(ubyte)x);
                vox.put(cast(ubyte)d);
                vox.put(cast(ubyte)y);
                vox.put(colIndex);
                numVoxels++;
            }
        }
    }

    write_LE_uint(&vox[xyziNumIndex], numVoxels);

    size_t endChunkXYZI = vox.length;
    write_LE_uint(&vox[xyziSizeIndex], cast(uint)(endChunkXYZI - xyziSizeIndex - 8));

    size_t endChunkMain = vox.length;
    write_LE_uint(&vox[mainChildrenSizeIndex], cast(uint)(endChunkMain - mainChildrenSizeIndex - 4));
    return vox.releaseData;
}

private
{
    static immutable uint[256] defaultPalette =
    [
        0x00000000, 0xffffffff, 0xffccffff, 0xff99ffff, 0xff66ffff, 0xff33ffff, 0xff00ffff, 0xffffccff, 0xffccccff, 0xff99ccff, 0xff66ccff, 0xff33ccff, 0xff00ccff, 0xffff99ff, 0xffcc99ff, 0xff9999ff,
        0xff6699ff, 0xff3399ff, 0xff0099ff, 0xffff66ff, 0xffcc66ff, 0xff9966ff, 0xff6666ff, 0xff3366ff, 0xff0066ff, 0xffff33ff, 0xffcc33ff, 0xff9933ff, 0xff6633ff, 0xff3333ff, 0xff0033ff, 0xffff00ff,
        0xffcc00ff, 0xff9900ff, 0xff6600ff, 0xff3300ff, 0xff0000ff, 0xffffffcc, 0xffccffcc, 0xff99ffcc, 0xff66ffcc, 0xff33ffcc, 0xff00ffcc, 0xffffcccc, 0xffcccccc, 0xff99cccc, 0xff66cccc, 0xff33cccc,
        0xff00cccc, 0xffff99cc, 0xffcc99cc, 0xff9999cc, 0xff6699cc, 0xff3399cc, 0xff0099cc, 0xffff66cc, 0xffcc66cc, 0xff9966cc, 0xff6666cc, 0xff3366cc, 0xff0066cc, 0xffff33cc, 0xffcc33cc, 0xff9933cc,
        0xff6633cc, 0xff3333cc, 0xff0033cc, 0xffff00cc, 0xffcc00cc, 0xff9900cc, 0xff6600cc, 0xff3300cc, 0xff0000cc, 0xffffff99, 0xffccff99, 0xff99ff99, 0xff66ff99, 0xff33ff99, 0xff00ff99, 0xffffcc99,
        0xffcccc99, 0xff99cc99, 0xff66cc99, 0xff33cc99, 0xff00cc99, 0xffff9999, 0xffcc9999, 0xff999999, 0xff669999, 0xff339999, 0xff009999, 0xffff6699, 0xffcc6699, 0xff996699, 0xff666699, 0xff336699,
        0xff006699, 0xffff3399, 0xffcc3399, 0xff993399, 0xff663399, 0xff333399, 0xff003399, 0xffff0099, 0xffcc0099, 0xff990099, 0xff660099, 0xff330099, 0xff000099, 0xffffff66, 0xffccff66, 0xff99ff66,
        0xff66ff66, 0xff33ff66, 0xff00ff66, 0xffffcc66, 0xffcccc66, 0xff99cc66, 0xff66cc66, 0xff33cc66, 0xff00cc66, 0xffff9966, 0xffcc9966, 0xff999966, 0xff669966, 0xff339966, 0xff009966, 0xffff6666,
        0xffcc6666, 0xff996666, 0xff666666, 0xff336666, 0xff006666, 0xffff3366, 0xffcc3366, 0xff993366, 0xff663366, 0xff333366, 0xff003366, 0xffff0066, 0xffcc0066, 0xff990066, 0xff660066, 0xff330066,
        0xff000066, 0xffffff33, 0xffccff33, 0xff99ff33, 0xff66ff33, 0xff33ff33, 0xff00ff33, 0xffffcc33, 0xffcccc33, 0xff99cc33, 0xff66cc33, 0xff33cc33, 0xff00cc33, 0xffff9933, 0xffcc9933, 0xff999933,
        0xff669933, 0xff339933, 0xff009933, 0xffff6633, 0xffcc6633, 0xff996633, 0xff666633, 0xff336633, 0xff006633, 0xffff3333, 0xffcc3333, 0xff993333, 0xff663333, 0xff333333, 0xff003333, 0xffff0033,
        0xffcc0033, 0xff990033, 0xff660033, 0xff330033, 0xff000033, 0xffffff00, 0xffccff00, 0xff99ff00, 0xff66ff00, 0xff33ff00, 0xff00ff00, 0xffffcc00, 0xffcccc00, 0xff99cc00, 0xff66cc00, 0xff33cc00,
        0xff00cc00, 0xffff9900, 0xffcc9900, 0xff999900, 0xff669900, 0xff339900, 0xff009900, 0xffff6600, 0xffcc6600, 0xff996600, 0xff666600, 0xff336600, 0xff006600, 0xffff3300, 0xffcc3300, 0xff993300,
        0xff663300, 0xff333300, 0xff003300, 0xffff0000, 0xffcc0000, 0xff990000, 0xff660000, 0xff330000, 0xff0000ee, 0xff0000dd, 0xff0000bb, 0xff0000aa, 0xff000088, 0xff000077, 0xff000055, 0xff000044,
        0xff000022, 0xff000011, 0xff00ee00, 0xff00dd00, 0xff00bb00, 0xff00aa00, 0xff008800, 0xff007700, 0xff005500, 0xff004400, 0xff002200, 0xff001100, 0xffee0000, 0xffdd0000, 0xffbb0000, 0xffaa0000,
        0xff880000, 0xff770000, 0xff550000, 0xff440000, 0xff220000, 0xff110000, 0xffeeeeee, 0xffdddddd, 0xffbbbbbb, 0xffaaaaaa, 0xff888888, 0xff777777, 0xff555555, 0xff444444, 0xff222222, 0xff111111
    ];

    ubyte findNearestColor(RGBA c)
    {
        if (c.a == 0)
            return 0;
        int bestIndex = 0;
        int bestScore = int.max;
        for (int n = 1; n < 256; ++n)
        {
            uint pal = defaultPalette[n];
            int r = (pal >> 16) & 255;
            int g = (pal >> 8) & 255;
            int b = (pal >> 0) & 255;
            int score = (r - c.r)*(r - c.r) + (g - c.g)*(g - c.g) + (b - c.b)*(b - c.b);
            if (score < bestScore)
            {
                bestScore = score;
                bestIndex = n;
                if (score == 0)
                    break;
            }
        }
        return cast(ubyte)bestIndex;
    }

    void write_LE_uint(ubyte* bytes, uint v) 
    {
        bytes[0] = (0x000000ff & v);
        bytes[1] = (0x0000ff00 & v) >> 8;
        bytes[2] = (0x00ff0000 & v) >> 16;
        bytes[3] = (0xff000000 & v) >> 24;
    }
}
