/**
Copyright: Auburn Sounds 2015-2018.
License:   All Rights Reserved.
*/
module main;

import std.stdio;
import std.math;
import std.path;
import std.random;
import std.file;
import std.algorithm;
import std.conv;
import std.string;
import std.process;

import consolecolors;

import bindbc.sdl;
import bindbc.sdl.mixer;
    


void usage()
{
    void flag(string arg, string desc, string possibleValues, string defaultDesc)
    {
        string argStr = format("        %s", arg);
        cwrite(argStr.lcyan);
        for(size_t i = argStr.length; i < 24; ++i)
            write(" ");
        cwritefln("%s".white, desc);
        if (possibleValues)
            cwritefln("                        Possible values: ".grey ~ "%s".yellow, possibleValues);
        if (defaultDesc)
            cwritefln("                        Default: ".grey ~ "%s".lcyan, defaultDesc);
        cwriteln;
    }
    cwriteln();
    cwriteln( "This is ".white ~ "abtest".lcyan ~ ": A/B sound testing tool.".white);
    cwriteln();
    cwriteln("USAGE".white);
    cwriteln("        abtest A.wav B.wav".lcyan);
    
    cwriteln();
    cwriteln();
    cwriteln("FLAGS".white);
    cwriteln();
    flag("-t --topic", "Select questions to ask.", "diffuse | focused | all | none", "all");
    flag("-a --amplify", "Scale differences between A and B.", null, "1.0");
    flag("-n          ", "Number of decisions/questions.", "5 to 12", "6");
    flag("-d --driver",  "Force a particular audio driver through SDL_AUDIODRIVER", null, null);
    flag("-h --help", "Shows this help", null, null);

    cwriteln();
    cwriteln("EXAMPLES".white);
    cwriteln();
    cwriteln("        # Normal comparison".lgreen);
    cwriteln("        abtest baseline.wav candidate.wav".lcyan);
    cwriteln();
    cwriteln("        # Comparison with only focused questionning and amplification of difference x2".lgreen);
    cwriteln("        # (this might not make any sense depending on the context)".lgreen);
    cwriteln("        abtest baseline.wav candidate.wav --amplify 2 --topic focused".lcyan);
    cwriteln();
    cwriteln("NOTES".white);
    cwriteln();
    cwriteln("      \"Diffuse\" questions are about snap decisions using 'System 1' intuitive judgement.");
    cwriteln("      \"Focused\" questions are about conscious rational analysis, using 'System 2' reasoning.");
    cwriteln("      See the book \"Thinking, Fast and Slow\" by Kahneman.");
    cwriteln("      Our opinion: this maps to two ways to hear sound.");
    cwriteln();
}

