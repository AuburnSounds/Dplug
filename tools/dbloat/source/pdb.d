module pdb;

import std.string;
import std.conv;
import std.algorithm;


enum SymbolCategory
{
    otherDCode, // stuff that is not recognized to be msvc, phobos, or druntime, probably YOUR CODE
    msvc,
    phobos,
    druntime,
    ldata,
    undef, // not sure what this is, bad category
    gdata,
    thunk,
    public_,
    const_,
}

enum int SYMBOL_NUM_CATEGORIES = cast(int)(SymbolCategory.max + 1);

string symbolCategoryName(SymbolCategory cat)
{
    final switch (cat) with (SymbolCategory)
    {
        case thunk: return "thunk";
        case public_: return "public";
        case const_: return "const";
        case ldata: return "ldata";
        case gdata: return "gdata";
        case msvc: return "msvc";
        case phobos: return "phobos";
        case druntime: return "druntime";
        case otherDCode: return "other";
        case undef: return "undef";
    }
}

string symbolCategoryColor(SymbolCategory cat)
{
    final switch (cat) with (SymbolCategory)
    {
        case thunk: return "grey";
        case public_: return "grey";
        case const_: return "grey";
        case ldata: return "white";
        case gdata: return "lmagenta";
        case msvc: return "lblue";
        case phobos: return "yellow";
        case druntime: return "yellow";
        case otherDCode: return "lgreen";
        case undef: return "lred"; // because it's misclassified
    }
}

bool symbolCategoryDefaultVisibility(SymbolCategory cat)
{
    final switch (cat) with (SymbolCategory)
    {
        case thunk: return false;
        case public_: return false;
        case const_: return false;
        case ldata: return false;
        case gdata: return false;
        case msvc: return false;
        case phobos: return false;
        case druntime: return false;
        case otherDCode: return true;
        case undef: return true; // because it's probably misclassified
    }
}

// classify all symbols to be able to make a camembert
SymbolCategory categorizeSymbol(SymbolInfo sym)
{
    // Always 6 bytes mostly
    if (sym.kind == "THUNK")
        return SymbolCategory.thunk;

    if (sym.kind == "PUBLIC") // symbol with no size
        return SymbolCategory.public_;

    if (sym.kind == "CONST") // symbol with no size, manifest constant
        return SymbolCategory.const_;

    // TPI parsing incomplete
    if (sym.kind == "LDATA")
        return SymbolCategory.ldata;

    // TPI parsing incomplete
    if (sym.kind == "GDATA")
        return SymbolCategory.gdata;

    if (sym.isMSVCSymbol())
        return SymbolCategory.msvc;

    if (sym.isPhobosSymbol())
        return SymbolCategory.phobos;

    if (sym.isDRuntimeSymbol())
        return SymbolCategory.druntime;

    if (sym.isDSymbol())
        return SymbolCategory.otherDCode;

    return SymbolCategory.undef;
}



// PDB file uses MSF (Multi-Stream File) format
// Magic signature for PDB 7.0 format
immutable string PDB_SIGNATURE = "Microsoft C/C++ MSF 7.00\r\n\x1ADS\0\0\0";

struct MSFSuperBlock 
{
    char[32] FileMagic;
    uint BlockSize;
    uint FreeBlockMapBlock;
    uint NumBlocks;
    uint NumDirectoryBytes;
    uint Unknown;
    uint BlockMapAddr;
}

struct PDBStreamHeader 
{
    uint Version;
    uint Signature;
    uint Age;
    ubyte[16] Guid;
}

struct SymbolInfo 
{
    string name;
    uint section;
    uint offset;
    string kind;
    uint size;  // Size in bytes (for functions)
    string moduleName;  // Source module/object file

    SymbolCategory category; // more usable semantic categories

    string getDemangled()
    {
        import std.demangle;
        if (isDSymbol)
            return demangle(name);
        else 
            return name;
    }

    bool isDSymbol()
    {
        // No way to know, since we have demangled names it seems
        return true;/*
        cwriteln("NAME IS ", name);
        return name.startsWith("_D");*/
    }

    bool isPhobosSymbol()
    {
      /*  if (!isDSymbol())
        {
            cwriteln(getDemangled(), " is not a D symbol");
            return false;
        } */

        if(getDemangled().indexOf("std.") != -1)
            return true;
        return false;
    }

    bool isDRuntimeSymbol()
    {
        /*if (!isDSymbol())
            return false;*/

        // Complete this if misclassified

        string demangled = getDemangled();
        if(demangled.indexOf("object.") != -1)
            return true;
        if(demangled.indexOf("core.internal.") != -1)
            return true;

        if(demangled.indexOf("core.lifetime") != -1)
            return true;

        if(demangled.indexOf("core.memory") != -1)
            return true;

        if(demangled.indexOf("core.exception") != -1)
            return true;
            
        return false;
    }

