module plugin;

import std.algorithm : any;
import std.ascii : isUpper;
import std.conv;
import std.process;
import std.string;
import std.file;
import std.regex;
import std.json;
import std.path;
import std.stdio;
import std.datetime;
import std.range;

import consolecolors;

import utils;
import rsrc;

import arch;
import dplug.client.daw;

import sdlang;

enum Compiler
{
    ldc,
    gdc,
    dmd,
}

static if (__VERSION__ >= 2087)
{
    alias jsonTrue = JSONType.true_;
    alias jsonFalse = JSONType.false_;
}
else
{
    alias jsonTrue = JSON_TYPE.TRUE;
    alias jsonFalse = JSON_TYPE.FALSE;
}

string toString(Compiler compiler)
{
    final switch(compiler) with (Compiler)
    {
        case dmd: return "dmd";
        case gdc: return "gdc";
        case ldc: return "ldc";
    }
}

string toStringUpper(Compiler compiler)
{
    final switch(compiler) with (Compiler)
    {
        case dmd: return "DMD";
        case gdc: return "GDC";
        case ldc: return "LDC";
    }
}

string toStringArchs(Arch[] archs)
{
    string r = "";
    foreach(size_t i, arch; archs)
    {
        final switch(arch) with (Arch)
        {
            case x86:
                if (i) r ~= " and ";
                r ~= "x86";
                break;
            case x86_64:
                if (i) r ~= " and ";
                r ~= "x86_64";
                break;
            case arm32:
                if (i) r ~= " and ";
                r ~= "arm32";
                break;
            case arm64:
                if (i) r ~= " and ";
                r ~= "arm64";
                break;
            case universalBinary:
                if (i) r ~= " and ";
                r ~= "Universal Binary";
                break;
            case all:
                assert(false);
        }
    }
    return r;
}

// from a valid configuration name, extracts the rest of the name.
// Typically configuration would be like: "VST-FULL" => "FULL" or "AAX-FREE" => "FREE".
// Used for installer file name.
string stripConfig(string config) pure nothrow @nogc
{
    if (config.length >= 5 && config[0..5] == "VST3-")
        return config[5..$];
    if (config.length >= 5 && config[0..5] == "VST2-")
        return config[5..$];
    if (config.length >= 3 && config[0..3] == "AU-")
        return config[3..$];
    if (config.length >= 4 && config[0..4] == "AAX-")
        return config[4..$];
    if (config.length >= 4 && config[0..4] == "LV2-")
        return config[4..$];
    if (config.length >= 4 && config[0..4] == "FLP-")
        return config[4..$];
    if (config.length >= 5 && config[0..5] == "CLAP-")
        return config[5..$];
    return null;
}

bool configIsVST3(string config) pure nothrow @nogc
{
    return config.length >= 4 && config[0..4] == "VST3";
}

bool configIsVST2(string config) pure nothrow @nogc
{
    return config.length >= 4 && config[0..4] == "VST2";
}

bool configIsAU(string config) pure nothrow @nogc
{
    return config.length >= 2 && config[0..2] == "AU";
}

bool configIsAAX(string config) pure nothrow @nogc
{
    return config.length >= 3 && config[0..3] == "AAX";
}

bool configIsLV2(string config) pure nothrow @nogc
{
    return config.length >= 3 && config[0..3] == "LV2";
}

bool configIsFLP(string config) pure nothrow @nogc
{
    return config.length >= 3 && config[0..3] == "FLP";
}

bool configIsCLAP(string config) pure nothrow @nogc
{
    return config.length >= 4 && config[0..4] == "CLAP";
}


struct Plugin
{
    string rootDir;               // relative or absolute path to dub.json directory (is is given by --root)
    string name;                  // name, extracted from dub.json or dub.sdl (eg: 'distort')
    string CFBundleIdentifierPrefix;
    string licensePath;           // can be null
    string iconPathWindows;       // can be null or a path to a .ico
    string iconPathOSX;           // can be null or a path to a (large) .png
    bool hasGUI;
    string dubTargetPath;         // extracted from dub.json, used to build the dub output file path

    string pluginName;            // Prettier name, extracted from plugin.json (eg: 'Distorter', 'Graillon 2')
    string pluginUniqueID;
    string pluginHomepage;
    string vendorName;
    string vendorUniqueID;
    string vendorSupportEmail;

    string[] configurations;      // Available configurations, taken from dub.json

    // Public version of the plugin
    // Each release of a plugin should upgrade the version somehow
    int publicVersionMajor;
    int publicVersionMinor;
    int publicVersionPatch;

    // The certificate identity to be used for Mac code signing
    string developerIdentityOSX = null;

    // The certificate identity to be used for Windows code signing
    string developerIdentityWindows = null;

    // Same but for wraptool, which needs the certificate "thumbprint".
    string certThumbprintWindows = null;

    // The timestamp URL used on Windows code signing.
    string timestampServerURLWindows = null;

    // relative path to a .png for the Mac installer
    string installerPNGPath;

    // relative path to .bmp image for Windows installer header
    string windowsInstallerHeaderBmp;

    // Windows-only, points to a .p12/.pfx certificate...
    // Is needed to codesign anything.
    private string keyFileWindows;

    // ...and the password of its private key
    // Support "!PROMPT" as special value.
    private string keyPasswordWindows;

    // <Used for Apple notarization>
    string vendorAppleID;
    string appSpecificPassword_altool;
    string appSpecificPassword_stapler;
    string keychainProfile;
    // </Used for Apple notarization>

