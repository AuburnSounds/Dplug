import std.process;
import std.file;
import std.stdio;
import std.string;
import std.uuid;


// Builds plugins and make an archive

void usage()
{
    writeln("usage: release -c <compiler> -a <arch> -b <build>");
    writeln("  -a                selects arch x86|x64|all (default: win => all   mac => x64)");
    writeln("  -b                selects builds (default: release-nobounds)");
    writeln("  -c                selects compiler dmd|ldc|gdc|all (default: dmd)");
    writeln("  -f|--force        selects compiler dmd|ldc|gdc|all (default: no)");
    writeln("  -comb|--combined  combined build (default: no)");
    writeln("  -h|--help         shows this help");
}

enum Compiler
{
    ldc,
    gdc,
    dmd,
    all
}

enum Arch
{
    x86,
    x64,
    universalBinary
}

Arch[] allArchitectureqForThisPlatform()
{
    Arch[] archs = [Arch.x86, Arch.x64];
        version (OSX)
            archs ~= [Arch.universalBinary]; // only Mac has universal binaries
    return archs;
}

string toString(Arch arch)
{
    final switch(arch) with (Arch)
    {
        case x86: return "32-bit";
        case x64: return "64-bit";
        case universalBinary: return "Universal-Binary";
    }
}

void main(string[] args)
{
    // TODO get executable name from dub.json
    try
    {
        Compiler compiler = Compiler.dmd;
        version (OSX)
            compiler = Compiler.ldc;

        Arch[] archs = allArchitectureqForThisPlatform();
        version (OSX)
            archs = [ Arch.x64 ];

        string build="debug";
        bool verbose = false;
        bool force = false;
        bool combined = false;
        bool help = false;

        string osString = "";
        version (OSX)
            osString = "Mac-OS-X";
        else version(linux)
            osString = "Linux";
        else version(Windows)
            osString = "Windows";


        for (int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "-v")
                verbose = true;
            else if (arg == "-c")
            {
                ++i;
                if (args[i] == "dmd")
                    compiler = Compiler.dmd;
                else if (args[i] == "gdc")
                    compiler = Compiler.gdc;
                else if (args[i] == "ldc")
                    compiler = Compiler.ldc;
                else if (args[i] == "all")
                    compiler = Compiler.all;
                else throw new Exception("Unrecognized compiler (available: dmd, ldc, gdc, all)");
            }
            else if (arg == "-comb"|| arg == "--combined")
                combined = true;
            else if (arg == "-a")
            {
                ++i;
                if (args[i] == "x86" || args[i] == "x32")
                    archs = [ Arch.x86 ];
                else if (args[i] == "x64" || args[i] == "x86_64")
                    archs = [ Arch.x64 ];
                else if (args[i] == "all")
                {
                    archs = allArchitectureqForThisPlatform();
                }
                else throw new Exception("Unrecognized arch (available: x86, x32, x64, x86_64, all)");
            }
            else if (arg == "-h" || arg == "-help" || arg == "--help")
                help = true;
            else if (arg == "-b")
            {
                build = args[++i];
            }
            else if (arg == "-f" || arg == "--force")
                force = true;
            else
                throw new Exception(format("Unrecognized argument %s", arg));
        }

        if (help)
        {
            usage();
            return;
        }

        string mingw64Path = `C:\D\mingw-w64\mingw32\bin`;
        string vc10Path = `C:\Program Files (x86)\Microsoft Visual Studio 10.0\VC\bin;`
                        ~ `C:\Program Files (x86)\Microsoft Visual Studio 10.0\Common7\IDE`;

        string vc12Path = `C:\Program Files (x86)\Microsoft Visual Studio 12.0\VC\bin;`
                        ~ `C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE`;

        string vc14Path = `C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\bin;`
                        ~ `C:\Program Files (x86)\Microsoft Visual Studio 14.0\Common7\IDE`;


        Plugin plugin = readDubDescription();
        string dirName = format("%s-%s", plugin.name, plugin.ver);

        void fileMove(string source, string dest)
        {
            std.file.copy(source, dest);
            std.file.remove(source);
        }

        string dubPath = `C:\Users\ponce\Desktop\dub\bin`;
        auto oldpath = environment["PATH"];

        static string outputDirectory(string dirName, string osString, Arch arch, string compiler)
        {
            return format("%s/%s_%s_VST_%s", dirName, osString, toString(arch), compiler);
        }


        void buildAndPackage(string compiler, Arch[] architectures)
        {
            foreach (arch; architectures)
            {
                bool is64b = arch == Arch.x64;
                version(Windows)
                {
                    if (compiler == "gdc" && !is64b)
                        environment["PATH"] = `C:\d\gdc-32b\bin;` ~ oldpath;
                    if (compiler == "gdc" && is64b)
                        environment["PATH"] = `C:\d\gdc-64b\bin;` ~ oldpath;
                    if (compiler == "ldc" && !is64b)
                        environment["PATH"] = `c:\d\ldc-32b\bin` ~ ";" ~ mingw64Path ~ ";" ~ oldpath;
                    if (compiler == "ldc" && is64b)
                    {
                        environment["PATH"] = `c:\d\ldc-64b\bin` ~ ";" ~ vc14Path ~";" ~ `C:\Users\ponce\Desktop\dub\bin`;// ~ ";" ~ oldpath;
                        environment["LIB"] = `C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\LIB\amd64;`
                                             `C:\Program Files (x86)\Windows Kits\10\lib\10.0.10150.0\ucrt\x64;`
                                             `C:\Program Files (x86)\Windows Kits\NETFXSDK\4.6\lib\um\x64;`
                                             `C:\Program Files (x86)\Windows Kits\8.1\lib\winv6.3\um\x64`;
                    }
                }

                // Produce output compatible with earlier OSX
                version(OSX)
                {
                    environment["MACOSX_DEPLOYMENT_TARGET"] = is64b ? "10.7" : "10.6";
                }

                string path = outputDirectory(dirName, osString, arch, compiler);

                writefln("Creating directory %s", path);
                mkdirRecurse(path);

                if (arch != Arch.universalBinary)
                    buildPlugin(compiler, build, is64b, verbose, force, combined);

                version(Windows)
                {
                    // On Windows, simply copy the file
                    fileMove(plugin.outputFile, path ~ "/" ~ plugin.outputFile);
                }
                else version(OSX)
                {
                    // On Mac, make a bundle directory
                    string contentsDir = path ~ "/" ~ plugin.name ~ ".vst/Contents";
                    string ressourcesDir = contentsDir ~ "/Resources";
                    string macosDir = contentsDir ~ "/MacOS";
                    mkdirRecurse(ressourcesDir);
                    mkdirRecurse(macosDir);

                    string plist = makePListFile(plugin);
                    std.file.write(contentsDir ~ "/Info.plist", cast(void[])plist);

                    std.file.write(contentsDir ~ "/PkgInfo", cast(void[])makePkgInfo());

                    string exePath = macosDir ~ "/" ~ plugin.name;

                    if (arch == Arch.universalBinary)
                    {
                        string path32 = outputDirectory(dirName, osString, Arch.x86, compiler)
                        ~ "/" ~ plugin.name ~ ".vst/Contents/MacOS/" ~plugin.name;

                        string path64 = outputDirectory(dirName, osString, Arch.x64, compiler)
                        ~ "/" ~ plugin.name ~ ".vst/Contents/MacOS/" ~plugin.name;

                        writefln("*** Making an universal binary with lipo");

                        string cmd = format("lipo -create %s %s -output %s", path32, path64, exePath);
                        safeCommand(cmd);
                    }
                    else
                        fileMove(plugin.outputFile, exePath);
                }
            }
        }

        bool hasDMD = compiler == Compiler.dmd || compiler == Compiler.all;
        bool hasGDC = compiler == Compiler.gdc || compiler == Compiler.all;
        bool hasLDC = compiler == Compiler.ldc || compiler == Compiler.all;

        // DMD builds
        if (hasDMD) buildAndPackage("dmd", archs);
        if (hasGDC) buildAndPackage("gdc", archs);
        if (hasLDC) buildAndPackage("ldc", archs);
    }
    catch(Exception e)
    {
        writefln("error: %s", e.msg);
    }
}