    bool isMSVCSymbol()
    {
        if(moduleName.indexOf("libcmt") != -1)
            return true;
        if(moduleName.indexOf("libvcruntime") != -1)
            return true;
        if(moduleName.indexOf("ucrt") != -1)
            return true;
        if(moduleName.indexOf("vcstartup") != -1)
            return true;
        if(moduleName.indexOf("crts") != -1)
            return true;
        return false;
    }
}

struct PDBParseResult 
{
    bool success;
    string error;
    uint blockSize;
    uint numStreams;
    uint age;
    ubyte[16] guid;
    string[] streamNames;
    SymbolInfo[] symbols;

    void categorizeAll()
    {
        foreach(ref sym; symbols)
        {
            sym.category = categorizeSymbol(sym);
        }
    }
}

// TPI Stream Header (Type Info)
struct TPIStreamHeader {
    uint Version;
    uint HeaderSize;
    uint TypeIndexBegin;   // First type index (usually 0x1000)
    uint TypeIndexEnd;     // One past last type index
    uint TypeRecordBytes;  // Size of type record data
    // More fields follow but we only need these
}

// Get size of a simple/primitive type (type index < 0x1000)
uint getSimpleTypeSize(uint typeIndex) {
    // Simple type encoding:
    // Bits 0-3: type (int, float, etc.)
    // Bits 4-7: size/mode
    // Bits 8-11: pointer mode (0 = not pointer)
    
    uint pointerMode = (typeIndex >> 8) & 0xF;
    if (pointerMode != 0) {
        // It's a pointer type
        // Mode 2 = 32-bit pointer, mode 3 = 64-bit pointer
        if (pointerMode == 2) return 4;  // 32-bit pointer
        if (pointerMode == 3) return 8;  // 64-bit pointer
        return 8;  // Assume 64-bit for other modes
    }
    
    uint baseType = typeIndex & 0xFF;
    
    // Common simple types
    switch (baseType) {
        case 0x00: return 0;   // T_NOTYPE
        case 0x03: return 0;   // T_VOID
        case 0x10: return 1;   // T_CHAR
        case 0x20: return 1;   // T_UCHAR
        case 0x68: return 1;   // T_INT1
        case 0x69: return 1;   // T_UINT1
        case 0x11: return 2;   // T_SHORT
        case 0x21: return 2;   // T_USHORT
        case 0x72: return 2;   // T_INT2
        case 0x73: return 2;   // T_UINT2
        case 0x12: return 4;   // T_LONG
        case 0x22: return 4;   // T_ULONG
        case 0x74: return 4;   // T_INT4
        case 0x75: return 4;   // T_UINT4
        case 0x13: return 8;   // T_QUAD
        case 0x23: return 8;   // T_UQUAD
        case 0x76: return 8;   // T_INT8
        case 0x77: return 8;   // T_UINT8
        case 0x40: return 4;   // T_REAL32 (float)
        case 0x41: return 8;   // T_REAL64 (double)
        case 0x42: return 10;  // T_REAL80
        case 0x30: return 1;   // T_BOOL08
        case 0x31: return 2;   // T_BOOL16
        case 0x32: return 4;   // T_BOOL32
        case 0x33: return 8;   // T_BOOL64
        case 0x70: return 1;   // T_RCHAR (really a char)
        case 0x71: return 2;   // T_WCHAR
        case 0x7A: return 4;   // T_CHAR32
        default: return 0;     // Unknown
    }
}

// Type size lookup table (built from TPI stream)
struct TypeSizeTable {
    uint[] sizes;       // Sizes indexed by (typeIndex - typeIndexBegin)
    uint typeIndexBegin;
    uint typeIndexEnd;
    
    uint getSize(uint typeIndex) {
        if (typeIndex < 0x1000) {
            return getSimpleTypeSize(typeIndex);
        }
        if (typeIndex >= typeIndexBegin && typeIndex < typeIndexEnd) {
            return sizes[typeIndex - typeIndexBegin];
        }
        return 0;  // Unknown type
    }
}