    bool receivesMIDI;
    bool sendsMIDI;
    bool isSynth;

    bool hasFutureVST3FolderWindows;

    PluginCategory category;

    string prettyName() pure const nothrow
    {
        return vendorName ~ " " ~ pluginName;
    }

    string publicVersionString() pure const nothrow
    {
        return to!string(publicVersionMajor) ~ "." ~ to!string(publicVersionMinor) ~ "." ~ to!string(publicVersionPatch);
    }

    // AU version integer
    int publicVersionInt() pure const nothrow
    {
        return (publicVersionMajor << 16) | (publicVersionMinor << 8) | publicVersionPatch;
    }

    string makePkgInfo(string config) pure const nothrow
    {
        if (configIsAAX(config))
            return "TDMwPTul"; // this should actually have no effect on whether or not the AAX plug-ins load
        else
            return "BNDL" ~ vendorUniqueID;
    }

    string copyright() const  // Copyright information, copied in the OSX bundle
    {
        SysTime time = Clock.currTime(UTC());
        return format("Copyright %s, %s", vendorName, time.year);
    }

    // Allows anything permitted in a filename
    static string sanitizeFilenameString(string s) pure
    {
        string r = "";
        foreach(dchar ch; s)
        {
            if (ch >= 'A' && ch <= 'Z')
                r ~= ch;
            else if (ch >= 'a' && ch <= 'z')
                r ~= ch;
            else if (ch >= '0' && ch <= '9')
                r ~= ch;
            else if (ch == '.')
                r ~= ch;
            else
                r ~= "-";
        }
        return r;
    }

    // Make a proper bundle identifier from a string
    static string sanitizeBundleString(string s) pure
    {
        string r = "";
        foreach(dchar ch; s)
        {
            if (ch >= 'A' && ch <= 'Z')
                r ~= ch;
            else if (ch >= 'a' && ch <= 'z')
                r ~= ch;
            else if (ch == '.')
                r ~= ch;
            else
                r ~= "-";
        }
        return r;
    }

    // The file name DUB outputs.
    // The real filename is found lazily, since DUB may change its method of naming over time,
    // but we don't want to rely on `dub describe` which has untractable problem with:
    // `dub describe` being slow on bad network conditions, and `dub describe --skip-registry=all` possibly not terminating
    // Uses an heuristic for DUB naming, which might get wrong eventually.
    string dubOutputFileName()
    {
        if (dubOutputFileNameCached !is null)
            return dubOutputFileNameCached;

        // We assume a build has been made, now find the name of the output file

        string[] getPotentialPathes()
        {
            string[] possiblePathes;
            version(Windows)
                possiblePathes ~=  [name  ~ ".dll"];
            else version(OSX)
            {
                // support multiple DUB versions, this name changed to .dylib in Aug 2018
                // newer names goes first to avoid clashes
                possiblePathes ~= ["lib" ~ name ~ ".dylib", "lib" ~ name ~ ".so"];
            }
            else version(linux)
                 possiblePathes ~= ["lib" ~ name ~ ".so"];
            else
                static assert(false, "unsupported OS");

            if (dubTargetPath !is null)
            {
                foreach(ref path; possiblePathes)
                {
                    path = std.path.buildPath(dubTargetPath, path);
                }
            }
            else if (rootDir != ".")
            {
                foreach(ref path; possiblePathes)
                {
                    path = std.path.buildPath(rootDir, path).array.to!string;
                }
            }

            return possiblePathes;
        }

        auto possiblePaths = getPotentialPathes();

        // Find the possible path for which the file exists
        foreach(path; possiblePaths)
        {
            if (std.file.exists(path))
            {
                dubOutputFileNameCached = path;
                return path;
            }
        }
        throw new Exception(
            format!"Didn't find a plug-in file in %s . See dplug-build source to check the heuristic for DUB naming in `dubOutputFileName()`."(
                possiblePaths));
    }
    string dubOutputFileNameCached = null;

    // Gets a config to extract the name of the configuration beyond the prefix
    string getNotarizationBundleIdentifier(string config) pure const
    {
        string verName = stripConfig(config);
        if (verName)
            verName = "-" ~ verName;
        else
            verName = "";
        return format("%s.%s%s-%s.pkg",
                      CFBundleIdentifierPrefix,
                      sanitizeBundleString(pluginName),
                      verName,
                      publicVersionString);
    }

    string getVST3BundleIdentifier() pure const
    {
        return CFBundleIdentifierPrefix ~ ".vst3." ~ sanitizeBundleString(pluginName);
    }

    string getVSTBundleIdentifier() pure const
    {
        return CFBundleIdentifierPrefix ~ ".vst." ~ sanitizeBundleString(pluginName);
    }

    string getAUBundleIdentifier() pure const
    {
        return CFBundleIdentifierPrefix ~ ".audiounit." ~ sanitizeBundleString(pluginName);
    }

    string getAAXBundleIdentifier() pure const
    {
        return CFBundleIdentifierPrefix ~ ".aax." ~ sanitizeBundleString(pluginName);
    }

    string getLV2BundleIdentifier() pure const
    {
        return CFBundleIdentifierPrefix ~ ".lv2." ~ sanitizeBundleString(pluginName);
    }

    string getFLPBundleIdentifier() pure const
    {
        return CFBundleIdentifierPrefix ~ ".flp." ~ sanitizeBundleString(pluginName);
    }

