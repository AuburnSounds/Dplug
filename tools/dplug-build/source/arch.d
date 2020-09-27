module arch;


// Architecture (one single dplug-build invocation may specify several of them)
enum Arch
{
    x86,
    x86_64,
    arm32,           // ARM 32-bit for Raspberry Pi
    arm64,           // Apple Silicon
    universalBinary, // stitching x86_64 and arm64 in a single binary
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


// Build OS, the OS dplug-build is built for
OS buildOS()
{
    version(OSX)
	    return OS.macOS;
    else version(Windows)
        return OS.windows;
    else version(linux)
        return OS.linux;
}

// Build architecture, the arch dplug-build is built for
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

