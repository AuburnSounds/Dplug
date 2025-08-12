import std.string;
import std.file;
import std.conv;
import std.random;
import std.math;

import yxml;
import utils;
import var;
import consolecolors;
import parseproject;
import settings;
import diffevol;

// TODO: 
// - certaines <var> ont un minimum qu'on voudrait bien spécifier
// - first step of DE should not cross but only compute random pop results
// - first step of DE should have gaussian random

enum Algorithm
{
    /// Just evaluate initial state
    here,

    /// For each <var>, evaluate a 1D pattern and keep the best
    /// Each variable is set to their best known value between -s steps
    /// so all at once.
    /// You can use --pattern and --pattern-stddev
    gradient,

    /// For each <var>, evaluate a 1D pattern and keep the best.
    /// Each variable is set to their best known right before the next
    /// variable is considered.
    /// This helps convergence in the case the problem has well decorrelated
    /// variables.
    /// You can use --pattern and --pattern-stddev
    /// Note: this has no moat over gradient, so it is deprecated
    whirlpool,

    /// Differential Evolution
    /// Reference: 
    /// "Differential Evolution – A Simple and Efficient Heuristic for 
    ///  Global Optimization over Continuous" (1997) - Storn & Price
    diffevol,    
}

string algorithmDescription(Algorithm algo)
{
    final switch(algo)
    {
        case Algorithm.here: return "Here (single point sample)";
        case Algorithm.diffevol: return "Differential Evolution";
        case Algorithm.gradient: return "Simple Gradient";
        case Algorithm.whirlpool: return "Whirlpool";
    }
}

enum string DEFAULT_SEARCH_PATTERN = "0.97848, 1.0, 1.022"; // best one according to meta-param analysis