void safeCommand(string cmd)
{
    writefln("*** %s", cmd);
    auto pid = spawnShell(cmd);
    auto errorCode = wait(pid);
    if (errorCode != 0)
        throw new Exception(format("Command '%s' returned %s", cmd, errorCode));
}

void buildPlugin(string compiler, string build, bool is64b, bool verbose, bool force, bool combined)
{
    if (compiler == "ldc")
        compiler = "ldc2";

    version(linux)
    {
        combined = true; // for -FPIC
    }

    writefln("*** Building with %s, %s arch", compiler, is64b ? "64-bit" : "32-bit");
    // build the output file
    string arch = is64b ? "x86_64" : "x86";

    string cmd = format("dub build --build=%s --arch=%s --compiler=%s %s %s %s", build,arch,
        compiler,
        force ? "--force" : "",
        verbose ? "-v" : "",
        combined ? "--combined" : "");
    safeCommand(cmd);
}


struct Plugin
{
    string name;       // name, extracted from dub.json
    string ver;        // version information
    string outputFile; // result of build
    string copyright;  // Copyright information, copied in the bundle
    string CFBundleIdentifier;
}

Plugin readDubDescription()
{
    Plugin result;
    auto dubResult = execute(["dub", "describe"]);

    if (dubResult.status != 0)
        throw new Exception(format("dub returned %s", dubResult.status));

    import std.json;
    JSONValue description = parseJSON(dubResult.output);

    string mainPackage = description["mainPackage"].str;

    foreach (pack; description["packages"].array())
    {
        string name = pack["name"].str;
        if (name == mainPackage)
        {
            result.name = name;
            result.ver = pack["version"].str;
            result.outputFile = pack["targetFileName"].str;

            string copyright = pack["copyright"].str;

            if (copyright == "")
            {
                version(OSX)
                {                    
                    throw new Exception("Your dub.json is missing a non-empty \"copyright\" field to put in Info.plist");
                }
                else
                    writeln("Warning: missing \"copyright\" field in dub.json");
            }
            result.copyright = copyright;
        }
    }

    // Open dub.json directly to find keys that DUB doesn't bypass
    JSONValue rawDubFile = parseJSON(cast(string)(std.file.read("dub.json")));

    try
    {
        result.CFBundleIdentifier = rawDubFile["CFBundleIdentifier"].str;
    }
    catch(Exception e)
    {
        version (OSX)
            throw new Exception("Your dub.json is missing a non-empty \"CFBundleIdentifier\" field to put in Info.plist");
        else
            writeln("Warning: missing \"CFBundleIdentifier\" field in dub.json");
    }
    return result;
}