    // <Apple specific>

    // filename of the final installer
    // give a config to extract a configuration name in case of multiple configurations
    string finalPkgFilename(string config) pure const
    {
        string verName = stripConfig(config);
        if (verName)
            verName = "-" ~ verName;
        else
            verName = "";
        return format("%s%s-%s.pkg", sanitizeFilenameString(pluginName),
                                     verName,
                                     publicVersionString);
    }

    string pkgFilenameVST3() pure const
    {
        return sanitizeFilenameString(pluginName) ~ "-vst3.pkg";
    }

    string pkgFilenameVST2() pure const
    {
        return sanitizeFilenameString(pluginName) ~ "-vst.pkg";
    }

    string pkgFilenameAU() pure const
    {
        return sanitizeFilenameString(pluginName) ~ "-au.pkg";
    }

    string pkgFilenameAAX() pure const
    {
        return sanitizeFilenameString(pluginName) ~ "-aax.pkg";
    }

    string pkgFilenameLV2() pure const
    {
        return sanitizeFilenameString(pluginName) ~ "-lv2.pkg";
    }

    string pkgFilenameFLP() pure const
    {
        return sanitizeFilenameString(pluginName) ~ "-fl.pkg";
    }

    string pkgBundleVST3() pure const
    {
        return CFBundleIdentifierPrefix ~ "." ~ sanitizeBundleString(pkgFilenameVST3());
    }

    string pkgBundleVST2() pure const
    {
        return CFBundleIdentifierPrefix ~ "." ~ sanitizeBundleString(pkgFilenameVST2());
    }

    string pkgBundleAU() pure const
    {
        return CFBundleIdentifierPrefix ~ "." ~ sanitizeBundleString(pkgFilenameAU());
    }

    string pkgBundleAAX() pure const
    {
        return CFBundleIdentifierPrefix ~ "." ~ sanitizeBundleString(pkgFilenameAAX());
    }

    string pkgBundleLV2() pure const
    {
        return CFBundleIdentifierPrefix ~ "." ~ sanitizeBundleString(pkgFilenameLV2());
    }

    string pkgBundleFLP() pure const
    {
        return CFBundleIdentifierPrefix ~ "." ~ sanitizeBundleString(pkgFilenameFLP());
    }

    string getAppleID()
    {
        if (vendorAppleID is null)
            throw new Exception(`Missing "vendorAppleID" in plugin.json. Notarization need this key.`);
        return vendorAppleID;
    }

    string getDeveloperIdentityMac()
    {
        if (developerIdentityOSX is null)
            throw new Exception(`Missing "developerIdentity-osx" in plugin.json`);
        return developerIdentityOSX;
    }

    // </Apple specific>

    // <Windows specific>

    string windowsInstallerName(string config) pure const
    {
        string verName = stripConfig(config);
        if(verName)
            verName = "-" ~ verName;
        else
            verName = "";
        return format("%s%s-%s.exe", sanitizeFilenameString(pluginName), verName, publicVersionString);
    }

    bool hasKeyFileOrDevIdentityWindows()
    {
        return (keyFileWindows !is null) || (developerIdentityWindows !is null);
    }

    string getKeyFileWindows()
    {
        if (keyFileWindows is null)
            throw new Exception(`Missing "keyFile-windows" or "developerIdentity-windows" ("certThumbprint-windows" for AAX) in plugin.json`);

        return buildPath(rootDir, keyFileWindows).array.to!string;
    }

    string getKeyPasswordWindows()
    {
        promptWindowsKeyFilePasswordLazily();
        if (keyPasswordWindows is null)
            throw new Exception(`Missing "keyPassword-windows" or "developerIdentity-windows"("certThumbprint-windows" for AAX) in plugin.json (Recommended value: "!PROMPT" or "$ENVVAR")`);
        return expandDplugVariables(keyPasswordWindows);
    }

    // </Windows specific>


    // <PACE Ilok specific>

    /// The iLok account of the AAX developer    
    private string iLokAccount;    

    /// The iLok password of the AAX developer (special value "!PROMPT")
    private string iLokPassword;    

    /// The wrap configuration GUID (go to PACE Central to create such wrap configurations)
    private string wrapConfigGUID;  

    string getILokAccount()
    {
        if (iLokAccount is null)
            throw new Exception(`Missing "iLokAccount" in plugin.json (Note: pace.json has moved to plugin.json, see Dplug's Release Notes)`);
        return expandDplugVariables(iLokAccount);
    }

    string getILokPassword()
    {
        promptIlokPasswordLazily();
        if (iLokPassword is null)
            throw new Exception(`Missing "iLokPassword" in plugin.json (Recommended value: "!PROMPT" or "$ENVVAR")`);
        return expandDplugVariables(iLokPassword);
    }

    string getWrapConfigGUID()
    {
        if (wrapConfigGUID is null)
            throw new Exception(`Missing "wrapConfigGUID" in plugin.json`);
        return expandDplugVariables(wrapConfigGUID);
    }

    // </PACE Ilok specific>


    string getLV2PrettyName()
    {
        // Note: Carla doesn't support IRI with escaped character, so we have to remove
        // spaces in LV2 else the binaries aren't found.
        // This function is only used for the final binary name.
        // See_also: the LV2 client.
        return prettyName.replace(" ", "");
    }

    string getFirstConfiguration()
    {
        if (configurations.length == 0)
            throw new Exception("Missing configurations, can't build");
        return configurations[0];
    }