// Parse TPI stream to build type size table
TypeSizeTable parseTPIStream(ubyte[] tpiData) {
    TypeSizeTable table;
    
    if (tpiData.length < TPIStreamHeader.sizeof) return table;
    
    auto header = *cast(TPIStreamHeader*)(tpiData.ptr);
    
    table.typeIndexBegin = header.TypeIndexBegin;
    table.typeIndexEnd = header.TypeIndexEnd;
    
    uint numTypes = header.TypeIndexEnd - header.TypeIndexBegin;
    table.sizes = new uint[numTypes];
    
    // Track types that reference other types (for second pass resolution)
    uint[] typeRefs = new uint[numTypes];  // 0 = no ref, else = referenced type index
    
    // Type records start after the header
    size_t offset = header.HeaderSize;
    uint typeIdx = 0;
    
    while (offset + 4 <= tpiData.length && typeIdx < numTypes) {
        ushort recLen = *cast(ushort*)(tpiData.ptr + offset);
        ushort leafType = *cast(ushort*)(tpiData.ptr + offset + 2);
        
        if (recLen < 2 || offset + 2 + recLen > tpiData.length) break;
        
        uint size = 0;
        uint refType = 0;
        
        switch (leafType) {
            case 0x1001: // LF_MODIFIER - modified type, get underlying size
                if (recLen >= 6) {
                    uint underlyingType = *cast(uint*)(tpiData.ptr + offset + 4);
                    if (underlyingType < 0x1000) {
                        size = getSimpleTypeSize(underlyingType);
                    } else {
                        // Store reference for second pass
                        refType = underlyingType;
                    }
                }
                break;
                
            case 0x1002: // LF_POINTER
                // All pointers are 8 bytes on x64
                size = 8;
                break;
                
            case 0x1503: // LF_ARRAY
                // LF_ARRAY: elemType(4) + idxType(4) + size(variable) + name
                if (recLen >= 10) {
                    // Size is encoded as a numeric leaf after the two type indices
                    size_t sizeOffset = offset + 12;
                    if (sizeOffset < tpiData.length) {
                        size = readNumericLeaf(tpiData, sizeOffset);
                    }
                }
                break;
                
            case 0x1504: // LF_CLASS
            case 0x1505: // LF_STRUCTURE
                // Structure: count(2) + property(2) + field(4) + derived(4) + vshape(4) + size(variable) + name
                if (recLen >= 20) {
                    size_t sizeOffset = offset + 20;
                    if (sizeOffset < tpiData.length) {
                        size = readNumericLeaf(tpiData, sizeOffset);
                    }
                }
                break;
                
            case 0x1506: // LF_UNION
                // Union: count(2) + property(2) + field(4) + size(variable) + name
                if (recLen >= 12) {
                    size_t sizeOffset = offset + 12;
                    if (sizeOffset < tpiData.length) {
                        size = readNumericLeaf(tpiData, sizeOffset);
                    }
                }
                break;
                
            case 0x1507: // LF_ENUM
                // Enum: count(2) + property(2) + utype(4) + field(4) + name
                // Size is determined by underlying type
                if (recLen >= 12) {
                    uint utype = *cast(uint*)(tpiData.ptr + offset + 8);
                    if (utype < 0x1000) {
                        size = getSimpleTypeSize(utype);
                    } else {
                        refType = utype;
                    }
                }
                if (size == 0 && refType == 0) size = 4;  // Default enum size
                break;
                
            case 0x1008: // LF_PROCEDURE
            case 0x1009: // LF_MFUNCTION
                // Procedures don't have a size (they're function types)
                size = 0;
                break;
                
            default:
                // Unknown type, leave size as 0
                break;
        }
        
        table.sizes[typeIdx] = size;
        typeRefs[typeIdx] = refType;
        
        // Move to next record
        offset += 2 + recLen;
        typeIdx++;
    }
    
    // Second pass: resolve type references (LF_MODIFIER, LF_ENUM with complex underlying type)
    // Iterate until no more changes (handles chains of references)
    bool changed = true;
    int maxIterations = 10;  // Prevent infinite loops
    while (changed && maxIterations > 0) {
        changed = false;
        maxIterations--;
        foreach (i; 0 .. numTypes) {
            if (table.sizes[i] == 0 && typeRefs[i] != 0) {
                uint refIdx = typeRefs[i];
                if (refIdx < 0x1000) {
                    table.sizes[i] = getSimpleTypeSize(refIdx);
                    changed = true;
                } else if (refIdx >= table.typeIndexBegin && refIdx < table.typeIndexEnd) {
                    uint resolvedSize = table.sizes[refIdx - table.typeIndexBegin];
                    if (resolvedSize > 0) {
                        table.sizes[i] = resolvedSize;
                        changed = true;
                    }
                }
            }
        }
    }
    
    return table;
}

// Read a numeric leaf value (used for sizes in type records)
uint readNumericLeaf(ubyte[] data, size_t offset) {
    if (offset + 2 > data.length) return 0;
    
    ushort value = *cast(ushort*)(data.ptr + offset);
    
    // If value < 0x8000, it's a direct 16-bit value
    if (value < 0x8000) {
        return value;
    }
    
    // Otherwise it's a numeric leaf type
    switch (value) {
        case 0x8000: // LF_CHAR
            if (offset + 3 <= data.length)
                return cast(uint)(cast(byte)data[offset + 2]);
            break;
        case 0x8001: // LF_SHORT
            if (offset + 4 <= data.length)
                return cast(uint)(*cast(short*)(data.ptr + offset + 2));
            break;
        case 0x8002: // LF_USHORT
            if (offset + 4 <= data.length)
                return *cast(ushort*)(data.ptr + offset + 2);
            break;
        case 0x8003: // LF_LONG
            if (offset + 6 <= data.length)
                return cast(uint)(*cast(int*)(data.ptr + offset + 2));
            break;
        case 0x8004: // LF_ULONG
            if (offset + 6 <= data.length)
                return *cast(uint*)(data.ptr + offset + 2);
            break;
        case 0x8009: // LF_QUADWORD
        case 0x800A: // LF_UQUADWORD
            if (offset + 10 <= data.length)
                return cast(uint)(*cast(ulong*)(data.ptr + offset + 2));  // Truncate to 32-bit
            break;
        default:
            break;
    }
    
    return 0;
}