int main(string[] args)
{
    try
    {
        int numQuestions = 6;
        int topicMask = DIFFUSE | FOCUSED;
        string inputFileA = null;
        string inputFileB = null;
        float amplifyDiff = 1.0f;
        bool help = false;
        string driver = null;

        for (int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "-t" || arg == "-topic")
            {
                i++;
                if (args[i] == "diffuse")
                    topicMask = DIFFUSE;
                else if (args[i] == "focused")
                    topicMask = FOCUSED;
                else if (args[i] == "all")
                    topicMask = DIFFUSE | FOCUSED;
                else if (args[i] == "none")
                    topicMask = 0;
                else
                    throw new Exception("Bad topic, expected --topic {diffuse|focused|all|none}");
            }
            else if (arg == "-a" || arg == "-topic")
            {
                i++;
                amplifyDiff  =to!float(args[i]);
            }
            else if (arg == "-d" || arg == "--driver")
            {
                i++;
                driver = args[i];
            }
            else if (arg == "-n")
            {
                i++;
                numQuestions = to!int(args[i]);
            }
            else if (arg == "-h" || arg == "--help")
            {
                help = true;
            }
            else if (inputFileA is null)
            {
                inputFileA = arg;
            }
            else if (inputFileB is null)
            {
                inputFileB = arg;
            }
            else
            {
                error("Too many command-line arguments.");
                usage();
                return 1;
            }
        }

        cwriteln("First of all, make sure you are in a comfortable position, try to use your most");
        cwriteln("accurate headphones, and breathe.");
        cwriteln();

        if (help)
        {
            usage();
            return 0;
        }

        if (numQuestions < 5)
            throw new Exception("Number of questions too low. See --help for documentation.");

        if (inputFileA is null || inputFileB is null)
        {
            error("Missing files.");
            usage();
            return 1;
        }

        string[] questions = getQuestionsFromMask(topicMask, numQuestions);

        if (driver)
            environment["SDL_AUDIODRIVER"] = driver;

        // Transcode inputs to 32-bit WAV with audio-format.


        // Translate input to 32-bit float WAV file so that SDL_mixer can always read them
        string inputFileA_tr = buildPath(tempDir, "abtest-input-1.wav");
        string inputFileB_tr = buildPath(tempDir, "abtest-input-2.wav");
        transcode(inputFileA, inputFileA_tr, inputFileB, inputFileB_tr, amplifyDiff);

        // Load SDL
        SDLSupport ret = loadSDL();
        if(ret != sdlSupport) 
        {
            if(ret == SDLSupport.noLibrary)
                throw new Exception("SDL shared library failed to load");
            else if(SDLSupport.badLibrary)
                throw new Exception("One or more symbols failed to load.");
            else
                throw new Exception("Cannot load SDL, unknown error");
        }

        if(loadSDLMixer() != sdlMixerSupport) 
        {
            throw new Exception("SDL_mixer shared library failed to load");
        }

        if (driver)
        {
            cwriteln("*** Available audio drivers");
            for (int i = 0; i < SDL_GetNumAudioDrivers(); ++i) 
            {
                string driverName =  fromStringz(SDL_GetAudioDriver(i)).idup;
                bool selected = (driver == driverName);
                cwritefln("- Audio driver %s: %s", i, selected ? escapeCCL(driverName).yellow : escapeCCL(driverName).lcyan);
            }
            cwriteln;
        }
        
        if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) != 0) throw new Exception("SDL_Init failed");

        {
            int flags = Mix_Init(0); // whatever
            if ((flags & 0) != 0)
            {
                throw new Exception("Mix_Init failed");
            }
        }

        if (Mix_OpenAudio(44100, AUDIO_F32SYS, MIX_DEFAULT_CHANNELS, 1024) )
            throw new Exception("Mix_OpenAudio failed");

        // Load sounds
        Mix_Chunk* soundA = Mix_LoadWAV(toStringz(inputFileA_tr));
        cwriteln;
        Mix_Chunk* soundB = Mix_LoadWAV(toStringz(inputFileB_tr));
        cwriteln;

        // winner for each question
        // 0 => A
        // 1 => B
        // 0.5 => draw
        // NaN => skipped
        float[] choiceQuestion; 
        for (int question = 0; question < numQuestions; ++question)
        {
            // New question
            cwritefln("*** Question #%d".white, question + 1);

            // 1. Random exchange 
            Mix_Chunk* A = soundA;
            Mix_Chunk* B = soundB;
            bool randomlyExchanged = uniform(0, 100) >= 50;
            if (randomlyExchanged)
            {
                swap(A, B);
            }

            int currentSelected = 0; // A

            Mix_Volume(0, 255);
            Mix_Volume(1, 0);

            // 2. Play both at once, looping
            // Listen only to A at first
            Mix_FadeInChannel(0, A, 10000, 0);
            Mix_FadeInChannel(1, B, 10000, 0);
        //    Mix_Volume(0, 255);
        //    Mix_Volume(1, 0);

            bool choosen = false;
            bool badChoice = false;
            while(!choosen)
            {
                if (!badChoice)
                {
                    cwriteln;
                    cwritefln("  " ~ questions[question].white);
                    cwritefln("    * Type " ~ "'a'".yellow ~" to listen to A");
                    cwritefln("    * Type " ~ "'b'".yellow ~" to listen to B");
                    cwritefln("    * Type " ~ "' '".yellow ~" to choose current (%s) and move to next question", currentSelected == 0 ? "A" : "B" );
                    cwritefln("    * Type " ~ "'='".yellow ~" to declare a draw and move to next question",  );
                    cwritefln("    * Type " ~ "'s'".yellow ~" to skip this question",  );
                }
                badChoice = false;
                
                cwriteln;
                cwritef("    Choice? ".yellow);

                was_return:
                char choice = readCharFromStdin();
                
                switch (choice)
                {
                    case 'a':
                    case 'A':
                        Mix_Volume(0, 255);
                        Mix_Volume(1, 0);
                        currentSelected = 0;
                        break;
                    case 'b':
                    case 'B':
                        Mix_Volume(0, 0);
                        Mix_Volume(1, 255);
                        currentSelected = 1;
                        break;
                    case 's':
                        choosen = true;
                        choiceQuestion ~= float.nan;
                        break;
                    case '=':
                        choosen = true;
                        choiceQuestion ~= 0.5f;
                        break;
                    case ' ':

                        if (randomlyExchanged)
                            currentSelected = 1 - currentSelected;
                        choiceQuestion ~= currentSelected;
                        choosen = true;
                        break;
                    case '\n':
                    case '\r':
                    case '\t':
                        goto was_return;
                    default:
                        error("Bad choice. Choose 'a', 'b', ' ', or '=' instead.");
                        badChoice = true;
                }
               
            }   
            cwriteln;         
        }

        // Computer score
        float scoreA = 0, scoreB = 0;
        for (int question = 0; question < numQuestions; ++question)
        {
            if (!isNaN(choiceQuestion[question]))
            {
                if (choiceQuestion[question] == 0) scoreA += 1;
                if (choiceQuestion[question] == 1.0f) scoreB += 1;
                if (choiceQuestion[question] == 0.5f) { scoreA += 0.5f; scoreB += 0.5f; }
            }
        }

        // Display scores
        cwritefln("*** TOTAL RESULTS".white);
        cwritefln("  => %s got %s votes", inputFileA.lcyan, to!string(scoreA).yellow);
        cwritefln("  => %s got %s votes", inputFileB.lcyan, to!string(scoreB).yellow);
        cwriteln;
        cwritefln("*** DETAILS".white);

        for (int question = 0; question < numQuestions; ++question)
        {
            string result;
            if (choiceQuestion[question] == 0) result = inputFileA.lcyan;
            if (choiceQuestion[question] == 1.0f) result = inputFileB.lcyan;
            if (choiceQuestion[question] == 0.5f) result = "draw".yellow;
            if (isNaN(choiceQuestion[question])) result = "skipped".lred;
            cwritefln("    %60s => %s", questions[question], result);
        }
        cwriteln;

        Mix_CloseAudio();
        Mix_Quit();
        SDL_Quit();

        return 0;
    }
    catch(Exception e)
    {
        error(e.msg);
        return 1;
    }
}     
    
