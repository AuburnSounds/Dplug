import core.stdc.string;

import std.file;
import std.stdio;
import std.array;
import std.conv;
import std.uni;
import std.uuid;
import std.process;
import std.string;
import std.path;
import std.json;

import core.time, core.thread;
import dplug.core.sharedlib;

import consolecolors;
import utils;
import plugin;
import arch;
import nsis;

// This define the paths to install plug-ins in on macOS
string MAC_VST3_DIR     = "/Library/Audio/Plug-Ins/VST3";
string MAC_VST_DIR      = "/Library/Audio/Plug-Ins/VST";
string MAC_AU_DIR       = "/Library/Audio/Plug-Ins/Components";
string MAC_AAX_DIR      = "/Library/Application Support/Avid/Audio/Plug-Ins";
string MAC_LV2_DIR      = "/Library/Audio/Plug-Ins/LV2";
string MAC_CLAP_DIR      = "/Library/Audio/Plug-Ins/CLAP";
string MAC_FLP_DIR      = "/Library/Audio/Plug-Ins/FL"; // Note: this one is fictional, there is no such FL directory.


string WIN_VST3_DIR     = "$PROGRAMFILES64\\Common Files\\VST3";
string WIN_VST_DIR      = "$PROGRAMFILES64\\VSTPlugins";
string WIN_LV2_DIR      = "$PROGRAMFILES64\\Common Files\\LV2";
string WIN_AAX_DIR      = "$PROGRAMFILES64\\Common Files\\Avid\\Audio\\Plug-Ins";
string WIN_CLAP_DIR     = "$PROGRAMFILES64\\Common Files\\CLAP";
string WIN_VST3_DIR_X86 = "$PROGRAMFILES\\Common Files\\VST3";
string WIN_VST_DIR_X86  = "$PROGRAMFILES\\VSTPlugins";
string WIN_LV2_DIR_X86  = "$PROGRAMFILES\\Common Files\\LV2";
string WIN_AAX_DIR_X86  = "$PROGRAMFILES\\Common Files\\Avid\\Audio\\Plug-Ins";
string WIN_CLAP_DIR_X86 = "$PROGRAMFILES\\Common Files\\CLAP";
// Note: FLP installation dir default is dynamically discovered by the installer.

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
        string argStr = format("  %s", arg);
        cwrite(argStr.lcyan);
        for(size_t i = argStr.length; i < 19; ++i)
            write(" ");
        cwritefln("%s", desc);
        if (possibleValues)
            cwritefln("                   Accepts: ".grey ~ "%s".yellow, possibleValues);
        if (defaultDesc)
            cwritefln("                   Default: ".grey ~ "%s", defaultDesc.orange);
   //     cwriteln;
    }

    cwriteln();
    cwriteln( "This is the <strong><lcyan>dplug-build</lcyan></strong> tool: plugin bundler and DUB front-end.🔧");
    cwriteln();
    cwriteln("────────── <on_blue> FLAGS </> ────────── 😸🚩".white);
    cwriteln();
    flag("-a --arch", "Select target architectures", "x86 | x86_64 | arm64 | all", "Windows=&gt;x86_64   macOS=&gt;all   Linux=&gt;x86_64");
    flag("-b --build", "Select DUB build type", null, "debug");
    flag("-c --config", "Select DUB configs. Known prefix needed", "VST2x | VST3x | AUx | AAXx | LV2x | FLPx", "first one found");
    flag("--compiler", "Select D compiler", null, "ldc2");
    flag("--compiler-x86_64", " Force compiler for x86_64 architecture", null, "same as --compiler");
    flag("--combined", "Combined build", null, null);
    flag("--final", "Release. Shortcut for --combined -b release-nobounds", null, null);
    flag("-f --force", "Force rebuild", null, null);
    flag("-q --quiet", "Quieter output", null, null);
    flag("-v --verbose", "Verbose output", null, null);
    flag("--no-color", "Disable colored output", null, null);
    flag("--parallel", "Use dub --parallel", null, null);
    flag("--redub", "Use redub instead of dub", null, null);
    flag("--root", "Path where plugin.json is", null, "current working directory");
    flag("--installer", "Make an installer " ~ "                   (Windows, macOS)".lred, null, null);
    flag("--notarize", "Notarize the installer " ~ "                       (macOS)".lred, null, null);
    flag("--publish", "Copy plugin in system directories " ~ "            (macOS)".lred, null, null);
    flag("--auval", "Audio Unit validation with auval " ~ "             (macOS)".lred, null, null);
    
    flag("--os", "Cross-compile to another OS" ~ "                  (future)".lred, "linux | macos | windows | autodetect", "build OS");
    flag("-h --help", "Show this help", null, null);

    cwriteln();
    cwriteln("────────── <on_blue> EXAMPLES </> ────────── 😸💡".white);
    cwriteln();
    cwriteln("  💠   # Make optimized VST2/AU plugin for all supported architectures".lgreen);
    cwriteln("       dplug-build --final -c VST2-CONF -c AU-CONF -a all".lcyan);
    cwriteln();
    cwriteln("  💠   # Build arm64 Audio Unit plugin for profiling with LDC".lgreen);
    cwriteln("       dplug-build --compiler ldc2 -a arm64 -c AU -b release-debug".lcyan);
    cwriteln;
    cwriteln("  💠   # Build an x86 VST3 in given directory".lgreen);
    cwriteln("       dplug-build --root ../products/my-product -c VST3-CONF -a x86".lcyan);
    cwriteln;
    cwriteln;
    cwriteln("──────────── <on_blue> LORE </> ──────────── 😸📖".white);
    cwriteln;
    cwriteln("  dplug-build".lcyan ~ " detects plugin format based on the " ~ "configuration".yellow ~ " name's\n  prefix: " ~ `"VST2" | "VST3" | "AU" | "AAX" | "LV2" | "FLP".`.yellow);
    cwriteln("  The name(s) used with " ~ "-c --config".lcyan ~ " must exist in your " ~ "dub.json".lcyan ~ " file.");
    cwriteln();
    cwriteln("  dplug-build".lcyan ~ " needs a " ~ "plugin.json".lcyan ~ " file and will help write it.");
    cwriteln("  Some information is also gathered from " ~ "dub.json".lcyan ~ " or " ~ "dub.sdl".lcyan ~ ".");
    cwriteln();
    cwriteln("  Be sure to check the Dplug Wiki!✨");
    cwriteln("  💠  <blink>https://github.com/AuburnSounds/Dplug/wiki</blink>".lcyan);
    cwriteln();
}

