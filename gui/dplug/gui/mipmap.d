module dplug.gui.mipmap;

import ae.utils.graphics;

import gfm.math;


/// Mipmapped images.
/// Supports non power-of-two textures.
/// Size of the i+1-th mipmap is { (width)/2, (height)/2 }
struct Mipmap(COLOR)
{
    Image!COLOR[] levels;

    /// Set number of levels and size
    /// maxLevel = 0 => only one image
    /// maxLevel = 1 => one image + one 2x downsampled mipmap
    void size(int maxLevel, int w, int h)
    {
        levels.length = maxLevel + 1;

        for (int level = 0; level <= maxLevel; ++level)
        {
            levels[level].size(w, h);
            w  = (w + 0) >> 1;
            h  = (h + 0) >> 1;
        }
    }

    /// Regenerates the uppser levels based on changes in the provided rectangle.
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
            ImageRef!COLOR thisLevel = levels[i].toRef();
            ImageRef!COLOR previousLevel = levels[i - 1].toRef();

            updateRect = impactOnNextLevel(updateRect, previousLevel.w, previousLevel.h);

            for (int y = updateRect.min.y; y < updateRect.max.y; ++y)
            {
                COLOR[] L0 = previousLevel.scanline(y * 2);
                COLOR[] L1 = previousLevel.scanline(y * 2 + 1);
                COLOR[] dest = thisLevel.scanline(y);

                for (int x = updateRect.min.x; x < updateRect.max.x; ++x)
                {
                    COLOR A = L0.ptr[2 * x];
                    COLOR B = L0.ptr[2 * x + 1];
                    COLOR C = L1.ptr[2 * x];
                    COLOR D = L1.ptr[2 * x + 1];                      
                    dest.ptr[x] = COLOR.op!q{(a + b + c + d + 2) >> 2}(A, B, C, D);
                }
            }
        }
    }
}

unittest
{
    Mipmap!RGBA a;
    a.size(4, 256, 256);

    Mipmap!S16 b;
    b.size(16, 17, 333);    
}