import std.process;
import std.file;
import std.stdio;
import std.string;
import std.path;
import std.regex;
import std.conv;
import std.uuid;

import colorize;

string white(string s) @property
{
    return s.color(fg.light_white);
}

string grey(string s) @property
{
    return s.color(fg.white);
}

string cyan(string s) @property
{
    return s.color(fg.light_cyan);
}

string green(string s) @property
{
    return s.color(fg.light_green);
}

string yellow(string s) @property
{
    return s.color(fg.light_yellow);
}

string red(string s) @property
{
    return s.color(fg.light_red);
}

void info(string msg)
{
    cwritefln("info: %s".white, msg);
}

void warning(string msg)
{
    cwritefln("warning: %s".yellow, msg);
}

void error(string msg)
{
    cwritefln("error: %s".red, msg);
}

void usage()
{

    void flag(string arg, string desc, string possibleValues, string defaultDesc)
    {
        string argStr = format("        %s", arg);
        cwrite(argStr.cyan);
        for(size_t i = argStr.length; i < 24; ++i)
            write(" ");
        cwritefln("%s".white, desc);
        if (possibleValues)
            cwritefln("                        Possible values: ".grey ~ "%s".color(fg.light_yellow), possibleValues);
        if (defaultDesc)
            cwritefln("                        Default: ".grey ~ "%s".color(fg.cyan), defaultDesc);
        cwriteln;
    }

    cwriteln();
    cwriteln( "This is the ".white ~ "release".cyan ~ " tool: plugin bundler and DUB front-end.".white);
    cwriteln();
    cwriteln("FLAGS".white);
    cwriteln();
    flag("-a --arch", "Selects target architecture.", "x86 | x86_64 | all", "Windows => all   OSX => x86_64");
    flag("-b --build", "Selects build type.", "same ones as dub accepts", "debug");
    flag("--compiler", "Selects D compiler.", "dmd | ldc | gdc", "ldc");
    flag("-c --config", "Selects build configuration.", "VST | AU | name starting with \"VST\" | name starting with \"AU\"", "ldc");
    flag("-f --force", "Forces rebuild", null, "no");
    flag("--combined", "Combined build", null, "no");
    flag("-v --verbose", "Verbose output", null, "no");
    flag("-h --help", "Shows this help", null, null);

    cwriteln();
    cwriteln("EXAMPLES".white);
    cwriteln();
    cwriteln("        # Releases a final VST plugin for all architectures".green);
    cwriteln("        release -c ldc -a all -b release-nobounds --combined".cyan);
    cwriteln();
    cwriteln("        # Builds a 32-bit Audio Unit plugin for profiling".green);
    cwriteln("        release -c dmd -a x86 --config AU -b release-debug".cyan);
    cwriteln();
    cwriteln("        # Shows help".green);
    cwriteln("        release -h".cyan);

    cwriteln();
    cwriteln("NOTES".white);
    cwriteln();
    cwriteln("      The configuration name used with " ~ "--config".cyan ~ " must exist in your dub.json file.");
    cwriteln();
    cwriteln("      --combined".cyan ~ " has no effect on code speed, but can avoid flags problems.".grey);
    cwriteln();
    cwriteln("      release".cyan ~ " expects a " ~ "plugin.json".cyan ~ " file for proper bundling and will provide help".grey);
    cwriteln("      for populating it. For other informations it reads the " ~ "dub.json".cyan ~ " file.".grey);
    cwriteln();
    cwriteln();
}

