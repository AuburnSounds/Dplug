/**
    UDAs to label @tuning constants. Most of them, except
    @tuning, are designed to let the `evolve` tool know that
    they should be ignored from evolution.

    See also: the `evolve` tool and related presentation
              at DConf 2025.

    Copyright: Guillaume Piolat 2024-2026.
    License: http://www.boost.org/LICENSE_1_0.txt, BSL-1.0
*/
module dplug.dsp.udas;


/** 
    This constant has an effect on fitness (can be software 
    performance but often is the _sound_ of a plugin) and 
    MUST be choosen carefully. It is important enough to
    warrant highlighting it with this semantic flag.

    This is used when `evolve` parses the project to get 
    back all tuning variables.
*/ 
struct tuning
{
}

// Every such @tuning variable can get more precise 
// semantics with those other tags below, they all mean to 
// remove the variable from selection for evolution without
// a comment to justify why every time.

/** 
    This @tuning variable was important and is now exposed 
    as an (possibly internal) plug-in parameter instead of a 
    varialbe/constant, so there is no single best value and 
    it should not evolve. It is now user-defined.
*/
struct promotedToParameter
{
}

/** 
    This @tuning variable was already tuned and we're 100% 
    sure this is the best value, whatever happens. It should 
    not evolve, for we have a rare certainty about it.
*/
struct optimal
{
}

/**
   This @tuning variable is of historical value, for example 
   a V1 tuning. Changing it would break session compatiblity
   and/or user expectations.

   Thus, it should not evolve.
*/
struct historical
{
}

/** 
    This @tuning variable affects of lot of oher tuning 
    constants, and as such it's tricky to evolve. It
    probably shouldn't be done.
*/
struct manyDependees
{
}

/**
    This @tuning variable changes audio plug-in latency and 
    as such it shall not evolve until the fitness measure we 
    use support that.
*/
struct changesLatency
{
}

/**
    This @tuning variable is ONLY subjective.
    There is no objective measure yet that can choose a 
    better value for this, for example if this is a 
    degradation.
    Example: adding noise is often a negative until 
             stylistic/genre choices enable it.
    So, not evolving, should it.
*/
struct subjective
{
}

/** 
    We don't trust either the evolution algorithm or the
    fitness measure to evolve this @tuning variable.
    A very reasonable stance.
*/
struct ignore
{
}

/** 
    Changing this @tuning variable doesn't seem to change 
    the objective measure, yet the variable was subjectively 
    tuned successfully.
    Not sure what happens, any situation where our 
    understanding fail.
*/
struct dubious
{
}

/** 
    This tuning variable affects presentation or UX, not 
    sound or performance. It should be tuned for aesthetics 
    by a human.
*/
struct graphical
{
}