// Always return 
string[] getQuestionsFromMask(int mask, int numberOfQuestions)
{
    // First, all questions diffused, then all questions 

    // sorted from better questions to worse
    string[] DIFFUSE_QUESTIONS =
    [
        "What would you rather hear in " ~ "YOUR MUSIC".yellow ~ "?",
        "Which sound feels more " ~ "TRUE".yellow ~ "?",
        "What would you rather hear in your " ~ "CAR".yellow ~ "?",
        "What would you rather hear on the " ~ "RADIO".yellow ~ "?",
        "Which sound is the " ~ "WINNER".yellow ~ "?",
        "Which sound feels more " ~ "FREE".yellow ~ "?"
    ];

    // sorted from better questions to worse
    string[] FOCUSED_QUESTIONS =
    [
        "Which sound has the best "~"LOWS".yellow ~ "?",
        "Which sound has the best "~"HIGHS".yellow ~ "?",
        "Which sound is the "~"CLEANEST".yellow ~ "?",
        "Which sound has better "~"DYNAMICS".yellow ~ "?",
        "Which sound has better "~"PHASE".yellow ~ "?",
        "Which sound has the best "~"MIDS".yellow ~ "?",
    ];

    string GENERIC_QUESTION = "Which sound do you choose?";

    string[] result;
    int remain = numberOfQuestions;

    if (mask & DIFFUSE)
    {
        int numQuestionDiffuse = numberOfQuestions;
        if (mask & FOCUSED)
        {
            numQuestionDiffuse = (numberOfQuestions + 1) / 2;   
        }
        if (numQuestionDiffuse > 6)
            numQuestionDiffuse = 6;
        if (numQuestionDiffuse > remain)
            numQuestionDiffuse = remain;

        foreach(n; 0..numQuestionDiffuse)
            result ~= DIFFUSE_QUESTIONS[n];

        remain -= numQuestionDiffuse;
    }
    if (mask & FOCUSED)
    {
        int numQuestionFocused = remain;
        if (numQuestionFocused > 6)
            numQuestionFocused = 6;

        foreach(n; 0..numQuestionFocused)
            result ~= FOCUSED_QUESTIONS[n];

        remain -= numQuestionFocused;
    }

    // Add empty question
    foreach(n; 0..remain)
        result ~= GENERIC_QUESTION;
    return result;
}    