enum Compiler
{
    ldc,
    gdc,
    dmd,
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

int main(string[] args)
{
    try
    {
        Compiler compiler = Compiler.ldc; // use LDC by default

        Arch[] archs = allArchitectureqForThisPlatform();
        version (OSX)
            archs = [ Arch.x64 ];

        string build="debug";
        string config = "VST";
        bool verbose = false;
        bool force = false;
        bool combined = false;
        bool help = false;
        string prettyName = null;

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
            if (arg == "-v" || arg == "--verbose")
                verbose = true;
            else if (arg == "--compiler")
            {
                ++i;
                if (args[i] == "dmd")
                    compiler = Compiler.dmd;
                else if (args[i] == "gdc")
                    compiler = Compiler.gdc;
                else if (args[i] == "ldc")
                    compiler = Compiler.ldc;
                else throw new Exception("Unrecognized compiler (available: dmd, ldc, gdc)");
            }
            else if (arg == "-c" || arg == "--config")
            {
                ++i;
                config = args[i];
            }
            else if (arg == "--combined")
                combined = true;
            else if (arg == "-a" || arg == "--arch")
            {
                ++i;
                if (args[i] == "x86" || args[i] == "x32")
                    archs = [ Arch.x86 ];
                else if (args[i] == "x64" || args[i] == "x86_64" || args[i] == "x86-64")
                    archs = [ Arch.x64 ];
                else if (args[i] == "all")
                {
                    archs = allArchitectureqForThisPlatform();
                }
                else throw new Exception("Unrecognized arch (available: x86, x32, x64, x86_64, all)");
            }
            else if (arg == "-h" || arg == "-help" || arg == "--help")
                help = true;
            else if (arg == "-b" || arg == "--build")
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
            return 0;
        }

        Plugin plugin = readPluginDescription();
        string dirName = "builds";

        void fileMove(string source, string dest)
        {
            std.file.copy(source, dest);
            std.file.remove(source);
        }

        auto oldpath = environment["PATH"];

        static string outputDirectory(string dirName, string osString, Arch arch, string config)
        {
            return format("%s/%s-%s-%s", dirName, osString, toString(arch), config); // no spaces because of lipo call
        }

        void buildAndPackage(string compiler, string config, Arch[] architectures, string iconPath)
        {
            foreach (arch; architectures)
            {
                bool is64b = arch == Arch.x64;
                version(Windows)
                {
                    // TODO: remove when LDC on Windows is a single archive (should happen for 1.0.0)
                    // then fiddling with PATH will be useless
                    if (compiler == "ldc" && !is64b)
                        environment["PATH"] = `c:\d\ldc-32b\bin` ~ ";" ~ oldpath;
                    if (compiler == "ldc" && is64b)
                        environment["PATH"] = `c:\d\ldc-64b\bin` ~ ";" ~ oldpath;
                }

                // Create a .rsrc for this set of architecture when building an AU
                string rsrcPath = null;
                version(OSX)
                {
                    // Make icns and copy it (if any provided in plugin.json)
                    if (configIsAU(config))
                    {
                        rsrcPath = makeRSRC(plugin, arch, verbose);
                    }
                }

                string path = outputDirectory(dirName, osString, arch, config);

                mkdirRecurse(path);

                if (arch != Arch.universalBinary)
                {
                    buildPlugin(compiler, config, build, is64b, verbose, force, combined);
                    cwritefln("    => build OK, available in %s".green, path);
                    cwriteln();
                }

                version(Windows)
                {
                    string appendBitness(string filename)
                    {
                        if (is64b)
                        {
                            // Issue #84
                            // Rename 64-bit binary on Windows to get Reaper to list both 32-bit and 64-bit plugins if in the same directory
                            return stripExtension(filename) ~ "-64" ~ extension(filename);
                        }
                        else
                            return filename;
                    }

                    // On Windows, simply copy the file
                    fileMove(plugin.targetFileName, path ~ "/" ~ appendBitness(plugin.targetFileName)); // TODO: use pretty name
                }
                else version(OSX)
                {
                    // Only accepts two configurations: VST and AudioUnit
                    string pluginDir;
                    if (configIsVST(config))
                        pluginDir = plugin.prettyName ~ ".vst";
                    else if (configIsAU(config))
                        pluginDir = plugin.prettyName ~ ".component";
                    else
                        pluginDir = plugin.prettyName;

                    // On Mac, make a bundle directory
                    string contentsDir = path ~ "/" ~ pluginDir ~ "/Contents";
                    string ressourcesDir = contentsDir ~ "/Resources";
                    string macosDir = contentsDir ~ "/MacOS";
                    mkdirRecurse(ressourcesDir);
                    mkdirRecurse(macosDir);

                    string plist = makePListFile(plugin, config, iconPath != null);
                    std.file.write(contentsDir ~ "/Info.plist", cast(void[])plist);

                    std.file.write(contentsDir ~ "/PkgInfo", cast(void[])makePkgInfo());

                    if (iconPath)
                        std.file.copy(iconPath, contentsDir ~ "/Resources/icon.icns");

                    string exePath = macosDir ~ "/" ~ plugin.prettyName;

                    // Copy .rsrc file (if needed)
                    if (rsrcPath)
                        std.file.copy(rsrcPath, contentsDir ~ "/Resources/" ~ baseName(exePath) ~ ".rsrc");

                    if (arch == Arch.universalBinary)
                    {
                        string path32 = outputDirectory(dirName, osString, Arch.x86, config)
                        ~ "/" ~ pluginDir ~ "/Contents/MacOS/" ~ plugin.prettyName;

                        string path64 = outputDirectory(dirName, osString, Arch.x64, config)
                        ~ "/" ~ pluginDir ~ "/Contents/MacOS/" ~ plugin.prettyName;

                        cwritefln("*** Making an universal binary with lipo".white);

                        string cmd = format("lipo -create %s %s -output %s", path32, path64, exePath);
                        safeCommand(cmd);
                        cwritefln("    => Universal build OK, available in %s".green, path);
                        cwriteln();
                    }
                    else
                    {
                        fileMove(plugin.targetFileName, exePath);
                    }
                }
            }
        }

        bool hasDMD = compiler == Compiler.dmd;
        bool hasGDC = compiler == Compiler.gdc;
        bool hasLDC = compiler == Compiler.ldc;

        mkdirRecurse(dirName);

        string iconPath = null;
        version(OSX)
        {
            // Make icns and copy it (if any provided in plugin.json)
            if (plugin.iconPath)
            {
                iconPath = makeMacIcon(plugin.name, plugin.iconPath); // TODO: this should be lazy
            }
        }

        // Copy license (if any provided in plugin.json)
        if (plugin.licensePath)
            std.file.copy(plugin.licensePath, dirName ~ "/" ~ baseName(plugin.licensePath));

        // Copy user manual (if any provided in plugin.json)
        if (plugin.userManualPath)
            std.file.copy(plugin.userManualPath, dirName ~ "/" ~ baseName(plugin.userManualPath));

        // DMD builds
        if (hasDMD) buildAndPackage("dmd", config, archs, iconPath);
        if (hasGDC) buildAndPackage("gdc", config, archs, iconPath);
        if (hasLDC) buildAndPackage("ldc", config, archs, iconPath);
        return 0;
    }
    catch(ExternalProgramErrored e)
    {
        error(e.msg);
        return e.errorCode;
    }
    catch(Exception e)
    {
        error(e.msg);
        return -1;
    }
}

class ExternalProgramErrored : Exception
{
    public
    {
        @safe pure nothrow this(int errorCode,
                                string message,
                                string file =__FILE__,
                                size_t line = __LINE__,
                                Throwable next = null)
        {
            super(message, file, line, next);
            this.errorCode = errorCode;
        }

        int errorCode;
    }
}


void safeCommand(string cmd)
{
    cwritefln("$ %s".cyan, cmd);
    auto pid = spawnShell(cmd);
    auto errorCode = wait(pid);
    if (errorCode != 0)
        throw new ExternalProgramErrored(errorCode, format("Command '%s' returned %s", cmd, errorCode));
}

void buildPlugin(string compiler, string config, string build, bool is64b, bool verbose, bool force, bool combined)
{
    if (compiler == "ldc")
        compiler = "ldc2";

    version(linux)
    {
        combined = true; // for -FPIC
    }

    cwritefln("*** Building with %s, %s arch".white, compiler, is64b ? "64-bit" : "32-bit");
    // build the output file
    string arch = is64b ? "x86_64" : "x86";

    // Produce output compatible with earlier OSX
    // LDC does not support earlier than 10.7
    version(OSX)
    {
        environment["MACOSX_DEPLOYMENT_TARGET"] = "10.7";
    }

    string cmd = format("dub build --build=%s --arch=%s --compiler=%s %s %s %s %s",
        build, arch,
        compiler,
        force ? "--force" : "",
        verbose ? "-v" : "",
        combined ? "--combined" : "",
        config ? "--config=" ~ config : ""
        );
    safeCommand(cmd);
}


struct Plugin
{
    string name;       // name, extracted from dub.json(eg: 'distort')
    string targetFileName; // result of build
    string copyright;  // Copyright information, copied in the bundle
    string CFBundleIdentifierPrefix;
    string userManualPath; // can be null
    string licensePath;    // can be null
    string iconPath;       // can be null or a path to a (large) .png
    string prettyName;     // Prettier name, extracted from plugin.json (eg: 'My Company Distorter')

    string pluginUniqueID;
    string manufacturerName;
    string manufacturerUniqueID;

    // Public version of the plugin
    // Each release of a plugin should upgrade the version somehow
    int publicVersionMajor;
    int publicVersionMinor;
    int publicVersionPatch;

    string publicVersionString() pure const nothrow
    {
        return to!string(publicVersionMajor) ~ "." ~ to!string(publicVersionMinor) ~ "." ~ to!string(publicVersionMinor);
    }
}

Plugin readPluginDescription()
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
            result.targetFileName = pack["targetFileName"].str;

            string copyright = pack["copyright"].str;

            if (copyright == "")
            {
                version(OSX)
                {
                    throw new Exception("Your dub.json is missing a non-empty \"copyright\" field to put in Info.plist");
                }
                else
                    writeln("warning: missing \"copyright\" field in dub.json");
            }
            result.copyright = copyright;
        }
    }

    if (!exists("plugin.json"))
    {
        throw new Exception("needs a plugin.json description for proper bundling. Please create one next to dub.json.");
    }

    // Open an eventual plugin.json directly to find keys that DUB doesn't bypass
    JSONValue rawPluginFile = parseJSON(cast(string)(std.file.read("plugin.json")));

    // Optional keys

    // prettyName is the fancy Manufacturer + Product name that will be displayed as much as possible in:
    // - bundle name
    // - renamed executable file names
    try
    {
        result.prettyName = rawPluginFile["prettyName"].str;
    }
    catch(Exception e)
    {
        info("Missing \"prettyName\" in plugin.json (eg: \"My Company Compressor\")\n        => Using dub.json \"name\" key instead.");
        result.prettyName = result.name;
    }

    try
    {
        result.userManualPath = rawPluginFile["userManualPath"].str;
    }
    catch(Exception e)
    {
        info("Missing \"userManualPath\" in plugin.json (eg: \"UserManual.pdf\")");
    }

    try
    {
        result.licensePath = rawPluginFile["licensePath"].str;
    }
    catch(Exception e)
    {
        info("Missing \"licensePath\" in plugin.json (eg: \"license.txt\")");
    }

    try
    {
        result.iconPath = rawPluginFile["iconPath"].str;
    }
    catch(Exception e)
    {
        info("Missing \"iconPath\" in plugin.json (eg: \"gfx/myIcon.png\")");
    }

    // Mandatory keys, but with workarounds

    try
    {
        result.CFBundleIdentifierPrefix = rawPluginFile["CFBundleIdentifierPrefix"].str;
    }
    catch(Exception e)
    {
        warning("Missing \"CFBundleIdentifierPrefix\" in plugin.json (eg: \"com.myaudiocompany\")\n         => Using \"com.totoaudio\" instead.");
        result.CFBundleIdentifierPrefix = "com.totoaudio";
    }

    try
    {
        result.manufacturerName = rawPluginFile["manufacturerName"].str;

    }
    catch(Exception e)
    {
        warning("Missing \"manufacturerName\" in plugin.json (eg: \"Example Corp\")\n         => Using \"Toto Audio\" instead.");
        result.manufacturerName = "Toto Audio";
    }

    try
    {
        result.manufacturerUniqueID = rawPluginFile["manufacturerUniqueID"].str;
    }
    catch(Exception e)
    {
        warning("Missing \"manufacturerUniqueID\" in plugin.json (eg: \"aucd\")\n         => Using \"Toto\" instead.");
        result.manufacturerUniqueID = "Toto";
    }

    if (result.manufacturerUniqueID.length != 4)
        throw new Exception("\"manufacturerUniqueID\" should be a string of 4 characters (eg: \"aucd\")");

    try
    {
        result.pluginUniqueID = rawPluginFile["pluginUniqueID"].str;
    }
    catch(Exception e)
    {
        warning("Missing \"pluginUniqueID\" provided in plugin.json (eg: \"val8\")\n         => Using \"tot0\" instead, change it for a proper release.");
        result.pluginUniqueID = "tot0";
    }

    if (result.pluginUniqueID.length != 4)
        throw new Exception("\"pluginUniqueID\" should be a string of 4 characters (eg: \"val8\")");

        // In developpement, should stay at 0.x.y to avoid various AU caches
    string publicV;
    try
    {
        publicV = rawPluginFile["publicVersion"].str;
    }
    catch(Exception e)
    {
        warning("no \"publicVersion\" provided in plugin.json (eg: \"1.0.1\")\n         => Using \"0.0.0\" instead.");
        publicV = "0.0.0";
    }

    if (auto captures = matchFirst(publicV, regex(`(\d+)\.(\d+)\.(\d+)`)))
    {
        result.publicVersionMajor = to!int(captures[1]);
        result.publicVersionMinor = to!int(captures[2]);
        result.publicVersionPatch = to!int(captures[3]);
    }
    else
    {
        throw new Exception("\"publicVersion\" should follow the form x.y.z with 3 integers (eg: \"1.0.0\")");
    }

    return result;
}

bool configIsVST(string config)
{
    return config.length >= 3 && config[0..3] == "VST";
}

bool configIsAU(string config)
{
    return config.length >= 2 && config[0..2] == "AU";
}

