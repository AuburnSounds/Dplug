import std.stdio;
import std.file;
import std.string;
import std.conv;
import std.math;
import std.algorithm;
import std.demangle;

import pdb;
import consolecolors;

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
    cwriteln( "This is the <strong><lcyan>dbloat</lcyan></strong> tool: parses a .pdb and show largest functions.");
    cwriteln();
    cwriteln("<strong>Usage: <lcyan>dbloat</></> <yellow>&lt;file.pdb&gt;</>");
    cwriteln();
    cwriteln("────────── <on_blue> FLAGS </> ────────── 😸🚩".white);
    cwriteln();
    flag("--help", "Show this help", null, null);
    flag("-n &lt;int&gt;", "      Number of top functions to list", "integer", "10");

    cwriteln("");

    cwriteln("Note: you can enable/disable any category of symbols with -cat or +cat flags".white);
    cwriteln("");
}

int main(string[] args) 
{
    try
    {
        enableConsoleUTF8();

        string inpath;
        bool help = false;
        int nFunctions = 10;
        bool[SYMBOL_NUM_CATEGORIES] visibility;
        foreach(cat; 0..SYMBOL_NUM_CATEGORIES)
        {
            SymbolCategory category = cast(SymbolCategory)cat;
            visibility[cat] = symbolCategoryDefaultVisibility(category);
        }

        for (int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "--help")
                help = true;
            else if (arg == "-n")
            {
                ++i;
                nFunctions = to!int(args[i]);
            }
            else if (arg.startsWith("+") || arg.startsWith("-"))
            {
                bool plus = arg.startsWith("+");
                bool found = false;

                if (arg[1..$] == "all")
                {
                    if (plus) visibility[] = true;
                    else visibility[] = false;
                    found = true;
                }
                else foreach(cat; 0..SYMBOL_NUM_CATEGORIES)
                {
                    SymbolCategory category = cast(SymbolCategory)cat;
                    string name = symbolCategoryName(category);
                    if (arg[1..$] == name)
                    {
                        if (plus) visibility[cat] = true;
                        else visibility[cat] = false;
                        found = true;
                    }
                }
                if (!found) throw new CCLException("Unknown category in +- argument.");
            }
            else
            {
                if (inpath !is null)            
                {
                    throw new CCLException("Too many files provided, unknown flag %s. See --help", arg);
                }
                inpath = arg;
            }
        }

        if (help) 
        {
            usage;
            return 0;
        }

        if ( (inpath is null) || !inpath.endsWith(".pdb"))
        {
            throw new CCLException("No .pdb file provided, see --help");
        }

        if (nFunctions <= 0)
        {
            throw new CCLException("-n must be > 0");
        }

        ubyte[] pdbBytes = cast(ubyte[]) read(inpath);
        auto pdbResult = parsePDB(pdbBytes);

        if (!pdbResult.success) 
        {
            throw new CCLException(format("Error while parsing %s", inpath));
        }

        pdbResult.categorizeAll();



        cwriteln;
        displaySymbols(inpath, pdbResult.symbols, nFunctions, visibility);
        return 0;
    }
    catch(CCLException e)
    {
        cwritefln("<lred>error:</> %s", e.msg);
        return 1;
    }
}

void displaySymbols(string filename,
                    SymbolInfo[] symbols,
                    int maxSym,
                    bool[SYMBOL_NUM_CATEGORIES] visibility) 
{    
    cwritefln(`<strong>*** OVERVIEW ***</>`);
    cwritefln(`  - <yellow>%s</> has <lcyan>%s</> symbols.`, filename, symbols.length);
    cwriteln();
    cwriteln("<strong>*** REPARTITION ***</>");
    
    int[SYMBOL_NUM_CATEGORIES] catBytes;
    int[SYMBOL_NUM_CATEGORIES] catSymbols;

    foreach (sym; symbols) 
    {
        catBytes[sym.category] += sym.size;
        catSymbols[sym.category] += 1;
    }

    foreach(cat; 0..SYMBOL_NUM_CATEGORIES)
    {
        SymbolCategory category = cast(SymbolCategory)cat;
        string categColor = symbolCategoryColor(category);
        string catName    = symbolCategoryName(category);
        while (catName.length < 10) catName ~= ' ';
        bool visible = visibility[cat];
        string visibleMsg = visible ? "" : " <grey>(hidden)</>";
        cwritefln(`  - <%s>#%s</> <lcyan>%5d symbols</> <lblue>%6d bytes</>%s`, categColor, catName, catSymbols[cat], catBytes[cat], visibleMsg);
    }

    cwriteln();
    cwritefln("<strong>*** TOP %d LARGEST SYMBOLS ***</>", maxSym);

    if (symbols.length > maxSym)
        symbols = symbols[0..maxSym];

    foreach (sym; symbols) 
    {
        // Do not show everything
        if (!visibility[sym.category])
            continue;

        string name = sym.name;//getDemangled();

        string categColor = symbolCategoryColor(sym.category);
        string catName    = symbolCategoryName(sym.category);
        cwritefln(`<lblue>%6s bytes</> <white>%s</> <%s>#%s</>`, sym.size, escapeCCL(name), categColor, catName);
    }
}