// Read a block from the PDB file
ubyte[] readBlock(ubyte[] data, uint blockIndex, uint blockSize) {
    size_t offset = cast(size_t)blockIndex * blockSize;
    if (offset + blockSize > data.length) return null;
    return data[offset .. offset + blockSize];
}

// Read multiple blocks and concatenate
ubyte[] readBlocks(ubyte[] data, uint[] blockIndices, uint blockSize, uint totalSize) {
    ubyte[] result;
    uint remaining = totalSize;
    
    foreach (blockIdx; blockIndices) {
        auto block = readBlock(data, blockIdx, blockSize);
        if (block is null) return null;
        
        uint toTake = remaining < blockSize ? remaining : blockSize;
        result ~= block[0 .. toTake];
        remaining -= toTake;
        
        if (remaining == 0) break;
    }
    
    return result;
}

// Read null-terminated string from data
string readString(ubyte[] data, size_t offset) {
    if (offset >= data.length) return "";
    
    size_t end = offset;
    while (end < data.length && data[end] != 0) end++;
    
    if (end == offset) return "";
    return cast(string) data[offset .. end].idup;
}

PDBParseResult parsePDB(ubyte[] data) {
    if (data.length < MSFSuperBlock.sizeof) {
        return PDBParseResult(false, "File too small for PDB.");
    }

    auto superBlock = *cast(MSFSuperBlock*) data.ptr;
    
    // Verify signature
    if (superBlock.FileMagic[0 .. PDB_SIGNATURE.length] != PDB_SIGNATURE) {
        return PDBParseResult(false, "Invalid PDB signature. Not a valid PDB 7.0 file.");
    }

    uint blockSize = superBlock.BlockSize;
    uint numDirectoryBytes = superBlock.NumDirectoryBytes;
    
    // Calculate number of blocks needed for the stream directory
    uint numDirectoryBlocks = (numDirectoryBytes + blockSize - 1) / blockSize;
    
    // Read the block map (list of blocks that contain the stream directory)
    auto blockMapData = readBlock(data, superBlock.BlockMapAddr, blockSize);
    if (blockMapData is null) {
        return PDBParseResult(false, "Failed to read block map.");
    }
    
    // Get block indices for the stream directory
    uint[] directoryBlockIndices;
    for (uint i = 0; i < numDirectoryBlocks; i++) {
        if ((i + 1) * 4 > blockMapData.length) break;
        directoryBlockIndices ~= *cast(uint*)(blockMapData.ptr + i * 4);
    }
    
    // Read the stream directory
    auto directoryData = readBlocks(data, directoryBlockIndices, blockSize, numDirectoryBytes);
    if (directoryData is null || directoryData.length < 4) {
        return PDBParseResult(false, "Failed to read stream directory.");
    }
    
    // Parse stream directory
    uint numStreams = *cast(uint*)(directoryData.ptr);
    
    if (4 + numStreams * 4 > directoryData.length) {
        return PDBParseResult(false, "Invalid stream directory.");
    }
    
    // Read stream sizes
    uint[] streamSizes;
    for (uint i = 0; i < numStreams; i++) {
        streamSizes ~= *cast(uint*)(directoryData.ptr + 4 + i * 4);
    }
    
    // Calculate block indices for each stream
    size_t blockIndexOffset = 4 + numStreams * 4;
    uint[][] streamBlockIndices;
    
    foreach (size; streamSizes) {
        uint numBlocks = (size + blockSize - 1) / blockSize;
        if (size == 0xFFFFFFFF) numBlocks = 0; // Empty/deleted stream
        
        uint[] blocks;
        for (uint i = 0; i < numBlocks; i++) {
            if (blockIndexOffset + 4 > directoryData.length) break;
            blocks ~= *cast(uint*)(directoryData.ptr + blockIndexOffset);
            blockIndexOffset += 4;
        }
        streamBlockIndices ~= blocks;
    }
    
    // Try to read PDB stream (stream 1) for GUID and Age
    uint age = 0;
    ubyte[16] guid;
    
    if (numStreams > 1 && streamSizes[1] >= PDBStreamHeader.sizeof) {
        auto pdbStreamData = readBlocks(data, streamBlockIndices[1], blockSize, streamSizes[1]);
        if (pdbStreamData !is null && pdbStreamData.length >= PDBStreamHeader.sizeof) {
            auto pdbHeader = *cast(PDBStreamHeader*)(pdbStreamData.ptr);
            age = pdbHeader.Age;
            guid = pdbHeader.Guid;
        }
    }
    
    // Parse TPI stream (stream 2) to get type sizes
    TypeSizeTable typeTable;
    if (numStreams > 2 && streamSizes[2] >= TPIStreamHeader.sizeof && streamSizes[2] != 0xFFFFFFFF) {
        auto tpiData = readBlocks(data, streamBlockIndices[2], blockSize, streamSizes[2]);
        if (tpiData !is null) {
            typeTable = parseTPIStream(tpiData);
        }
    }
    
    // Try to parse symbols from DBI stream (stream 3) and symbol records
    SymbolInfo[] symbols;
    
    if (numStreams > 3 && streamSizes[3] >= 64 && streamSizes[3] != 0xFFFFFFFF) {
        auto dbiData = readBlocks(data, streamBlockIndices[3], blockSize, streamSizes[3]);
        if (dbiData !is null && dbiData.length >= 64) {
            // DBI header layout:
            // Offset 0:  VersionSignature (4 bytes)
            // Offset 4:  VersionHeader (4 bytes)
            // Offset 8:  Age (4 bytes)
            // Offset 12: GlobalStreamIndex (2 bytes)
            // Offset 14: BuildNumber (2 bytes)
            // Offset 16: PublicStreamIndex (2 bytes)
            // Offset 18: PdbDllVersion (2 bytes)
            // Offset 20: SymRecordStream (2 bytes) <- Symbol record stream
            // Offset 22: PdbDllRbld (2 bytes)
            // Offset 24: ModInfoSize (4 bytes)
            // Offset 28: SectionContributionSize (4 bytes)
            // Offset 32: SectionMapSize (4 bytes)
            // Offset 36: SourceInfoSize (4 bytes)
            // ... etc
            
            ushort globalStreamIdx = *cast(ushort*)(dbiData.ptr + 12);
            ushort publicStreamIdx = *cast(ushort*)(dbiData.ptr + 16);
            ushort symRecordStreamIdx = *cast(ushort*)(dbiData.ptr + 20);
            uint modInfoSize = *cast(uint*)(dbiData.ptr + 24);
            
            // Read symbol record stream (needed by GSI/PSI)
            ubyte[] symRecordData = null;
            if (symRecordStreamIdx != 0xFFFF && symRecordStreamIdx < numStreams) {
                uint symStreamIdx = cast(uint)symRecordStreamIdx;
                if (streamSizes[symStreamIdx] > 0 && streamSizes[symStreamIdx] != 0xFFFFFFFF) {
                    symRecordData = readBlocks(data, streamBlockIndices[symStreamIdx], 
                                              blockSize, streamSizes[symStreamIdx]);
                    if (symRecordData !is null) {
                        // Try parsing symbol records directly
                        symbols = parseSymbolRecords(symRecordData, "", &typeTable);
                    }
                }
            }
            
            // Parse module info substream to get per-module symbol streams
            // Module info starts at offset 64 (after DBI header)
            if (modInfoSize > 0 && 64 + modInfoSize <= dbiData.length) {
                size_t modOffset = 64;
                size_t modEnd = 64 + modInfoSize;
                
                while (modOffset + 64 <= modEnd) {
                    // DbiModuleInfo structure:
                    // Offset 0:  Unused1 (4 bytes)
                    // Offset 4:  SectionContr (28 bytes)
                    // Offset 32: Flags (2 bytes)
                    // Offset 34: ModuleSymStream (2 bytes) <- Module's symbol stream index
                    // Offset 36: SymByteSize (4 bytes) <- Size of symbols in module stream
                    // Offset 40: C11ByteSize (4 bytes)
                    // Offset 44: C13ByteSize (4 bytes)
                    // Offset 48: SourceFileCount (2 bytes)
                    // Offset 50: Padding (2 bytes)
                    // Offset 52: Unused2 (4 bytes)
                    // Offset 56: SourceFileNameIndex (4 bytes)
                    // Offset 60: PdbFilePathNameIndex (4 bytes)
                    // Offset 64: ModuleName (null-terminated string)
                    // After ModuleName: ObjFileName (null-terminated string)
                    
                    ushort moduleSymStream = *cast(ushort*)(dbiData.ptr + modOffset + 34);
                    uint symByteSize = *cast(uint*)(dbiData.ptr + modOffset + 36);
                    
                    // Read module name
                    string modName = readString(dbiData, modOffset + 64);
                    
                    // Find end of this entry - skip ModuleName
                    size_t nameOffset = modOffset + 64;
                    while (nameOffset < modEnd && dbiData[nameOffset] != 0) nameOffset++;
                    nameOffset++; // Skip null terminator
                    // Skip ObjFileName  
                    while (nameOffset < modEnd && dbiData[nameOffset] != 0) nameOffset++;
                    nameOffset++; // Skip null terminator
                    
                    // Align to 4-byte boundary
                    nameOffset = (nameOffset + 3) & ~cast(size_t)3;
                    
                    // Parse symbols from this module's stream
                    // IMPORTANT: Only parse symByteSize bytes - the stream also contains
                    // C11/C13 line info after the symbols which would be garbage if parsed as symbols
                    if (moduleSymStream != 0xFFFF && moduleSymStream < numStreams && symByteSize > 4) {
                        if (streamSizes[moduleSymStream] > 0 && streamSizes[moduleSymStream] != 0xFFFFFFFF) {
                            // Read only symByteSize bytes, not the entire stream
                            uint bytesToRead = symByteSize;
                            if (bytesToRead > streamSizes[moduleSymStream]) {
                                bytesToRead = streamSizes[moduleSymStream];
                            }
                            auto modSymData = readBlocks(data, streamBlockIndices[moduleSymStream], 
                                                        blockSize, bytesToRead);
                            if (modSymData !is null && modSymData.length > 4) {
                                // Module symbol stream starts with a 4-byte signature
                                // Symbol records are from offset 4 to symByteSize
                                auto modSymbols = parseSymbolRecords(modSymData[4 .. $], modName, &typeTable);
                                symbols ~= modSymbols;
                            }
                        }
                    }
                    
                    modOffset = nameOffset;
                }
            }
            
            // If no symbols found, try global symbols stream (uses hash table into symRecordData)
            if (symbols.length == 0 && globalStreamIdx != 0xFFFF && globalStreamIdx < numStreams) {
                uint gStreamIdx = cast(uint)globalStreamIdx;
                if (streamSizes[gStreamIdx] > 0 && streamSizes[gStreamIdx] != 0xFFFFFFFF) {
                    auto gData = readBlocks(data, streamBlockIndices[gStreamIdx], 
                                           blockSize, streamSizes[gStreamIdx]);
                    if (gData !is null && symRecordData !is null) {
                        symbols = parseGlobalSymbolStream(gData, symRecordData, &typeTable);
                    }
                }
            }
            
            // Also try public symbols stream
            if (symbols.length == 0 && publicStreamIdx != 0xFFFF && publicStreamIdx < numStreams) {
                uint pStreamIdx = cast(uint)publicStreamIdx;
                if (streamSizes[pStreamIdx] > 0 && streamSizes[pStreamIdx] != 0xFFFFFFFF) {
                    auto pData = readBlocks(data, streamBlockIndices[pStreamIdx], 
                                           blockSize, streamSizes[pStreamIdx]);
                    if (pData !is null && symRecordData !is null) {
                        symbols = parsePublicSymbolStream(pData, symRecordData, &typeTable);
                    }
                }
            }
        }
    }
    
    // Generate stream names for display
    string[] streamNames;
    string[] defaultNames = [
        "Old MSF Directory",
        "PDB Stream",
        "TPI Stream (Type Info)",
        "DBI Stream (Debug Info)",
        "IPI Stream"
    ];
    
    for (uint i = 0; i < numStreams; i++) {
        string name;
        if (i < defaultNames.length) {
            name = defaultNames[i];
        } else {
            name = "Stream " ~ to!string(i);
        }
        
        if (streamSizes[i] == 0xFFFFFFFF) {
            name ~= " (deleted)";
        } else {
            name ~= " (" ~ to!string(streamSizes[i]) ~ " bytes)";
        }
        streamNames ~= name;
    }

    // Sort symbols by decreasing size
    symbols.sort!((a, b) => b.size < a.size);

    return PDBParseResult(true, null, blockSize, numStreams, age, guid, streamNames, symbols);
}

