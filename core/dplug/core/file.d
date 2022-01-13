/**
Reading files without the D runtime.

Copyright: Guillaume Piolat 2015-2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.core.file;

import core.stdc.stdio;

import dplug.core.nogc;

nothrow:
@nogc:

/// Replacement for `std.file.read`.
/// Returns: File contents, allocated with malloc. `null` on error.
/// Note: the result file gets an additional terminal zero after the slice, so that 
/// it can be converted to a C string at no cost. 
// FUTURE: this should be depreciated in favor of take a char*, this is confusing
ubyte[] readFile(const(char)[] fileNameZ)
{
    // assuming that fileNameZ is zero-terminated, since it will in practice be
    // a static string
    FILE* file = fopen(assumeZeroTerminated(fileNameZ), "rb".ptr);
    if (file)
    {
        scope(exit) fclose(file);

        // finds the size of the file
        fseek(file, 0, SEEK_END);
        long size = ftell(file);
        fseek(file, 0, SEEK_SET);

        // Is this too large to read? 
        // Refuse to read more than 1gb file (if it happens, it's probably a bug).
        if (size > 1024*1024*1024)
            return null;

        // Read whole file in a mallocated slice
        ubyte[] fileBytes = mallocSliceNoInit!ubyte(cast(int)size + 1); // room for one additional '\0' byte
        size_t remaining = cast(size_t)size;

        ubyte* p = fileBytes.ptr;

        while (remaining > 0)
        {
            size_t bytesRead = fread(p, 1, remaining, file);
            if (bytesRead == 0)
            {
                freeSlice(fileBytes);
                return null;
            }
            p += bytesRead;
            remaining -= bytesRead;
        }

        fileBytes[size] = 0;

        return fileBytes[0..size];
    }
    else
        return null;
}
ubyte[] readFile(const(char)* fileNameZ)
{
    import core.stdc.string: strlen;
    return readFile(fileNameZ[0..strlen(fileNameZ)]);
}
