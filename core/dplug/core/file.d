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

/** 
    Replacement for `std.file.read`.

    Params:
        fileNameZ = A zero-terminated path.

    Returns: File content, allocated with `malloc`. `null` on error.
             The resulting slice gets an additional terminal zero byte
             ('\0') after the slice, so that it can be converted to a 
             C string at no cost.

             `null` on error.

    WARNING: `fileNameZ` MUST be followed by a terminal zero byte ('\0').
*/
ubyte[] readFile(const(char)[] fileNameZ)
{
    // FUTURE: this should be depreciated in favor of take a char*, 
    // this is confusing
    FILE* file = fopen(assumeZeroTerminated(fileNameZ), "rb".ptr);
    if (file)
    {
        scope(exit) fclose(file);

        // Finds the size of the file
        if (fseek(file, 0, SEEK_END) != 0)
            return null;

        long size = ftell(file);
        if (size < 0)
            return null;

        if (fseek(file, 0, SEEK_SET) != 0)
            return null;

        // Is this too large to read? 
        // Refuse to read more than 1gb file 
        // (if it happens, it's probably a bug).
        if (size > 1024*1024*1024)
            return null;

        // Read whole file in a mallocated slice
        // +1 for one additional '\0' byte
        ubyte[] fileBytes = mallocSliceNoInit!ubyte(cast(int)size + 1); 
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

        fileBytes[cast(size_t)size] = 0;

        return fileBytes[0..cast(size_t)size];
    }
    else
        return null;
}
///ditto
ubyte[] readFile(const(char)* fileNameZ)
{
    import core.stdc.string: strlen;
    return readFile(fileNameZ[0..strlen(fileNameZ)]);
}


/** 
    Replacement for `std.file.write`.

    Params:
        fileNameZ = A zero-terminated path.
        bytes = Content for the file to-be.

    Returns: false on error. File may exist or not in this case.

    WARNING: `fileNameZ` MUST be followed by a terminal zero byte ('\0').
*/
bool writeFile(const(char)[] fileNameZ, const(ubyte)[] bytes)
{
    // assuming that fileNameZ is zero-terminated, since it will in 
    // practice be a static string
    FILE* file = fopen(assumeZeroTerminated(fileNameZ), "wb".ptr);
    if (file)
    {
        scope(exit) fclose(file);

        size_t n = fwrite(bytes.ptr, 1, bytes.length, file);
        return n == bytes.length;
    }
    else
        return false;
}
///ditto
bool writeFile(const(char)* fileNameZ, const(ubyte)[] bytes)
{
    import core.stdc.string: strlen;
    return writeFile(fileNameZ[0..strlen(fileNameZ)], bytes);
}