string makePListFile(Plugin plugin)
{
    string productName = plugin.name;
    string copyright = plugin.copyright;

    string productVersion = "1.0.0";
    string content = "";

    content ~= `<?xml version="1.0" encoding="UTF-8"?>` ~ "\n";
    content ~= `<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">` ~ "\n";
    content ~= `<plist version="1.0">` ~ "\n";
    content ~= `    <dict>` ~ "\n";

    void addKeyString(string key, string value)
    {
        content ~= format("        <key>%s</key>\n        <string>%s</string>\n", key, value);
    }

    addKeyString("CFBundleDevelopmentRegion", "English");

    addKeyString("CFBundleGetInfoString", productVersion ~ ", " ~ copyright);
    addKeyString("CFBundleIdentifier", plugin.CFBundleIdentifier);
    addKeyString("CFBundleInfoDictionaryVersion", "6.0");
    addKeyString("CFBundlePackageType", "BNDL");
    addKeyString("CFBundleShortVersionString", productVersion);
    addKeyString("CFBundleSignature", "ABAB"); // doesn't matter http://stackoverflow.com/questions/1875912/naming-convention-for-cfbundlesignature-and-cfbundleidentifier
    addKeyString("CFBundleVersion", productVersion);
    addKeyString("LSMinimumSystemVersion", "10.7.0");
    content ~= `    </dict>` ~ "\n";
    content ~= `</plist>` ~ "\n";
    return content;
}

string makePkgInfo()
{
    return "BNDLABAB";
}

