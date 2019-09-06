module rsrc;


struct RSRCResource
{
    int typeNum;
    ushort resourceID;
    bool purgeable;
    string name = null;
    const(ubyte)[] content;
    ushort nameOffset;
    uint dataOffset;
}

struct RSRCType
{
    char[4] id;
    int numRes()
    {
        return cast(int)(resIndices.length);
    }
    int[] resIndices; // indices of resources of this type
}

struct RSRCWriter
{
    ubyte[] buffer;
    RSRCResource[] resources;
    RSRCType[] types;

    void addType(char[4] id)
    {
        types ~= RSRCType(id, []);
    }


    void addResource(int typeNum, ushort resourceID, bool purgeable, string name, const(ubyte)[] content)
    {
        types[typeNum].resIndices ~= cast(int)(resources.length);
        resources ~= RSRCResource(typeNum, resourceID, purgeable, name, content);
    }

    ubyte[] write()
    {
        // compute resource data
        ubyte[] resourceData;
        foreach(r; resources)
        {
            r.dataOffset = cast(uint)resourceData.length;
            resourceData.writeBE_uint(cast(uint)(r.content.length));
            resourceData ~= r.content;
        }

        ubyte[] resourceMap = buildResourceMap();

        ubyte[] buffer;

        // Offset from beginning of resource file to resource data. Basically guaranteed to be 0x100.
        buffer.writeBE_uint(0x100);

        /// Offset from beginning of resource file to resource map.
        buffer.writeBE_uint(0x100 + cast(uint)(resourceData.length));

        // Length of resource data
        buffer.writeBE_uint(cast(uint)(resourceData.length));

        // Length of resource map
        buffer.writeBE_uint(cast(uint)(resourceMap.length));

        // System-reserved data. In practice, this is usually all null bytes.
        foreach(n; 0..112)
            buffer.writeBE_ubyte(0);
        foreach(n; 0..128)
            buffer.writeBE_ubyte(0);
        return buffer ~ resourceData ~ resourceMap;
    }

    ubyte[] buildResourceMap()
    {
        ubyte[] buf;
        foreach(n; 0..16 + 4 + 2)
            buf.writeBE_ubyte(0); // Note: rez duplicates the file first 16 bytes here...

        buf.writeBE_ushort(0);

        ubyte[] resourceName = buildResourceNameList();
        ubyte[] typelist = buildTypeList();

        // Offset from beginning of resource map to type list.
        buf.writeBE_ushort(28); // = size of resource map header

        // Offset from beginning of resource map to resource name list.
        buf.writeBE_ushort(cast(ushort)(28 + typelist.length));

        return buf ~ typelist ~ resourceName;
    }

    ubyte[] buildTypeList()
    {
        ubyte[] buf;
        buf.writeBE_ushort( cast(ushort)(types.length - 1));

        ubyte[] referenceLists;

        int offsetOfFirstReferenceList = 2 + cast(int)(types.length) * 8;

        foreach(t; types)
        {
            // Resource type. This is usually a 4-character ASCII mnemonic, but may be any 4 bytes.
            foreach(n; 0..4)
                buf.writeBE_ubyte(cast(ubyte)(t.id[n]));

            // Number of resources of this type in the map minus 1.
            buf.writeBE_ushort( cast(ushort)(t.numRes - 1));

            // Offset from beginning of type list to reference list for resources of this type.
            buf.writeBE_ushort( cast(ushort)( offsetOfFirstReferenceList + referenceLists.length) );

            // build reference list for this type
            foreach(rindex; 0..t.numRes)
            {
                const(RSRCResource) res = resources[t.resIndices[rindex]];

                // Resource ID
                referenceLists.writeBE_ushort(res.resourceID);

                // Offset from beginning of resource name list to length of resource name, or -1 (0xffff) if none.
                referenceLists.writeBE_ushort(res.nameOffset);

                // Resource attributes. Combination of ResourceAttrs flags, see below. (Note: packed into 4 bytes together with the next 3 bytes.)
                referenceLists.writeBE_ubyte(res.purgeable ? (1 << 5) : 0);

                // Offset from beginning of resource data to length of data for this resource. (Note: packed into 4 bytes together with the previous 1 byte.)
                uint doffset = res.dataOffset;
                referenceLists.writeBE_ubyte((doffset & 0xff0000) >> 16);
                referenceLists.writeBE_ubyte((doffset & 0x00ff00) >> 8);
                referenceLists.writeBE_ubyte((doffset & 0x0000ff) >> 0);

                // Reserved for handle to resource (in memory). Should be 0 in file.
                referenceLists.writeBE_uint(0);
            }
        }

        return buf ~ referenceLists;
    }

    ubyte[] buildResourceNameList()
    {
        ubyte[] buf;
        foreach(ref r; resources)
        {
            string name = r.name;

            if (name !is null)
            {
                r.nameOffset = cast(ushort)(buf.length);
                buf.writeBE_ubyte(cast(ubyte)(name.length));
                foreach(char ch; name)
                    buf.writeBE_ubyte(cast(ubyte)ch);
            }
            else
                r.nameOffset = 0xffff;
        }
        return buf;
    }

}

void writeBE_ubyte(ref ubyte[] buf, ubyte b)
{
    buf ~= b;
}

void writeBE_ushort(ref ubyte[] buf, ushort s)
{
    buf ~= (s >> 8) & 0xff;
    buf ~= (s >> 0) & 0xff;
}

void writeBE_uint(ref ubyte[] buf, uint u)
{
    buf ~= (u >> 24) & 0xff;
    buf ~= (u >> 16) & 0xff;
    buf ~= (u >>  8) & 0xff;
    buf ~= (u >>  0) & 0xff;
}

ubyte[] makeRSRC_pstring(string s)
{
    import std.stdio;
    assert(s.length <= 255);
    ubyte[] buf;
    buf.writeBE_ubyte(cast(ubyte)(s.length));
    foreach(char ch; s)
    {
        buf.writeBE_ubyte(cast(ubyte)(ch));
    }
    return buf;
}

ubyte[] makeRSRC_fourCC(char[4] ch)
{
    ubyte[] buf;
    buf.writeBE_ubyte(ch[0]);
    buf.writeBE_ubyte(ch[1]);
    buf.writeBE_ubyte(ch[2]);
    buf.writeBE_ubyte(ch[3]);
    return buf;
}

ubyte[] makeRSRC_fourCC_string(string fourcc)
{
    assert(fourcc.length == 4);
    ubyte[] buf;
    buf.writeBE_ubyte(fourcc[0]);
    buf.writeBE_ubyte(fourcc[1]);
    buf.writeBE_ubyte(fourcc[2]);
    buf.writeBE_ubyte(fourcc[3]);
    return buf;
}

ubyte[] makeRSRC_cstring(string s)
{
    ubyte[] buf;
    foreach(char ch; s)
    {
        buf.writeBE_ubyte(cast(ubyte)(ch));
    }
    buf.writeBE_ubyte(0);
    return buf;
}