    bool configExists(string config)
    {
        foreach(c; configurations)
            if (config == c)
                return true;
        return false;
    }

    string[] getMatchingConfigurations(string pattern)
    {
        string[] results;

        auto reg = regex(pattern);
        foreach(c; configurations)
        {
            if (c == pattern)
            {
                results ~= c;
            }
        }
        if (results.length == 0)
        {
            string availConfig = format("%s", configurations);
            throw new CCLException(format("No configuration matches: '%s'. Available: %s", pattern.red, availConfig.yellow));
        }
        return results;
    }

    void vst3RelatedChecks()
    {
        if (vendorSupportEmail is null)
            warning(`Missing "vendorSupportEmail" in plugin.json. Email address will be wrong in VST3 format.`);
        if (pluginHomepage is null)
            warning(`Missing "pluginHomepage" in plugin.json. Plugin homepage will be wrong in VST3 format.`);
    }


    private void promptIlokPasswordLazily()
    {
        if (iLokPassword == "!PROMPT")
        {
            cwriteln();
            cwritefln(`Please enter your iLok password (seen "!PROMPT"):`.lcyan);
            iLokPassword = chomp(readln());
            cwriteln();
        }
    }

    private void promptWindowsKeyFilePasswordLazily()
    {   
        if (keyPasswordWindows == "!PROMPT")
        {
            cwriteln();
            cwritefln(`Please enter your certificate Windows password (seen "!PROMPT"):`.lcyan);
            keyPasswordWindows = chomp(readln());
            cwriteln();
        }
    }
}


class DplugBuildBuiltCorrectlyException : Exception
{
    public
    {
        @safe pure nothrow this(string message,
                                string file =__FILE__,
                                size_t line = __LINE__,
                                Throwable next = null)
        {
            super(message, file, line, next);
        }
    }
}

