module arch;


// Supported OS + arch combination

import std.process;
import std.string;

public:

enum Arch
{
    windows_x86,
    windows_x86_64,
    windows_arm64,
    mac_x86_64,
    mac_arm64,
    mac_UB,
    linux_x86_64
}


Arch detectArch(const(char)[] pluginPath)
{
    version(Windows)
    {
        import std.stdio;
        File f = File(pluginPath, "rb");
        f.seek(0x3c);

        short[1] bufOffset;
        short[] offset = f.rawRead(bufOffset[]);

        f.seek(offset[0]);

        ubyte[6] buf;
        ubyte[] flag = f.rawRead(buf[]);

        if (flag[] == "PE\x00\x00\x4C\x01")
            return Arch.windows_x86;
        else if (flag[] == "PE\x00\x00\x64\x86")
            return Arch.windows_x86_64;
        else if (flag[] == "PE\x00\x00\x64\xAA")
            return Arch.windows_arm64;
        else
            throw new Exception("Unsupported OS/arch combination in bench, please modify the bench tool");
    }
    else version(OSX)
    {
        // run a `file` command
        auto fileResult = executeShell(escapeShellCommand("file", pluginPath));
        if (fileResult.status != 0) throw new Exception("file command failed");

        bool has_x86_64 = indexOf(fileResult.output, "Mach-O 64-bit dynamically linked shared library x86_64") != -1;
        bool has_arm64  = indexOf(fileResult.output, "Mach-O 64-bit dynamically linked shared library arm64") != -1;

        if ( has_x86_64 && !has_arm64) return Arch.mac_x86_64;
        if (!has_x86_64 &&  has_arm64) return Arch.mac_arm64;
        if ( has_x86_64 &&  has_arm64) return Arch.mac_UB;
        throw new Exception("Unsupported arch combination in bench, please modify the bench tool");
    }
    else version(linux)
    {
        auto fileResult = executeShell(escapeShellCommand("file", pluginPath));
        if (fileResult.status != 0) throw new Exception("file command failed");
        bool has_x86_64 = indexOf(fileResult.output, "x86_64") != -1;
        if (has_x86_64) return Arch.linux_x86_64;
        throw new Exception("Unsupported arch combination in bench, please modify the bench tool");
    }
    else
        throw new Exception("Unsupported OS/arch combination in bench, please modify the bench tool");
}


string archName(Arch arch)
{
    final switch(arch) with(Arch)
    {
        case windows_x86:    return "x86";
        case windows_x86_64: return "x86_64";
        case windows_arm64:  return "arm64";
        case mac_x86_64:     return "x86_64";
        case mac_arm64:      return "arm64";
        case mac_UB:         return "Universal Binary";
        case linux_x86_64:   return "x86_64";
    }
}


// bench tool assume naming conventions for the `process` executable:
//
// On Windows, process.exe    exists for x86    VST 2.4
//             process64.exe  exists for x86_64 VST 2.4
//
// On macOS,   process-x86_64 exists for x86_64 VST 2.4
//             process-arm64  exists for x86_64 VST 2.4
//
// This is necessary in order to compare plugins between different architectures.
string processExecutablePathForThisArch(Arch arch)
{
    final switch(arch) with(Arch)
    {
        case windows_x86:    return "process.exe";
        case windows_x86_64: return "process64.exe";
        case windows_arm64:  return "process-arm64.exe";
        case mac_x86_64:     return "process-x86_64";
        case mac_arm64:      return "process-arm64";
        case mac_UB:         return "process-arm64"; // Can use any, so might as well take the fastest option
        case linux_x86_64:   return "process";
    }
}

private: