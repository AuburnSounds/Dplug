import core.stdc.string;

import std.file;
import std.stdio;
import std.conv;
import std.uni;
import std.uuid;
import std.process;
import std.string;
import std.path;

import core.time, core.thread;
import dplug.core.sharedlib;

import colorize;
import utils;
import plugin;
import arch;

// This define the paths to install plug-ins in on macOS
string MAC_VST3_DIR     = "/Library/Audio/Plug-Ins/VST3";
string MAC_VST_DIR      = "/Library/Audio/Plug-Ins/VST";
string MAC_AU_DIR       = "/Library/Audio/Plug-Ins/Components";
string MAC_AAX_DIR      = "/Library/Application Support/Avid/Audio/Plug-Ins";
string MAC_LV2_DIR      = "/Library/Audio/Plug-Ins/LV2";

string WIN_VST3_DIR     = "$PROGRAMFILES64\\Common Files\\VST3";
string WIN_VST_DIR      = "$PROGRAMFILES64\\VSTPlugins";
string WIN_LV2_DIR      = "$PROGRAMFILES64\\Common Files\\LV2";
string WIN_AAX_DIR      = "$PROGRAMFILES64\\Common Files\\Avid\\Audio\\Plug-Ins";
string WIN_VST3_DIR_X86 = "$PROGRAMFILES\\Common Files\\VST3";
string WIN_VST_DIR_X86  = "$PROGRAMFILES\\VSTPlugins";
string WIN_LV2_DIR_X86  = "$PROGRAMFILES\\Common Files\\LV2";


version(linux)
{
    version(DigitalMars)
    {
        static assert(false, 
        "\n\nERROR (Work-around #450)\n" ~ 
        "\n" ~ 
        "  Please build dplug-build with the LDC compiler:\n" ~ 
        "  => https://github.com/ldc-developers/ldc/releases\n" ~
        "  when using Linux.\n" ~
        "\n" ~ 
        "\n" ~ 
        "RATIONALE\n" ~ 
        "\n" ~ 
        "  On Linux, building dplug-build with DMD creates crashes with plugins that expose calls\n" ~
        "  to a D host. To avoid those crashes, Dplug library users shall builds dplug-build with\n" ~
        "  LDC. Such a dplug-build will work more reliably as host, for unknown druntime reasons.\n" ~ 
        "  See also: https://github.com/AuburnSounds/Dplug/issues/450 for details.\n" ~ 
        "\n");
    }
}

// What flavour of AUv2 we generate.
enum enableAUv2AudioComponentAPI = true;   // new style of AUv2, need an extended plist
enum enableAUv2ComponentManagerAPI = true; // old API, .rsrc

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
            cwritefln("                        Possible values: ".grey ~ "%s".yellow, possibleValues);
        if (defaultDesc)
            cwritefln("                        Default: ".grey ~ "%s".cyan, defaultDesc);
        cwriteln;
    }

    cwriteln();
    cwriteln( "This is the ".white ~ "dplug-build".cyan ~ " tool: plugin bundler and DUB front-end.".white);
    cwriteln();
    cwriteln("FLAGS".white);
    cwriteln();
    flag("-a --arch", "Selects target architecture.", "x86 | x86_64 | all", "Windows => all   macOS => x86_64    Linux => x86_64");
    flag("-b --build", "Selects build type.", "same ones as dub accepts", "debug");
    flag("--compiler", "Selects D compiler.", "dmd | ldc | gdc", "ldc");
    flag("-c --config", "Adds a build configuration.", "VST2 | VST3 | AU | AAX | LV2 | name starting with \"VST2\", \"VST3\",\"AU\", \"AAX\", or \"LV2\"", "all");
    flag("-f --force", "Forces rebuild", null, "no");
    flag("--combined", "Combined build, important for cross-module inlining with LDC!", null, "no");
    flag("--os", "Cross-compile to another OS." ~ "(FUTURE)".red, "linux | macos | windows | autodetect", "build OS");
    flag("-q --quiet", "Quieter output", null, "no");
    flag("-v --verbose", "Verbose output", null, "no");
    flag("--no-color", "Disable colored output", null, null);
    flag("-sr --skip-registry", " Skip checking the DUB registry\n                        Avoid network, doesn't update dependencies", null, "no");
    flag("--final", "Shortcut for --combined -b release-nobounds", null, null);
    flag("--installer", "Make an installer " ~ "(Windows and OSX only)".red, null, "no");
    flag("--notarize", "Notarize the installer " ~ "(OSX only)".red, null, "no");
    flag("--publish", "Make the plugin available in standard directories " ~ "(OSX only, DOESN'T WORK)".red, null, "no");
    flag("--auval", "Check Audio Unit validation with auval " ~ "(OSX only, DOESN'T WORK)".red, null, "no");
    flag("--rez", "Generate Audio Unit .rsrc file with Rez " ~ "(OSX only)".red, null, "no");
    flag("-h --help", "Shows this help", null, null);

    cwriteln();
    cwriteln("EXAMPLES".white);
    cwriteln();
    cwriteln("        # Releases an optimized VST/AU plugin for all supported architecture".green);
    cwriteln("        dplug-build --final -c VST-CONFIG -c AU-CONFIG".cyan);
    cwriteln();
    cwriteln("        # Builds a 64-bit Audio Unit plugin for profiling with DMD".green);
    cwriteln("        dplug-build --compiler dmd -a x86_64 --config AU -b release-debug".cyan);
    cwriteln();
    cwriteln("        # Shows help".green);
    cwriteln("        dplug-build -h".cyan);

    cwriteln();
    cwriteln("NOTES".white);
    cwriteln();
    cwriteln("      The configuration name used with " ~ "--config".cyan ~ " must exist in your " ~ "dub.json".cyan ~ " file.");
    cwriteln("      dplug-build".cyan ~ " detects plugin format based on the " ~ "configuration".yellow ~ " name's prefix: " ~ `"VST2" | "VST3" | "AU" | "AAX" | "LV2".`.yellow);
    cwriteln();
    cwriteln("      --combined".cyan ~ " has an important effect on code speed, as it can be required for inlining in LDC.".grey);
    cwriteln();
    cwriteln("      dplug-build".cyan ~ " expects a " ~ "plugin.json".cyan ~ " file for proper bundling and will provide help".grey);
    cwriteln("      for populating it. For other informations it reads the " ~ "dub.json".cyan ~ " file.".grey);
    cwriteln();
    cwriteln();
}