Plugin readPluginDescription(string rootDir, bool quiet)
{
    string dubJsonPath = to!string(buildPath(rootDir, "dub.json").array);
    string dubSDLPath = to!string(buildPath(rootDir, "dub.sdl").array);

    bool JSONexists = exists(dubJsonPath);
    bool SDLexists = exists(dubSDLPath);

    if (!JSONexists && !SDLexists)
    {
        throw new CCLException("Needs a " ~ "dub.json".lcyan ~ " or " ~ "dub.sdl".lcyan ~ " file. Please launch " ~ "dplug-build".lcyan ~ " in a plug-in project directory, or use " ~ "--root".lcyan ~ ".\n" ~
                               "File " ~ escapeCCL(dubJsonPath).yellow ~ ` doesn't exist.`);
    }

    if (JSONexists && SDLexists)
    {
        warning("Both dub.json and dub.sdl found, ignoring dub.sdl.");
        SDLexists = false;
    }

    Plugin result;
    result.rootDir = rootDir;

    string fromDubPathToToRootDirPath(string pathRelativeToDUBJSON)
    {
        return buildPath(rootDir, pathRelativeToDUBJSON).array.to!string;
    }

    string fromPluginPathToToRootDirPath(string pathRelativeToPluginJSON)
    {
        return buildPath(rootDir, pathRelativeToPluginJSON).array.to!string;
    }

    enum useDubDescribe = true;

    JSONValue dubFile;
    Tag sdlFile;

    // Open an eventual plugin.json directly to find keys that DUB doesn't bypass
    if (JSONexists)
        dubFile = parseJSON(cast(string)(std.file.read(dubJsonPath)));

    if (SDLexists)
        sdlFile = parseFile(dubSDLPath);

    
    try
    {
        if (JSONexists) result.name = dubFile["name"].str;
        if (SDLexists) result.name = sdlFile.getTagValue!string("name");
    }
    catch(Exception e)
    {
        throw new Exception("Missing \"name\" in dub.json (eg: \"myplugin\")");
    }

    // Try to find if the project has the version identifier "futureVST3FolderWindows"
    try
    {
        if (JSONexists)
        {
            foreach(e; dubFile["versions"].array)
            {
                if (e.str == "futureVST3FolderWindows")
                    result.hasFutureVST3FolderWindows = true;
            }
        }
        if (SDLexists) 
        {
            // I really hate the fact that SDLang exists and we had to 
            // adopt it in D, never choose that one. Both formats
            // manage to be worse than XML in practice.
            // And look, this parsing code compares defavorable to std.json
            foreach(e; sdlFile.getTag("versions").values)
            {
                if (e.get!string() == "futureVST3FolderWindows")
                    result.hasFutureVST3FolderWindows = true;
            }
        }
    }
    catch(Exception e)
    {
    }

    // We simply launched `dub` to build dplug-build. So we're not building a plugin.
    // avoid the embarassment of having a red message that confuses new users.
    // You've read correctly: you can't name your plugin "dplug-build" as a consequence.
    if (result.name == "dplug-build")
    {
        throw new DplugBuildBuiltCorrectlyException("");
    }

    // Check configuration names, they must be valid
    void checkConfigName(string cname)
    {
        if (!configIsAAX(cname)
            &&!configIsVST2(cname)
            &&!configIsVST3(cname)
            &&!configIsAU(cname)
            &&!configIsLV2(cname)
            &&!configIsCLAP(cname)
            &&!configIsFLP(cname)
            )
            throw new Exception(format("Configuration name should start with \"VST2\", \"VST3\", \"AU\", \"AAX\", \"LV2\", \"CLAP\" or \"FLP\". '%s' is not a valid configuration name.", cname));
    }

    try
    {
        if (JSONexists)
        {
            JSONValue[] config = dubFile["configurations"].array();
            foreach(c; config)
            {
                string cname = c["name"].str;
                checkConfigName(cname);
                result.configurations ~= cname;
            }
        }
        if (SDLexists)
        {
            foreach(Tag ctag; sdlFile.maybe.tags["configuration"])
            {
                string cname = ctag.expectValue!string();
                checkConfigName(cname);
                result.configurations ~= cname;
            }
        }
    }
    catch(Exception e)
    {
        warning(e.msg);
        warning("At least one configuration was skipped by dplug-build because of invalid prefix.");
        result.configurations = [];
    }

    // Support for DUB targetPath
    try
    {
        if (JSONexists) result.dubTargetPath = fromDubPathToToRootDirPath(dubFile["targetPath"].str);
        if (SDLexists) result.dubTargetPath = fromDubPathToToRootDirPath(sdlFile.getTagValue!string("targetPath"));
    }
    catch(Exception e)
    {
        // silent, targetPath not considered
        result.dubTargetPath = null;
    }

    string pluginJsonPath = to!string(buildPath(rootDir, "plugin.json").array);

    if (!exists(pluginJsonPath))
    {
        throw new CCLException("Needs a " ~ "plugin.json".lcyan ~ " for proper bundling. Please create one next to " ~ "dub.json".lcyan ~ ".");
    }

    // Open an eventual plugin.json directly to find keys that DUB doesn't bypass
    JSONValue rawPluginFile = parseJSON(cast(string)(std.file.read(pluginJsonPath)));

    // Optional keys

    // prettyName is the fancy Manufacturer + Product name that will be displayed as much as possible in:
    // - bundle name
    // - renamed executable file names
    try
    {
        result.pluginName = rawPluginFile["pluginName"].str;
    }
    catch(Exception e)
    {
        if (!quiet) info("Missing \"pluginName\" in plugin.json (eg: \"My Compressor\")\n        => Using dub.json \"name\" key instead.");
        result.pluginName = result.name;
    }

    // TODO: not all characters are allowed in pluginName.
    //       All characters in pluginName should be able to be in a filename.
    //       For Orion compatibility is should not have '-' in the file name
    //       For Windows compatibility, probably more characters are disallowed.

    // Note: dplug-build parses it but doesn't need hasGUI
    try
    {
        result.hasGUI = toBool(rawPluginFile["hasGUI"]);
    }
    catch(Exception e)
    {
        warning("Missing \"hasGUI\" in plugin.json (must be true or false)\n    => Using false instead.");
        result.hasGUI = false;
    }

    try
    {
        string userManualPath = rawPluginFile["userManualPath"].str;
        warning("\"userManualPath\" key has been removed");
    }
    catch(Exception e)
    {
    }

    try
    {
        result.licensePath = rawPluginFile["licensePath"].str;
    }
    catch(Exception e)
    {
        if (!quiet) info("Missing \"licensePath\" in plugin.json (eg: \"license.txt\")");
    }

    try
    {
        result.developerIdentityOSX = rawPluginFile["developerIdentity-osx"].str;
    }
    catch(Exception e)
    {
        result.developerIdentityOSX = null;
    }

    try
    {
        result.keychainProfile = rawPluginFile["keychainProfile-osx"].str;
    }
    catch(Exception e)
    {
        result.keychainProfile = null;
    }

    try
    {
        result.developerIdentityWindows = rawPluginFile["developerIdentity-windows"].str;
    }
    catch(Exception e)
    {
        result.developerIdentityWindows = null;
    }

    try
    {
        result.certThumbprintWindows = rawPluginFile["certThumbprint-windows"].str;
    }
    catch(Exception e)
    {
        result.certThumbprintWindows = null;
    }

    try
    {
        result.timestampServerURLWindows = rawPluginFile["timestampServerURL-windows"].str;
    }
    catch(Exception e)
    {
        result.timestampServerURLWindows = null;
    }

    try
    {
        result.installerPNGPath = rawPluginFile["installerPNGPath"].str;
    }
    catch(Exception e)
    {
        result.installerPNGPath = null;
    }

    try
    {
        result.windowsInstallerHeaderBmp = rawPluginFile["windowsInstallerHeaderBmp"].str;

        // take rootDir into account
        result.windowsInstallerHeaderBmp = buildPath(rootDir, result.windowsInstallerHeaderBmp).array.to!string;
    }
    catch(Exception e)
    {
        result.windowsInstallerHeaderBmp = null;
    }

    try
    {
        result.keyFileWindows = rawPluginFile["keyFile-windows"].str;
    }
    catch(Exception e)
    {
        result.keyFileWindows = null;
    }

    try
    {
        result.keyPasswordWindows = rawPluginFile["keyPassword-windows"].str;
    }
    catch(Exception e)
    {
        result.keyPasswordWindows = null;
    }

    try
    {
        result.iconPathWindows = rawPluginFile["iconPath-windows"].str;
    }
    catch(Exception e)
    {
        if (!quiet) info("Missing \"iconPath-windows\" in plugin.json (eg: \"gfx/myIcon.ico\")");
    }

    try
    {
        result.iconPathOSX = rawPluginFile["iconPath-osx"].str;
    }
    catch(Exception e)
    {
        if (!quiet) info("Missing \"iconPath-osx\" in plugin.json (eg: \"gfx/myIcon.png\")");
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
        result.vendorName = rawPluginFile["vendorName"].str;

    }
    catch(Exception e)
    {
        warning("Missing \"vendorName\" in plugin.json (eg: \"Example Corp\")\n         => Using \"Toto Audio\" instead.");
        result.vendorName = "Toto Audio";
    }

    try
    {
        result.vendorUniqueID = rawPluginFile["vendorUniqueID"].str;
    }
    catch(Exception e)
    {
        warning("Missing \"vendorUniqueID\" in plugin.json (eg: \"aucd\")\n         => Using \"Toto\" instead.");
        result.vendorUniqueID = "Toto";
    }

    if (result.vendorUniqueID.length != 4)
        throw new Exception("\"vendorUniqueID\" should be a string of 4 characters (eg: \"aucd\")");

    if (!any!isUpper(result.vendorUniqueID))
        throw new Exception("\"vendorUniqueID\" should contain at least one upper case character (eg: \"Aucd\")");

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

    // TODO: check for special characters in pluginUniqueID and vendorUniqueID
    //       I'm not sure if Audio Unit would take anything not printable, would auval support it?

    // In developement, publicVersion should stay at 0.x.y to avoid various AU caches
    // (this is only the theory...)
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

    bool toBoolean(JSONValue value)
    {
        if (value.type == jsonTrue)
            return true;
        if (value.type == jsonFalse)
            return false;
        throw new Exception("Expected a boolean");
    }

    try
    {
        result.isSynth = toBoolean(rawPluginFile["isSynth"]);
    }
    catch(Exception e)
    {
        result.isSynth = false;
    }

    try
    {
        result.receivesMIDI = toBoolean(rawPluginFile["receivesMIDI"]);
    }
    catch(Exception e)
    {
        result.receivesMIDI = false;
    }

    try
    {
        result.sendsMIDI = toBoolean(rawPluginFile["sendsMIDI"]);
    }
    catch(Exception e)
    {
        result.sendsMIDI = false;
    }

    if (result.sendsMIDI && !result.receivesMIDI)
    {
        throw new Exception("In plugin.json, \"sendsMIDI\" is true but \"receivesMIDI\" is false. Plugins that sends MIDI must also receive MIDI.");
    }

    try
    {
        result.category = parsePluginCategory(rawPluginFile["category"].str);
        if (result.category == PluginCategory.invalid)
            throw new Exception("");
    }
    catch(Exception e)
    {
        error("Missing or invalid \"category\" provided in plugin.json (eg: \"effectDelay\")");
        throw new Exception("=> Check dplug/client/daw.d to find a suitable \"category\" for plugin.json.");
    }

    try
    {
        result.vendorAppleID = rawPluginFile["vendorAppleID"].str;
    }
    catch(Exception e){}
    try
    {
        result.appSpecificPassword_altool = expandDplugVariables( rawPluginFile["appSpecificPassword-altool"].str );
    }
    catch(Exception e){}
    try
    {
        result.appSpecificPassword_stapler = expandDplugVariables( rawPluginFile["appSpecificPassword-stapler"].str );
    }
    catch(Exception e){}

    try
    {
        result.pluginHomepage = rawPluginFile["pluginHomepage"].str;
    }
    catch(Exception e)
    {
        // Only warn on VST3 build if pluginHomepage is missing
        result.pluginHomepage = null;
    }

    try
    {
        result.vendorSupportEmail = rawPluginFile["vendorSupportEmail"].str;
    }
    catch(Exception e)
    {
        // Only warn on VST3 build if vendorSupportEmail is missing
        result.vendorSupportEmail = null;
    }

    try
    {
        result.iLokAccount = rawPluginFile["iLokAccount"].str;
    }
    catch(Exception e)
    {
        result.iLokAccount = null;
    }

    try
    {
        result.iLokPassword = rawPluginFile["iLokPassword"].str;
    }
    catch(Exception e)
    {
        result.iLokPassword = null;
    }

    try
    {
        result.wrapConfigGUID = rawPluginFile["wrapConfigGUID"].str;
    }
    catch(Exception e)
    {
        result.wrapConfigGUID = null;
    }

    return result;
}