string makePListFile(Plugin plugin, string config, bool hasIcon)
{
    string copyright = plugin.copyright;

    string productVersion = plugin.publicVersionString;
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

    string CFBundleIdentifier;
    if (configIsVST(config))
        CFBundleIdentifier = plugin.CFBundleIdentifierPrefix ~ ".vst." ~ plugin.name;
    else if (configIsAU(config))
        CFBundleIdentifier = plugin.CFBundleIdentifierPrefix ~ ".audiounit." ~ plugin.name;
    else
    {
        writeln(`warning: your configuration name doesn't start with "VST" or "AU"`);
        CFBundleIdentifier = plugin.CFBundleIdentifierPrefix ~ "." ~ plugin.name;
    }
    //addKeyString("CFBundleName", plugin.prettyName);
    addKeyString("CFBundleIdentifier", CFBundleIdentifier);

    addKeyString("CFBundleVersion", productVersion);
    addKeyString("CFBundleShortVersionString", productVersion);
    //addKeyString("CFBundleExecutable", plugin.prettyName);

    enum isAudioComponentAPIImplemented = false;

    if (isAudioComponentAPIImplemented && configIsAU(config))
    {
        content ~= "        <key>AudioComponents</key>\n";
        content ~= "        <array>\n";
        content ~= "            <dict>\n";
        content ~= "                <key>type</key>\n";
        content ~= "                <string>aufx</string>\n";
        content ~= "                <key>subtype</key>\n";
        content ~= "                <string>dely</string>\n";
        content ~= "                <key>manufacturer</key>\n";
        content ~= "                <string>" ~ plugin.manufacturerUniqueID ~ "</string>\n"; // TODO XML escape that
        content ~= "                <key>name</key>\n";
        content ~= format("                <string>%s</string>\n", plugin.name);
        content ~= "                <key>version</key>\n";
        content ~= "                <integer>0</integer>\n";
        content ~= "                <key>factoryFunction</key>\n";
        content ~= "                <string>dplugAUComponentFactoryFunction</string>\n";
        content ~= "                <key>sandboxSafe</key><true/>\n";
        content ~= "            </dict>\n";
        content ~= "        </array>\n";
    }

    addKeyString("CFBundleInfoDictionaryVersion", "6.0");
    addKeyString("CFBundlePackageType", "BNDL");

    addKeyString("CFBundleSignature", "ABAB"); // doesn't matter http://stackoverflow.com/questions/1875912/naming-convention-for-cfbundlesignature-and-cfbundleidentifier

    addKeyString("LSMinimumSystemVersion", "10.7.0");
   // content ~= "        <key>VSTWindowCompositing</key><true/>\n";

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

string makeRSRC(Plugin plugin, Arch arch, bool verbose)
{
    string pluginName = plugin.name;
    cwritefln("*** Generating a .rsrc file for %s arch...".white, to!string(arch));
    string temp = tempDir();

    string rPath = buildPath(temp, "plugin.r");

    auto rFile = File(rPath, "w");
    static immutable string rFileBase = cast(string) import("plugin-base.r");

    string plugVer = to!string((plugin.publicVersionMajor << 16) | (plugin.publicVersionMinor << 8) | plugin.publicVersionPatch);

    rFile.writefln(`#define PLUG_NAME "%s"`, pluginName); // no escaping there, TODO
    rFile.writefln("#define PLUG_MFR_ID '%s'", plugin.manufacturerUniqueID);
    rFile.writefln("#define PLUG_VER %s", plugVer);
    rFile.writefln("#define PLUG_UNIQUE_ID '%s'", plugin.pluginUniqueID);

    rFile.writeln(rFileBase);
    rFile.close();

    string rsrcPath = buildPath(temp, "plugin.rsrc");

    string archFlags;
    final switch(arch) with (Arch)
    {
        case x86: archFlags = "-arch i386"; break;
        case x64: archFlags = "-arch x86_64"; break;
        case universalBinary: archFlags = "-arch i386 -arch x86_64"; break;
    }

    string verboseFlag = verbose ? " -p" : "";
    /* -t BNDL */
    safeCommand(format("rez %s%s -o %s -useDF %s", archFlags, verboseFlag, rsrcPath, rPath));


    if (!exists(rsrcPath))
        throw new Exception(format("%s wasn't created", rsrcPath));

    if (getSize(rsrcPath) == 0)
        throw new Exception(format("%s is an empty file", rsrcPath));

    cwritefln("    => Written %s bytes to %s".color(fg.light_green), getSize(rsrcPath), rsrcPath);
    cwriteln();
    return rsrcPath;
}