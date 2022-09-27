module arch;


// Architecture (one single dplug-build invocation may specify several of them)
enum Arch
{
    x86,
    x86_64,
    arm32,           // ARM 32-bit for Raspberry Pi
    arm64,           // Apple Silicon
    universalBinary, // stitching x86_64 and arm64 in a single binary
    all              // all arch supported on target OS. Placeholder value.
}

// True if represent a single arch that can go inside a universal binary
bool isSingleArchEnum(Arch arch) pure
{
    final switch(arch) with (Arch)
    {
        case x86:    return true;
        case x86_64: return true;
        case arm32:  return true;
        case arm64:  return true;
        case universalBinary: return false;
        case all:    return false;
    }
}

string convertArchToPrettyString(Arch arch) pure
{
    final switch(arch) with (Arch)
    {
        case x86:    return "x86";
        case x86_64: return "x86_64";
        case arm32:  return "arm32";
        case arm64:  return "arm64";
        case universalBinary: return "Universal Binary";
        case all:    return "all";
    }
}

string convertArchToDUBFlag(Arch arch, OS targetOS) pure
{
    final switch(arch) with (Arch)
    {
        case x86:    return "--arch=x86 ";
        case x86_64: return "--arch=x86_64 ";

        // Explanation: the dub and ldc2 bundled on Raspberry Pi OS build to the right arch by default
        // aka: arm-linux-gnueabihf
        case arm32:  return "";

        // LLVM Triple for Apple Silicon
        case arm64:
        {
            if (targetOS == OS.macOS)
                return "--arch=arm64-apple-macos ";
            else
                return "--arch=aarch64 ";
        }  

        case universalBinary: assert(false);
        case all: assert(false);
    }
}

enum OS
{
    linux,
    windows,
    macOS
}

string convertOSToString(OS os) pure
{
    final switch(os)
    {
        case OS.macOS: return "macOS";
        case OS.windows: return "Windows";
        case OS.linux: return "Linux";
    }
}


// Build OS, the OS dplug-build is built for.
OS buildOS()
{
    version(OSX)
        return OS.macOS;
    else version(Windows)
        return OS.windows;
    else version(linux)
        return OS.linux;
}

// Build architecture, the arch dplug-build is built for.
Arch buildArch()
{
    version(X86)
        return Arch.x86;
    else version(X86_64)
        return Arch.x86_64;
    else version(ARM)
        return Arch.arm32;
    else version(AArch64)
        return Arch.arm64;
    else
        static assert(false, "dplug-build was built for an architecture unknown to itself.");
}

Arch[] allArchitecturesWeCanBuildForThisOS(OS targetOS)
{
    // Note: we examine buildArch to know the arch we can build for with this dplug-build.

    Arch arch = buildArch();
    final switch (targetOS)
    {
        case OS.macOS:
        {
            // On arm64, build Universal Binaries with both arm64 and x86_64.
            if (buildArch == Arch.arm64 || buildArch == Arch.x86_64)
                return [ Arch.x86_64, Arch.arm64, Arch.universalBinary ];
            else
                throw new Exception("dplug-build on macOS should be built with a x86_64 or arm64 architecture.");
        }

        case OS.windows:
        {
            if (buildArch == Arch.x86 || buildArch == Arch.x86_64 )
                return [ Arch.x86_64, Arch.x86];
            else
                throw new Exception("dplug-build on Windows should be built with a x86_64 or x86 architecture.");
        }

        case OS.linux:
        {
            if (buildArch == Arch.x86_64)
                return [ Arch.x86_64]; // we have no support for 32-bit plug-ins on Linux
            else if (buildArch == Arch.arm32)
                return [ Arch.arm32];
            else if (buildArch == Arch.arm64)
                return [ Arch.arm64];
            else
                throw new Exception("dplug-build on Linux should be built with a x86_64, arm64, or arm32 architecture.");
        }
    }
}

Arch[] defaultArchitecturesToBuildForThisOS(OS targetOS)
{
    Arch arch = buildArch();
    Arch[] res = allArchitecturesWeCanBuildForThisOS(targetOS);

    if (targetOS == OS.windows)
        return [ Arch.x86_64 ];

    return res;
}