bool toBool(JSONValue v)
{
    if (v.type == jsonFalse)
        return false;
    else if (v.type == jsonTrue)
        return true;
    else
        throw new Exception("expected boolean value");
}


string makePListFile(Plugin plugin, string config, bool hasIcon, bool isAudioComponentAPIImplemented)
{
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

    addKeyString("CFBundleGetInfoString", productVersion ~ ", " ~ plugin.copyright);

    string CFBundleIdentifier;
    if (configIsVST2(config))
        CFBundleIdentifier = plugin.getVSTBundleIdentifier();
    else if (configIsVST3(config))
        CFBundleIdentifier = plugin.getVST3BundleIdentifier();
    else if (configIsAU(config))
        CFBundleIdentifier = plugin.getAUBundleIdentifier();
    else if (configIsAAX(config))
        CFBundleIdentifier = plugin.getAAXBundleIdentifier();
    else if (configIsLV2(config))
        CFBundleIdentifier = plugin.getLV2BundleIdentifier();
    else if (configIsFLP(config))
        CFBundleIdentifier = plugin.getFLPBundleIdentifier();
    else
        throw new Exception("Configuration name given by --config must start with \"VST\", \"VST3\", \"AU\", \"AAX\", \"LV2\", or \"FLP\"");

    // Doesn't seem useful at all
    //addKeyString("CFBundleName", plugin.prettyName);
    //addKeyString("CFBundleExecutable", plugin.prettyName);

    addKeyString("CFBundleIdentifier", CFBundleIdentifier);

    addKeyString("CFBundleVersion", productVersion);
    addKeyString("CFBundleShortVersionString", productVersion);

    // PACE signing need this on Mac to find the executable to sign
    addKeyString("CFBundleExecutable", plugin.prettyName);

    if (isAudioComponentAPIImplemented && configIsAU(config))
    {
        content ~= "        <key>AudioComponents</key>\n";
        content ~= "        <array>\n";
        content ~= "            <dict>\n";
        content ~= "                <key>type</key>\n";
        if (plugin.isSynth)
            content ~= "                <string>aumu</string>\n";
        else if (plugin.receivesMIDI)
            content ~= "                <string>aumf</string>\n";
        else
            content ~= "                <string>aufx</string>\n";

        // We use VST unique plugin ID as subtype in Audio Unit
        // So apparently no chance to give a categoy here.
        char[4] uid = plugin.pluginUniqueID;
        string suid = escapeXMLString(uid.idup);//format("%c%c%c%c", uid[0], uid[1], uid[2], uid[3]));
        content ~= "                <key>subtype</key>\n";
        content ~= "                <string>" ~ suid ~ "</string>\n";

        char[4] vid = plugin.vendorUniqueID;
        string svid = escapeXMLString(vid.idup);
        content ~= "                <key>manufacturer</key>\n";
        content ~= "                <string>" ~ svid ~ "</string>\n";
        content ~= "                <key>name</key>\n";
        content ~= format("                <string>%s</string>\n", escapeXMLString(plugin.vendorName ~ ": " ~ plugin.pluginName));
        content ~= "                <key>description</key>\n";
        content ~= format("                <string>%s</string>\n", escapeXMLString(plugin.vendorName ~ " " ~ plugin.pluginName));
        content ~= "                <key>version</key>\n";
        content ~= format("                <integer>%s</integer>\n", plugin.publicVersionInt()); // TODO correct?
        content ~= "                <key>factoryFunction</key>\n";
        content ~= "                <string>dplugAUComponentFactoryFunction</string>\n";
        content ~= "                <key>sandboxSafe</key>\n";
        content ~= "                <true/>\n";
        content ~= "            </dict>\n";
        content ~= "        </array>\n";
    }

    addKeyString("CFBundleInfoDictionaryVersion", "6.0");
    addKeyString("CFBundlePackageType", "BNDL");
    addKeyString("CFBundleSignature", plugin.pluginUniqueID); // doesn't matter http://stackoverflow.com/questions/1875912/naming-convention-for-cfbundlesignature-and-cfbundleidentifier

   // Set to 10.9
    addKeyString("LSMinimumSystemVersion", "10.9.0");

   // content ~= "        <key>VSTWindowCompositing</key><true/>\n";

    if (hasIcon)
        addKeyString("CFBundleIconFile", "icon");
    content ~= `    </dict>` ~ "\n";
    content ~= `</plist>` ~ "\n";
    return content;
}

