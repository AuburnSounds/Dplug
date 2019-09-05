module rsrc;
import dplug.client.binrange;



struct RSRCResource
{
    int typeNum;
    ushort resourceID;
    bool purgeable;
    string name = null;
    const(ubyte)[] content;
    ushort nameOffset;
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

    void addString(int typeNum, ushort resourceID, bool purgeable, string name, string s)
    {
        addResource(typeNum, resourceID, purgeable, name, cast(const(ubyte)[])s);
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
            resourceData.writeBE!uint(cast(uint)(r.content.length));
            resourceData ~= r.content;
        }

        ubyte[] resourceMap = buildResourceMap();

        ubyte[] buffer;

        // Offset from beginning of resource file to resource data. Basically guaranteed to be 0x100.
        buffer.writeBE!uint(0x100);

        /// Offset from beginning of resource file to resource map.
        buffer.writeBE!uint(0x100 + cast(uint)(resourceData.length));

        // Length of resource data
        buffer.writeBE!uint(cast(uint)(resourceData.length));

        // Length of resource map, unknown yet TODO
        buffer.writeBE!uint(cast(uint)(resourceMap.length));

        // System-reserved data. In practice, this is usually all null bytes.
        foreach(n; 0..112)
            buffer.writeBE!ubyte(0);
        foreach(n; 0..128)
            buffer.writeBE!ubyte(0);
        return buffer ~ resourceData ~ resourceMap;
    }

    ubyte[] buildResourceMap()
    {
        ubyte[] buf;
        foreach(n; 0..16 + 4 + 2)
            buf.writeBE!ubyte(0);

        buf.writeBE!ushort(0); // TODO which flags?

        ubyte[] resourceName = buildResourceNameList();
        ubyte[] typelist = buildTypeList();

        // Offset from beginning of resource map to type list.
        buf.writeBE!ushort(28); // = size of resource map header

        // Offset from beginning of resource map to resource name list.
        buf.writeBE!ushort(cast(ushort)(28 + typelist.length));

        return buf ~ typelist ~ resourceName;
    }

    ubyte[] buildTypeList()
    {
        ubyte[] buf;
        buf.writeBE!ushort( cast(ushort)(types.length - 1));

        ubyte[] referenceLists;

        int offsetOfFirstReferenceList = 2 + cast(int)(types.length) * 8;

        foreach(t; types)
        {
            // Resource type. This is usually a 4-character ASCII mnemonic, but may be any 4 bytes.
            foreach(n; 0..4)
                buf.writeBE!ubyte(cast(ubyte)(t.id[n]));

            // Number of resources of this type in the map minus 1.
            buf.writeBE!ushort( cast(ushort)(t.numRes - 1));

            // Offset from beginning of type list to reference list for resources of this type.
            buf.writeBE!ushort( cast(ushort)( offsetOfFirstReferenceList + referenceLists.length) );

            // build reference list for this type
            foreach(rindex; 0..t.numRes)
            {
                const(RSRCResource) res = resources[t.resIndices[rindex]];

                // Resource ID
                referenceLists.writeBE!ushort(res.resourceID);

                // Offset from beginning of resource name list to length of resource name, or -1 (0xffff) if none.
                referenceLists.writeBE!ushort(res.nameOffset);

                // Resource attributes. Combination of ResourceAttrs flags, see below. (Note: packed into 4 bytes together with the next 3 bytes.)
                referenceLists.writeBE!ubyte(res.purgeable ? (1 << 5) : 0);

                // Offset from beginning of resource data to length of data for this resource. (Note: packed into 4 bytes together with the previous 1 byte.)
                referenceLists.writeBE!ubyte(0);
                referenceLists.writeBE!ubyte(0); // TODO
                referenceLists.writeBE!ubyte(0); // ?????

                // Reserved for handle to resource (in memory). Should be 0 in file.
                referenceLists.writeBE!int(0);
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

            if (name is null)
            {
                r.nameOffset = cast(ushort)(buf.length);
                buf.writeBE!ubyte(cast(ubyte)(name.length));
                foreach(char ch; name)
                    buf.writeBE!ubyte(cast(ubyte)ch);
            }
            else
                r.nameOffset = 0xffff;
        }
        return buf;
    }

}