int main(string[] args)
{
    try
    {
        enableConsoleUTF8();
        string compiler = "ldc2";      // use LDC by default
        string compiler_x86_64 = null; // Default: Use same as --compiler

        // The _target_ architectures. null means "default".
        Arch[] archs = null;

        string build = "debug";
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
        bool redub = false;
        bool legacyPT10 = false;
        bool finalFlag = false;
        string prettyName = null;
        string rootDir = ".";

        OS targetOS = buildOS();
        string osString = convertOSToString(targetOS);

        // Expand macro arguments
        for (int i = 1; i < args.length; )
        {
            string arg = args[i];
            if (arg == "--final")
            {
                finalFlag = true;
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
                disableConsoleColors();
            else if (arg == "--compiler")
            {
                ++i;
                compiler = args[i];
            }
            else if (arg == "--compiler-x86_64")
            {
                ++i;
                compiler_x86_64 = args[i];
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
            else if (arg == "--rez")  // this flag left undocumented, noone ever used it
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
            else if (arg == "--root")
            {
                ++i;
                rootDir = args[i];
            }
            else if (arg == "--installer")
            {
                // BUG here: order between --os and --installer
                if (targetOS == OS.macOS)
                    makeInstaller = true;
                else if (targetOS == OS.windows)
                    makeInstaller = true;
                else
                    warning("--installer not supported on that OS");
            }
            else if (arg == "--legacy-pt10") // this flag left undocumented, noone ever used it
            {
                if (targetOS == OS.windows)
                    legacyPT10 = true;
                else
                    warning("--legacy-pt10 not supported on that OS");
            }
            else if (arg == "--combined")
                combined = true;
            else if (arg == "--os")
            {
                ++i;
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
                    archs = [ Arch.all ];
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
            else if (arg == "--redub")
                redub = true;
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
        {
            if (notarize && !makeInstaller)
                throw new Exception("Flag --notarize cannot be used without --installer.");

            if (finalFlag && makeInstaller && !notarize)
                warning("--final and --installer used but not --notarize. Users will see an \"unidentified developer\" pop-up.");
        }

        if (archs is null)
        {
            // Autodetect target archs that dplug-build is able to build, for the target OS
            archs = defaultArchitecturesToBuildForThisOS(targetOS);
        }
        else if (archs == [ Arch.all ])
        {
            archs = allArchitecturesWeCanBuildForThisOS(targetOS);
        }

        assert(archs != [ Arch.all ]);

        if (compiler_x86_64 is null)
            compiler_x86_64 = compiler;

        Plugin plugin = readPluginDescription(rootDir, quiet, verbose);

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

        string outputDir = buildPath(rootDir, "builds").array.to!string;

        // A directory for the Mac installer
        string resDir    = buildPath(outputDir, "res-install").array.to!string; 

        void fileMove(string source, string dest)
        {
            std.file.copy(source, dest);
            std.file.remove(source);
        }

        auto oldpath = environment["PATH"];

        // Get output directory for per-arch dplug-build artifacts.
        // Find these under: ./builds/xxxxxxxxxx
        static string outputDirectory(string outputDir, 
                                      bool temp, 
                                      string osString, 
                                      Arch arch, 
                                      string config)
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
                    case all:   assert(false);
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

        // Only used for AAX. A copy of presets, that allows to create multi-arch AAX.
        // Kept in memory because presets are fairly small.
        static struct TFXPreset
        {
            string filename; // eg: "stuff.tfx"
            immutable(ubyte)[] content;
        }
        TFXPreset[] tfxPresets = null;


        cwriteln();

        if (!quiet)
        {
            cwritefln("=&gt; Bundling plug-in ".lgreen ~ "%s".yellow ~ " from ".lgreen ~ "%s".yellow
                      ~ ", archs ".lgreen ~ "%s".yellow,
                plugin.pluginName, plugin.vendorName, toStringArchs(archs));
            cwritefln("   configurations: ".lgreen ~ "%s".yellow
                       ~ ", build type ".lgreen ~ "%s".yellow
                       ~ ", compiler ".lgreen ~ "%s".yellow,
                       configurations, build, compiler);
            if (publish)
                cwritefln("   The binaries will be copied to standard plugin directories.".lgreen);
            if (auval)
                cwritefln("   Then Audio Unit validation with auval will be performed for arch %s.".lgreen, archs[$-1]);
            if (makeInstaller)
            {
                if (targetOS == OS.macOS)
                    cwritefln("   Then a Mac installer will be created for distribution outside of the App Store.".lgreen);
                if (targetOS == OS.windows)
                    cwritefln("   Then a Windows installer will be created for distribution.".lgreen);
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
                // Only build x86_64 AAX on Windows
                if (targetOS == OS.windows && configIsAAX(config) && (arch != Arch.x86_64) && !(legacyPT10 && arch == Arch.x86) )
                {
                    cwritefln("info: Skipping architecture %s for AAX on Windows\n", arch);
                    continue;
                }

                // Only build x86_64 FLP on Windows
                if (targetOS == OS.windows && configIsFLP(config) && (arch != Arch.x86_64))
                {
                    cwritefln("info: Skipping architecture %s for FLP on Windows\n", arch);
                    continue;
                }

                // Does not try to build 32-bit under Mac
                if (targetOS == OS.macOS)
                {
                    if (arch == Arch.x86)
                    {
                       throw new Exception("Can't make 32-bit x86 builds for macOS");
                    }
                }

                // Does not try to build AU under Windows
                if (targetOS == OS.windows)
                {
                    if (configIsAU(config))
                        throw new Exception("Can't build AU format for Windows");
                }

                // Does not try to build FLP except on Windows and Mac
                if (targetOS != OS.windows && targetOS != OS.macOS)
                {
                    if (configIsFLP(config))
                        throw new Exception("Can't build FLP format outside Windows and macOS");
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
                // Also, in some cases the temporary builds don't need signatures.

                bool isTemp = false;
                if (targetOS == OS.macOS)
                {
                    if (oneOfTheArchIsUB)
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

                string path = outputDirectory(outputDir, isTemp, osString, arch, config).normalizedPath;

                mkdirRecurse(path);

                if (arch != Arch.universalBinary)
                {
                    // Apply compiler path overrides, allows to build a plugins with different 
                    // compilers depending on the arch.
                    string compilerPath;
                    bool pathOverriden;
                    if (arch == Arch.x86_64 && (compiler_x86_64 != compiler))
                    {
                        compilerPath = compiler_x86_64;
                        pathOverriden = true;
                    }
                    else
                    {
                        compilerPath = compiler;
                        pathOverriden = false;
                    }

                    buildPlugin(targetOS, compilerPath, pathOverriden, config, build, arch, rootDir, verbose, force, combined, quiet, skipRegistry, parallel, redub);
                    double bytes = getSize(plugin.dubOutputFileName()) / (1024.0 * 1024.0);
                    cwritefln("    =&gt; Build OK, binary size = %0.1f mb, available in %s".lgreen, bytes, normalizedPath("./" ~ path));
                    cwriteln();
                }

                void signAAXBinaryWithPACE(string binaryPathInOut)
                {
                    try
                    {
                        string verboseFlag = verbose ? "--verbose " : "";

                        string identFlag;
                        string dsigFlag = "";
                        if (targetOS == OS.windows)
                        {
                            string identity;

                            // Using certThumbprint-windows takes precedence over .P12 file and passwords
                            if (plugin.certThumbprintWindows !is null)
                            {
                                // sign using certificate in store (supports cloud signing like Certum)
                                // For wraptool, this needs to be the thumbprint.
                                identFlag = format("--signid %s ", escapeShellArgument(plugin.certThumbprintWindows));
                            }
                            else
                            {
                                // sign using keyfile and password in store (supports key file like Sectigo)
                                identFlag = format("--keyfile %s --keypassword %s ", 
                                                   plugin.getKeyFileWindows(), 
                                                   plugin.getKeyPasswordWindows());
                            }
                        }
                        else if (targetOS == OS.macOS)
                        {
                            // Note sure if harmless actually
                            //dsigFlag = "--dsig1-compat false ";
                            identFlag = format("--signid %s ", escapeShellArgument(plugin.getDeveloperIdentityMac()));
                        }
                        else
                            throw new Exception("AAX not supported on that OS");

                        // Note: --allowsigningservice doesn't make any difference (2022) since for just signing cloud doesn't seem to make it... 
                        // Presumably the idea was to favour PACE customers that uses full wrapping.
                        string cmd = format(`wraptool sign %s--account %s --password %s %s--wcguid %s %s--in %s --out %s`,
                                            verboseFlag,
                                            plugin.getILokAccount(),
                                            plugin.getILokPassword(),
                                            identFlag,
                                            plugin.getWrapConfigGUID(),
                                            dsigFlag,
                                            escapeShellArgument(binaryPathInOut),
                                            escapeShellArgument(binaryPathInOut));
                        safeCommand(cmd);
                    }
                    catch(Exception e)
                    {
                        error(e.msg);
                        warning(`AAX signature failed, plugin won't run in Pro Tools and won't notarize.` ~ "\n" ~
                                `         Do NOT distribute such a build.` ~ "\n");
                    }
                }

                void extractAAXPresetsFromBinary(string binaryPath, string contentsDir, Arch targetArch)
                {
                    bool formerlyExtracted = false;
                    if (targetArch != buildArch)
                    {
                         if (tfxPresets is null)
                            throw new Exception("Can't extract presets from AAX plug-in because dplug-build is built with a different arch, and the x86_64 arch wasn't built before. Re-run this build, including the x86_64 arch.\n");
                        formerlyExtracted = true;
                    }
                    else
                    {
                        // Preset extraction itself
                        SharedLib lib;
                        lib.load(plugin.dubOutputFileName());
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
                            TFXPreset[]* presetArray;
                            int presetCount = 0;
                        }

                        Context context = Context(&tfxPresets);

                        static extern(C) void processPreset(const(char)* name,
                                                            const(ubyte)* tfxContent,
                                                            size_t len,
                                                            void* userPointer)
                        {
                            Context* context = cast(Context*)userPointer;
                            const(char)[] presetName = name[0..strlen(name)];

                            TFXPreset preset;
                            preset.filename = (presetName ~ ".tfx").idup;
                            preset.content = tfxContent[0..len].idup;
                            *(context.presetArray) ~= preset;
                            context.presetCount += 1;
                        }

                        enumerateTFX_t ptrDplugEnumerateTFX = cast(enumerateTFX_t) lib.loadSymbol("DplugEnumerateTFX");
                        ptrDplugEnumerateTFX(&processPreset, &context);
                        lib.unload();
                    }

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

                    // Write files stored in tfxPresets
                    foreach(p; tfxPresets)
                    {
                        std.file.write(factoryPresetsLocation ~ "/" ~ p.filename, p.content);
                    }

                    cwritefln("    =&gt; Copied %s AAX factory presets %sfrom binary".lgreen, tfxPresets.length, formerlyExtracted ? "(formerly extracted) " : "");
                    cwriteln();
                }

                // Extract manifest from LV2 Binary
                void extractLV2ManifestFromBinary(string binaryPath, string outputDir, Arch targetArch, string binaryName)
                {
                    bool formerlyExtracted = false;
                    if (targetArch != buildArch)
                    {
                        if (lv2Manifest is null)
                            throw new Exception("Can't extract manifest from LV2 plug-in because dplug-build is built with a different arch, and the x86_64 arch wasn't built before. Re-run this build, including the x86_64 arch.\n");
                        formerlyExtracted = true;
                    }
                    else
                    {
                        cwritefln("*** Extract LV2 manifest from binary...");
                        SharedLib lib;
                        lib.load(binaryPath);
                        if (!lib.hasSymbol("GenerateManifestFromClient"))
                            throw new Exception("Couldn't find the symbol GenerateManifestFromClient in the plug-in");

                        alias generateManifest = extern(C) int function(char* manifestBuf, int manifestBufLen,
                                                                        const(char)* binaryFileName, int binaryFileNameLen);

                        generateManifest ptrGenerateManifest = cast(generateManifest) lib.loadSymbol("GenerateManifestFromClient");

                        // How much bytes do we need for the manifest? 
                        int manifestLen = ptrGenerateManifest(null, 0, binaryName.ptr, cast(int)(binaryName.length));

                        // Generate the manifest again, this time copy it in a properly sized buffer.
                        char[] manifestBuf = new char[manifestLen];
                        manifestLen = ptrGenerateManifest(manifestBuf.ptr, cast(int)(manifestBuf.length),
                                                          binaryName.ptr, cast(int)(binaryName.length));
                        lib.unload();
                        lv2Manifest = manifestBuf[0..manifestLen].idup;
                    }

                    // write manifest
                    string manifestPath = outputDir ~ "/manifest.ttl";
                    std.file.write(manifestPath, lv2Manifest);

                    cwritefln("    =&gt; Written %s bytes to%s manifest.ttl.".lgreen, getSize(manifestPath), formerlyExtracted ? " (formerly extracted)" : "");
                    cwriteln();
                }

                if (targetOS == OS.windows)
                {
                    // size used in installer
                    int sizeInKiloBytes = cast(int) (getSize(plugin.dubOutputFileName()) / (1024.0));

                    // plugin path used in installer
                    string pluginDirectory;

                    // This should avoid too much misdetection by antivirus software.
                    // If people complain about false positives with dlang programs, please
                    // report the false positive to the AV vendor!
                    bool SIGN_WINDOWS_PLUGINS = makeInstaller && plugin.hasKeyFileOrDevIdentityWindows;

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

                        // Note: no need to codesign again, as signtool does it
                    }
                    else if (configIsLV2(config))
                    {
                        // Create both a TTL and the .lv2 directory
                        string pluginFinalName = plugin.getLV2PrettyName() ~ ".dll";
                        pluginDirectory = path ~ "/" ~ plugin.prettyName ~ ".lv2";
                        string pluginFinalPath = pluginDirectory ~ "/" ~ pluginFinalName;
                        mkdirRecurse(pluginDirectory);
                        fileMove(plugin.dubOutputFileName, pluginFinalPath);
                        extractLV2ManifestFromBinary(pluginFinalPath, pluginDirectory, arch, pluginFinalName);

                        if (SIGN_WINDOWS_PLUGINS) 
                            signExecutableWindows(plugin, pluginFinalPath);
                    }
                    else if (configIsFLP(config))
                    {
                        // Needed structure is:
                        //
                        // <Plugin Name>/
                        //           Plugin.nfo                  // brand name
                        //           <Plugin Name>.dll           // x86 executable
                        //           <Plugin Name_x64>.dll       // x86_64 executable
                        //
                        // Else it won't be listed or scanned.
                        //
                        // Then this directory must be installed in:
                        //     $PROGRAMFILES\Image-Line\FL Studio $FLVER\Plugins\Fruity\Effects
                        //  or 
                        //     $PROGRAMFILES\Image-Line\FL Studio $FLVER\Plugins\Fruity\Generators
                        //
                        string pluginFinalName;
                        if (arch == Arch.x86)
                            pluginFinalName = plugin.pluginName ~ ".dll";
                        else if (arch == Arch.x86_64)
                            pluginFinalName = plugin.pluginName ~ "_x64.dll";
                        else
                            throw new Exception("Unsupported architecture for FLP plug-in format");

                        pluginDirectory = path ~ "/" ~ plugin.pluginName;
                        mkdirRecurse(pluginDirectory);

                        string pluginFinalPath = pluginDirectory ~ "/" ~ pluginFinalName;
                        fileMove(plugin.dubOutputFileName, pluginFinalPath);

                        // Create NFO file
                        string NFOPath = pluginDirectory ~ "/Plugin.nfo";
                        string NFOcontent = format("ps_vendorname=%s\n", plugin.vendorName);  // spaces allowed in that .nfo
                        std.file.write(NFOPath, NFOcontent);

                        if (SIGN_WINDOWS_PLUGINS) 
                            signExecutableWindows(plugin, pluginFinalPath);
                    }
                    else if (configIsCLAP(config)) // CLAP special case, needs to be named .clap
                    {
                        pluginDirectory = path ~ "/" ~ plugin.prettyName ~ ".clap";
                        fileMove(plugin.dubOutputFileName, pluginDirectory);
                        if (SIGN_WINDOWS_PLUGINS) 
                            signExecutableWindows(plugin, pluginDirectory);
                    }
                    else if (configIsVST3(config)) // VST3 special case, needs to be named .vst3 (but can't be _linked_ as .vst3)
                    {
                        if (plugin.hasFutureVST3FolderWindows)
                        {
                            // Note: some vendors don't put an icon
                            //       some vendors don't put a binary in binary folders
                            //       some vendors don't put a moduleinfo.json
                            // it's all optional, as it seems.
                            //
                            // In particular moduleinfo.json is optional according to the SDK
                            // and could be created with VST3 SDK (moduleinfotool)

                            pluginDirectory = path ~ "/" ~ plugin.prettyName ~ ".vst3";

                            string binaryFolder    = pluginDirectory ~ "/Contents/" ~  convertArchToVST3WindowsDirectoryName(arch);
                            string resourcesFolder = pluginDirectory ~ "/Contents/Resources";
                            mkdirRecurse(pluginDirectory);
                            mkdirRecurse(resourcesFolder);
                            mkdirRecurse(binaryFolder);

                            // Copy binary
                            string pluginFinalPath = binaryFolder ~ "/" ~ plugin.prettyName ~ ".vst3";
                            fileMove(plugin.dubOutputFileName, pluginFinalPath);
                            if (SIGN_WINDOWS_PLUGINS) 
                                signExecutableWindows(plugin, pluginFinalPath);

                            // FUTURE: icon support
                            //string INIcontent = "[.ShellClassInfo]\nIconResource=Plugin.ico,0";
                            //std.file.write(pluginDirectory ~ "/desktop.ini", INIcontent);                               
                        }
                        else
                        {
                            // Simply copy the file, single file .vst3
                            // which is deprecated normally and on the way out
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

                            pluginDirectory = path ~ "/" ~ appendBitnessVST3(plugin.prettyName, plugin.dubOutputFileName);
                            fileMove(plugin.dubOutputFileName, pluginDirectory);
                            if (SIGN_WINDOWS_PLUGINS) 
                                signExecutableWindows(plugin, pluginDirectory);
                        }                        
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

                        if (SIGN_WINDOWS_PLUGINS) 
                            signExecutableWindows(plugin, pluginDirectory);
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
                            if (arch == arch.x86_64)
                                installDir = WIN_AAX_DIR;
                            else
                                installDir = WIN_AAX_DIR_X86;
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
                        else if (configIsCLAP(config))
                        {
                            format = "CLAP";
                            title = "CLAP plug-in";
                            if (arch == arch.x86_64)
                                installDir = WIN_CLAP_DIR;
                            else
                                installDir = WIN_CLAP_DIR_X86;
                        }
                        else if (configIsFLP(config))
                        {
                            format = "FLP";
                            title = "FLStudio plug-in";
                            installDir = "dummy path"; // detected at runtime
                        }

                        windowsPackages ~= WindowsPackage(format, pluginDirectory, title, installDir, sizeInKiloBytes, arch == arch.x86_64);
                    }
                }
                else if (targetOS == OS.linux)
                {
                    if(configIsLV2(config))
                    {
                        // Create both a TTL and the .lv2 directory
                        string pluginDirectory = path ~ "/" ~ plugin.prettyName ~ ".lv2";
                        string pluginFinalName = plugin.getLV2PrettyName() ~ ".so";
                        string pluginFinalPath = pluginDirectory ~ "/" ~ pluginFinalName;
                        mkdirRecurse(pluginDirectory);
                        fileMove(plugin.dubOutputFileName, pluginFinalPath);
                        extractLV2ManifestFromBinary(pluginFinalPath, pluginDirectory, arch, pluginFinalName);
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
                    else if (configIsCLAP(config))
                    {
                        pluginDir = plugin.prettyName ~ ".clap";
                        installDir = MAC_CLAP_DIR;
                    }
                    else if (configIsFLP(config))
                    {
                        pluginDir = plugin.pluginName;
                        installDir = MAC_FLP_DIR;
                    }
                    else
                        assert(false, "unsupported plugin format");

                    // On Mac, make a bundle directory
                    string bundleDir = path ~ "/" ~ pluginDir;


                    void mergeExecutablesWithLIPO(string path_arm64, string path_x86_64, string pluginFinalPath, string path)
                    {
                        cwritefln("*** Making an universal binary with lipo");

                        string cmd = format("xcrun lipo -create %s %s -output %s",
                                            escapeShellArgument(path_arm64),
                                            escapeShellArgument(path_x86_64),
                                            escapeShellArgument(pluginFinalPath));
                        safeCommand(cmd);
                        double bytes = getSize(pluginFinalPath) / (1024.0 * 1024.0);
                        cwritefln("    =&gt; Universal build OK, binary size = %0.1f mb, available in %s".lgreen, bytes, normalizedPath("./" ~ path));
                        cwriteln();
                    }

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
                        
                        // Note: there is no support for Universal Binary in LV2
                        if (arch == Arch.universalBinary)
                        {     
                            bool TEMP = true;              
                            string path_arm64  = outputDirectory(outputDir, TEMP, osString, Arch.arm64,  config) ~ "/" ~ pluginDir ~ "/" ~ pluginFinalName;
                            string path_x86_64 = outputDirectory(outputDir, TEMP, osString, Arch.x86_64, config) ~ "/" ~ pluginDir ~ "/" ~ pluginFinalName;
                            mergeExecutablesWithLIPO(path_arm64, path_x86_64, pluginFinalPath, path);
                        }
                        else
                        {
                            fileMove(plugin.dubOutputFileName, pluginFinalPath);                            
                        }
                        extractLV2ManifestFromBinary(pluginFinalPath, bundleDir, arch, pluginFinalName);
                    }
                    else if (configIsFLP(config))
                    {
                        // FLP is also special on Mac, it needs this structure:
                        //
                        // <Plugin Name>/
                        //           Plugin.nfo                  // brand name
                        //           <Plugin Name>.dylib         // can be an Universal Binary v2
                        string pluginFinalName = plugin.pluginName ~ "_x64.dylib";
                        string pluginFinalPath = bundleDir ~ "/" ~ pluginFinalName;
                        mkdirRecurse(bundleDir);

                        if (arch == Arch.universalBinary)
                        {
                            bool TEMP = true;
                            string path_arm64  = outputDirectory(outputDir, TEMP, osString, Arch.arm64,  config) ~ "/" ~ pluginDir ~ "/" ~ pluginFinalName;
                            string path_x86_64 = outputDirectory(outputDir, TEMP, osString, Arch.x86_64, config) ~ "/" ~ pluginDir ~ "/" ~ pluginFinalName;
                            mergeExecutablesWithLIPO(path_arm64, path_x86_64, pluginFinalPath, path);
                        }
                        else
                        {
                            fileMove(plugin.dubOutputFileName, pluginFinalPath);
                        }

                        // Create NFO file
                        string NFOPath = bundleDir ~ "/Plugin.nfo";
                        string NFOcontent = format("ps_vendorname=%s\n", plugin.vendorName);  // spaces allowed in that .nfo
                        std.file.write(NFOPath, NFOcontent);
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
                                rsrcPath = makeRSRC_internal(outputDir, plugin, arch, verbose);
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

                            cwritefln("*** Making an universal binary with lipo");

                            string cmd = format("xcrun lipo -create %s %s -output %s",
                                                escapeShellArgument(path_arm64),
                                                escapeShellArgument(path_x86_64),
                                                escapeShellArgument(exePath));
                            safeCommand(cmd);
                            double bytes = getSize(exePath) / (1024.0 * 1024.0);
                            cwritefln("    =&gt; Universal build OK, binary size = %0.1f mb, available in %s".lgreen, bytes, normalizedPath("./" ~ path));
                            cwriteln();
                        }
                        else
                        {
                            fileMove(plugin.dubOutputFileName, exePath);
                        }
                    }

                    // Note: on Mac, the bundle path is passed instead, since wraptool won't accept the executable only
                    if (configIsAAX(config))
                    {
                        if (!isTemp)
                            signAAXBinaryWithPACE(bundleDir);
                    }
                    else
                    {
                        enum SIGN_MAC_BUNDLES = true;
                        if (SIGN_MAC_BUNDLES && !isTemp && makeInstaller)
                        {
                            // eventually sign with codesign
                            cwritefln("*** Signing bundle %s...", bundleDir);
                            if (plugin.developerIdentityOSX !is null)
                            {
                                string command = format(`xcrun codesign --options=runtime --strict -f -s %s --timestamp %s --digest-algorithm=sha1,sha256`,
                                    escapeShellArgument(plugin.developerIdentityOSX), escapeShellArgument(bundleDir));
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
                        cwritefln("*** Publishing to %s...", installDir);

                        string sourceDir = escapeShellArgument(path ~ "/" ~ pluginDir);
                        string destDir = escapeShellArgument(installDir ~ "/");

                        string cmd = format("sudo cp -R %s %s", sourceDir, destDir);
                        safeCommand(cmd);

/*
                        int filesCopied = copyRecurse(path ~ "/" ~ pluginDir, installDir ~ "/" ~ pluginDir, verbose);
                        cwritefln("    =&gt; %s files copied.".green, filesCopied);
                        cwriteln();
*/
                        if (auval)
                        {
                            cwriteln("*** Validation with auval...");

                            bool is32b = (arch == Arch.x86);
                            string exename = is32b ? "auval" : "auvaltool";
                            cmd = format("%s%s -v aufx %s %s -de -dw",
                                exename,
                                is32b ? " -32 ":"",
                                plugin.pluginUniqueID,
                                plugin.vendorUniqueID);
                            safeCommand(cmd);

                            cwriteln("    =&gt; Audio Unit passed validation.".lgreen);
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
                        else if (configIsCLAP(config))
                        {
                            pkgIdentifier = plugin.pkgBundleCLAP();
                            pkgFilename   = plugin.pkgFilenameCLAP();
                            title = "FLStudio plug-in";
                        }
                        else if (configIsFLP(config))
                        {
                            pkgIdentifier = plugin.pkgBundleFLP();
                            pkgFilename   = plugin.pkgFilenameFLP();
                            title = "FLStudio plug-in";
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
                            if (plugin.developerIdentityOSX !is null)
                            {
                                signStr = format(" --sign %s --timestamp", escapeShellArgument(plugin.developerIdentityOSX));
                            }
                            else
                            {
                                warning("Can't sign the installer. Please provide a key \"developerIdentity-osx\" in your plugin.json. Users computers will reject this installer.");
                            }
                        }

                        string quietStr = verbose ? "" : " --quiet";


                        // This was supposed to resolve AAX wraptool upgrade problems, and be cleaner.
                        // instead of using --component, use --root 
                        // In reality, fix for #732 was never reproduced, and this is JUST enabled to
                        // test in the wild with a small sample of people, in case we have to use that later.
                        bool useComponentPlist = false;//(configIsAAX(config));

                        string componentPlistFlag;
                        string bundleFlag;
                        if (useComponentPlist)
                        {
                            string pbXML = outputDir ~ "/temp/pkgbuild-options.plist";
                            string rootPath = path;
                            std.file.write(pbXML, cast(void[]) makePListFileForPKGBuild(pluginDir));
                            componentPlistFlag = " --component-plist " ~ escapeShellArgument(pbXML);
                            bundleFlag = "--root " ~ escapeShellArgument(rootPath);
                        }
                        else
                        {
                            componentPlistFlag = "";
                            bundleFlag = "--component " ~ escapeShellArgument(bundleDir);
                        }

                        // Create individual .pkg installer for each VST, AU, CLAP, or AAX given
                        string cmd = format("xcrun pkgbuild%s%s%s --install-location %s --identifier %s --version %s %s %s",
                            signStr,
                            quietStr,
                            componentPlistFlag,
                            escapeShellArgument(installDir),
                            pkgIdentifier,
                            plugin.publicVersionString,
                            bundleFlag,
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
                iconPathOSX = makeMacIcon(outputDir, plugin.name, plugin.iconPathOSX); // FUTURE: this should be lazy
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

            string licensePathReal = buildPath(rootDir, plugin.licensePath).array.to!string;

            if (extension(licensePathReal) == ".md")
            {
                // Convert license markdown to HTML
                if (!quiet) cwritefln("*** Converting license file to HTML... ");
                string markdown = cast(string)std.file.read(licensePathReal);

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
                if (!quiet) cwritefln(" =&gt; OK\n".lgreen);
            }
            else
                throw new Exception("License file should be a Markdown .md file");
        }

        if ((targetOS == OS.macOS) && makeInstaller)
        {
            cwriteln("*** Generating final Mac installer...");
            string finalPkgPath = outputDir ~ "/" ~ plugin.finalPkgFilename(configurations[0]);
            generateMacInstaller(rootDir, outputDir, resDir, plugin, macInstallerPackages, finalPkgPath, verbose, archs);
            cwriteln("    =&gt; OK".lgreen);
            cwriteln;

            if (notarize)
            {
                // Note: this doesn't have to match anything, it's just there in emails
                string primaryBundle = plugin.getNotarizationBundleIdentifier(configurations[0]);

                cwritefln("*** Notarizing final Mac installer %s...", primaryBundle);
                notarizeMacInstaller(outputDir, plugin, finalPkgPath, primaryBundle, verbose);
                cwriteln("    =&gt; Notarization OK".lgreen);
                cwriteln;
            }
        }

        if ((targetOS == OS.windows) && makeInstaller)
        {
            cwriteln("*** Generating Windows installer...");
            string windowsInstallerPath = outputDir ~ "/" ~ plugin.windowsInstallerName(configurations[0]);
            generateWindowsInstaller(outputDir, plugin, windowsPackages, windowsInstallerPath, verbose);
            cwriteln;
        }

        return 0;
    }
    catch(DplugBuildBuiltCorrectlyException e)
    {
        cwriteln;
        cwriteln("    Congratulations! 🎉 ".lgreen ~ "dplug-build".lcyan ~ " built successfully.".lgreen);
        cwriteln("    Type " ~ "dplug-build --help".lcyan ~ " to know about its usage.");
        cwriteln("    You'll probably want " ~ "dplug-build".lcyan ~ " to be in your" ~ " PATH".yellow ~ "✨");
        cwriteln;
        return 0;
    }
    catch(ExternalProgramErrored e)
    {
        error(escapeCCL(e.msg));
        return e.errorCode;
    }
    catch(CCLException e) // An exception with a coloured message
    {
        cwritefln("\n<lred>Error:</lred> %s", e.msg);
        return -1;
    }
    catch(Exception e) // An uncoloured exception.
    {
        cwritefln("\n<lred>Error:</lred> %s", escapeCCL(e.msg));
        return -1;
    }
}

void buildPlugin(OS targetOS, 
                 string compiler, bool pathOverriden, string config, string build, Arch arch, 
                 string rootDir,
                 bool verbose, bool force, bool combined, bool quiet, 
                 bool skipRegistry, bool parallel,  bool useRedub)
{
    cwritefln("*** Building configuration %s with %s%s, %s arch...", 
              config, 
              compiler, 
              pathOverriden ? " (overriden path)" : "",
              convertArchToPrettyString(arch));

    // If we want to support Notarization, we can't target earlier than 10.11
    // Note: it seems it is overriden at some point and when notarizing you can't target lower
    // If you want Universal Binary 2, can't target earlier than 10.12
    // So nowadays we set it to 10.12.
    version(OSX)
    {
        environment["MACOSX_DEPLOYMENT_TARGET"] = "10.12";
    }

    if (targetOS == OS.windows && compilerIsLDC(compiler))
    {
        // Dplug issue #726
        // See upstream issue: https://github.com/dlang/dub/issues/2568
        // When using the newer LDC and DUB, we need to ensure static linking on Windows.
        // And the ONLY way is now using DFLAGS.
        // This requires LDC 1.28+, but Dplug already required that.
        if (!quiet) info("ldc compiler detected, using a modified DFLAGS for proper Windows druntime static linking");
        environment["DFLAGS"] = "-fvisibility=hidden -dllimport=none";
    }

    string dubBinary = useRedub ? "redub" : "dub";

    string cmd = format("%s build --build=%s %s--compiler=%s%s%s%s%s%s%s%s%s",
        dubBinary,
        build, 
        convertArchToDUBFlag(arch, targetOS),
        compiler,
        force ? " --force" : "",
        verbose ? " -v" : "",
        quiet ? " -q" : "",
        combined ? " --combined" : "",
        config ? " --config=" ~ config : "",
        skipRegistry ? " --skip-registry=all" : "",
        parallel ? " --parallel" : "",
        rootDir != "." ? " --root=" ~ escapeShellArgument(rootDir) : ""
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

void generateMacInstaller(string rootDir,
                          string outputDir,
                          string resDir,
                          Plugin plugin,
                          MacPackage[] packs,
                          string outPkgPath,
                          bool verbose,
                          Arch[] archs)
{
    string distribPath = "mac-distribution.txt";

    string content = "";

    content ~= `<?xml version="1.0" encoding="utf-8"?>` ~ "\n";
    content ~= `<installer-gui-script minSpecVersion="1">` ~ "\n";

    content ~= format(`<title>%s</title>` ~ "\n", plugin.prettyName ~ " v" ~ plugin.publicVersionString);

    if (plugin.installerPNGPath)
    {
        string backgroundPath = resDir ~ "/background.png";
        string sourceBackground = buildPath(rootDir, plugin.installerPNGPath).array.to!string;
        std.file.copy(sourceBackground, backgroundPath);
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

    string getHostArchitecturesList()
    {
        string r = "";
        int archCount = 0;

        foreach(arch; archs)
        {
            if (isSingleArchEnum(arch))
            {
                if (archCount > 0) r ~= ",";
                r ~= convertArchToPrettyString(arch);
                archCount++;
            }
        }
        return r;
    }
    
    // Note: the installer itself must support the same architectures than generated.
    content ~= format(`<options customize="always" hostArchitectures="%s" require-scripts="false"/>` ~ "\n", 
                      getHostArchitecturesList());

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
    if (plugin.developerIdentityOSX !is null)
    {
        signStr = format(" --sign %s --timestamp", escapeShellArgument(plugin.developerIdentityOSX));
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
    string cmd = format("xcrun productbuild%s%s --resources %s --distribution %s%s %s",
                        signStr,
                        quietStr,
                        escapeShellArgument(resDir),
                        escapeShellArgument(distribPath),
                        packagePaths,
                        escapeShellArgument(outPkgPath));
    safeCommand(cmd);
}

void notarizeMacInstaller(string outputDir, Plugin plugin, string outPkgPath, string primaryBundleId, bool verbose)
{
    string verboseFlag = verbose ? "--verbose " : "";

    // Used with notarytool.
    string notaJSONPath = outputDir ~ "/temp/notarization-status.json";

    // Used in legacy notarization mode.
    string uploadXMLPath = outputDir ~ "/temp/notarization-upload.xml";    
    string pollXMLPath = outputDir ~ "/temp/notarization-poll.xml";

    string authString;

    if (plugin.appSpecificPassword_stapler)
        warning(`"appSpecificPassword-stapler" is not needed anymore. You can safely remove it.`);

    // keychainProfile overrides vendor Apple ID, app-specific passwords, and 
    if (plugin.keychainProfile is null)
    {
        if (plugin.vendorAppleID is null)
            throw new Exception(`Missing "vendorAppleID" in plugin.json. Notarization need this key, or "keychainProfile-osx".`);

        if (plugin.appSpecificPassword_altool is null)
            throw new Exception(`Missing "appSpecificPassword-altool" in plugin.json. Notarization need this key.`);

        authString = format("--team-id %s --apple-id %s --password %s",  plugin.getDeveloperIdentityMac(), plugin.vendorAppleID, plugin.appSpecificPassword_altool);
    }
    else
    {
        authString = format("--keychain-profile %s",  escapeShellArgument(plugin.keychainProfile));
    }

    bool notarizationSucceeded = false;
    bool notarizationFailed = false;
    string LogFileURL = "unknown location";

   
    {
        // New notarytool use, former method was discontinued on 1st Nov 2023.
        // Check we have all variable


        {
            string cmd = format(`xcrun notarytool submit %s--wait --no-progress %s %s -f json > %s`,
                                verboseFlag,
                                authString,
                                //uploadXMLPath,
                                escapeShellArgument(outPkgPath),
                                escapeShellArgument(notaJSONPath)
                                );
            safeCommand(cmd);
        }

        // Did notarization succeeded?
        JSONValue notaStatus = parseJSON(cast(string)(std.file.read(notaJSONPath)));      
        string status = notaStatus["status"].str;
        string notaID = notaStatus["id"].str;
        cwritefln(`Status: <lcyan>"%s"</lcyan>`, escapeCCL(notaStatus["status"].str));
        cwritefln(`Message: <lcyan>"%s"</lcyan>`, escapeCCL(notaStatus["message"].str));
        cwritefln(`id: <lcyan>%s</lcyan>`, escapeCCL(notaStatus["id"].str));

        notarizationFailed = (status != "Accepted");
        notarizationSucceeded = !notarizationFailed;

        if (notarizationFailed)
        {
            cwritefln("    =&gt; Notarization failed, asking notarytool again for why".lred);
            cwriteln();

            {
                string cmd = format(`xcrun notarytool log %s %s`, notaID, authString);
                safeCommand(cmd);
            }
            throw new Exception("Failed notarization");
        }
    }


    {
        safeCommand( format(`xcrun stapler staple %s`, escapeShellArgument(outPkgPath) ) );
    }
}