// pkgbuild can take a .plist file to specify additional bundle options
string makePListFileForPKGBuild(string bundleName)
{
    string content = "";

    content ~= `<?xml version="1.0" encoding="UTF-8"?>` ~ "\n";
    content ~= `<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">` ~ "\n";
    content ~= `<plist version="1.0">` ~ "\n";
    content ~= `    <array><dict>` ~ "\n";
    content ~= `        <key>RootRelativeBundlePath</key><string>` ~ escapeXMLString(bundleName) ~ `</string>` ~ "\n";
    content ~= `        <key>BundleIsVersionChecked</key><false/>` ~ "\n";
    content ~= `        <key>BundleOverwriteAction</key><string>upgrade</string>` ~ "\n";
    content ~= `    </dict></array>` ~ "\n";
    content ~= `</plist>` ~ "\n";
    return content;
}

// return path of newly made icon
string makeMacIcon(string outputDir, string pluginName, string pngPath)
{
    string iconSetDir = buildPath(outputDir, "temp/" ~ pluginName ~ ".iconset");
    string outputIcon = buildPath(outputDir, "temp/" ~ pluginName ~ ".icns");

    if(!outputIcon.exists)
    {
        //string cmd = format("lipo -create %s %s -output %s", path32, path64, exePath);
        try
        {
            safeCommand(format("mkdir %s", iconSetDir));
        }
        catch(Exception e)
        {
            cwritefln(" =&gt; %s".yellow, e.msg);
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

string makeRSRC_internal(string outputDir, Plugin plugin, Arch arch, bool verbose)
{
    if (arch != Arch.x86_64 
        && arch != Arch.arm64 
        && arch != Arch.universalBinary)
    {
        throw new Exception("Can't use internal .rsrc generation for this arch");
    }

    cwritefln("*** Generating a .rsrc file for the bundle...");

    string rsrcPath = outputDir ~ "/temp/plugin-" ~ convertArchToPrettyString(arch) ~ ".rsrc";
    RSRCWriter rsrc;
    rsrc.addType("STR ");
    rsrc.addType("dlle");
    rsrc.addType("thng");
    rsrc.addResource(0, 1000, true, null, makeRSRC_pstring(plugin.vendorName ~ ": " ~ plugin.pluginName));
    rsrc.addResource(0, 1001, true, null, makeRSRC_pstring(plugin.pluginName ~ " AU"));
    rsrc.addResource(1, 1000, false, null, makeRSRC_cstring("dplugAUEntryPoint"));
    ubyte[] thng;
    {
        if (plugin.isSynth)
            thng ~= makeRSRC_fourCC("aumu");
        else if (plugin.receivesMIDI)
            thng ~= makeRSRC_fourCC("aumf");
        else
            thng ~= makeRSRC_fourCC("aufx");
        thng ~= makeRSRC_fourCC_string(plugin.pluginUniqueID);
        thng ~= makeRSRC_fourCC_string(plugin.vendorUniqueID);
        thng.writeBE_uint(0);
        thng.writeBE_uint(0);
        thng.writeBE_uint(0);
        thng.writeBE_ushort(0);
        thng ~= makeRSRC_fourCC("STR ");
        thng.writeBE_ushort(1000);
        thng ~= makeRSRC_fourCC("STR ");
        thng.writeBE_ushort(1001);
        thng.writeBE_uint(0); // icon
        thng.writeBE_ushort(0);
        thng.writeBE_uint(plugin.publicVersionInt());
        enum componentDoAutoVersion = 0x01;
        enum componentHasMultiplePlatforms = 0x08;
        thng.writeBE_uint(componentDoAutoVersion | componentHasMultiplePlatforms);
        thng.writeBE_ushort(0);

        if (arch == Arch.x86_64)
        {
            thng.writeBE_uint(1); // 1 platform
            thng.writeBE_uint(0x10000000);
            thng ~= makeRSRC_fourCC("dlle");
            thng.writeBE_ushort(1000);
            thng.writeBE_ushort(8 /* platformX86_64NativeEntryPoint */);
        }
        else if (arch == Arch.arm64)
        {
            thng.writeBE_uint(1); // 1 platform
            thng.writeBE_uint(0x10000000);
            thng ~= makeRSRC_fourCC("dlle");
            thng.writeBE_ushort(1000);
            thng.writeBE_ushort(9 /* platformArm64NativeEntryPoint */);
        }
        else if (arch == Arch.universalBinary)
        {
            thng.writeBE_uint(2); // 2 platform, arm64 then x86_64

            thng.writeBE_uint(0x10000000);
            thng ~= makeRSRC_fourCC("dlle");
            thng.writeBE_ushort(1000);
            thng.writeBE_ushort(9 /* platformArm64NativeEntryPoint */);
            
            thng.writeBE_uint(0x10000000);
            thng ~= makeRSRC_fourCC("dlle");
            thng.writeBE_ushort(1000);
            thng.writeBE_ushort(8 /* platformX86_64NativeEntryPoint */);
        }
        else
            assert(false, "not supported yet");
    }

    rsrc.addResource(2, 1000, false, plugin.vendorName ~ ": " ~ plugin.pluginName, thng);

    std.file.write(rsrcPath, rsrc.write());
    cwritefln("    =&gt; Written %s bytes.".lgreen, getSize(rsrcPath));
    cwriteln();
    return rsrcPath;
}

string makeRSRC_with_Rez(Plugin plugin, Arch arch, bool verbose)
{
    if (arch != Arch.x86_64)
        throw new Exception("Can't use --rez for another arch than x86_64");
    string pluginName = plugin.pluginName;
    cwritefln("*** Generating a .rsrc file for the bundle, using Rez...");
    string temp = tempDir();

    string rPath = buildPath(temp, "plugin.r");

    File rFile = File(rPath, "w");
    static immutable string rFileBase = cast(string) import("plugin-base.r");

    rFile.writefln(`#define PLUG_MFR "%s"`, plugin.vendorName); // no C escaping there, FUTURE
    rFile.writefln("#define PLUG_MFR_ID '%s'", plugin.vendorUniqueID);
    rFile.writefln(`#define PLUG_NAME "%s"`, pluginName); // no C escaping there, FUTURE
    rFile.writefln("#define PLUG_UNIQUE_ID '%s'", plugin.pluginUniqueID);
    rFile.writefln("#define PLUG_VER %d", plugin.publicVersionInt());

    rFile.writefln("#define PLUG_IS_INST %s", (plugin.isSynth ? "1" : "0"));
    rFile.writefln("#define PLUG_DOES_MIDI %s", (plugin.receivesMIDI ? "1" : "0"));

    rFile.writeln(rFileBase);
    rFile.close();

    string rsrcPath = "reference.rsrc";

    string archFlags;
    final switch(arch) with (Arch)
    {
        case x86: archFlags = "-arch i386"; break;
        case x86_64: archFlags = "-arch x86_64"; break;
        case arm32: assert(false);
        case arm64: assert(false);
        case universalBinary: assert(false);
        case all:   assert(false);
    }

    string verboseFlag = verbose ? " -p" : "";

    safeCommand(format("rez %s%s -o %s -useDF %s", archFlags, verboseFlag, rsrcPath, rPath));


    if (!exists(rsrcPath))
        throw new Exception(format("%s wasn't created", rsrcPath));

    if (getSize(rsrcPath) == 0)
        throw new Exception(format("%s is an empty file", rsrcPath));

    cwritefln("    =&gt; Written %s bytes.".lgreen, getSize(rsrcPath));
    cwriteln();
    return rsrcPath;
}
