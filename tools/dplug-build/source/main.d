import core.stdc.string;

import std.file;
import std.stdio;
import std.conv;
import std.uni;
import std.uuid;
import std.process;
import std.string;
import std.path;

import dplug.core.sharedlib;

import colorize;
import utils;
import plugin;

// This define the paths to install plug-ins on macOS
string MAC_VST3_DIR = "/Library/Audio/Plug-Ins/VST3";
string MAC_VST_DIR = "/Library/Audio/Plug-Ins/VST";
string MAC_AU_DIR  = "/Library/Audio/Plug-Ins/Components";
string MAC_AAX_DIR = "/Library/Application Support/Avid/Audio/Plug-Ins";
string MAC_LV2_DIR = "/Library/Audio/Plug-Ins/LV2";


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
    cwriteln( "This is the ".white ~ "dplug-build".cyan ~ " tool: plugin bundler and DUB front-end.".white);
    cwriteln();
    cwriteln("FLAGS".white);
    cwriteln();
    flag("-a --arch", "Selects target architecture.", "x86 | x86_64 | all", "Windows => all   macOS => x86_64    Linux => x86_64");
    flag("-b --build", "Selects build type.", "same ones as dub accepts", "debug");
    flag("--compiler", "Selects D compiler.", "dmd | ldc | gdc", "ldc");
    flag("-c --config", "Adds a build configuration.", "VST | VST3 | AU | AAX | LV2 | name starting with \"VST\", \"VST3\",\"AU\", \"AAX\", or \"LV2\"", "all");
    flag("-f --force", "Forces rebuild", null, "no");
    flag("--combined", "Combined build, important for cross-module inlining with LDC!", null, "no");
    flag("-q --quiet", "Quieter output", null, "no");
    flag("-v --verbose", "Verbose output", null, "no");
    flag("-sr --skip-registry", " Skip checking the DUB registry\n                        Avoid network, doesn't update dependencies", null, "no");
    flag("--final", "Shortcut for --force --combined -b release-nobounds", null, null);
    flag("--installer", "Make an installer " ~ "(OSX only)".red, null, "no");
    flag("--publish", "Make the plugin available in standard directories " ~ "(OSX only, DOESN'T WORK)".red, null, "no");
    flag("--auval", "Check Audio Unit validation with auval " ~ "(OSX only, DOESN'T WORK)".red, null, "no");
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
    cwriteln("      dplug-build".cyan ~ " detects plugin format based on the " ~ "configuration".yellow ~ " name's prefix: " ~ "VST | VST3 | AU | AAX | LV2.".yellow);
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

        Arch[] archs = allArchitectureqForThisPlatform();

        // Until 32-bit is eventually fixed for macOS, remove it from default arch
        version(OSX)
            archs = [ Arch.x86_64 ];

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
        bool skipRegistry = false;
        string prettyName = null;


        string osString = "";
        version (OSX)
            osString = "macOS";
        else version(linux)
            osString = "Linux";
        else version(Windows)
            osString = "Windows";

        // Expand macro arguments
        for (int i = 1; i < args.length; )
        {
            string arg = args[i];
            if (arg == "--final")
            {
                args = args[0..i] ~ ["--force",
                                     "--combined",
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
            else if (arg == "--installer")
            {
                version(OSX)
                    makeInstaller = true;
                else
                    warning("--installer not supported on that OS");
            }
            else if (arg == "--combined")
                combined = true;
            else if (arg == "-a" || arg == "--arch")
            {
                ++i;

                if (args[i] == "x86")
                    archs = [ Arch.x86 ];
                else if (args[i] == "x86_64")
                    archs = [ Arch.x86_64 ];
                else if (args[i] == "all")
                {
                    archs = allArchitectureqForThisPlatform();
                }
                else
                    throw new Exception("Unrecognized arch (available: x86, x86_64, all)");
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

        if (quiet && verbose)
            throw new Exception("Can't have both --quiet and --verbose flags.");

        if (help)
        {
            usage();
            return 0;
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

        version(OSX)
        {
            // A path to .pkg artifacts to distribute together
            MacPackage[] macInstallerPackages;
        }

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
                cwritefln("   Then a Mac installer will be created for distribution outside of the App Store.".green);
            cwriteln();
        }

        void buildAndPackage(string config, Arch[] architectures, string iconPath)
        {
            // Is one of those arch Universal Binary?
            bool oneOfTheArchIsUB = false;
            foreach (arch; architectures)
            {
                if (arch == Arch.universalBinary)
                    oneOfTheArchIsUB = true;
            }

            foreach (int archCount, arch; architectures)
            {
                bool is64b = arch == Arch.x86_64;

                // Does not try to build 32-bit builds of AAX, or Universal Binaries
                if (configIsAAX(config) && (arch == Arch.universalBinary || arch == Arch.x86))
                {
                    cwritefln("info: Skipping architecture %s for AAX\n".white, arch);
                    continue;
                }

                // Does not try to build AU under Windows
                version(Windows)
                {
                    if (configIsAU(config))
                        throw new Exception("Can't build AU format on Windows");
                }

                // Does not try to build AAX or AU under Linux
                version(linux)
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
                version(OSX)
                {
                    if (!configIsAAX(config) && oneOfTheArchIsUB)
                    {
                        // In short: this build is deemed "temporary" if it's only a step toward building a
                        // multi-arch Universal Binary on macOS.
                        if (arch == Arch.x86)
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
                    buildPlugin(compiler, config, build, is64b, verbose, force, combined, quiet, skipRegistry);

                    double bytes = getSize(plugin.dubOutputFileName) / (1024.0 * 1024.0);
                    cwritefln("    => Build OK, binary size = %0.1f mb, available in ./%s".green, bytes, path);
                    cwriteln();
                }

                void signAAXBinaryWithPACE(string binaryPathInOut)
                {
                    if (!plugin.hasPACEConfig)
                    {
                        warning("Plug-in will not be signed by PACE because no pace.json found");
                        return;
                    }

                    // Get password from the user if "!PROMPT" was used
                    plugin.paceConfig.promptPasswordsLazily();

                    auto paceConfig = plugin.paceConfig;

                    version(Windows)
                    {
                        string cmd = format(`wraptool sign %s--account %s --password %s --keyfile %s --keypassword %s --wcguid %s --in %s --out %s`,
                                            (verbose ? "--verbose " : ""),
                                            paceConfig.iLokAccount,
                                            paceConfig.iLokPassword,
                                            paceConfig.keyFileWindows,
                                            paceConfig.keyPasswordWindows,
                                            paceConfig.wrapConfigGUID,
                                            escapeShellArgument(binaryPathInOut),
                                            escapeShellArgument(binaryPathInOut));
                        safeCommand(cmd);
                    }
                    else version(OSX)
                    {
                        string cmd = format(`wraptool sign --verbose --account %s --password %s --signid %s --wcguid %s --in %s --out %s`,
                                            paceConfig.iLokAccount,
                                            paceConfig.iLokPassword,
                                            escapeShellArgument(paceConfig.developerIdentityOSX),
                                            paceConfig.wrapConfigGUID,
                                            escapeShellArgument(binaryPathInOut),
                                            escapeShellArgument(binaryPathInOut));
                        safeCommand(cmd);
                        writeln();
                    }
                    else
                        assert(false);
                }

                void extractAAXPresetsFromBinary(string binaryPath, string contentsDir, bool is64b)
                {
                    // Extract presets from the AAX plugin binary by executing it.
                    // Because of this release itself must be 64-bit.
                    // To avoid this coupling, presets should be stored outside of the binary in the future.
                    if ((void*).sizeof == 4 && is64b)
                        warning("Can't extract presets from a 64-bit AAX plug-in when dplug-build is built as a 32-bit program.\n");
                    else if ((void*).sizeof == 8 && !is64b)
                        warning("Can't extract presets from a 32-bit AAX plug-in when dplug-build is built as a 64-bit program.\n");
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

                void extractLV2ManifestFromBinary(string binaryPath, string outputDir, bool is64b, string binaryName)
                {
                    // Extract ports from LV2 Binary
                    // Because of this release itself must be 64-bit.
                    // To avoid this coupling, presets should be stored outside of the binary in the future.
                    if ((void*).sizeof == 4 && is64b)
                        warning("Can't extract ports from a 64-bit LV2 plug-in when dplug-build is built as a 32-bit program.\n");
                    else if ((void*).sizeof == 8 && !is64b)
                        warning("Can't extract ports from a 32-bit LV2 plug-in when dplug-build is built as a 64-bit program.\n");
                    else
                    {
                        SharedLib lib;
                        lib.load(binaryPath);
                        if (!lib.hasSymbol("GenerateManifestFromClient"))
                            throw new Exception("Couldn't find the symbol ExtractPortConfiguration in the plug-in");

                        // Note: this is duplicated in dplug:lv2 in lv2_init.d
                        alias generateManifestFromClientCallback = extern(C) void function(const(ubyte)* fileContents, size_t len, const(char)[] path); 
                        alias generateManifest = extern(C) void function(generateManifestFromClientCallback, const(char)[] binaryFileName, const(char)[] licensePath, const(char)[] buildDir);

                        static extern(C) void processManifest(const(ubyte*) fileContents, size_t len, const(char)[] path)
                        {
                            const(char)[] manifest = cast(const(char)[])fileContents[0..len];
                            cwriteln(manifest);
                            std.file.write(path ~ "/manifest.ttl", fileContents[0..len]);
                        }
                        generateManifest ptrGenerateManifest = cast(generateManifest) lib.loadSymbol("GenerateManifestFromClient");
                        ptrGenerateManifest(&processManifest, binaryName, plugin.licensePath, outputDir);
                        lib.unload();

                        cwritefln("    => Extracted LV2 manifest from binary".green);
                        cwriteln();
                    }
                }

                version(Windows)
                {
                    // Special case for AAX need its own directory, but according to Voxengo releases,
                    // its more minimal than either JUCE or IPlug builds.
                    // Only one file (.dll even) seems to be needed in <plugin-name>.aaxplugin\Contents\x64
                    // Note: only 64-bit AAX supported.
                    if (configIsAAX(config))
                    {
                        string pluginFinalName = plugin.prettyName ~ ".aaxplugin";
                        string contentsDir = path ~ "/" ~ (plugin.prettyName ~ ".aaxplugin") ~ "/Contents/";

                        extractAAXPresetsFromBinary(plugin.dubOutputFileName, contentsDir, is64b);

                        if (is64b)
                        {
                            mkdirRecurse(contentsDir ~ "x64");
                            fileMove(plugin.dubOutputFileName, contentsDir ~ "x64/" ~ pluginFinalName);
                            signAAXBinaryWithPACE(contentsDir ~ "x64/" ~ pluginFinalName);
                        }
                        else
                        {
                            mkdirRecurse(contentsDir ~ "Win32");
                            fileMove(plugin.dubOutputFileName, contentsDir ~ "Win32/" ~ pluginFinalName);
                            signAAXBinaryWithPACE(contentsDir ~ "Win32/" ~ pluginFinalName);
                        }
                    }
                    else if (configIsLV2(config))
                    {
                        // must create TTL, and a .lv2 directory
                        string pluginFinalName = plugin.prettyName ~ ".dll";
                        string pluginDirectory = path ~ "/" ~ plugin.prettyName ~ ".lv2";
                        string pluginFinalPath = pluginDirectory ~ "/" ~ pluginFinalName;

                        mkdirRecurse(pluginDirectory);
                        fileMove(plugin.dubOutputFileName, pluginFinalPath);
                        extractLV2ManifestFromBinary(pluginFinalPath, pluginDirectory, is64b, pluginFinalName);
                    }
                    else if (configIsVST3(config)) // VST3 special case, needs to be named .vst3 (but can't be _linked_ as .vst3)
                    {
                        string appendBitnessVST3(string prettyName, string originalPath)
                        {
                            if (is64b)
                            {
                                // Issue #84
                                // Rename 64-bit binary on Windows to get Reaper to list both 32-bit and 64-bit plugins if in the same directory
                                return prettyName ~ "-64.vst3";
                            }
                            else
                                return prettyName ~ ".vst3";
                        }
                        // Simply copy the file
                        fileMove(plugin.dubOutputFileName, path ~ "/" ~ appendBitnessVST3(plugin.prettyName, plugin.dubOutputFileName));
                    }
                    else
                    {
                        string appendBitness(string prettyName, string originalPath)
                        {
                            if (is64b)
                            {
                                // Issue #84
                                // Rename 64-bit binary on Windows to get Reaper to list both 32-bit and 64-bit plugins if in the same directory
                                return prettyName ~ "-64" ~ extension(originalPath);
                            }
                            else
                                return prettyName ~ extension(originalPath);
                        }

                        // Simply copy the file
                        fileMove(plugin.dubOutputFileName, path ~ "/" ~ appendBitness(plugin.prettyName, plugin.dubOutputFileName));
                    }
                }
                else version(linux)
                {
                    string soPath = path ~ "/" ~ plugin.prettyName ~ ".so";
                    fileMove(plugin.dubOutputFileName, soPath);
                    if(configIsLV2(config))
                    {
                        extractLV2ManifestFromBinary(soPath, path, is64b, plugin.prettyName ~ ".so");
                    }
                }
                else version(OSX)
                {
                    // Only accepts two configurations: VST and AudioUnit
                    string pluginDir;
                    string installDir;
                    if (configIsVST(config))
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
                    else
                        assert(false, "unsupported plugin format");

                    // On Mac, make a bundle directory
                    string bundleDir = path ~ "/" ~ pluginDir;
                    string contentsDir = path ~ "/" ~ pluginDir ~ "/Contents/";
                    string ressourcesDir = contentsDir ~ "Resources";
                    string macosDir = contentsDir ~ "MacOS";
                    mkdirRecurse(ressourcesDir);
                    mkdirRecurse(macosDir);

                    if (configIsAAX(config))
                        extractAAXPresetsFromBinary(plugin.dubOutputFileName, contentsDir, is64b);

                    // Generate Plist
                    string plist = makePListFile(plugin, config, iconPath != null);
                    std.file.write(contentsDir ~ "Info.plist", cast(void[])plist);

                    void[] pkgInfo = cast(void[]) plugin.makePkgInfo(config);
                    std.file.write(contentsDir ~ "PkgInfo", pkgInfo);

                    string exePath = macosDir ~ "/" ~ plugin.prettyName;

                    // Create a .rsrc for this set of architecture when building an AU
                    if (configIsAU(config))
                    {
                        string rsrcPath = makeRSRC(plugin, arch, verbose);
                        std.file.copy(rsrcPath, contentsDir ~ "Resources/" ~ baseName(exePath) ~ ".rsrc");
                    }

                    if (iconPath)
                        std.file.copy(iconPath, contentsDir ~ "Resources/icon.icns");

                    if (arch == Arch.universalBinary)
                    {
                        string path32 = outputDirectory(outputDir, true, osString, Arch.x86, config)
                        ~ "/" ~ pluginDir ~ "/Contents/MacOS/" ~ plugin.prettyName;

                        string path64 = outputDirectory(outputDir, true, osString, Arch.x86_64, config)
                        ~ "/" ~ pluginDir ~ "/Contents/MacOS/" ~ plugin.prettyName;

                        cwritefln("*** Making an universal binary with lipo".white);

                        string cmd = format("lipo -create %s %s -output %s",
                                            escapeShellArgument(path32),
                                            escapeShellArgument(path64),
                                            escapeShellArgument(exePath));
                        safeCommand(cmd);
                        cwritefln("    => Universal build OK, available in ./%s".green, path);
                        cwriteln();
                    }
                    else
                    {
                        fileMove(plugin.dubOutputFileName, exePath);
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
                                string command = format(`codesign --strict -f -s %s --timestamp %s`,
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
                        if (configIsVST(config))
                        {
                            pkgIdentifier = plugin.pkgBundleVST();
                            pkgFilename   = plugin.pkgFilenameVST();
                            title = "VST plug-in";
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
                            installDir,
                            pkgIdentifier,
                            plugin.publicVersionString,
                            escapeShellArgument(bundleDir),
                            escapeShellArgument(pathToPkg));
                        safeCommand(cmd);
                        cwriteln;
                    }
                }
            }
        }

        mkdirRecurse(outputDir);
        mkdirRecurse(outputDir ~ "/temp");
        if (makeInstaller)
            mkdirRecurse(outputDir ~ "/res-install");

        string iconPath = null;
        version(OSX)
        {
            // Make icns and copy it (if any provided in plugin.json)
            if (plugin.iconPath)
            {
                iconPath = makeMacIcon(plugin.name, plugin.iconPath); // FUTURE: this should be lazy
            }
        }

        // Copy license (if any provided in plugin.json)
        // Ensure it is HTML.
        if (plugin.licensePath)
        {
            string licensePath = outputDir ~ "/license.html";
            if (extension(plugin.licensePath) == ".html")
            {
                std.file.copy(plugin.licensePath, licensePath);
            }
            else if (extension(plugin.licensePath) == ".md")
            {
                // Convert license markdown to HTML
                cwritefln("*** Converting license file to HTML... ".white);
                string markdown = cast(string)std.file.read(plugin.licensePath);
                string html = convertMarkdownFileToHTML(markdown);
                std.file.write(licensePath, html);
                cwritefln(" => OK\n".green);
            }
            else
                throw new Exception("License file should be a Markdown .md or HTML .html file");
        }

        // Copy user manual (if any provided in plugin.json)
        if (plugin.userManualPath)
            std.file.copy(plugin.userManualPath, outputDir ~ "/" ~ baseName(plugin.userManualPath));

        // Build various configuration
        foreach(config; configurations)
            buildAndPackage(config, archs, iconPath);

        version(OSX)
        {
            if (makeInstaller)
            {
                cwriteln("*** Generating final Mac installer...".white);
                string finalPkgPath = outputDir ~ "/" ~ plugin.finalPkgFilename(configurations[0]);
                generateMacInstaller(outputDir, resDir, plugin, macInstallerPackages, finalPkgPath, verbose);
                cwriteln("    => OK".green);
                cwriteln;
            }
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

void buildPlugin(string compiler, string config, string build, bool is64b, bool verbose, bool force, bool combined, bool quiet, bool skipRegistry)
{
     cwritefln("*** Building configuration %s with %s, %s arch...".white, config, compiler, is64b ? "64-bit" : "32-bit");
    // build the output file
    string arch = is64b ? "x86_64" : "x86";

    // Produce output compatible with earlier OSX
    // LDC >= 1.1 does not support earlier than 10.8
    version(OSX)
    {
        environment["MACOSX_DEPLOYMENT_TARGET"] = "10.8";
    }

    string cmd = format("dub build --build=%s --arch=%s --compiler=%s%s%s%s%s%s%s",
        build, arch,
        compiler,
        force ? " --force" : "",
        verbose ? " -v" : "",
        quiet ? " -q" : "",
        combined ? " --combined" : "",
        config ? " --config=" ~ config : "",
        skipRegistry ? " --skip-registry=all" : ""
        );
    safeCommand(cmd);
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