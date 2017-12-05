import core.stdc.string;

import std.file;
import std.stdio;
import std.conv;
import std.uuid;
import std.process;
import std.string;
import std.path;

import dplug.core.sharedlib;

import colorize;
import utils;
import plugin;

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
    flag("-c --config", "Adds a build configuration.", "VST | AU | AAX | name starting with \"VST\", \"AU\" or \"AAX\"", "all");
    flag("-f --force", "Forces rebuild", null, "no");
    flag("--combined", "Combined build", null, "no");
    flag("-q --quiet", "Quieter output", null, "no");
    flag("-v --verbose", "Verbose output", null, "no");
    flag("-sr --skip-registry", " Skip checking the DUB registry\n                        Avoid network, doesn't update dependencies", null, "no");
    flag("--publish", "Make the plugin available in standard directories " ~ "(OSX only, DOESN'T WORK)".red, null, "no");
    flag("--auval", "Check Audio Unit validation with auval " ~ "(OSX only, DOESN'T WORK)".red, null, "no");
    flag("-h --help", "Shows this help", null, null);


    cwriteln();
    cwriteln("EXAMPLES".white);
    cwriteln();
    cwriteln("        # Releases a final VST plugin for 32-bit and 64-bit".green);
    cwriteln("        release --compiler ldc -a all -b release-nobounds --combined".cyan);
    cwriteln();
    cwriteln("        # Builds a 32-bit Audio Unit plugin for profiling".green);
    cwriteln("        release --compiler dmd -a x86 --config AU -b release-debug".cyan);
    cwriteln();
    cwriteln("        # Shows help".green);
    cwriteln("        release -h".cyan);

    cwriteln();
    cwriteln("NOTES".white);
    cwriteln();
    cwriteln("      The configuration name used with " ~ "--config".cyan ~ " must exist in your " ~ "dub.json".cyan ~ " file.");
    cwriteln("      release".cyan ~ " detects plugin format based on the " ~ "configuration".yellow ~ " name's prefix: " ~ "AU | VST | AAX.".yellow);
    cwriteln();
    cwriteln("      --combined".cyan ~ " has no effect on code speed, but can avoid DUB flags problems.".grey);
    cwriteln();
    cwriteln("      release".cyan ~ " expects a " ~ "plugin.json".cyan ~ " file for proper bundling and will provide help".grey);
    cwriteln("      for populating it. For other informations it reads the " ~ "dub.json".cyan ~ " file.".grey);
    cwriteln();
    cwriteln();
}

