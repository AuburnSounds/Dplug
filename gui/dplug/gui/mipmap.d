module dplug.gui.mipmap;

import ae.utils.graphics;

import gfm.math;


/// Mipmapped images.
/// Supports non power-of-two textures.
/// Size of the i+1-th mipmap is { (width)/2, (height)/2 }
struct Mipmap
{
    Image!RGBA[] levels;

    /// Set number of levels and size
    /// maxLevel = 0 => only one image
    /// maxLevel = 1 => one image + one 2x downsampled mipmap
    void size(int maxLevel, int w, int h)
    {
        levels.length = 0;

        for (int level = 0; level <= maxLevel; ++level)
        {
            if (w == 0 || h == 0)
                break;
            levels.length = levels.length + 1;
            levels[level].size(w, h);
            w  = (w + 0) >> 1;
            h  = (h + 0) >> 1;
        }
    }

    /// Interpolates a color between mipmap levels.  Floating-point level, spatial linear interpolation.
    /// x and y are in base level coordinates (top-left pixel is on (0.5, 0.5) coordinates).
    /// Clamped to borders.
    vec3f linearMipmapSample(float level, float x, float y)
    {
        int ilevel = cast(int)level;
        float flevel = level - ilevel;
        return linearSample(ilevel, x, y) * (1 - flevel) + linearSample(ilevel + 1, x, y) * flevel;
    }

    /// Interpolates a color.  Integer level, spatial linear interpolation.
    /// x and y are in base level coordinates (top-left pixel is on (0.5, 0.5) coordinates).
    /// Clamped to borders.
    vec3f linearSample(int level, float x, float y)
    {
        if (level < 0)
            level = 0;
        int numLevels = cast(int)levels.length;
        if (level >= numLevels)
            level = numLevels - 1;

        Image!RGBA* image = &levels[level];

        float divider = 1.0f / (1 << level);
        x *= divider;
        y *= divider;

        float maxX = image.w - 1.001f; // avoids an edge case with truncation
        float maxY = image.h - 1.001f;

        if (x < 0)
            x = 0;
        if (y < 0)
            y = 0;
        if (x > maxX)
            x = maxX;
        if (y > maxY)
            y = maxY;

        int ix = cast(int)x;
        int iy = cast(int)y;
        float fx = x - ix;

        int ixp1 = ix + 1;
        if (ixp1 >= image.w)
            ixp1 = image.w - 1;
        int iyp1 = iy + 1;
        if (iyp1 >= image.h)
            iyp1 = image.h - 1;

        float fxm1 = 1 - fx;
        float fy = y - iy;
        float fym1 = 1 - fy;

        RGBA[] L0 = image.scanline(iy);
        RGBA[] L1 = image.scanline(iyp1);

        RGBA A = L0.ptr[ix];
        RGBA B = L0.ptr[ixp1];
        RGBA C = L1.ptr[ix];
        RGBA D = L1.ptr[ixp1];

        float rup = A.r * fxm1 + B.r * fx;
        float rdown = C.r * fxm1 + D.r * fx;
        float r = (A.r * fxm1 + B.r * fx) * fym1 + (C.r * fxm1 + D.r * fx) * fy;

        float gup = A.g * fxm1 + B.g * fx;
        float gdown = C.g * fxm1 + D.g * fx;
        float g = (A.g * fxm1 + B.g * fx) * fym1 + (C.g * fxm1 + D.g * fx) * fy;

        float bup = A.b * fxm1 + B.b * fx;
        float bdown = C.b * fxm1 + D.b * fx;
        float b = (A.b * fxm1 + B.b * fx) * fym1 + (C.b * fxm1 + D.b * fx) * fy;

        return vec3f(r, g, b);
    }

    /// Returns: Width of the base level.
    int width() pure const nothrow @nogc
    {
        return levels[0].w;
    }

    /// Returns: Height of the base level.
    int height() pure const nothrow @nogc
    {
        return levels[0].h;
    }

    /// Regenerates the whole upper levels.
    /// Uses a flat 2x2 filter
    void generateMipmaps()
    {
        generateMipmaps( box2i(0, 0, width(), height()) );
    }

    /// Regenerates the upper levels based on changes in the provided rectangle.
    /// Uses a flat 2x2 filter
    void generateMipmaps(box2i updateRect)
    {
        // Computes impact of updating the area box on next level
        static box2i impactOnNextLevel(box2i area, int currentLevelWidth, int currentLevelHeight)
        {
            int xmin = area.min.x / 2;
            int ymin = area.min.y / 2;
            int xmax = (area.max.x + 1) / 2;
            if (xmax >  currentLevelWidth / 2)
                xmax = currentLevelWidth / 2;
            int ymax = (area.max.y + 1) / 2;
            if (ymax >  currentLevelHeight / 2)
                ymax = currentLevelHeight / 2;
            return box2i(xmin, ymin, xmax, ymax);
        }

        for (int i = 1; i < cast(int)levels.length; ++i)
        {
            Image!RGBA* thisLevel = &levels[i];
            Image!RGBA* previousLevel = &levels[i - 1];

            updateRect = impactOnNextLevel(updateRect, previousLevel.w, previousLevel.h);

            for (int y = updateRect.min.y; y < updateRect.max.y; ++y)
            {
                RGBA[] L0 = previousLevel.scanline(y * 2);
                RGBA[] L1 = previousLevel.scanline(y * 2 + 1);
                RGBA[] dest = thisLevel.scanline(y);

                for (int x = updateRect.min.x; x < updateRect.max.x; ++x)
                {
                    RGBA A = L0.ptr[2 * x];
                    RGBA B = L0.ptr[2 * x + 1];
                    RGBA C = L1.ptr[2 * x];
                    RGBA D = L1.ptr[2 * x + 1];
                    dest.ptr[x] = RGBA.op!q{(a + b + c + d + 2) >> 2}(A, B, C, D);
                }
            }
        }
    }
}

unittest
{
    Mipmap a;
    a.size(4, 256, 256);

    Mipmap b;
    b.size(16, 17, 333);
}