// Parse symbol records from the symbol stream
SymbolInfo[] parseSymbolRecords(ubyte[] symData, string moduleName = "", TypeSizeTable* typeTable = null) {
    SymbolInfo[] symbols;
    size_t offset = 0;
    
    while (offset + 4 <= symData.length) {
        ushort recLen = *cast(ushort*)(symData.ptr + offset);
        ushort recType = *cast(ushort*)(symData.ptr + offset + 2);
        
        if (recLen < 2 || offset + 2 + recLen > symData.length) break;
        
        // Parse specific symbol types
        string kind;
        string name;
        uint section = 0;
        uint symOffset = 0;
        uint procSize = 0;
        uint typeIndex = 0;
        
        switch (recType) {
            case 0x110C: // S_PUB32 - Public symbol (32-bit)
                kind = "PUBLIC";
                // PUBSYM32: pubsymflags(4) + off(4) + seg(2) + name
                if (recLen >= 12) {
                    symOffset = *cast(uint*)(symData.ptr + offset + 8);
                    section = *cast(ushort*)(symData.ptr + offset + 12);
                    name = readString(symData, offset + 14);
                }
                break;
                
            case 0x110D: // S_GDATA32 - Global data
            case 0x110E: // S_LDATA32 - Local data  
                kind = (recType == 0x110D) ? "GDATA" : "LDATA";
                // DATASYM32: typind(4) + off(4) + seg(2) + name
                if (recLen >= 12) {
                    typeIndex = *cast(uint*)(symData.ptr + offset + 4);
                    symOffset = *cast(uint*)(symData.ptr + offset + 8);
                    section = *cast(ushort*)(symData.ptr + offset + 12);
                    name = readString(symData, offset + 14);
                    // Look up size from type table
                    if (typeTable !is null) {
                        procSize = typeTable.getSize(typeIndex);
                    }
                }
                break;
                
            case 0x1110: // S_GPROC32 - Global procedure
            case 0x1111: // S_LPROC32 - Local procedure
                kind = (recType == 0x1110) ? "GPROC" : "LPROC";
                // PROCSYM32: pParent(4) + pEnd(4) + pNext(4) + len(4) + 
                //            DbgStart(4) + DbgEnd(4) + typind(4) + off(4) + seg(2) + flags(1) + name
                // Minimum size: 35 bytes for fields + at least 1 byte for name = 36
                // Some short records with same type code are not real PROCSYM32, skip them
                if (recLen >= 36) {
                    procSize = *cast(uint*)(symData.ptr + offset + 16);  // len field (CodeSize)
                    symOffset = *cast(uint*)(symData.ptr + offset + 32);
                    section = *cast(ushort*)(symData.ptr + offset + 36);
                    if (offset + 39 < symData.length) {
                        name = readString(symData, offset + 39);
                    }
                    
                    // TODO: this parsing is probably wrong

                    // Sanity check: if procSize is unreasonably large (> 100MB), skip
                    // This catches malformed records where we're reading garbage
                    if (procSize > 100_000_000) {
                        name = "";  // Skip this symbol
                    }
                }
                break;
                
            case 0x1114: // S_GPROC32_ID
            case 0x1115: // S_LPROC32_ID
                kind = (recType == 0x1114) ? "GPROC" : "LPROC";
                // ProcIdSym: Id(4) + CodeOffset(4) + Segment(2) + Flags(1) + Name
                // Note: No size field in _ID variants!
                if (recLen >= 13) {
                    symOffset = *cast(uint*)(symData.ptr + offset + 8);
                    section = *cast(ushort*)(symData.ptr + offset + 12);
                    if (offset + 15 < symData.length) {
                        name = readString(symData, offset + 15);
                    }
                    // No size available for _ID symbols
                    procSize = 0;
                }
                break;
                
            case 0x1102: // S_THUNK32
                kind = "THUNK";
                // THUNKSYM32: pParent(4) + pEnd(4) + pNext(4) + off(4) + seg(2) + len(2) + ord(1) + name
                if (recLen >= 22) {
                    symOffset = *cast(uint*)(symData.ptr + offset + 16);
                    section = *cast(ushort*)(symData.ptr + offset + 20);
                    procSize = *cast(ushort*)(symData.ptr + offset + 22);  // len field (2 bytes)
                    name = readString(symData, offset + 25);
                }
                break;
            
            case 0x1107: // S_CONSTANT - Constant value
                kind = "CONST";
                // CONSTSYM: typind(4) + value(variable) + name
                // The value is a numeric leaf, so we need to parse it carefully
                if (recLen >= 8) {
                    // Skip typind(4), then parse numeric leaf to find name
                    size_t nameOffset = offset + 8; // Start after typind
                    // Check if it's a simple 2-byte value or larger
                    if (nameOffset < symData.length) {
                        ushort leafType = *cast(ushort*)(symData.ptr + nameOffset);
                        if (leafType < 0x8000) {
                            // It's a direct value, name follows
                            name = readString(symData, nameOffset + 2);
                        } else {
                            // It's a numeric leaf, skip based on type
                            size_t leafSize = 2; // Default
                            switch (leafType) {
                                case 0x8000: leafSize = 2; break; // LF_CHAR
                                case 0x8001: leafSize = 4; break; // LF_SHORT
                                case 0x8002: leafSize = 4; break; // LF_USHORT
                                case 0x8003: leafSize = 6; break; // LF_LONG
                                case 0x8004: leafSize = 6; break; // LF_ULONG
                                case 0x8009: leafSize = 10; break; // LF_QUADWORD
                                case 0x800A: leafSize = 10; break; // LF_UQUADWORD
                                default: leafSize = 2; break;
                            }
                            name = readString(symData, nameOffset + leafSize);
                        }
                    }
                }
                section = 0;
                symOffset = 0;
                break;
                
            default:
                break;
        }
        
        if (name.length > 0) 
        {
            symbols ~= SymbolInfo(name, section, symOffset, kind, procSize, moduleName);
        }
        
        // Move to next record (recLen doesn't include the length field itself)
        offset += 2 + recLen;
        // Align to 4-byte boundary
        offset = (offset + 3) & ~cast(size_t)3;
    }
    
    return symbols;
}