int main(string[] args)
{
    try
    {
        Compiler compiler = Compiler.ldc; // use LDC by default

        Arch[] archs = allArchitectureqForThisPlatform();
        version (OSX)
            archs = [ Arch.x86_64 ];

        string build="debug";
        string[] configurations = [];
        bool verbose = false;
        bool quiet = false;
        bool force = false;
        bool combined = false;
        bool help = false;
        bool publish = false;
        bool auval = false;
        bool skipRegistry = false;
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
            else if (arg == "-q" || arg == "--quiet")
                quiet = true;
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
                configurations ~= args[i];
            }
            else if (arg == "-sr" || arg == "--skip-registry")
            {
                skipRegistry = true;
            }
            else if (arg == "--combined")
                combined = true;
            else if (arg == "-a" || arg == "--arch")
            {
                ++i;
                if (args[i] == "x32" || args[i] == "x64" || args[i] == "x86-64")
                    throw new Exception("This arch switch value has been deprecated (available: x86, x86_64, all)");

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
                throw new Exception(format("Unrecognized argument '%s'. Type \"release -h\" for help.", arg));
        }

        if (quiet && verbose)
            throw new Exception("Can't have both --quiet and --verbose flags.");

        if (help)
        {
            usage();
            return 0;
        }

        cwriteln("*** Reading dub.json and plugin.json...".white);

        Plugin plugin = readPluginDescription();

        // If no configurations provided, take all
        if (configurations == [])
            configurations = plugin.getAllConfigurations();

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

        cwriteln();

        if (!quiet)
        {
            string dot = ".".green;
            cwritefln("=> The task is to bundle plugin ".green ~ "%s".yellow ~ " from ".green ~ "%s".yellow ~ dot, plugin.pluginName, plugin.vendorName);
            cwritefln("   This plugin will be working in ".green ~ "%s".yellow~dot, toStringArchs(archs));
            cwritefln("   The choosen configurations are ".green ~ "%s".yellow~dot, configurations);
            cwritefln("   The choosen build type is ".green ~ "%s".yellow ~ dot, build);
            if (publish)
                cwritefln("   The binaries will be copied to standard plugin directories.".green);
            if (auval)
                cwritefln("   Then Audio Unit validation with auval will be performed for arch %s.".green, archs[$-1]);
            cwriteln();
        }

        void buildAndPackage(string compiler, string config, Arch[] architectures, string iconPath)
        {
            foreach (int archCount, arch; architectures)
            {
                bool is64b = arch == Arch.x86_64;
                version(Windows)
                {
                    // FUTURE: remove when LDC on Windows is a single archive (should happen for 1.0.0)
                    // then fiddling with PATH will be useless
                    if (compiler == "ldc" && !is64b)
                        environment["PATH"] = `c:\d\ldc-32b\bin` ~ ";" ~ oldpath;
                    if (compiler == "ldc" && is64b)
                        environment["PATH"] = `c:\d\ldc-64b\bin` ~ ";" ~ oldpath;
                }

                string path = outputDirectory(dirName, osString, arch, config);

                mkdirRecurse(path);

                if (arch != Arch.universalBinary)
                {
                    buildPlugin(compiler, config, build, is64b, verbose, force, combined, quiet, skipRegistry);

                    double bytes = getSize(plugin.dubOutputFileName) / (1024.0 * 1024.0);
                    cwritefln("    => Build OK, binary size = %0.1f mb, available in %s".green, bytes, path);
                    cwriteln();
                }

                void extractAAXPresetsFromBinary(string binaryPath, string pluginDir)
                {
                    // Extract presets from the AAX plugin binary by executing it.
                    // Because of this release itself must be 64-bit.
                    // To avoid this coupling, presets should be stored outside of the binary in the future.
                    if ((void*).sizeof == 4)
                        throw new Exception("Can't extract presets from AAX plug-in when release is built as a 32-bit program. Please rebuild release with `dub -a x86_64`.");
                    else
                    {
                        // We need to have a sub-directory of vendorName else the presets aren't found.
                        // Then we need one level deeper else the presets aren't organized in sub-directories.
                        //
                        // "AAX plug-ins should include a set of presets in the following directory within the .aaxplugin:
                        //       MyPlugIn.aaxplugin/Contents/Factory Presets/MyPlugInPackage/
                        //  Where MyPlugInPackage is the plug-in's longest Package Name with 16 characters or fewer."
                        string packageName = plugin.vendorName;
                        if (packageName.length > 16)
                            packageName = packageName[0..16];
                        string factoryPresetsLocation = pluginDir ~ "Factory Presets/" ~ packageName ~ "/Factory Presets";

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

                version(Windows)
                {
                    // Special case for AAX need its own directory, but according to Voxengo releases,
                    // its more minimal than either JUCE or IPlug builds.
                    // Only one file (.dll even) seems to be needed in <plugin-name>.aaxplugin\Contents\x64
                    // Note: only 64-bit AAX supported.
                    if (configIsAAX(config))
                    {
                        string pluginFinalName = plugin.prettyName ~ ".aaxplugin";
                        string pluginDir = path ~ "/" ~ (plugin.prettyName ~ ".aaxplugin") ~ "/Contents/";

                        extractAAXPresetsFromBinary(plugin.dubOutputFileName, pluginDir);

                        if (is64b)
                        {
                            mkdirRecurse(pluginDir ~ "x64");
                            fileMove(plugin.dubOutputFileName, pluginDir ~ "x64/" ~ pluginFinalName);
                        }
                        else
                        {
                            mkdirRecurse(pluginDir ~ "Win32");
                            fileMove(plugin.dubOutputFileName, pluginDir ~ "Win32/" ~ pluginFinalName);
                        }
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

                        // On Windows, simply copy the file
                        fileMove(plugin.dubOutputFileName, path ~ "/" ~ appendBitness(plugin.prettyName, plugin.dubOutputFileName));
                    }
                }
                else version(OSX)
                {
                    // Only accepts two configurations: VST and AudioUnit
                    string pluginDir;
                    if (configIsVST(config))
                        pluginDir = plugin.prettyName ~ ".vst";
                    else if (configIsAU(config))
                        pluginDir = plugin.prettyName ~ ".component";
                    else if (configIsAAX(config))
                        pluginDir = plugin.prettyName ~ ".aaxplugin";
                    else
                        assert(false);

                    if (configIsAAX(config))
                        extractAAXPresetsFromBinary(plugin.dubOutputFileName, pluginDir);

                    // On Mac, make a bundle directory
                    string contentsDir = path ~ "/" ~ pluginDir ~ "/Contents";
                    string ressourcesDir = contentsDir ~ "/Resources";
                    string macosDir = contentsDir ~ "/MacOS";
                    mkdirRecurse(ressourcesDir);
                    mkdirRecurse(macosDir);

                    cwriteln("*** Generating Info.plist...".white);
                    string plist = makePListFile(plugin, config, iconPath != null);
                    cwritefln("    => Generated %s bytes.".green, plist.length);
                    cwriteln();
                    std.file.write(contentsDir ~ "/Info.plist", cast(void[])plist);

                    void[] pkgInfo = cast(void[]) plugin.makePkgInfo(config);
                    std.file.write(contentsDir ~ "/PkgInfo", pkgInfo);

                    string exePath = macosDir ~ "/" ~ plugin.prettyName;

                    // Create a .rsrc for this set of architecture when building an AU
                    version(OSX)
                    {
                        // Make a rsrc file and copy it (if needed)
                        if (configIsAU(config))
                        {
                            string rsrcPath = makeRSRC(plugin, arch, verbose);
                            std.file.copy(rsrcPath, contentsDir ~ "/Resources/" ~ baseName(exePath) ~ ".rsrc");
                        }
                    }

                    if (iconPath)
                        std.file.copy(iconPath, contentsDir ~ "/Resources/icon.icns");

                    if (arch == Arch.universalBinary)
                    {
                        string path32 = outputDirectory(dirName, osString, Arch.x86, config)
                        ~ "/" ~ pluginDir ~ "/Contents/MacOS/" ~ plugin.prettyName;

                        string path64 = outputDirectory(dirName, osString, Arch.x86_64, config)
                        ~ "/" ~ pluginDir ~ "/Contents/MacOS/" ~ plugin.prettyName;

                        cwritefln("*** Making an universal binary with lipo".white);

                        string cmd = format("lipo -create %s %s -output %s",
                                            escapeShellArgument(path32),
                                            escapeShellArgument(path64),
                                            escapeShellArgument(exePath));
                        safeCommand(cmd);
                        cwritefln("    => Universal build OK, available in %s".green, path);
                        cwriteln();
                    }
                    else
                    {
                        fileMove(plugin.dubOutputFileName, exePath);
                    }

                    // Should this arch be published? Only if the --publish arg was given and
                    // it's the last architecture in the list (to avoid overwrite)
                    if (publish && (archCount + 1 == architectures.length))
                    {
                        string destPath;
                        if (configIsVST(config))
                            destPath = "/Library/Audio/Plug-Ins/VST"; // This need elevated privileges
                        else if (configIsAU(config))
                            destPath = "/Library/Audio/Plug-Ins/Components"; // This need elevated privileges
                        else
                            assert(false);
                        cwritefln("*** Publishing to %s...".white, destPath);
                        int filesCopied = copyRecurse(path ~ "/" ~ pluginDir, destPath ~ "/" ~ pluginDir, verbose);
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
                }
            }
        }

        mkdirRecurse(dirName);

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
        if (plugin.licensePath)
            std.file.copy(plugin.licensePath, dirName ~ "/" ~ baseName(plugin.licensePath));

        // Copy user manual (if any provided in plugin.json)
        if (plugin.userManualPath)
            std.file.copy(plugin.userManualPath, dirName ~ "/" ~ baseName(plugin.userManualPath));

        // Build various configuration
        foreach(config; configurations)
            buildAndPackage(toString(compiler), config, archs, iconPath);
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
    if (compiler == "ldc")
        compiler = "ldc2";

    version(linux)
    {
        combined = true; // for -FPIC
    }

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


