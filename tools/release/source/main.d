import std.process;
import std.file;
import std.stdio;
import std.string;
import std.path;
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
        string dirName = "builds";

        void fileMove(string source, string dest)
        {
            std.file.copy(source, dest);
            std.file.remove(source);
        }

        string dubPath = `C:\Users\ponce\Desktop\dub\bin`;
        auto oldpath = environment["PATH"];

        static string outputDirectory(string dirName, string osString, Arch arch)
        {
            return format("%s/%s-%s-VST", dirName, osString, toString(arch)); // no spaces because of lipo call
        }


        void buildAndPackage(string compiler, Arch[] architectures, string iconPath)
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

                string path = outputDirectory(dirName, osString, arch);

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

                    string plist = makePListFile(plugin, iconPath != null);
                    std.file.write(contentsDir ~ "/Info.plist", cast(void[])plist);

                    std.file.write(contentsDir ~ "/PkgInfo", cast(void[])makePkgInfo());

                    if (iconPath)
                        std.file.copy(iconPath, contentsDir ~ "/Resources/icon.icns");

                    string exePath = macosDir ~ "/" ~ plugin.name;

                    if (arch == Arch.universalBinary)
                    {
                        string path32 = outputDirectory(dirName, osString, Arch.x86)
                        ~ "/" ~ plugin.name ~ ".vst/Contents/MacOS/" ~plugin.name;

                        string path64 = outputDirectory(dirName, osString, Arch.x64)
                        ~ "/" ~ plugin.name ~ ".vst/Contents/MacOS/" ~plugin.name;

                        writefln("*** Making an universal binary with lipo");

                        string cmd = format("lipo -create %s %s -output %s", path32, path64, exePath);
                        safeCommand(cmd);
                    }
                    else
                    {
                        fileMove(plugin.outputFile, exePath);
                    }
                }
            }
        }

        bool hasDMD = compiler == Compiler.dmd || compiler == Compiler.all;
        bool hasGDC = compiler == Compiler.gdc || compiler == Compiler.all;
        bool hasLDC = compiler == Compiler.ldc || compiler == Compiler.all;

        mkdirRecurse(dirName);

        string iconPath = null;
        version(OSX)
        {
            // Make icns and copy it (if any provided in dub.json)
            if (plugin.iconPath)
            {
                iconPath = makeMacIcon(plugin.name, plugin.iconPath); // TODO: this should be lazy
            }
        }

        // Copy license (if any provided in dub.json)
        if (plugin.licensePath)
            std.file.copy(plugin.licensePath, dirName ~ "/" ~ baseName(plugin.licensePath));

        // Copy user manual (if any provided in dub.json)
        if (plugin.iconPath)
            std.file.copy(plugin.userManualPath, dirName ~ "/" ~ baseName(plugin.userManualPath));

        // DMD builds
        if (hasDMD) buildAndPackage("dmd", archs, iconPath);
        if (hasGDC) buildAndPackage("gdc", archs, iconPath);
        if (hasLDC) buildAndPackage("ldc", archs, iconPath);
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

    // On OSX, 32-bit plugins made with LDC are compatible >= 10.7
    // while those made with DMD >= 10.6
    // So force DMD usage for 32-bit plugins.
    if ( (is64b == false) && (compiler == "ldc2") )
    {
        writefln("info: forcing DMD compiler for 10.6 compatibility");
        compiler = "dmd";
    }

    writefln("*** Building with %s, %s arch", compiler, is64b ? "64-bit" : "32-bit");
    // build the output file
    string arch = is64b ? "x86_64" : "x86";

    // Produce output compatible with earlier OSX
    version(OSX)
    {
        environment["MACOSX_DEPLOYMENT_TARGET"] = (compiler == "ldc2") ? "10.7" : "10.6";
    }

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
    string userManualPath; // can be null
    string licensePath;    // can be null
    string iconPath;       // can be null or a path to a (large) .png
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
            writeln("warning: missing \"CFBundleIdentifier\" field in dub.json");
    }

    try
    {
        result.userManualPath = rawDubFile["userManualPath"].str;
    }
    catch(Exception e)
    {
        writeln("info: no \"userManualPath\" provided in dub.json");
    }

    try
    {
        result.licensePath = rawDubFile["licensePath"].str;
    }
    catch(Exception e)
    {
        writeln("info: no \"licensePath\" provided in dub.json");
    }

    try
    {
        result.iconPath = rawDubFile["iconPath"].str;
    }
    catch(Exception e)
    {
        writeln("info: no \"iconPath\" provided in dub.json");
    }
    return result;
}

string makePListFile(Plugin plugin, bool hasIcon)
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
    addKeyString("LSMinimumSystemVersion", "10.6.0");
    if (hasIcon)
        addKeyString("CFBundleIconFile", "icon");
    content ~= `    </dict>` ~ "\n";
    content ~= `</plist>` ~ "\n";
    return content;
}

string makePkgInfo()
{
    return "BNDLABAB";
}

// return path of newly made icon
string makeMacIcon(string pluginName, string pngPath)
{
    string temp = tempDir();
    string iconSetDir = buildPath(tempDir(), pluginName ~ ".iconset");
    string outputIcon = buildPath(tempDir(), pluginName ~ ".icns");

    if(!outputIcon.exists)
    {
        //string cmd = format("lipo -create %s %s -output %s", path32, path64, exePath);
        try
        {
            safeCommand(format("mkdir %s", iconSetDir));
        }
        catch(Exception e)
        {
            writefln(" => %s", e.msg);
        }
        safeCommand(format("sips -z 16 16     %s --out %s/icon_16x16.png", pngPath, iconSetDir));
        safeCommand(format("sips -z 32 32     %s --out %s/icon_16x16@2x.png", pngPath, iconSetDir));
        safeCommand(format("sips -z 32 32     %s --out %s/icon_32x32.png", pngPath, iconSetDir));
        safeCommand(format("sips -z 64 64     %s --out %s/icon_32x32@2x.png", pngPath, iconSetDir));
        safeCommand(format("sips -z 128 128   %s --out %s/icon_128x128.png", pngPath, iconSetDir));
        safeCommand(format("sips -z 256 256   %s --out %s/icon_128x128@2x.png", pngPath, iconSetDir));
        safeCommand(format("iconutil --convert icns --output %s %s", outputIcon, iconSetDir));
    }
    return outputIcon;
}