// Parse global symbol stream (GSI)
// The GSI stream contains a hash table that references the symbol record stream
SymbolInfo[] parseGlobalSymbolStream(ubyte[] gsiData, ubyte[] symRecordData, TypeSizeTable* typeTable = null) {
    // GSI stream structure:
    // - GSI Header: hrSize (4), bucketsSize (4)
    // - Hash Records: array of (offset, refcnt) pairs
    // - Hash Buckets
    
    if (gsiData.length < 8) return [];
    
    uint hrSize = *cast(uint*)(gsiData.ptr);       // Size of hash records in bytes
    uint bucketsSize = *cast(uint*)(gsiData.ptr + 4);
    
    // Validate
    if (8 + hrSize > gsiData.length) return [];
    
    SymbolInfo[] symbols;
    
    // Hash records are 8 bytes each (offset: 4 bytes, refcnt: 4 bytes)
    // The offset points into the symbol record stream (+ 1)
    size_t numHashRecords = hrSize / 8;
    
    for (size_t i = 0; i < numHashRecords; i++) {
        size_t recOffset = 8 + i * 8;
        if (recOffset + 8 > gsiData.length) break;
        
        uint symOffset = *cast(uint*)(gsiData.ptr + recOffset);
        // uint refCnt = *cast(uint*)(gsiData.ptr + recOffset + 4);  // Not needed
        
        // Offset is 1-based, subtract 1 to get actual offset
        if (symOffset > 0) symOffset -= 1;
        
        // Parse symbol at this offset in the symbol record stream
        if (symOffset < symRecordData.length) {
            auto sym = parseSymbolAtOffset(symRecordData, symOffset, "", typeTable);
            if (sym.name.length > 0) {
                symbols ~= sym;
            }
        }
    }
    
    return symbols;
}

