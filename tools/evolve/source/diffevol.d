module diffevol;

import std.random;
import std.math;
import consolecolors;

import var;
import settings;



alias vector = double[];

alias population = vector[];

void differentialEvolution(Variable[] vars, 
                           TrainingSettings settings,
                           int numSteps)
{
    int D = cast(int)vars.length; // dimensionality, D in papers
    //int NP = populationSize;      // in original paper betweed 5*dimensions and 10*dimension
    //float CR = crossOverRate;
    //float F = Ffactor;


    // Those preferences were tuned with toy program in offlabs/diffevol-convergence
    // Choosen for ability to diminish search effort, and converge often.
    int NP = cast(int)(0.5f + 15 + D*5/8.0);
    float F = 0.45f;
    float F_stddev = 0.45f;

    float CR = 0.5f; 
    float CR_stddev = 0.1f;

    // Note: litterature says CR should be 0.1 if we look 
    // for unimodal function, and 0.9 in multimodal functions
    // But I don't know which one to take

    cwritefln("     <lgreen>Starting</lgreen> <white>Differential Evolution</white> with NP = %s, F = %f, and CR = %f.", NP, F, CR);

    vector initialGoodValue = new double[D];
    foreach(ivar; 0..vars.length)
    {
        initialGoodValue[ivar] = vars[ivar].originalValue;
    }

    int seed = 42;
    auto rng = Random(seed);

    // Random vector
    vector randomVector()
    {
        vector r;
        r.length = D;
        foreach(d; 0..D)
        {
            double goodValue = initialGoodValue[d];
            double smallValue = goodValue / 1.5;
            double bigValue = goodValue * 1.5;
            if (smallValue >= bigValue)
            {
                double temp = smallValue;
                smallValue = bigValue;
                bigValue = temp;
            }

            // Initialize between 0.5 and 1.5 of current value.
            // Could also be a gaussian presumably.
            r[d] = uniform(smallValue, bigValue, rng);
        }
        return r;
    }

    vector trial;
    trial.length = D;

    // Initialization
    population pop, pop2;
    pop.length = NP;
    pop2.length = NP;
    
    double[] bestFitness;
    bestFitness.length = NP;

    foreach(int n; 0..NP)
    {
        pop[n] = randomVector();
        pop2[n] = randomVector(); // whatever
        bestFitness[n] = double.infinity; // which mean on 1st gen, every trial is considered good
    }

    for (int generation = 0; generation < numSteps; ++generation)
    {
        cwritefln("<white>*** Start generation %d</white>", generation);

        foreach(int i; 0..NP)
        {
            // Pick a,b,c different from i and each other
            int a, b, c;
            do { a = uniform(0, NP, rng); } while (a == i);
            do { b = uniform(0, NP, rng); } while (b == i || b == a);
            do { c = uniform(0, NP, rng); } while (c == i || c == a || c == b);

            // Fill trial vector
            // randomly pick the first parameter
            // This is called: DE/rand/1/bin
            // Apparently there are way better ones.
            int j = uniform(0, D, rng);
            for (int k = 1; k <= D; ++k)
            {
                float t = uniform(0.0f, 1.0f, rng);
                
                float F_here = F + F_stddev * rand_gauss(rng);
                float CR_here = CR + CR_stddev * rand_gauss(rng);

                // always at least parameter is changed
                // generation 0 must not crossover genes
                if ((t < CR_here || k == D) && (generation != 0)) 
                {
                    trial[j] = pop[c][j] + F_here * (pop[a][j] - pop[b][j]);
                }
                else
                {
                    trial[j] = pop[i][j];
                }
                j = (j + 1) % D;
            }

            // Evaluate trial's fitness
            cwritefln("   <lgreen>Evaluating</lgreen> individual: <grey>%s</grey>", trial);
            foreach(d; 0..D)
            {
                vars[d].setValue(trial[d], false);
            }
            
            build(settings);
            double fitness = evaluate(settings);

            if (fitness < bestFitness[i])
            {
                bestFitness[i] = fitness;
                pop2[i][] = trial[];
            }
            else
            {
                pop2[i][] = pop[i][];
            }
        }

        // Swap populations
        foreach(int n; 0..NP)
        {
            foreach(int d; 0..D)
            {
                pop[n][d] = pop2[n][d];
            }
        }

        cwriteln("Population =");

        // Display population
        foreach(int n; 0..NP)
        {
            cwritefln(" - Cost %.6f: %s", bestFitness[n], pop[n]);
        }

        // Display current best
        int ibest = -1;
        double bestFitnessOfPop = double.infinity;
        int bestIndividual = -1;
        foreach(n; 0..NP)
        {
            if (bestFitnessOfPop > bestFitness[n])
            {
                bestFitnessOfPop = bestFitness[n];
                bestIndividual = n;
            }
        }

        // Display best
        cwritefln("Current best solution has a fitness of: <yellow>%.6f</yellow>", bestFitnessOfPop);
    /*    foreach(int d; 0..D)
        {
            cwritefln("               - <lcyan>%s</lcyan> = <lmagenta>%s</lmagenta>", vars[d].name, pop[bestIndividual][d]);
        } */
        foreach(int d; 0..D)
        {
            cwritefln("<lred>%s</lred>", escapeCCL(vars[d].regenWithValue(vars[d].originalValue)));
        }
        foreach(int d; 0..D)
        {
            cwritefln("<lgreen>%s</lgreen>", escapeCCL(vars[d].regenWithValue(pop[bestIndividual][d])));
        }


        cwriteln;
    }
}

float rand_gauss (ref Random rng) 
{
    float v1,v2,s;

    do {
        v1 = 2.0 * uniform(0.0f, 1.0f, rng) - 1;
        v2 = 2.0 * uniform(0.0f, 1.0f, rng) - 1;

        s = v1*v1 + v2*v2;
    } while ( s >= 1.0 );

    if (s == 0.0)
        return 0.0;
    else
        return (v1*sqrt(-2.0 * std.math.log(s) / s));
}