void usage()
{
    void flag(string arg, string desc, string possibleValues, string defaultDesc)
    {
        string argStr = format("  %s", arg);
        cwrite(argStr.lcyan);
        for(size_t i = argStr.length; i < 14; ++i)
            cwrite(" ");
        cwritefln("%s", desc);
        if (possibleValues)
            cwritefln("              Possible values: ".grey ~ "%s".yellow, possibleValues);
        if (defaultDesc)
            cwritefln("              Default: ".grey ~ "%s".lcyan, defaultDesc);
        cwriteln;
    }

    cwriteln;
    cwriteln(`<yellow> ___            _ </>`);
    cwriteln(`<yellow>| __|__ __ ___ | |__ __  ___ </>`);
    cwriteln(`<yellow>| _| \ V // _ \| |\ V / / -_)  </>`);
    cwriteln(`<yellow>|___| \_/ \___/|_| \_/  \___|  </>`);
    cwriteln;
    cwriteln();
    cwriteln("➡️ WHAT'S THIS?".white.on_black);
    cwriteln();
    cwriteln("✨<yellow>evolve</>✨ optimizes your magic constants with <b>gradient descent</>.");
    cwriteln();
    cwriteln();
    cwriteln("➡️ HOW IT WORKS".white.on_black);
    cwriteln();
    cwriteln("✨<yellow>evolve</>✨ builds a <b>D program</b> repeatedly while changing <lblue>float</>/<lblue>double</>");
    cwriteln("non-array variables and constants, marked with the <orange>@tuning</>");
    cwriteln("user-defined attribute (called <i><lgreen>variables</></> below).");
    cwriteln;
    cwriteln;
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln(`<on_black>    <lmagenta>// ---------------- source.d -----------------</>                    </>`);
    cwriteln(`<on_black>    <lgrey><lblue>import</> dplug.dsp.udas;</>                                            </>`);
    cwriteln(`<on_black>    <orange>@tuning</><lgrey> <lblue>float</> <lgreen>MY_MAGIC_CONSTANT0</>       = <yellow>0.10</>;                    </></>`);
    cwriteln(`<on_black>    <orange>@tuning</><lgrey> <lblue>double</> <lgreen>MY_MAGIC_CONSTANT1</>      = <yellow>0.28</>;                    </></>`);
    cwriteln(`<on_black>    <orange>@tuning</><lgrey> <lblue>enum float</> <lgreen>MY_MAGIC_CONSTANT2</>  = <yellow>0.30</>;                    </></>`);
    cwriteln(`<on_black>    <orange>@tuning</><lgrey> <lblue>enum double</> <lgreen>MY_MAGIC_CONSTANT3</> = <yellow>0.45</>;                    </></>`);  
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln;
    cwriteln;
    cwriteln("For evolution it needs a⚡<orange>fitness measure</>⚡to evaluate each build.");
    cwriteln("✨<yellow>evolve</>✨ runs from within a <b>DUB project</> directory, and uses the <yellow>git</>");
    cwriteln("working copy as temporary state.");
    cwriteln("<lblue>https://code.dlang.org/</>");
    cwriteln();
    cwriteln(`<lred>Warning:</> ✨<yellow>evolve</>✨ uses the current git working copy as starting`);
    cwriteln(`point, and will overwrite it while running. Use <yellow>git</> to validate or not`);
    cwriteln(`the changes it made (pick the right ones in the backlog), because it`);
    cwriteln(`will leave the repositery in a bad state.`);
    cwriteln;    
    cwriteln(`<lred>Warning:</> ✨<yellow>evolve</>✨ is <i>slow</i> and designed for when the fitness`);
    cwriteln(`evaluation is slow. You'll interrupt a run before it has finished most`);
    cwriteln(`of the time, and then will have a massive backlog to read to find the`);
    cwriteln(`right values.`);
    cwriteln();
    cwriteln(`<lgreen>Pro-tip:</> Run ✨<yellow>evolve</>✨ in multiple <yellow>git</> working copies to optimize`);
    cwriteln(`different variables.`);
    cwriteln();
    cwriteln();
    cwriteln("➡️ FLAGS".white.on_black);
    cwriteln();
    flag("-a --algo", "Choose an algorithm for gradient descent.", null, "<lcyan>-a </><orange>here</>");

    cwriteln(`    <orange>here     </> Compute fitness here, with current local changes.`);
    cwriteln(`              Do not change working copy.`);
    cwriteln;
    cwriteln(`    <orange>gradient </> Use <lcyan>--pattern</> search here, then change the best`);
    cwriteln(`              <lgreen>variable</> once all are evaluated.`);
    cwriteln;
    cwriteln(`    <orange>whirlpool</> Use <lcyan>--pattern</> search here, then change each`);
    cwriteln(`              tested <lgreen>variable</> immediately after evaluation.`);
    cwriteln;
    cwriteln(`    <orange>diffevol </> Use "Differential Evolution" algorithm.`);
    cwriteln(`              <lblue>https://en.wikipedia.org/wiki/Differential_evolution</>`);
    cwriteln();

    flag("-s --steps",  "Number of gradient steps, or generations.", null, "<yellow>1</>");    
    flag("--pattern", "Change the <lcyan>-a</><orange> gradient</>/<orange>whirlpool</> pattern search.", null, DEFAULT_SEARCH_PATTERN.yellow);
    flag("--pstddev", "Make <lcyan>--pattern</> noisey, except 1.0 <lred>(DANGER)</>.", null, "0.0".yellow);
    flag("--list-pack",  "Show list of DUB packages in project and exit.", null, null);
    flag("--excl-pack",  "Show list of ignored DUB packages and exit.", null, null);
    flag("--list-vars",  "Show list of <lgreen>variables</> in project and exit.", null, null);
    flag("-v",  "Verbose output.", null, "no");
    flag("-h --help",  "Show this help.", null, null);

    cwriteln();
    cwriteln();
    cwriteln("➡️ NOTES".white.on_black);
    cwriteln();
    cwriteln("✨<yellow>evolve</>✨ needs an " ~ "evolve.xml".orange ~ " file in the working directory.");
    cwriteln();
    cwriteln();
    cwriteln("➡️ EXAMPLE".white.on_black);
    cwriteln();
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln(`<on_black>    <lmagenta>// ---------------------- nichealgorithm.d -----------------------</></>`);
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln(`<on_black>    <lgrey><lblue>import</> dplug.dsp.udas;</>                                            </>`);
    cwriteln(`<on_black>    <lgrey><orange>@tuning</> <lblue>enum float</lblue> <lgreen>MY_VAR</> = <yellow>0.45f</>;</><lmagenta> // tricky to optimize!</>         </>`);
    cwriteln(`<on_black>    <lgrey><orange>@tuning</> <lblue>double</lblue> <lgreen>MY_OTHER_VAR</> = <yellow>0.168</>;</>                              </>`);

    cwriteln(`<on_black>    <lgrey>doSomethingWithThoseVariables();                                  </></>`);
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln(`<on_black>    <lmagenta>// ------------------------- evolve.xml --------------------------</></>`);
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln(`<on_black>    <yellow>&lt;</yellow><lblue>?xml</> <cyan>version</>=<yellow>"</yellow><lblue>1.0</><yellow>"</yellow> <cyan>encoding</>=<yellow>"</yellow><lblue>UTF-8</><yellow>"</yellow><yellow>?&gt;</yellow>                            </>`);
    cwriteln(`<on_black>    <yellow>&lt;</yellow><lblue>training</><yellow>&gt;</yellow>                                                        </>`);
    cwriteln(`<on_black>      <lmagenta>&lt;!-- Both these variable will be evolved --&gt;</>                    </>`);
    cwriteln(`<on_black>      <yellow>&lt;</yellow><lblue>var</> <cyan>name</>=<lgreen><yellow>"</yellow>MY_VAR<yellow>"</yellow></> <yellow>/&gt;</yellow>                                           </>`);
    cwriteln(`<on_black>      <yellow>&lt;</yellow><lblue>var</> <cyan>name</>=<lgreen><yellow>"</yellow>MY_OTHER_VAR<yellow>"</yellow></> <yellow>/&gt;</yellow>                                     </>`);
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln(`<on_black>      <lmagenta>&lt;!-- How to build and ⚡evaluate⚡ the program --&gt;</>              </>`);
    cwriteln(`<on_black>      <yellow>&lt;</yellow><lblue>fitness-command</><yellow>&gt;</yellow><orange>mytest -param</><yellow>&lt;/</yellow><lblue>fitness-command</><yellow>&gt;</yellow>                </>`);
    cwriteln(`<on_black>      <yellow>&lt;</yellow><lblue>build-command-windows</><yellow>&gt;</yellow><white>dub -b release</><yellow>&lt;/</yellow><lblue>build-command-windows</><yellow>&gt;</yellow>   </>`);
    cwriteln(`<on_black>      <yellow>&lt;</yellow><lblue>build-command-macos</><yellow>&gt;</yellow><white>dub</><yellow>&lt;/</yellow><lblue>build-command-macos</><yellow>&gt;</yellow>                  </>`);
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln(`<on_black>      <lmagenta>&lt;!-- Ignored package for parsing variables --&gt;</>                  </>`);
    cwriteln(`<on_black>      <yellow>&lt;</yellow><lblue>exclude-package</> <cyan>name</>=<orange><yellow>"</yellow>gamut<yellow>"</yellow></> <yellow>/&gt;</yellow>                                </>`);
    cwriteln(`<on_black>      <yellow>&lt;</yellow><lblue>exclude-package</> <cyan>name</>=<orange><yellow>"</yellow>dplug:dsp<yellow>"</yellow></> <yellow>/&gt;</yellow>                            </>`);
    cwriteln(`<on_black>    <yellow>&lt;/</yellow><lblue>training</><yellow>&gt;</>                                                       </>`);
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln(`<on_black>    <lmagenta># Run two steps of the <orange>whirlpool</> gradient descent algorithm</>       </>`);
    cwriteln(`<on_black>    <grey>$</> <yellow>evolve</> <lcyan>-a</> <orange>whirlpool</> <lcyan>--pattern</> <yellow>0.8,1.0,1.25</> <lcyan>-s</> <yellow>2</>                 </>`);
    cwriteln(`<on_black>                                                                      </>`);
    cwriteln();

}