// Parse public symbol stream (PSI)
SymbolInfo[] parsePublicSymbolStream(ubyte[] psiData, ubyte[] symRecordData, TypeSizeTable* typeTable = null) {
    // PSI stream has:
    // - Hash header: symHash (4), addrMap (4), numThunks (4), sizeOfThunk (4), etc.
    // - Then follows GSI-like hash structure
    
    if (psiData.length < 28) return [];
    
    uint symHashSize = *cast(uint*)(psiData.ptr);
    uint addrMapSize = *cast(uint*)(psiData.ptr + 4);
    
    // Skip PSI header (28 bytes) and parse the GSI-like hash
    if (28 + symHashSize > psiData.length) return [];
    
    // The hash section starts at offset 28
    ubyte[] hashSection = psiData[28 .. $];
    
    return parseGlobalSymbolStream(hashSection, symRecordData, typeTable);
}

// Parse a single symbol at a given offset
SymbolInfo parseSymbolAtOffset(ubyte[] symData, size_t offset, 
                               string moduleName = "", TypeSizeTable* typeTable = null) {
    SymbolInfo sym;
    sym.moduleName = moduleName;
    
    if (offset + 4 > symData.length) return sym;
    
    ushort recLen = *cast(ushort*)(symData.ptr + offset);
    ushort recType = *cast(ushort*)(symData.ptr + offset + 2);
    
    if (recLen < 2 || offset + 2 + recLen > symData.length) return sym;
    
    switch (recType) {
        case 0x110C: // S_PUB32 - Public symbol (32-bit)
            sym.kind = "PUBLIC";
            if (recLen >= 12) {
                sym.offset = *cast(uint*)(symData.ptr + offset + 8);
                sym.section = *cast(ushort*)(symData.ptr + offset + 12);
                sym.name = readString(symData, offset + 14);
            }
            break;
            
        case 0x110D: // S_GDATA32 - Global data
        case 0x110E: // S_LDATA32 - Local data  
            sym.kind = (recType == 0x110D) ? "GDATA" : "LDATA";
            if (recLen >= 12) {
                uint typeIdx = *cast(uint*)(symData.ptr + offset + 4);
                sym.offset = *cast(uint*)(symData.ptr + offset + 8);
                sym.section = *cast(ushort*)(symData.ptr + offset + 12);
                sym.name = readString(symData, offset + 14);
                // Look up size from type table if provided
                if (typeTable !is null) {
                    sym.size = typeTable.getSize(typeIdx);
                }
            }
            break;
            
        case 0x1110: // S_GPROC32 - Global procedure
        case 0x1111: // S_LPROC32 - Local procedure
            sym.kind = (recType == 0x1110) ? "GPROC" : "LPROC";
            if (recLen >= 36) {
                sym.size = *cast(uint*)(symData.ptr + offset + 16);  // len field
                sym.offset = *cast(uint*)(symData.ptr + offset + 32);
                sym.section = *cast(ushort*)(symData.ptr + offset + 36);
                if (offset + 39 < symData.length) {
                    sym.name = readString(symData, offset + 39);
                }
                // Sanity check: skip if size is unreasonably large
                if (sym.size > 100_000_000) {
                    sym.name = "";
                }
            }
            break;
            
        case 0x1114: // S_GPROC32_ID
        case 0x1115: // S_LPROC32_ID
            sym.kind = (recType == 0x1114) ? "GPROC" : "LPROC";
            // ProcIdSym: Id(4) + CodeOffset(4) + Segment(2) + Flags(1) + Name
            if (recLen >= 13) {
                sym.offset = *cast(uint*)(symData.ptr + offset + 8);
                sym.section = *cast(ushort*)(symData.ptr + offset + 12);
                if (offset + 15 < symData.length) {
                    sym.name = readString(symData, offset + 15);
                }
                sym.size = 0; // No size in _ID variants
            }
            break;
            
        case 0x1102: // S_THUNK32
            sym.kind = "THUNK";
            if (recLen >= 22) {
                sym.offset = *cast(uint*)(symData.ptr + offset + 16);
                sym.section = *cast(ushort*)(symData.ptr + offset + 20);
                sym.size = *cast(ushort*)(symData.ptr + offset + 22);  // len field (2 bytes)
                sym.name = readString(symData, offset + 25);
            }
            break;
            
        default:
            break;
    }
    
    return sym;
}

