module nsis;

import std.string;
import std.conv;
import std.file;
import std.path;

import plugin;
import utils;
import consolecolors;




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
        else if(pack.format == "FLP")
            return "For FL Studio only.";
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
    string nsisPath = "WindowsInstaller.nsi"; // Note: the NSIS script is generated in current directory.

    string content = "";
    content ~= "!include \"MUI2.nsh\"\n";
    content ~= "!include \"LogicLib.nsh\"\n";
    content ~= "!include \"x64.nsh\"\n";


    // See Issue #824, there is no real true win with this in non-100% DPI.
    //  - Either we keep the installer DPI-unaware and everything is blurry in non-100% DPI.
    //  - Either we set the flag to true and the MUI_HEADERIMAGE_BITMAP is resampled with something 
    //    that looks like nearest-neighbour sampling.
    //
    // Moral of story: make your MUI_HEADERIMAGE in pixel art style to suffer this in a way that looks
    // on-purpose.
    content ~= "ManifestDPIAware true\n";

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
    if (plugin.licensePath)
    {
        string licensePath = outputDir ~ "/license-expanded.md";
        content ~= "!insertmacro MUI_PAGE_LICENSE \"" ~ licensePath ~ "\"\n";
    }

    content ~= "!insertmacro MUI_PAGE_COMPONENTS\n";
    content ~= "!insertmacro MUI_LANGUAGE \"English\"\n\n";

    auto sections = packs.uniq!((p1, p2) => p1.format == p2.format);
    foreach(p; sections)
    {
        // FLStudio format optional, and disabled by default.
        bool optional = (p.format == "FLP");
        string optionalFlag = optional ? "/o " : "";
        content ~= `Section ` ~ optionalFlag ~ `"` ~ p.title ~ `" Sec` ~ p.format ~ "\n";
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
        if(p.format == "VST" || p.format == "FLP")
        {
            content ~= `Var InstDir` ~ formatSectionIdentifier(p) ~ "\n";
        }
    }

    content ~= "; check file can be written to\n";
    content ~= "Function checkNotRunning\n";
    content ~= "    Pop $0\n"; // pop path
    content ~= "    Pop $2\n"; // pop plugin name
    content ~= "    IfFileExists $0 0 skipclose\n";
    content ~= "    FileOpen $1 $0 \"a\"\n";
    content ~= "    IfErrors 0 skipcheck\n";
    content ~= "    MessageBox MB_OK|MB_ICONEXCLAMATION \"$2 is currently running. Please close your DAW.\"\n";
    content ~= "    skipcheck:\n";
    content ~= "    FileClose $1\n";
    content ~= "    skipclose:\n";
    content ~= "FunctionEnd\n\n";


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

        if (p.format == "FLP")
        {
            string identifier = formatSectionIdentifier(p);
            string formatNiceName = formatSectionDisplayName(p);
            content ~= "PageEx directory\n";
            content ~= "  PageCallbacks defaultInstDir" ~ identifier ~ ` "" getInstDir` ~ identifier ~ "\n";
            content ~= "  DirText \"" ~ "Your FLStudio Effect/ or Generators/ directory." ~ "\" \"\" \"\" \"\"\n";
            content ~= `  Caption ": FL Studio Directory."` ~ "\n";
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
        else if (p.format == "FLP")
        {
            string identifier = formatSectionIdentifier(p);
            // return installation path of FL Studio
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
            foreach(int FLMajor; [12, 20, 21, 22, 23, 24])
            {
                // If the FL directory exist, becomes the one directory.
                // If FL changes its plugin layout, or exceed FL 24, it will need to be redone.
                content ~= format(`  IfFileExists "$PROGRAMFILES64\Image-Line\FL Studio %s\*.*" yesFL%s noFL%s` ~"\n", FLMajor, FLMajor, FLMajor);
                content ~= format(`      yesFL%s:` ~"\n", FLMajor);
                if (plugin.isSynth)
                    content ~= format(`      StrCpy $INSTDIR "$PROGRAMFILES64\Image-Line\FL Studio %s\Plugins\Fruity\Generators"` ~"\n", FLMajor);
                else
                    content ~= format(`      StrCpy $INSTDIR "$PROGRAMFILES64\Image-Line\FL Studio %s\Plugins\Fruity\Effects"` ~"\n", FLMajor);
                content ~= format(`      noFL%s:` ~"\n", FLMajor);
            }
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

        // May point to a directory or a single file.
        // eg: "builds\Windows-64b-VST3\Witty Audio CLIP It-64.vst3"
        string pluginRelativePath = p.pluginDir.asNormalizedPath.array; 

        // eg: "Witty Audio Clip It-64.vst"
        string pluginBaseName = baseName(pluginRelativePath);

        // A NSIS literal that indicates the absolute path to install in.
        string outputPath;
        if (p.format == "VST" || p.format == "FLP") 
            outputPath =  "$InstDir" ~ formatSectionIdentifier(p);
        else
            outputPath = "\"" ~ p.installDir ~ "\"";

        // Only install the 64-bit package on 64-bit OS
        content ~= "  ${If} ${SectionIsSelected} ${Sec" ~ p.format ~ "}\n";
        if(p.is64b)
            content ~= "    ${AndIf} ${RunningX64}\n";
            
        if (p.format == "VST")
        {
            string instDirVar = "InstDir" ~ formatSectionIdentifier(p);
            content ~= format!"    WriteRegStr HKLM \"%s\" \"%s\" \"$%s\"\n"(regProductKey, instDirVar, instDirVar);
        }
        else if (p.format == "FLP")
        {
            string instDirVar = "InstDir" ~ formatSectionIdentifier(p);
            content ~= "    SetOutPath $" ~ instDirVar ~ "\n";
            content ~= format!"    WriteRegStr HKLM \"%s\" \"%s\" \"$%s\"\n"(regProductKey, instDirVar, instDirVar);
        }

        // Check that file isn't open.
        // Only do this when it isn't a directory
        // (FUTURE: do this for directories too, this doesn't work for FLP, LV2 and AAX).
        if (!pluginIsDir)
        {
            // Build a NSIS string that indicates which file to open to test for "already running" warning.
            // This seems the only way to concatenate reliably.
            content ~= "    StrCpy $0 " ~ outputPath ~ "\n";
            content ~= "    StrCpy $0 \"$0\\" ~ pluginBaseName ~ "\"\n";
            content ~= "    Push \"" ~ plugin.pluginName ~ "\"\n";
            content ~= "    Push $0\n";
            content ~= "    Call checkNotRunning\n";
        }

        content ~= "    SetOutPath " ~ outputPath ~ "\n";

        string recursiveFlag = pluginIsDir ? "/r " : "";
        content ~= "    File " ~ recursiveFlag ~ "\"" ~ pluginRelativePath ~ "\"\n";
        content ~= "  ${EndIf}\n";
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
            assert(!pluginIsDir);

            string instDirVar = "InstDir" ~ formatSectionIdentifier(p);
            content ~= format!"    ReadRegStr $%s HKLM \"%s\" \"%s\"\n"(instDirVar, regProductKey, instDirVar);
            content ~= format!"    ${If} $%s != \"\"\n"(instDirVar);
            content ~= format!"        Delete \"$%s\\%s\"\n"(instDirVar, p.pluginDir.baseName);
            content ~=        "    ${EndIf}\n";
        }
        else if (p.format == "FLP")
        {
            assert(pluginIsDir);

            // Readback installation dir, inside FL Studio directories
            string instDirVar = "InstDir" ~ formatSectionIdentifier(p);
            content ~= format!"    ReadRegStr $%s HKLM \"%s\" \"%s\"\n"(instDirVar, regProductKey, instDirVar);
            content ~= format!"    ${If} $%s != \"\"\n"(instDirVar);
            content ~= format!"        RMDir /r \"$%s\\%s\"\n"(instDirVar, p.pluginDir.baseName);
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

    // run makensis on the generated WindowsInstaller.nsi
    string nsisVerboseFlag = verbose ? "" : "/V1 ";
    string makeNsiCommand = format("makensis.exe %s%s", nsisVerboseFlag, nsisPath);
    safeCommand(makeNsiCommand);
    double sizeOfExe_mb = getSize(outExePath) / (1024.0*1024.0);
    cwritefln("    =&gt; Build OK, binary size = %0.1f mb, available in %s\n".lgreen, sizeOfExe_mb, normalizedPath(outExePath));

    if (!plugin.hasKeyFileOrDevIdentityWindows)
    {
        warning(`Do not distribute an unsigned installer. See: https://github.com/AuburnSounds/Dplug/wiki/Dplug-Installer-Guide`);
    }
    else
    {
        signExecutableWindows(plugin, outExePath);
    }
}



void signExecutableWindows(Plugin plugin, string exePath)
{
    try
    {
        string identity;
        // Using developerIdentity-windows takes precedence over .P12 file and passwords
        if (plugin.developerIdentityWindows !is null)
        {
            // sign using certificate in store (supports cloud signing like Certum)
            identity = format(`/n %s`, escapeShellArgument(plugin.developerIdentityWindows));
        }
        else
        {
            // sign using keyfile and password in store (supports key file like Sectigo)
            identity = format(`/f %s /p %s`, plugin.getKeyFileWindows(), plugin.getKeyPasswordWindows());
        }

        enum DEFAULT_TIMESTAMP_SERVER_URL = "http://timestamp.sectigo.com";
        string timestampURL = plugin.timestampServerURLWindows;
        if (timestampURL is null)
        {
            info(`Using a default timestamp URL. Use "timestampServerURL-windows" in plugin.json to override`);
            timestampURL = DEFAULT_TIMESTAMP_SERVER_URL;
        }

        // use windows signtool to sign the installer for distribution
        string cmd = format("signtool sign %s /tr %s /td sha256 /fd sha256 /q %s",
                            identity,
                            timestampURL,
                            escapeShellArgument(exePath));
        safeCommand(cmd);
        cwriteln("    =&gt; OK\n".lgreen);
    }
    catch(Exception e)
    {
        error(format("Code signature failed! %s", e.msg));
    }
}