int main(string[] args)
{
    try
    {
        string compiler = "ldc2"; // use LDC by default

        // The _target_ architectures. null means "all".
        Arch[] archs = null;

        string build="debug";
        string[] configurationPatterns = [];
        bool verbose = false;
        bool quiet = false;
        bool force = false;
        bool combined = false;
        bool help = false;
        bool publish = false;
        bool auval = false;
        bool makeInstaller = false;
        bool notarize = false;
        bool useRez = false;
        bool skipRegistry = false;
        bool parallel = false;
        string prettyName = null;

        OS targetOS = buildOS();
        string osString = convertOSToString(targetOS);

        // Expand macro arguments
        for (int i = 1; i < args.length; )
        {
            string arg = args[i];
            if (arg == "--final")
            {
                args = args[0..i] ~ ["--combined",
                                     "-b",
                                     "release-nobounds"] ~ args[i+1..$];
            }
            else
                ++i;
        }


        for (int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "-v" || arg == "--verbose")
                verbose = true;
            else if (arg == "-q" || arg == "--quiet")
                quiet = true;
            else if (arg == "--no-color")
                utils.enableColoredOutput = false;
            else if (arg == "--compiler")
            {
                ++i;
                compiler = args[i];
            }
            else if (arg == "-c" || arg == "--config")
            {
                ++i;
                configurationPatterns ~= args[i];
            }
            else if (arg == "-sr" || arg == "--skip-registry")
                skipRegistry = true;
            else if (arg == "--parallel")
                parallel = true;
            else if (arg == "--rez")
            {
                if (targetOS == OS.macOS)
                    useRez = true;
                else
                    warning("--rez not supported on that OS");
            }
            else if (arg == "--notarize")
            {
                notarize = true;
            }
            else if (arg == "--installer")
            {
                if (targetOS == OS.macOS)
                    makeInstaller = true;
                else if (targetOS == OS.windows)
                    makeInstaller = true;
                else
                    warning("--installer not supported on that OS");
            }
            else if (arg == "--combined")
                combined = true;
            else if (arg == "--os")
            {
                if (args[i] == "linux")
                    targetOS = OS.linux;
                else if (args[i] == "macos")
                    targetOS = OS.macOS;
                else if (args[i] == "windows")
                    targetOS = OS.windows;
                else if (args[i] == "autodetect")
                    targetOS = buildOS();
                else
                    throw new Exception("Unrecognized OS (available: linux, macos, windows, autodetect)");            
            }
            else if (arg == "-a" || arg == "--arch")
            {
                ++i;

                // You can select a single arch for fast building, or "all".
                // all is also the default.
                if (args[i] == "x86")
                    archs = [ Arch.x86 ];
                else if (args[i] == "x86_64")
                    archs = [ Arch.x86_64 ];
                else if (args[i] == "arm32")
                    archs = [ Arch.arm32 ];
                else if (args[i] == "arm64")
                    archs = [ Arch.arm64 ];
                else if (args[i] == "UB")
                    archs = [ Arch.x86_64, Arch.arm64, Arch.universalBinary ];
                else if (args[i] == "all")
                {
                    archs = null;
                }
                else
                    throw new Exception("Unrecognized arch combination (available: x86, x86_64, arm32, arm64, UB, all)");            
            }
            else if (arg == "-h" || arg == "-help" || arg == "--help")
                help = true;
            else if (arg == "-b" || arg == "--build")
            {
                build = args[++i];
            }
            else if (arg == "-f" || arg == "--force")
                force = true;
            else if (arg == "--publish")
                publish = true;
            else if (arg == "--auval")
            {
                publish = true; // Need publishing to use auval
                auval = true;
            }
            else
                throw new Exception(format("Unrecognized argument '%s'. Type \"dplug-build -h\" for help.", arg));
        }

        if (help)
        {
            usage();
            return 0;
        }

        // Check validity of flags

        if (targetOS != buildOS)
        {
            throw new Exception("Cross-compiling isn't supported yet. Target --os should be the same as the dplug-build OS.");
        }

        if (notarize && (targetOS != OS.macOS))
        {
            warning("--notarize not supported on that target OS");
        }

        if (quiet && verbose)
            throw new Exception("Can't have both --quiet and --verbose flags.");

        if (targetOS == OS.macOS)
            if (notarize && !makeInstaller)
                throw new Exception("Flag --notarize cannot be used without --installer.");

        if (archs is null)
        {
            // Autodetect target archs that dplug-build is able to build, for the target OS
            archs = allArchitecturesWeCanBuildForThisOS(targetOS);
        }

        Plugin plugin = readPluginDescription();

        // Get configurations
        string[] configurations;
        foreach(pattern; configurationPatterns)
            configurations ~= plugin.getMatchingConfigurations(pattern);

        // Error on duplicate configurations
        for(int confA = 0; confA < configurations.length; ++confA)
            for(int confB = confA+1; confB < configurations.length; ++confB)
                if (configurations[confA] == configurations[confB])
                {
                    throw new Exception(format("configuration specified twice: '%s'", configurations[confA]));
                }


        // Detect if we try to build a VST2.
        // => In this case, error if VST2_SDK isn't defined.
        // => else, force VST2_SDK to a dummy value before calling any DUB command.
        {
            bool buildingVST2 = false;
            foreach(string conf; configurations)
            {
                if (configIsVST2(conf))
                    buildingVST2 = true;
            }

            // In case the VST2_SDK isn't pointed by a variable, redirect the user to the appropriate
            // Wiki page. Also, in case that user can't find a VST2 SDK, let her build other format
            // by faking the variable. This will allow dub to build a plug-in anyway.
            auto VST2_SDK = environment.get("VST2_SDK");
            if (VST2_SDK is null)
            {
                if (buildingVST2)
                    throw new Exception("cannot build VST2 plug-in since the environment variable VST2_SDK isn't defined.\n       See https://github.com/AuburnSounds/Dplug/wiki/Dplug-VST2-Guide for details.\n");
                else
                {
                    environment["VST2_SDK"] = "dummy-VST2_SDK-path"; // define a dummy VST2_SDK for the sake of building
                }
            }
        }

        // If no configuration provided, take the first one like DUB
        if (configurations == [])
            configurations = [ plugin.getFirstConfiguration() ];

        string outputDir = "builds";
        string resDir    = "builds/res-install"; // A directory for the Mac installer

        void fileMove(string source, string dest)
        {
            std.file.copy(source, dest);
            std.file.remove(source);
        }

        auto oldpath = environment["PATH"];

        static string outputDirectory(string outputDir, bool temp, string osString, Arch arch, string config)
        {
            static string toString(Arch arch)
            {
                final switch(arch) with (Arch)
                {
                    case x86: return "32b-";
                    case x86_64: return "64b-";
                    case arm32: return "arm32-";
                    case arm64: return "arm64-";
                    case universalBinary: return "";
                }
            }
            return format("%s%s/%s-%s%s",
                          outputDir,
                          temp ? "/temp" : "",
                          osString,
                          toString(arch),
                          config); // no spaces because of lipo call
        }


        // A path to .pkg artifacts to distribute together
        // only use when targetting macOS
        MacPackage[] macInstallerPackages;

        // Only used when targetting Windows
        WindowsPackage[] windowsPackages;

        // Only used for LV2. A copy of the manifest, that allows to create multi-arch LV2.
        string lv2Manifest = null;

        cwriteln();

        if (!quiet)
        {
            cwritefln("=> Bundling plug-in ".green ~ "%s".yellow ~ " from ".green ~ "%s".yellow
                      ~ ", archs ".green ~ "%s".yellow,
                plugin.pluginName, plugin.vendorName, toStringArchs(archs));
            cwritefln("   configurations: ".green ~ "%s".yellow
                       ~ ", build type ".green ~ "%s".yellow
                       ~ ", compiler ".green ~ "%s".yellow,
                       configurations, build, compiler);
            if (publish)
                cwritefln("   The binaries will be copied to standard plugin directories.".green);
            if (auval)
                cwritefln("   Then Audio Unit validation with auval will be performed for arch %s.".green, archs[$-1]);
            if (makeInstaller)
            {
                if (targetOS == OS.macOS)
                    cwritefln("   Then a Mac installer will be created for distribution outside of the App Store.".green);
                if (targetOS == OS.windows)
                    cwritefln("   Then a Windows installer will be created for distribution.".green);
            }
            cwriteln();
        }

        void buildAndPackage(string config, Arch[] architectures, string iconPathOSX)
        {
            // Is one of those arch Universal Binary?
            bool oneOfTheArchIsUB = false;
            foreach (arch; architectures)
            {
                if (arch == Arch.universalBinary)
                    oneOfTheArchIsUB = true;
            }

            foreach (size_t archCount, arch; architectures)
            {
                // Only build AAX if it's for x86_64
                if (configIsAAX(config) && (arch != Arch.x86_64))
                {
                    cwritefln("info: Skipping architecture %s for AAX\n".white, arch);
                    continue;
                }

                // Does not try to build 32-bit under Mac
                if (targetOS == OS.macOS)
                {
                    if (arch == Arch.x86)
                    {
                       throw new Exception("Can't make 32-bit builds on macOS");
                    }
                }

                // Does not try to build Universal Binary for LV2 on mac (AAX is handled before)
                if (targetOS == OS.macOS)
                {
                    if (configIsLV2(config) && (arch != Arch.x86_64))
                    {
                        cwritefln("info: Skipping architecture %s for LV2\n".white, arch);
                        continue;
                    }
                }

                // Does not try to build AU under Windows
                if (targetOS == OS.windows)
                {
                    if (configIsAU(config))
                        throw new Exception("Can't build AU format on Windows");
                }


                // Does not try to build AAX or AU under Linux
                if (targetOS == OS.linux)
                {
                    if (configIsAAX(config))
                        throw new Exception("Can't build AAX format on Linux");
                    if (configIsAU(config))
                        throw new Exception("Can't build AU format on Linux");
                }

                // Do we need this build in the installer?
                // isTemp is true for plugin build that are only there to jumpstart
                // the creation of universal binaries.
                // As such their content shouln't be mistaken for something that would be redistributed

                bool isTemp = false;
                if (targetOS == OS.macOS)
                {
                    if (!configIsAAX(config) && !configIsLV2(config) && oneOfTheArchIsUB)
                    {
                        // In short: this build is deemed "temporary" if it's only a step toward building a
                        // multi-arch Universal Binary on macOS 11.
                        if (arch == Arch.arm64)
                            isTemp = true;
                        else if (arch == Arch.x86_64)
                            isTemp = true;
                    }
                }

                // VST3-related warning in case of missing keys
                if (configIsVST3(config))
                    plugin.vst3RelatedChecks();

                string path = outputDirectory(outputDir, isTemp, osString, arch, config);

                mkdirRecurse(path);

                if (arch != Arch.universalBinary)
                {
                    buildPlugin(compiler, config, build, arch, verbose, force, combined, quiet, skipRegistry, parallel);
                    double bytes = getSize(plugin.dubOutputFileName) / (1024.0 * 1024.0);
                    cwritefln("    => Build OK, binary size = %0.1f mb, available in ./%s".green, bytes, path);
                    cwriteln();
                }

                void signAAXBinaryWithPACE(string binaryPathInOut)
                {
                    try
                    {
                        string verboseFlag = verbose ? "--verbose " : "";

                        string identFlag;
                        if (targetOS == OS.windows)
                        {
                            identFlag = format("--keyfile %s --keypassword %s ", 
                                               plugin.getKeyFileWindows(), 
                                               plugin.getKeyPasswordWindows());
                        }
                        else if (targetOS == OS.macOS)
                        {
                            identFlag = format("--signid %s ", escapeShellArgument(plugin.getDeveloperIdentity()));
                        }
                        else
                            throw new Exception("AAX not supported on that OS");

                        string cmd = format(`wraptool sign %s--account %s --password %s %s--wcguid %s --in %s --out %s`,
                                            verboseFlag,
                                            plugin.getILokAccount(),
                                            plugin.getILokPassword(),
                                            identFlag,
                                            plugin.getWrapConfigGUID(),
                                            escapeShellArgument(binaryPathInOut),
                                            escapeShellArgument(binaryPathInOut));
                        safeCommand(cmd);
                    }
                    catch(Exception e)
                    {
                        error(e.msg);
                        warning(`AAX signature failed, plugin won't run in the normal Pro Tools.` ~ "\n" ~
                                `         Do NOT distribute such a build.` ~ "\n");
                    }
                }

                void extractAAXPresetsFromBinary(string binaryPath, string contentsDir, Arch targetArch)
                {
                    // Extract presets from the AAX plugin binary by executing it.
                    // Because of this dplug-build and the target plug-in should have the same architecture.

                    // To avoid this coupling, presets could be stored outside of the binary in the future?
                    if (targetArch != buildArch)
                        warning("Can't extract presets from AAX plug-in when dplug-build is built with a different arch.\n");
                    else
                    {
                        // We need to have a sub-directory of vendorName else the presets aren't found.
                        // Then we need one level deeper else the presets aren't organized in sub-directories.
                        //
                        // "AAX plug-ins should include a set of presets in the following directory within the .aaxplugin:
                        //       MyPlugIn.aaxplugin/Contents/Factory Presets/MyPlugInPackage/
                        //  Where MyPlugInPackage is the plug-in's longest Package Name with 16 characters or fewer."
                        string packageName = plugin.pluginName;
                        if (packageName.length > 16)
                            packageName = packageName[0..16];
                        string factoryPresetsLocation =
                            format(contentsDir ~ "Factory Presets/" ~ packageName ~ "/%s Factory Presets", plugin.prettyName);

                        mkdirRecurse(factoryPresetsLocation);

                        SharedLib lib;
                        lib.load(plugin.dubOutputFileName);
                        if (!lib.hasSymbol("DplugEnumerateTFX"))
                            throw new Exception("Couldn't find the symbol DplugEnumerateTFX in the plug-in");

                        // Note: this is duplicated in dplug-aax in aax_init.d
                        // This callback is called with:
                        // - name a zero-terminated C string
                        // - a buffer representing the .tfx content
                        // - a user-provided pointer
                        alias enumerateTFXCallback = extern(C) void function(const(char)* name, const(ubyte)* tfxContent, size_t len, void* userPointer);
                        alias enumerateTFX_t = extern(C) void function(enumerateTFXCallback, void* userPointer);

                        struct Context
                        {
                            string factoryPresetsDir;
                            int presetCount = 0;
                        }

                        Context context = Context(factoryPresetsLocation);

                        static extern(C) void processPreset(const(char)* name,
                                                            const(ubyte)* tfxContent,
                                                            size_t len,
                                                            void* userPointer)
                        {
                            Context* context = cast(Context*)userPointer;
                            const(char)[] presetName = name[0..strlen(name)];
                            std.file.write(context.factoryPresetsDir ~ "/" ~ presetName ~ ".tfx", tfxContent[0..len]);
                            context.presetCount += 1;
                        }

                        enumerateTFX_t ptrDplugEnumerateTFX = cast(enumerateTFX_t) lib.loadSymbol("DplugEnumerateTFX");
                        ptrDplugEnumerateTFX(&processPreset, &context);
                        lib.unload();

                        cwritefln("    => Extracted %s AAX factory presets from binary".green, context.presetCount);
                        cwriteln();
                    }
                }

                void extractLV2ManifestFromBinary(string binaryPath, string outputDir, Arch targetArch, string binaryName)
                {
                    // Extract ports from LV2 Binary
                    // Because of this release itself must be 64-bit.
                    // To avoid this coupling, presets should be stored outside of the binary in the future.
                    bool formerlyExtracted = false;
                    if (targetArch != buildArch)
                    {
                        if (lv2Manifest is null)
                            throw new Exception("Can't extract manifest from LV2 plug-in because dplug-build is built with a different arch, and the x86_64 arch wasn't built before. Re-run this build, including the x86_64 arch.\n");
                        formerlyExtracted = true;
                    }
                    else
                    {
                        cwritefln("*** Extract LV2 manifest from binary...".white);
                        SharedLib lib;
                        lib.load(binaryPath);
                        if (!lib.hasSymbol("GenerateManifestFromClient"))
                            throw new Exception("Couldn't find the symbol ExtractPortConfiguration in the plug-in");

                        alias generateManifest = extern(C) int function(char* manifestBuf, int manifestBufLen,
                                                                        const(char)* binaryFileName, int binaryFileNameLen);

                        generateManifest ptrGenerateManifest = cast(generateManifest) lib.loadSymbol("GenerateManifestFromClient");

                        // set max manifest size to 1 Million characters/bytes.  We whould never exceed this I hope
                        char[] manifestBuf = new char[1000 * 1000];
                        int manifestLen = ptrGenerateManifest(manifestBuf.ptr, cast(int)(manifestBuf.length),
                                                              binaryName.ptr, cast(int)(binaryName.length));
                        lib.unload();
                        lv2Manifest = manifestBuf[0..manifestLen].idup;
                    }

                    // write manifest
                    string manifestPath = outputDir ~ "/manifest.ttl";
                    std.file.write(manifestPath, lv2Manifest);

                    cwritefln("    => Written %s bytes to%s manifest.ttl.".green, getSize(manifestPath), formerlyExtracted ? " (formerly extracted)" : "");
                    cwriteln();
                }

                if (targetOS == OS.windows)
                {
                    // size used in installer
                    int sizeInKiloBytes = cast(int) (getSize(plugin.dubOutputFileName) / (1024.0));

                    // plugin path used in installer
                    string pluginDirectory;

                    // Special case for AAX need its own directory, but according to Voxengo releases,
                    // its more minimal than either JUCE or IPlug builds.
                    // Only one file (.dll even) seems to be needed in <plugin-name>.aaxplugin\Contents\x64
                    // Note: only 64-bit AAX supported.
                    if (configIsAAX(config))
                    {
                        string pluginFinalName = plugin.prettyName ~ ".aaxplugin";
                        pluginDirectory = path ~ "/" ~ (plugin.prettyName ~ ".aaxplugin");
                        string contentsDir = pluginDirectory ~ "/Contents/";

                        extractAAXPresetsFromBinary(plugin.dubOutputFileName, contentsDir, arch);

                        if (arch == Arch.x86_64)
                        {
                            mkdirRecurse(contentsDir ~ "x64");
                            fileMove(plugin.dubOutputFileName, contentsDir ~ "x64/" ~ pluginFinalName);
                            signAAXBinaryWithPACE(contentsDir ~ "x64/" ~ pluginFinalName);
                        }
                        else if (arch == Arch.x86)
                        {
                            mkdirRecurse(contentsDir ~ "Win32");
                            fileMove(plugin.dubOutputFileName, contentsDir ~ "Win32/" ~ pluginFinalName);
                            signAAXBinaryWithPACE(contentsDir ~ "Win32/" ~ pluginFinalName);
                        }
                        else
                            throw new Exception("AAX doesn't support this arch");
                    }
                    else if (configIsLV2(config))
                    {
                        // must create TTL, and a .lv2 directory
                        string pluginFinalName = plugin.getLV2PrettyName() ~ ".dll";
                        pluginDirectory = path ~ "/" ~ plugin.prettyName ~ ".lv2";
                        string pluginFinalPath = pluginDirectory ~ "/" ~ pluginFinalName;

                        mkdirRecurse(pluginDirectory);
                        fileMove(plugin.dubOutputFileName, pluginFinalPath);
                        extractLV2ManifestFromBinary(pluginFinalPath, pluginDirectory, arch, pluginFinalName);
                    }
                    else if (configIsVST3(config)) // VST3 special case, needs to be named .vst3 (but can't be _linked_ as .vst3)
                    {
                        string appendBitnessVST3(string prettyName, string originalPath)
                        {
                            if (arch == Arch.x86_64)
                            {
                                // Issue #84
                                // Rename 64-bit binary on Windows to get Reaper to list both 32-bit and 64-bit plugins if in the same directory
                                // Note: I don't think that's necessary...
                                return prettyName ~ "-64.vst3";
                            }
                            else
                                return prettyName ~ ".vst3";
                        }
                        // Simply copy the file
                        pluginDirectory = path ~ "/" ~ appendBitnessVST3(plugin.prettyName, plugin.dubOutputFileName);
                        fileMove(plugin.dubOutputFileName, pluginDirectory);
                    }
                    else
                    {
                        string appendBitness(string prettyName, string originalPath)
                        {
                            if (arch == Arch.x86_64)
                            {
                                // Issue #84
                                // Rename 64-bit binary on Windows to get Reaper to list both 32-bit and 64-bit plugins if in the same directory
                                return prettyName ~ "-64" ~ extension(originalPath);
                            }
                            else
                                return prettyName ~ extension(originalPath);
                        }

                        // Simply copy the file
                        pluginDirectory = path ~ "/" ~ appendBitness(plugin.prettyName, plugin.dubOutputFileName);
                        fileMove(plugin.dubOutputFileName, pluginDirectory);
                    }

                    if(!isTemp && makeInstaller)
                    {
                        string title;
                        string format;
                        string installDir;

                        if(configIsVST2(config))
                        {
                            format = "VST";
                            title = "VST 2.4 plug-in";
                            if (arch == arch.x86_64)
                                installDir = WIN_VST_DIR;
                            else
                                installDir = WIN_VST_DIR_X86;
                        }
                        else if (configIsVST3(config))
                        {
                            format = "VST3";
                            title = "VST 3 plug-in";
                            if (arch == arch.x86_64)
                                installDir = WIN_VST3_DIR;
                            else
                                installDir = WIN_VST3_DIR_X86;
                        }
                        else if (configIsAAX(config))
                        {
                            format = "AAX";
                            title = "AAX plug-in";
                            installDir = WIN_AAX_DIR;
                        }
                        else if (configIsLV2(config))
                        {
                            format = "LV2";
                            title = "LV2 plug-in";
                            if (arch == arch.x86_64)
                                installDir = WIN_LV2_DIR;
                            else
                                installDir = WIN_LV2_DIR_X86;
                        }

                        windowsPackages ~= WindowsPackage(format, pluginDirectory, title, installDir, sizeInKiloBytes, arch == arch.x86_64);
                    }
                }
                else if (targetOS == OS.linux)
                {
                    if(configIsLV2(config))
                    {
                        string pluginFinalPath = plugin.getLV2PrettyName() ~ ".so";
                        string soPath = path ~ "/" ~ pluginFinalPath;
                        fileMove(plugin.dubOutputFileName, soPath);
                        extractLV2ManifestFromBinary(soPath, path, arch, pluginFinalPath);
                    }
                    else if (configIsVST3(config)) 
                    {
                        // VST3 special case, needs to be a .vst3 bundle
                        string pluginDirectory = path ~ "/" ~ plugin.prettyName ~ ".vst3";
                        string exeDirectory = pluginDirectory ~ "/Contents/x86_64-linux";
                        mkdirRecurse(pluginDirectory);
                        mkdirRecurse(exeDirectory);
                        fileMove(plugin.dubOutputFileName, exeDirectory ~ "/" ~ plugin.prettyName ~ ".so");
                    }
                    else if (configIsVST2(config)) // VST2 special case
                    {
                        // Simply copy the file
                        fileMove(plugin.dubOutputFileName, path ~ "/" ~ plugin.prettyName ~ ".so");
                    }
                }
                else if (targetOS == OS.macOS)
                {
                    // Only accepts two configurations: VST and AudioUnit
                    string pluginDir;
                    string installDir;
                    if (configIsVST2(config))
                    {
                        pluginDir = plugin.prettyName ~ ".vst";
                        installDir = MAC_VST_DIR;
                    }
                    else if (configIsVST3(config))
                    {
                        pluginDir = plugin.prettyName ~ ".vst3";
                        installDir = MAC_VST3_DIR;
                    }
                    else if (configIsAU(config))
                    {
                        pluginDir = plugin.prettyName ~ ".component";
                        installDir = MAC_AU_DIR;
                    }
                    else if (configIsAAX(config))
                    {
                        pluginDir = plugin.prettyName ~ ".aaxplugin";
                        installDir = MAC_AAX_DIR;
                    }
                    else if (configIsLV2(config))
                    {
                        pluginDir = plugin.prettyName ~ ".lv2";
                        installDir = MAC_LV2_DIR;
                    }
                    else
                        assert(false, "unsupported plugin format");

                    // On Mac, make a bundle directory
                    string bundleDir = path ~ "/" ~ pluginDir;

                    if (configIsLV2(config))
                    {
                        // LV2 is special on Mac, because it only need this structure:
                        //
                        // directory.lv2/
                        //     manifest.ttl
                        //     binary.dylib
                        //
                        // So in LV2 it's not an actual bundle with a plist and all

                        // must create TTL, and a .lv2 directory
                        string pluginFinalName = plugin.getLV2PrettyName() ~ ".dylib";
                        string pluginFinalPath = bundleDir ~ "/" ~ pluginFinalName;
                        mkdirRecurse(bundleDir);
                        fileMove(plugin.dubOutputFileName, pluginFinalPath);
                        extractLV2ManifestFromBinary(pluginFinalPath, bundleDir, arch, pluginFinalName);

                        // Note: there is no support for Universal Binary in LV2
                    }
                    else
                    {
                        string contentsDir = path ~ "/" ~ pluginDir ~ "/Contents/";
                        string ressourcesDir = contentsDir ~ "Resources";
                        string macosDir = contentsDir ~ "MacOS";
                        mkdirRecurse(ressourcesDir);
                        mkdirRecurse(macosDir);

                        if (configIsAAX(config))
                            extractAAXPresetsFromBinary(plugin.dubOutputFileName, contentsDir, arch);

                        // Generate Plist
                        string plist = makePListFile(plugin, config, iconPathOSX != null, enableAUv2AudioComponentAPI);
                        std.file.write(contentsDir ~ "Info.plist", cast(void[])plist);

                        void[] pkgInfo = cast(void[]) plugin.makePkgInfo(config);
                        std.file.write(contentsDir ~ "PkgInfo", pkgInfo);

                        string exePath = macosDir ~ "/" ~ plugin.prettyName;

                        // Create a .rsrc for this set of architecture when building an AU
                        if (enableAUv2ComponentManagerAPI && configIsAU(config))
                        {
                            string rsrcPath;
                            if (useRez)
                                rsrcPath = makeRSRC_with_Rez(plugin, arch, verbose);
                            else
                            {
                                rsrcPath = makeRSRC_internal(plugin, arch, verbose);
                            }
                            std.file.copy(rsrcPath, contentsDir ~ "Resources/" ~ baseName(exePath) ~ ".rsrc");
                        }

                        if (iconPathOSX)
                            std.file.copy(iconPathOSX, contentsDir ~ "Resources/icon.icns");

                        if (arch == Arch.universalBinary)
                        {
                            string path_arm64  = outputDirectory(outputDir, true, osString, Arch.arm64, config)
                            ~ "/" ~ pluginDir ~ "/Contents/MacOS/" ~ plugin.prettyName;

                            string path_x86_64 = outputDirectory(outputDir, true, osString, Arch.x86_64, config)
                            ~ "/" ~ pluginDir ~ "/Contents/MacOS/" ~ plugin.prettyName;

                            cwritefln("*** Making an universal binary with lipo".white);

                            string cmd = format("lipo -create %s %s -output %s",
                                                escapeShellArgument(path_arm64),
                                                escapeShellArgument(path_x86_64),
                                                escapeShellArgument(exePath));
                            safeCommand(cmd);
                            double bytes = getSize(exePath) / (1024.0 * 1024.0);
                            cwritefln("    => Universal build OK, binary size = %0.1f mb, available in ./%s".green, bytes, path);
                            cwriteln();
                        }
                        else
                        {
                            fileMove(plugin.dubOutputFileName, exePath);                            
                        }
                    }

                    // Note: on Mac, the bundle path is passed instead, since wraptool won't accept the executable only
                    if (configIsAAX(config))
                        signAAXBinaryWithPACE(bundleDir);
                    else
                    {
                        enum SIGN_MAC_BUNDLES = true;
                        if (SIGN_MAC_BUNDLES && !isTemp && makeInstaller)
                        {
                            // eventually sign with codesign
                            cwritefln("*** Signing bundle %s...".white, bundleDir);
                            if (plugin.developerIdentity !is null)
                            {
                                string command = format(`codesign --strict -f -s %s --timestamp %s --digest-algorithm=sha1,sha256`,
                                    escapeShellArgument(plugin.developerIdentity), escapeShellArgument(bundleDir));
                                safeCommand(command);
                            }
                            else
                            {
                                warning("Can't sign the bundle. Please provide a key \"developerIdentity-osx\" in your plugin.json. Users computers may reject this bundle.");
                            }
                            cwriteln;
                        }
                    }

                    // Should this arch be published? Only if the --publish arg was given and
                    // it's the last architecture in the list (to avoid overwrite)
                    if (publish && (archCount + 1 == architectures.length))
                    {
                        cwritefln("*** Publishing to %s...".white, installDir);
                        int filesCopied = copyRecurse(path ~ "/" ~ pluginDir, installDir ~ "/" ~ pluginDir, verbose);
                        cwritefln("    => %s files copied.".green, filesCopied);
                        cwriteln();

                        if (auval)
                        {
                            cwriteln("*** Validation with auval...".white);

                            bool is32b = (arch == Arch.x86);
                            string exename = is32b ? "auval" : "auvaltool";
                            string cmd = format("%s%s -v aufx %s %s -de -dw",
                                exename,
                                is32b ? " -32 ":"",
                                plugin.pluginUniqueID,
                                plugin.vendorUniqueID);
                            safeCommand(cmd);

                            cwriteln("    => Audio Unit passed validation.".green);
                            cwriteln();
                        }
                    }

                    if (!isTemp && makeInstaller) // is this eligible to make it in the installer?
                    {
                        string pkgIdentifier;
                        string pkgFilename;
                        string title;

                        if (configIsVST2(config))
                        {

                            pkgIdentifier = plugin.pkgBundleVST2();
                            pkgFilename   = plugin.pkgFilenameVST2();
                            title = "VST 2.4 plug-in";
                        }
                        else if (configIsVST3(config))
                        {
                            pkgIdentifier = plugin.pkgBundleVST3();
                            pkgFilename   = plugin.pkgFilenameVST3();
                            title = "VST3 plug-in";
                        }
                        else if (configIsAU(config))
                        {
                            pkgIdentifier = plugin.pkgBundleAU();
                            pkgFilename   = plugin.pkgFilenameAU();
                            title = "AU plug-in";
                        }
                        else if (configIsAAX(config))
                        {
                            pkgIdentifier = plugin.pkgBundleAAX();
                            pkgFilename   = plugin.pkgFilenameAAX();
                            title = "AAX plug-in";
                        }
                        else if (configIsLV2(config))
                        {
                            pkgIdentifier = plugin.pkgBundleLV2();
                            pkgFilename   = plugin.pkgFilenameLV2();
                            title = "LV2 plug-in";
                        }
                        else
                            assert(false, "unsupported plugin format");

                        string versionStr = plugin.publicVersionString();
                        string pathToPkg = path ~ "/" ~ pkgFilename;
                        string distributionId = to!string(macInstallerPackages.length);

                        macInstallerPackages ~= MacPackage(pkgIdentifier, pathToPkg, pkgFilename, distributionId, title);

                        string signStr = "";
                        enum SIGN_MAC_INDIVIDUAL_PKG = true;
                        static if (SIGN_MAC_INDIVIDUAL_PKG)
                        {
                            if (plugin.developerIdentity !is null)
                            {
                                signStr = format(" --sign %s --timestamp", escapeShellArgument(plugin.developerIdentity));
                            }
                            else
                            {
                                warning("Can't sign the installer. Please provide a key \"developerIdentity-osx\" in your plugin.json. Users computers will reject this installer.");
                            }
                        }

                        string quietStr = verbose ? "" : " --quiet";


                        // Create individual .pkg installer for each VST, AU or AAX given
                        string cmd = format("pkgbuild%s%s --install-location %s --identifier %s --version %s --component %s %s",
                            signStr,
                            quietStr,
                            escapeShellArgument(installDir),
                            pkgIdentifier,
                            plugin.publicVersionString,
                            escapeShellArgument(bundleDir),
                            escapeShellArgument(pathToPkg));
                        safeCommand(cmd);
                        cwriteln;
                    }
                }
                else
                    throw new Exception("Unsupported OS");
            }
        }

        mkdirRecurse(outputDir);
        mkdirRecurse(outputDir ~ "/temp");
        if (makeInstaller)
            mkdirRecurse(outputDir ~ "/res-install");

        string iconPathOSX = null;
        if (targetOS == OS.macOS)
        {
            // Make icns and copy it (if any provided in plugin.json)
            if (plugin.iconPathOSX)
            {
                iconPathOSX = makeMacIcon(plugin.name, plugin.iconPathOSX); // FUTURE: this should be lazy
            }
        }

        // Build various configuration
        foreach(config; configurations)
            buildAndPackage(config, archs, iconPathOSX);

        // Copy license (if any provided in plugin.json)
        // Ensure it is HTML.
        if (plugin.licensePath)
        {
            string licensePath = outputDir ~ "/license.html";
            string licensePathExpanded = outputDir ~ "/license-expanded.md";

            if (extension(plugin.licensePath) == ".md")
            {
                // Convert license markdown to HTML
                cwritefln("*** Converting license file to HTML... ".white);
                string markdown = cast(string)std.file.read(plugin.licensePath);

                // Subsitute predefined macros to plugin.json specific values. 
                // It helps create licences that work for any vendor.
                markdown = markdown.replace("$VENDORNAME", plugin.vendorName)
                                   .replace("$PLUGINNAME", plugin.pluginName)
                                   .replace("$PUBLICVERSION", plugin.publicVersionString)
                                   .replace("$CURRENTYEAR", to!string(currentYear()));

                // Write a file with just macro expanded, for the Windows installer.
                std.file.write(licensePathExpanded, markdown);

                // Write a file with macro expanded and converted to HTML, for the Mac installer.
                string html = convertMarkdownFileToHTML(markdown);
                std.file.write(licensePath, html);
                cwritefln(" => OK\n".green);
            }
            else
                throw new Exception("License file should be a Markdown .md file");
        }

        if ((targetOS == OS.macOS) && makeInstaller)
        {
            cwriteln("*** Generating final Mac installer...".white);
            string finalPkgPath = outputDir ~ "/" ~ plugin.finalPkgFilename(configurations[0]);
            generateMacInstaller(outputDir, resDir, plugin, macInstallerPackages, finalPkgPath, verbose);
            cwriteln("    => OK".green);
            cwriteln;

            if (notarize)
            {
                // Note: this doesn't have to match anything, it's just there in emails
                string primaryBundle = plugin.getNotarizationBundleIdentifier(configurations[0]);

                cwritefln("*** Notarizing final Mac installer %s...".white, primaryBundle);
                notarizeMacInstaller(plugin, finalPkgPath, primaryBundle);
                cwriteln("    => Notarization OK".green);
                cwriteln;
            }
        }

        if ((targetOS == OS.windows) && makeInstaller)
        {
            cwriteln("*** Generating Windows installer...".white);
            string windowsInstallerPath = outputDir ~ "/" ~ plugin.windowsInstallerName(configurations[0]);
            generateWindowsInstaller(outputDir, plugin, windowsPackages, windowsInstallerPath, verbose);
            cwriteln;
        }

        return 0;
    }
    catch(DplugBuildBuiltCorrectlyException e)
    {
        cwriteln;
        cwriteln("    Congratulations! ".green ~ "dplug-build".cyan ~ " built successfully.".green);
        cwriteln("    Type " ~ "dplug-build --help".cyan ~ " to know about its usage.");
        cwriteln("    You'll probably want " ~ "dplug-build".cyan ~ " to be in your" ~ " PATH".yellow ~ ".");
        cwriteln;
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

void buildPlugin(string compiler, string config, string build, Arch arch, bool verbose, bool force, bool combined, bool quiet, bool skipRegistry, bool parallel)
{
    cwritefln("*** Building configuration %s with %s, %s arch...".white, config, compiler, convertArchToPrettyString(arch));

    // If we want to support Notarization, we can't target earlier than 10.11
    // Note: it seems it is overriden at some point and when notarizing you can't target lower
    // If you want Universal Binary 2, can't targer earlier than 10.12
    version(OSX)
    {
        environment["MACOSX_DEPLOYMENT_TARGET"] = "10.10";
    }

    string cmd = format("dub build --build=%s %s--compiler=%s%s%s%s%s%s%s%s",
        build, 
        convertArchToDUBFlag(arch),
        compiler,
        force ? " --force" : "",
        verbose ? " -v" : "",
        quiet ? " -q" : "",
        combined ? " --combined" : "",
        config ? " --config=" ~ config : "",
        skipRegistry ? " --skip-registry=all" : "",
        parallel ? " --parallel" : ""
        );
    safeCommand(cmd);
}

struct WindowsPackage
{
    string format;
    string pluginDir;
    string title;
    string installDir;
    double bytes;
    bool is64b;
}

void generateWindowsInstaller(string outputDir,
                              Plugin plugin,
                              WindowsPackage[] packs,
                              string outExePath,
                              bool verbose)
{
    import std.algorithm.iteration : uniq, filter;
    import std.regex: regex, replaceAll;
    import std.array : array;

    string regVendorKey = "Software\\" ~ plugin.vendorName;
    string regProductKey = regVendorKey ~ "\\" ~ plugin.pluginName;
    string regUninstallKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" ~ plugin.prettyName;

    // changes slashes in path to backslashes, which are the only supported within NSIS
    string escapeNSISPath(string path)
    {
        return path.replace("/", "\\");
    }

    string formatSectionDisplayName(WindowsPackage pack) pure
    {
        if (pack.format == "VST")
            return format("%s %s", "VST 2.4", pack.is64b ? "(64 bit)" : "(32 bit)");
        return format("%s %s", pack.format, pack.is64b ? "(64 bit)" : "(32 bit)");
    }

    string formatSectionIdentifier(WindowsPackage pack) pure
    {
        return format("%s%s", pack.format, pack.is64b ? "64b" : "32b");
    }

    string sectionDescription(WindowsPackage pack) pure
    {
        if (pack.format == "VST")
            return "For VST 2.4 hosts like FL Studio, Live, Bitwig, Studio One, etc. Includes both 32bit and 64bit components.";
        else if(pack.format == "VST3")
            return "For VST 3 hosts like Cubase, Digital Performer, Wavelab., etc. Includes both 32bit and 64bit components.";
        else if(pack.format == "AAX")
            return "For Pro Tools 11 or later.";
        else if(pack.format == "LV2")
            return "For LV2 hosts like REAPER, Mixbus, and Ardour.";
        else
            return "";
    }

    string vstInstallDirDescription(bool is64b) pure
    {
        string description = "";
        if (is64b)
            description ~= "Select your 64-bit VST 2.4 folder.";
        else
            description ~= "Select your 32-bit VST 2.4 folder.";
        return description;
    }

    //remove ./ if it occurs at the beginning of windowsInstallerHeaderBmp
    string headerImagePage = plugin.windowsInstallerHeaderBmp.replaceAll(r"^./".regex, "");
    string nsisPath = "WindowsInstaller.nsi";

    string content = "";

    content ~= "!include \"MUI2.nsh\"\n";
    content ~= "!include \"LogicLib.nsh\"\n";
    content ~= "!include \"x64.nsh\"\n";
    content ~= "BrandingText \"" ~ plugin.vendorName ~ "\"\n";
    content ~= "SpaceTexts none\n";
    content ~= `OutFile "` ~ outExePath ~ `"` ~ "\n";
    content ~= "RequestExecutionLevel admin\n";

    if (plugin.windowsInstallerHeaderBmp != null)
    {
        content ~= "!define MUI_HEADERIMAGE\n";
        content ~= "!define MUI_HEADERIMAGE_BITMAP \"" ~ escapeNSISPath(headerImagePage) ~ "\"\n";
    }

    content ~= "!define MUI_ABORTWARNING\n";
    if (plugin.iconPathWindows)
        content ~= "!define MUI_ICON \"" ~ escapeNSISPath(plugin.iconPathWindows) ~ "\"\n";

    // Use the markdown licence file with macro expanded.
    string licensePath = outputDir ~ "/license-expanded.md"; 
    content ~= "!insertmacro MUI_PAGE_LICENSE \"" ~ licensePath ~ "\"\n";

    content ~= "!insertmacro MUI_PAGE_COMPONENTS\n";
    content ~= "!insertmacro MUI_LANGUAGE \"English\"\n\n";

    auto sections = packs.uniq!((p1, p2) => p1.format == p2.format);
    foreach(p; sections)
    {
        content ~= `Section "` ~ p.title ~ `" Sec` ~ p.format ~ "\n";
        content ~= "AddSize " ~ p.bytes.to!string ~ "\n";
        content ~= "SectionEnd\n";
    }

    foreach(p; sections)
    {
        content ~= "LangString DESC_" ~ p.format ~ " ${LANG_ENGLISH} \"" ~ sectionDescription(p) ~ "\"\n";
    }

    content ~= "!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN\n";
    foreach(p; sections)
    {

        content ~= "!insertmacro MUI_DESCRIPTION_TEXT ${Sec" ~ p.format ~ "} $(DESC_" ~ p.format ~ ")\n";
    }
    content ~= "!insertmacro MUI_FUNCTION_DESCRIPTION_END\n\n";

    foreach(p; packs)
    {
        if(p.format == "VST")
        {
            content ~= `Var InstDir` ~ formatSectionIdentifier(p) ~ "\n";
        }
    }

    content ~= "Name \"" ~ plugin.pluginName ~ " v" ~ plugin.publicVersionString ~ "\"\n\n";

    foreach(p; packs)
    {
        if(p.format == "VST")
        {
            string identifier = formatSectionIdentifier(p);
            string formatNiceName = formatSectionDisplayName(p);
            content ~= "PageEx directory\n";
            content ~= "  PageCallbacks defaultInstDir" ~ identifier ~ ` "" getInstDir` ~ identifier ~ "\n";
            content ~= "  DirText \"" ~ vstInstallDirDescription(p.is64b) ~ "\" \"\" \"\" \"\"\n";
            content ~= `  Caption ": ` ~ formatNiceName ~ ` Directory"` ~ "\n";
            content ~= "PageExEnd\n";
        }
    }
    content ~= "Page instfiles\n";

    foreach(p; packs)
    {
        if(p.format == "VST")
        {
            string identifier = formatSectionIdentifier(p);

            content ~= "Function defaultInstDir" ~ identifier ~ "\n";
            if(p.is64b)
            {
                // The 64-bit version does not get installed on a 32-bit system, skip asking in this case
                content ~= "  ${IfNot} ${RunningX64}\n";
                content ~= "    Abort\n";
                content ~= "  ${EndIf}\n";
            }
            content ~= "  ${IfNot} ${SectionIsSelected} ${Sec" ~ p.format ~ "}\n";
            content ~= "    Abort\n";
            content ~= "  ${Else}\n";
            content ~= `    StrCpy $INSTDIR "` ~ p.installDir ~ `"` ~ "\n";
            content ~= "  ${EndIf}\n";
            content ~= "FunctionEnd\n\n";
            content ~= "Function getInstDir" ~ identifier ~ "\n";
            content ~= "  StrCpy $InstDir" ~ identifier ~ " $INSTDIR\n";
            content ~= "FunctionEnd\n\n";
        }
    }

    content ~= "Section\n";
    content ~= "  ${If} ${RunningX64}\n";
    content ~= "    SetRegView 64\n";
    content ~= "  ${EndIf}\n";

    auto lv2Packs = packs.filter!((p) => p.format == "LV2").array();
    foreach(p; packs)
    {
        bool pluginIsDir = p.pluginDir.isDir;

        {
            // Only install the 64-bit package on 64-bit OS
            content ~= "  ${If} ${SectionIsSelected} ${Sec" ~ p.format ~ "}\n";
            if(p.is64b)
                content ~= "    ${AndIf} ${RunningX64}\n";
            if (p.format == "VST")
            {
                string instDirVar = "InstDir" ~ formatSectionIdentifier(p);
                content ~= "    SetOutPath $" ~ instDirVar ~ "\n";
                content ~= format!"    WriteRegStr HKLM \"%s\" \"%s\" \"$%s\"\n"(regProductKey, instDirVar, instDirVar);
            }
            else
                content ~= "    SetOutPath \"" ~ p.installDir ~ "\"\n";
            content ~= "    File " ~ (pluginIsDir ? "/r " : "") ~ "\"" ~ p.pluginDir.asNormalizedPath.array ~ "\"\n";
            content ~= "  ${EndIf}\n";
        }
    }

    content ~= format!"    CreateDirectory \"$PROGRAMFILES\\%s\\%s\"\n"(plugin.vendorName, plugin.pluginName);
    content ~= format!"    WriteUninstaller \"$PROGRAMFILES\\%s\\%s\\Uninstall.exe\"\n"(plugin.vendorName, plugin.pluginName);
    content ~= format!"    WriteRegStr HKLM \"%s\" \"DisplayName\" \"%s\"\n"(regUninstallKey, plugin.prettyName);
    content ~= format!"    WriteRegStr HKLM \"%s\" \"UninstallString\" \"$PROGRAMFILES\\%s\\%s\\Uninstall.exe\"\n"(regUninstallKey, plugin.vendorName, plugin.pluginName);

    content ~= "SectionEnd\n\n";

    // Uninstaller

    content ~= "Section \"Uninstall\"\n";
    content ~= "  ${If} ${RunningX64}\n";
    content ~= "    SetRegView 64\n";
    content ~= "  ${EndIf}\n";
    foreach(p; packs)
    {
        bool pluginIsDir = p.pluginDir.isDir;

        if(p.is64b)
          content ~= "    ${If} ${RunningX64}\n";

        if (p.format == "VST")
        {
            string instDirVar = "InstDir" ~ formatSectionIdentifier(p);
            content ~= format!"    ReadRegStr $%s HKLM \"%s\" \"%s\"\n"(instDirVar, regProductKey, instDirVar);
            content ~= format!"    ${If} $%s != \"\"\n"(instDirVar);
            content ~= format!"        Delete \"$%s\\%s\"\n"(instDirVar, p.pluginDir.baseName);
            content ~=        "    ${EndIf}\n";
        }
        else if (pluginIsDir)
        {
            content ~= format!"    RMDir /r \"%s\\%s\"\n"(p.installDir, p.pluginDir.baseName);
        }
        else
        {
            content ~= format!"    Delete \"%s\\%s\"\n"(p.installDir, p.pluginDir.baseName);
        }

        if(p.is64b)
          content ~= "    ${EndIf}\n";
    }
    content ~= format!"    DeleteRegKey HKLM \"%s\"\n"(regProductKey);
    content ~= format!"    DeleteRegKey /ifempty HKLM \"%s\"\n"(regVendorKey);
    content ~= format!"    DeleteRegKey HKLM \"%s\"\n"(regUninstallKey);
    content ~= format!"    RMDir /r \"$PROGRAMFILES\\%s\\%s\"\n"(plugin.vendorName, plugin.pluginName);
    content ~= format!"    RMDir \"$PROGRAMFILES\\%s\"\n"(plugin.vendorName);
    content ~= "SectionEnd\n\n";

    std.file.write(nsisPath, cast(void[])content);

    // run makensis on the generated WindowsInstaller.nsi with verbosity set to errors only
    string makeNsiCommand = format("makensis.exe /V1 %s", nsisPath);
    safeCommand(makeNsiCommand);

    try
    {
        // use windows signtool to sign the installer for distribution
        string cmd = format("signtool sign /f %s /p %s /tr http://timestamp.sectigo.com /td sha256 /fd sha256 /q %s",
                            plugin.getKeyFileWindows(),
                            plugin.getKeyPasswordWindows(),
                            escapeShellArgument(outExePath));
        safeCommand(cmd);
        cwriteln("    => OK".green);
    }
    catch(Exception e)
    {
        error(format("Installer signature failed! %s", e.msg));
    }
}

struct MacPackage
{
    string identifier;
    string pathToPkg;
    string pkgFilename;
    string distributionId; // ID for the distribution.txt
    string title;
}

void generateMacInstaller(string outputDir,
                          string resDir,
                          Plugin plugin,
                          MacPackage[] packs,
                          string outPkgPath,
                          bool verbose)
{
    string distribPath = "mac-distribution.txt";

    string content = "";

    content ~= `<?xml version="1.0" encoding="utf-8"?>` ~ "\n";
    content ~= `<installer-gui-script minSpecVersion="1">` ~ "\n";

    content ~= format(`<title>%s</title>` ~ "\n", plugin.prettyName ~ " v" ~ plugin.publicVersionString);

    if (plugin.installerPNGPath)
    {
        string backgroundPath = resDir ~ "/background.png";
        std.file.copy(plugin.installerPNGPath, backgroundPath);
        content ~= format(`<background file="background.png" alignment="center" scaling="proportional"/>` ~ "\n");
    }
    else
    {
        warning("No PNG background provided. Add a key \"installerPNGPath\" in your plugin.json to have one.");
    }

    if (plugin.licensePath)
    {
        // this file should exist at this point
        string licensePath = outputDir ~ "/license.html";
        string reslicensePath = resDir ~ "/license.html";
        std.file.copy(licensePath, reslicensePath);
        content ~= format(`<license file="license.html" mime-type="text/html"/>` ~ "\n");
    }

    // This is a kind of forward declaration <pkg-ref> are merged
    foreach(p; packs)
        content ~= format(`<pkg-ref id="%s"/>` ~ "\n", p.distributionId);

    content ~= `<options customize="always" require-scripts="false"/>` ~ "\n";

    content ~= `<choices-outline>` ~ "\n";
    content ~= `    <line choice="default">` ~ "\n";

    foreach(p; packs)
        content ~= format(`        <line choice="%s"/>` ~ "\n", p.distributionId);
    content ~= `    </line>` ~ "\n";
    content ~= `</choices-outline>` ~ "\n";
    content ~= format(`<choice id="default" title="%s"/>` ~ "\n", plugin.prettyName ~ " v" ~ plugin.publicVersionString);

    foreach(p; packs)
    {
        content ~= format(`<choice id="%s" visible="true" title="%s">` ~ "\n",
            p.distributionId, p.title);
        content ~= format(`    <pkg-ref id="%s"/>` ~ "\n", p.distributionId);
        content ~= format(`</choice>` ~ "\n");

        // TODO: is this path relative to distribution.xml?
        content ~= format(`<pkg-ref id="%s" version="%s">%s</pkg-ref>` ~ "\n",
                          p.distributionId, plugin.publicVersionString(), p.pkgFilename);
    }

    content ~= `</installer-gui-script>` ~ "\n";

    std.file.write(distribPath, cast(void[])content);

    string signStr = "";
    if (plugin.developerIdentity !is null)
    {
        signStr = format(" --sign %s --timestamp", escapeShellArgument(plugin.developerIdentity));
    }
    else
    {
        warning("Can't sign the installer. Please provide a key \"developerIdentity-osx\" in your plugin.json. Users computers will reject this installer.");
    }


    string quietStr = verbose ? "" : " --quiet";

    // missing --version and --identifier?
    string packagePaths = "";
    foreach(p; packs)
       packagePaths ~= format(` --package-path %s`, escapeShellArgument(dirName(p.pathToPkg)));
    string cmd = format("productbuild%s%s --resources %s --distribution %s%s %s",
                        signStr,
                        quietStr,
                        escapeShellArgument(resDir),
                        escapeShellArgument(distribPath),
                        packagePaths,
                        escapeShellArgument(outPkgPath));
    safeCommand(cmd);
}

void notarizeMacInstaller(Plugin plugin, string outPkgPath, string primaryBundleId)
{
    string uploadXMLPath = buildPath(tempDir(), "notarization-upload.xml");
    string pollXMLPath = buildPath(tempDir(), "notarization-poll.xml");
    if (plugin.vendorAppleID is null)
        throw new Exception(`Missing "vendorAppleID" in plugin.json. Notarization need this key.`);
    if (plugin.appSpecificPassword_altool is null)
            throw new Exception(`Missing "appSpecificPassword-altool" in plugin.json. Notarization need this key.`);
    if (plugin.appSpecificPassword_stapler is null)
            throw new Exception(`Missing "appSpecificPassword-stapler" in plugin.json. Notarization need this key.`);

    {
        string cmd = format(`xcrun altool --notarize-app -t osx -f %s -u %s -p %s --primary-bundle-id %s --output-format xml > %s`,
                            escapeShellArgument(outPkgPath),
                            plugin.vendorAppleID,
                            plugin.appSpecificPassword_altool,
                            primaryBundleId,
                            uploadXMLPath,
                            );
        safeCommand(cmd);
    }

    import arsd.dom;

    // read XML
    string requestUUID = null;

    {
        auto doc = new Document();
        doc.parseUtf8( cast(string)(std.file.read(uploadXMLPath)), false, false);
        auto plist = doc.root;

        foreach(key; plist.querySelectorAll("key"))
        {
            if (key.innerHTML == "success-message")
            {
                auto value = key.nextSibling("string");
                cwritefln("    Upload returned message '%s'", value.innerHTML);
            }
            else if (key.innerHTML == "notarization-upload")
            {
                auto dict = key.nextSibling("dict");
                foreach(key2; dict.querySelectorAll("key"))
                {
                    if (key2.innerHTML == "RequestUUID")
                    {
                        requestUUID = key2.nextSibling("string").innerHTML;
                    }
                }
            }
        }
    }

    if (requestUUID)
    {
        cwritefln("    => Uploaded, RequestUUID = %s".green, requestUUID);
        cwriteln();
    }
    else
        throw new Exception("Couldn't parse RequestUUID");

    // Three possible outcomes: suceeded, invalid, and timeout (1 hour of polling)
    bool notarizationSucceeded = false;
    bool notarizationFailed = false;
    string LogFileURL = null;
    double timeout = 5000;
    double timeSpentPolling = 0;
    while(true)
    {
        if (notarizationSucceeded || notarizationFailed)
            break;

        if (timeSpentPolling > 3600 * 1000)
        {
            notarizationSucceeded = false;
            notarizationFailed = false;
            break;
        }

        string cmd = format(`xcrun altool --notarization-info %s --username %s --password %s --output-format xml > %s`,
                        escapeShellArgument(requestUUID),
                        plugin.vendorAppleID,
                        plugin.appSpecificPassword_altool,
                        pollXMLPath,
                        );

        int errorCode = 239;
        int retryAttempts = 0;
        do
        {
            errorCode = unsafeCommand(cmd);
            if(errorCode == 239)
            {
                cwritefln("    Notarization-info not yet available, retrying...".yellow);
            }
            else if (errorCode > 0)
            {
                throw new ExternalProgramErrored(errorCode, format("Command '%s' returned %s", cmd, errorCode));
            }
            ++retryAttempts;
        }
        while (errorCode == 239 && retryAttempts < 20);

        auto doc = new Document();
        doc.parseUtf8( cast(string)(std.file.read(pollXMLPath)), false, false);
        auto plist = doc.root;
        string status;
        foreach(key; plist.querySelectorAll("key"))
        {
            if (key.innerHTML == "notarization-info")
            {
                auto dict = key.nextSibling("dict");
                foreach(key2; dict.querySelectorAll("key"))
                {
                    if (key2.innerHTML == "LogFileURL")
                    {
                        LogFileURL = key2.nextSibling("string").innerHTML;
                    }
                    else if (key2.innerHTML == "Status")
                    {
                        status = key2.nextSibling("string").innerHTML;
                        if (status == "in progress")
                        {
                            cwriteln("    => Notarization in progress, waiting...");
                            Thread.sleep( (cast(long)timeout).msecs );
                            timeSpentPolling += timeout;
                            timeout = timeout * 1.61;
                            if (timeout > 60000) timeout = 60000; // can't exceed one minute
                        }
                        else if (status == "success")
                        {
                            notarizationSucceeded = true;
                        }
                        else if (status == "invalid")
                        {
                            notarizationFailed = true;
                        }
                    }
                }
            }
        }
        if (status is null)
            throw new Exception(format("Couldn't parse a status in %s", pollXMLPath));
    }
    if (notarizationFailed)
    {
        cwritefln("    => Notarization failed, log available at %s".red, LogFileURL);
        cwriteln();
        throw new Exception("Failed notarization");
    }

    if (!notarizationSucceeded)
        throw new Exception("Time out. Notarization took more than one hour. Consider uploading smaller packages.");

    cwritefln("    => Notarization succeeded, log available at %s".green, LogFileURL);
    cwriteln();

    {
        string cmd = format(`xcrun altool --notarize-app -t osx -f %s -u %s -p %s --primary-bundle-id %s --output-format xml > %s`,
                            escapeShellArgument(outPkgPath),
                            plugin.vendorAppleID,
                            plugin.appSpecificPassword_altool,
                            primaryBundleId,
                            uploadXMLPath,
                            );
        safeCommand( format(`xcrun stapler staple %s`, escapeShellArgument(outPkgPath) ) );
    }
}