enum string configFile = "evolve.xml";

int main(string[] args)
{
    try
    {
        enableConsoleUTF8();
        Algorithm algo = Algorithm.here;
        bool help = false;
        bool verbose = false;
        bool listPackages = false;
        bool listExcludedPackages = false;
        bool listVars = false;
        int numSteps = 1;
        string searchPattern = DEFAULT_SEARCH_PATTERN;
        double patternStddev = 0.0;

        for(int i = 1; i < args.length; ++i)
        {
            string arg = args[i];

            if (arg == "-h" || arg == "--help")
            {
                help = true;
            }
            else if (arg == "-v")
            {
                verbose = true;
            }
            else if (arg == "-s" || arg == "--step")
            {
                ++i;
                numSteps = to!int(args[i]);
            }
            else if (arg == "--pattern")
            {
                ++i;
                searchPattern = args[i];
            }
            else if (arg == "--pstddev")
            {
                ++i;
                patternStddev = to!double(args[i]);
            }
            else if (arg == "-a" || arg == "--algo")
            {
                ++i;
                if (args[i] == "here")
                    algo = Algorithm.here;
                else if (args[i] == "gradient")
                    algo = Algorithm.gradient;
                else if (args[i] == "diffevol")
                    algo = Algorithm.diffevol;
                else if (args[i] == "whirlpool")
                    algo = Algorithm.whirlpool;
                else
                    throw new Exception(`Algorithm valid value: here, gradient, diffevol, whirlpool`);

                verbose = true;
            }
            else if (arg == "--list-pack")
                listPackages = true;
            else if (arg == "--excl-pack")
                listExcludedPackages = true;
            else if (arg == "--list-vars")
                listVars = true;
            else
            {
                throw new Exception(format("unexpected argument '%s'", arg));
            }
        }

        if (help)
        {
            usage();
            return 0;
        }

        //if (!"plugin.json".exists())
        //    throw new Exception("Not a plug-in project, plugin.json is missing");

        if (!configFile.exists())
        {
            throw new CCLException(format("missing <orange>%s</>, see <lcyan>evolve --help</> for usage info", configFile));
            return 1;
        }

        TrainingSettings settings = parseTrainingSettings(configFile);

  

        Project project = parseDubDescription();
        string[] sourceFiles = project.getAllSourceFiles();

        bool earlyExit = false;
        if (listPackages)
        {
            cwriteln;
            cwritefln("Project has <yellow>%s</> <orange>DUB packages</>:", project.packages.length);
            foreach(pack; project.packages.byKey)
            {
                cwritefln(" - <orange>%s</orange>", pack);
            }
            earlyExit = true;
        }

        if (listExcludedPackages)
        {
            cwriteln;
            cwritefln("Config <orange>evolve.xml</> excludes <yellow>%s</> <orange>packages</>:", settings.excludedPackageNames.length);
            foreach(pack; settings.excludedPackageNames)
            {
                cwritefln(" - <orange>%s</orange>", pack);
            }
            earlyExit = true;
        }
        if (earlyExit) return 0;

        project.pruneWithSettings(settings);

        // Find all tuning variables
        foreach(name, pack; project.packages)
        {
            pack.parse(listVars);
        }
        if (listVars)
            return 0;

        // Select some variables

        Variable[] selected = project.getVariablesThatMatch(settings);

        cwritefln("      <lgreen>Prepare</lgreen> algorithm <lmagenta>%s</lmagenta> of <lcyan>%s</lcyan> variable(s):", algorithmDescription(algo), selected.length);

        foreach(var; selected)
        {
            cwritefln("               - <lcyan>%s</lcyan> with a starting value of <yellow>%s</yellow>", var.name, var.originalValue);
        }

        if (selected.length == 0)
        {
            throw new Exception("Nothing to do.");
        }
        cwriteln;

        if (algo == Algorithm.here)
        {
            cwriteln("<lgreen>Evaluating</lgreen> current state.");
            build(settings);
            double fitness = evaluate(settings);
            cwritefln("   =&gt; <yellow>%s</yellow>", fitness);
        }
        else if (algo == Algorithm.gradient || algo == Algorithm.whirlpool)
        {
            auto rng = Random();

            float F = 1.0f; // balance between exploration and convergence speed,
                            // this one was more robust than 0.7 or 1.0

            for (int step = 0; step < numSteps; ++step)
            {
                cwriteln;
                cwriteln("<white>***************</white>");
                cwritefln("<white>*** STEP %2d ***</white>", step);
                cwriteln("<white>***************</white>");
                cwriteln;
                cwriteln("<lgreen>Analyzing</lgreen> neighbourhood of each selected variable, in order to make a gradient.");

                // Parse "modifiers" in search pattern
                // eg: " 1.0,4.0,7.0" => [1.0, 4.0, 7.0]

                double[] modifiers;

                foreach(number; searchPattern.split(","))
                {
                    modifiers ~= to!double(strip(number));
                }

                if (modifiers.length == 0)
                {
                    throw new Exception("--pattern did not parse");
                }

                double firstFitnessComputed;

                foreach(var; selected)
                {
                    if (var.stopEvolution)
                        continue;

                    // forget last "best" fitness
                    var.bestKnownValueFitness = double.infinity;

                    double origValue = var.originalValue;

                    double[] modValues;
                    double[] modFitness;
                    double[] noisyModifiers;
                    modValues.length = modifiers.length;
                    modFitness.length = modifiers.length;

                    foreach(size_t modifierIndex, modifier; modifiers)
                    {
                        modValues[modifierIndex] = modifier * origValue;
                    }
                    
                    foreach(size_t modifierIndex, modifier; modifiers)
                    {
                        cwritefln("<white>*** Test with modifier = %.6f</white>", 
                                  modifier);
                        var.setValue( modValues[modifierIndex], true );
                        build(settings);
                        double fitness = evaluate(settings);
                        modFitness[modifierIndex] = fitness;
                        if (firstFitnessComputed != firstFitnessComputed)
                            firstFitnessComputed = fitness;
                    }

                    // find best fitness, min fitness, max fitness, and range
                    double minFitness = double.infinity;
                    double maxFitness = -double.infinity;
                    size_t minIndex = 100;
                    foreach(size_t idx, modifier; modifiers)
                    {
                        double fitness = modFitness[idx];
                        if (fitness < minFitness)
                        {
                            minIndex = idx;
                            minFitness = fitness;
                        }
                        if (fitness > maxFitness)
                        {
                            maxFitness = fitness;
                        }
                        if (fitness < var.bestKnownValueFitness)
                        {
                            var.bestKnownValueFitness = fitness;

                            // here is the kicker, not all steps are full steps
                            var.bestKnownValue = F * modValues[idx]  + (1 - F) * var.bestKnownValue;
                        }
                    }
                    double range = maxFitness - minFitness;
                    bool noBest = (range == 0); // there is no "best"

                    if (noBest)
                    {
                        cwritefln("No measure change detected for var %s! Disabling the variable of future changes.".lred, var.name);
                        var.setOriginalValue(true);
                        var.disableFurtherChanges;
                    }
                    
                    cwritefln("Pattern search for var %s", var.name);
                    foreach(size_t idx; 0..modifiers.length)
                    {
                        double fitness = modFitness[idx];
                        double value = modValues[idx];
                       
                        if (idx == minIndex && !noBest)
                            cwritefln("    - <lmagenta><yellow>%.8f</yellow> at value %s (best)</lmagenta>", fitness, value);
                        else
                            cwritefln("    - <yellow>%.8f</yellow> at value %s", fitness, value);
                    }

                    if (noBest)
                        cwritefln("    Those potential values all have identical fitness");
                    else
                    {
                        cwritefln("    Those values cover a range of: <yellow>%s</yellow>", range);
                        if (algo == Algorithm.whirlpool)
                        {
                            cwritefln("               - <lcyan>%s</lcyan> set to <lmagenta>%s</lmagenta>", var.name, var.bestKnownValue);
                            cwritefln("<lred>%s</lred>", escapeCCL(var.regenWithValue(var.originalValue)));
                            var.setBestKnownValue(false);
                            var.bestKnownValueFitness = double.infinity;
                            cwritefln("<lgreen>%s</lgreen>", escapeCCL(var.regenWithValue(var.bestKnownValue)));
                        }
                        else
                            var.setOriginalValue(false);
                    }
                }

                if (algo == Algorithm.whirlpool)
                {
                    
                }
                else
                {
                    cwriteln("      <lgreen>Setting</lgreen> start point to best found value:");
                    foreach(var; selected)
                    {
                        if (var.stopEvolution)
                            continue;
                        cwritefln("               - <lcyan>%s</lcyan> set to <lmagenta>%s</lmagenta>", var.name, var.bestKnownValue);
                        cwritefln("<lred>%s</lred>", escapeCCL(var.regenWithValue(var.originalValue)));
                        var.setBestKnownValue(false);                        
                        cwritefln("<lgreen>%s</lgreen>", escapeCCL(var.regenWithValue(var.bestKnownValue)));
                    }
                }
                cwritefln("Reminder: fitness at start point was: %.8f", firstFitnessComputed);
                cwriteln;
            }

        }
        else if (algo == Algorithm.diffevol)
        {
            differentialEvolution(selected, settings, numSteps);
        }
        return 0;
    }
    catch(CCLException e)
    {
        cwritefln("\n<lred>Error:</> %s", e.msg);
        return 1;
    }
    catch(Exception e)
    {
        cwritefln("\n<lred>Error:</> %s", escapeCCL(e.msg));
        return 1;
    }
}