// Questions:
enum DIFFUSE = 1;
enum FOCUSED = 2;

void info(string msg)
{
    cwritefln("info: %s".white, escapeCCL(msg));
}

void warning(string msg)
{
    cwritefln("warning: %s".yellow, escapeCCL(msg));
}

void error(string msg)
{
    cwritefln("error: %s".lred, escapeCCL(msg));
}

// Transcode inputs to WAV
// check similarity
// apply diff factor
void transcode(string inputFileA, string outputFileA,
               string inputFileB, string outputFileB, double diffFactor)
{
    import audioformats;

    AudioStream inputA, outputA, inputB, outputB;
    inputA.openFromFile(inputFileA);
    inputB.openFromFile(inputFileB);
    if (inputA.isError)
        throw new Exception(inputA.errorMessage);
    if (inputB.isError)
        throw new Exception(inputB.errorMessage);

    float sampleRateA = inputA.getSamplerate();
    int channelsA     = inputA.getNumChannels();
    long lengthFramesA = inputA.getLengthInFrames();

    float sampleRateB = inputB.getSamplerate();
    int channelsB     = inputB.getNumChannels();
    long lengthFramesB = inputB.getLengthInFrames();

    if (channelsA != channelsB)         throw new Exception("Cannot compare files with different number of channels.");
    if (lengthFramesA != lengthFramesB) throw new Exception("Cannot compare files with different length.");
    if (sampleRateA != sampleRateB)     throw new Exception("Cannot compare files with different sample rate.");

    float[] bufA = new float[1024 * channelsA];
    float[] bufB = new float[1024 * channelsB];

    outputA.openToFile(outputFileA, AudioFileFormat.wav, sampleRateA, channelsA);
    outputB.openToFile(outputFileB, AudioFileFormat.wav, sampleRateB, channelsB);
    if (outputA.isError)
        throw new Exception(outputA.errorMessage);
    if (outputB.isError)
        throw new Exception(outputB.errorMessage);

    // Chunked encode/decode
    int totalFramesA = 0;
    int framesReadA;
    int totalFramesB = 0;
    int framesReadB;
    do
    {
        framesReadA = inputA.readSamplesFloat(bufA);
        framesReadB = inputB.readSamplesFloat(bufB);
        if (inputA.isError)
            throw new Exception(inputA.errorMessage);
        if (inputB.isError)
            throw new Exception(inputB.errorMessage);

        if (framesReadA != framesReadB)
            throw new Exception("Read different frame count between files.");

        if (diffFactor != 1.0f)
        {
            foreach(n; 0..framesReadA)
            {
                double diff = cast(double)(bufB[n]) - cast(double)(bufA[n]) * 0.5 * (diffFactor - 1.0);
                bufA[n] -= diff;
                bufB[n] += diff;
            }
        }

        outputA.writeSamplesFloat(bufA[0..framesReadA*channelsA]);
        outputB.writeSamplesFloat(bufB[0..framesReadB*channelsB]);
        if (outputA.isError)
            throw new Exception(outputA.errorMessage);
        if (outputB.isError)
            throw new Exception(outputB.errorMessage);

        totalFramesA += framesReadA;
        totalFramesB += framesReadB;
    } while(framesReadA > 0);
}

char readCharFromStdin()
{
    import core.stdc.stdio;
    return cast(char) fgetc(stdin);
}