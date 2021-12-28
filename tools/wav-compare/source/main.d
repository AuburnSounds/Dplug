import std.stdio;
import std.algorithm;
import std.math;
import std.string;
import std.array;
import std.conv;
import std.file;

import waved;
import dplug.core;
import dplug.graphics;
import dplug.dsp;
import colorize;


void usage()
{
    writeln("Usage:");
    writeln("        wav-compare fileA.wav fileB.wav [-o diff.wav]");
    writeln();
    writeln("Description:");
    writeln("        This qualifies the difference between two files.");
    writeln;
    writeln("Flags:");
    writeln("        -h, --help   Shows this help");
    writeln("        -o <file>    Write instantaneous peak difference in a WAV file (default: no)");
    writeln("        -s <file>    Output spectrogram (default: no)");
    writeln("        -sw <width>  Spectrogram width (default: length / 512)");
    writeln("        -sh <height> Spectrogram height (default: 800)");
    writeln("        --strip <s>  Strip s seconds of the start. Avoid initialization conditions.");
    writeln("        --quiet      Less verbose output, just output RMS error (default: verbose)");    
    writeln;
}

int main(string[] args)
{
    try
    {
        bool help = false;
        string[] files = null;
        string outDiffFile = null;
        bool quiet = false;
        double stripSecs = 0.0;
        string spectrogramPath = null;
        int sh = 800;
        int sw = 0;

        for (int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "-h")
                help = true;
            else if (arg == "--quiet")
            {
                quiet = true;
            }
            else if (arg == "-o")
            {
                i += 1;
                outDiffFile = args[i];
            }
            else if (arg == "--strip")
            {
                i += 1;
                stripSecs = to!double(args[i]);
            }
            else if (arg == "-sw")
            {
                i += 1;
                sw = to!int(args[i]);
            }
            else if (arg == "-sh")
            {
                i += 1;
                sh = to!int(args[i]);
            }
            else if (arg == "--strip")
            {
                i += 1;
                stripSecs = to!double(args[i]);
            }
            else if (arg == "-s")
            {
                i += 1;
                spectrogramPath = args[i];
            }
            else
                files ~= arg;
        }

        if (help)
        {
            usage();
            return 1;
        }

        if (files.length < 2)
            throw new Exception("2 wav files must be provided");

        if (files.length > 2)
            throw new Exception("2 wav files must be provided");

        string fileA = files[0];
        string fileB = files[1];

        Sound soundA = decodeSound(fileA);
        Sound soundB = decodeSound(fileB);

        if (fileA == fileB)
            cwriteln(format("warning: comparing %s with itself, do you mean that?", fileA).color(fg.light_yellow));

        if (soundA.channels != soundB.channels)
            throw new Exception(format("%s and %s have different channel count", fileA, fileB));

        if (soundA.sampleRate != soundB.sampleRate)
            throw new Exception(format("%s and %s have different sample rate", fileA, fileB));

        if (soundA.samples.length != soundB.samples.length)
            throw new Exception(format("%s and %s have different length", fileA, fileB));

        int startSample = cast(int)(stripSecs * soundA.sampleRate);

        if (sw == 0)
            sw = soundB.lengthInFrames() / 512;

        // Normalize both sounds by the same amount
        // However we don't apply this factor yet to avoid introducing noise.
        // TODO: harmonic square root?
        real nFactor = (normalizeFactor(soundA) + normalizeFactor(soundB) ) * 0.5f;
        int channels = soundA.channels;

        int N = cast(int)(soundA.samples.length);

        // No need to deinterleave stereo, since the peak difference is what interest us
        real[] difference = new real[N];
        float[] diffFileContent = new float[N];

        // Note: the WAV output is an absolute value (simply A minus B)
        // while the RMS and peak numbers are given against normalized A and B
        for (int i = 0; i < N; ++i)
        {
            real diff = cast(real)soundA.samples[i] - soundB.samples[i];
            diffFileContent[i] = diff;
            difference[i] = nFactor * abs(diff);
        }

        if (startSample >= N)
        {
            throw new Exception(format("Using --strip with a duration longer than the content"));
        }

        real maxPeakDifference = reduce!max(difference[startSample..$]);//!("a > b")(difference).front;

        real rms = 0;
        for (int i = startSample; i < N; ++i)
            rms +=  difference[i] * difference[i];
        rms = sqrt(rms / (N - startSample));

        real peak_dB = convertLinearGainToDecibel(maxPeakDifference);
        real rms_dB = convertLinearGainToDecibel(rms);

        if (!quiet)
        {
            cwriteln;
            cwritefln(" Comparing %s vs %s", fileA.color(fg.light_white), fileB.color(fg.light_white));
            cwriteln();
            cwriteln ("    =================================".color(fg.light_white));
            cwritefln("        RMS difference = %s", format("%.2f dB", rms_dB).color(fg.light_yellow));
            cwriteln ("    =================================".color(fg.light_white));
            cwriteln();

            cwriteln(" An opinion from the comparison program:");
            cwriteln(format("    \"%s\"", getComment(rms_dB, peak_dB)).color(fg.light_cyan));
            cwriteln();

            if (isFinite(peak_dB - rms_dB))
                cwritefln(" => (Peak - RMS) Crest difference = %s", format("%.2f dB", peak_dB - rms_dB).color(fg.light_green));
        }
        else
        {
            writefln(format("%.2f dB", rms_dB));
        }

        // write absolute difference into
        if (outDiffFile)
        {
            Sound(soundA.sampleRate, channels, diffFileContent).encodeWAV(outDiffFile);

            if (!quiet)
            {
                cwritefln(" => Difference written in %s (max rel. peak = %s)", 
                          outDiffFile.color(fg.light_white),
                          format("%.2f dB", peak_dB).color(fg.light_green));
            }
        }

        if (spectrogramPath)
        {
            // Note: this will only show the left channel. 
            outputSpectrumOfDifferences(soundA, soundB, spectrogramPath, sw, sh, nFactor, quiet);
        }

        if (!quiet) cwriteln;
        return 0;
    }
    catch(Exception e)
    {
        cwriteln;
        cwritefln(format("error: %s", e.msg).color(fg.light_red));
        cwriteln;
        usage();
        writeln;
        return 1;
    }
}

real normalizeFactor(Sound s)
{
    int N = cast(int)(s.samples.length);

    // Compute RMS
    real rms = 0;
    for (int i = 0; i < N; ++i)
        rms += (cast(real)s.samples[i]) * s.samples[i];
    rms = sqrt(rms / N);
    return 1.0f / (rms + 1e-10f);
}

string getComment(float rms_dB, float peak_dB)
{
    if (rms_dB > -10)
    {
        return "This is a big difference, should be something that changes the phase, or something very audible (possibly an error)!";
    }
    else if (rms_dB > -30)
    {
        return "This might be a hearable difference inside your DAW, but this might also require an A/B test if it's mostly a phase thing.";
    }
    else if (rms_dB > -50)
    {
        return "This might be a bit hard to hear but perhaps easy to spot in an A/B test.";
    }
    else if (rms_dB > -80)
    {
        return "This is probably very subtle to hear and I'd say this requires an A/B test!";
    }
    else if (rms_dB > -110)
    {
        return "I doubt you may be able to hear it, but maybe do not take my word for it.";
    }
    else if (!isFinite(rms_dB))
    {
        return "This is identical up to -inf dB. There is nothing to listen to, because there is no difference.";
    }
    else 
    {
        return "I wouldn't even bother trying to hear this difference. It must be incredibly subtle.";
    }
}

void outputSpectrumOfDifferences(Sound soundA, Sound soundB, string spectrogramPath, int sw, int sh, real nFactor, bool quiet)
{
    if (!quiet)
    {
        cwriteln;
        cwritef(" Create a difference PNG in %s", spectrogramPath.color(fg.light_white));        
    }

    assert(soundA.sampleRate == soundB.sampleRate);
    assert(soundA.lengthInFrames == soundB. lengthInFrames);

    float samplerate = soundA.sampleRate;
    int N = soundA.lengthInFrames();
    float[] diff = new float[N];
    float[] A = soundA.channel(0);
    float[] B = soundB.channel(0);
    foreach(n; 0..N)
    {
        diff[n] = nFactor * (cast(real)A[n] - B[n]); // so that the relative difference is seen.
    }

    // What is the analysisPeriod that let us hit sw as length?
    int analysisPeriod = cast(int)(N / sw);
    if (analysisPeriod < 1) analysisPeriod = 1;

    // Good window size for this?
    int windowSize = (analysisPeriod * 2);

    // window size cannot be inferior to 20ms
    int minWindowSize = cast(int)(0.5f + samplerate * 0.020);
    if (windowSize < minWindowSize)
        windowSize = minWindowSize;

    int fftSize = nextPow2HigherOrEqual(windowSize);
    bool zeroPhaseWindowing = false;
    FFTAnalyzer!float fft;
    fft.initialize(windowSize, fftSize, analysisPeriod, WindowDesc(WindowType.hann, WindowAlignment.right), zeroPhaseWindowing);

    int half = fftSize/2 + 1;

    // Create an intermediate image
    int iheight = half;
    int iwidth = (N + analysisPeriod - 1) / analysisPeriod; // max number of analysis

    OwnedImage!RGBA temp = new OwnedImage!RGBA(iwidth, iheight);
    auto coeffs = new Complex!float[half];

    int hops = 0;
    foreach(n; 0..N)
    {
        if (fft.feed(diff[n], coeffs))
        {
            for (int c = 0; c < half; ++c)
            {
                temp[hops, half-1-c] = coeff2Color(coeffs[c]);
            }
            hops++;
        }
    }

    if (!quiet)
    {
        cwriteln;
        cwritef(" * Resize to %s x %s", sw, sh);
    }

    // TODO: log-frequency

    OwnedImage!RGBA spectrumImage = new OwnedImage!RGBA(sw, sh);
    ImageResizer resizer;
    resizer.resizeImageGeneric(temp.toRef, spectrumImage.toRef);

    if (!quiet)
    {
        cwriteln;
        cwritef(" * Convert to PNG");
    }
    ubyte[] png = convertImageRefToPNG(spectrumImage.toRef());
    scope(exit) freeSlice(png);
    std.file.write(spectrogramPath, png);

    if (!quiet) writeln;
}

 static immutable RGBA[8] dB_COLORS =
 [
    RGBA(255, 255, 255, 255), // 0db => white
    RGBA(255, 0,     0, 255), // -20db => red
    RGBA(255, 255,   0, 255), // -40db => yellow
    RGBA(0,   255,   0, 255), // -60db => green
    RGBA(0,   255, 255, 255), // -80db => cyan
    RGBA(0,     0, 255, 255), // -100db => blue
    RGBA(255,   0, 255, 255), // -120db => magenta
    RGBA(255,   0, 255, 255), // -140db or below => black
];

RGBA coeff2Color(Complex!float c)
{
    double len = abs(c);
    double dB = -convertLinearGainToDecibel!double(len);
    if (dB < 0) dB = 0;
    if (dB > 139.99f) dB = 139.99f;
    dB /= 20.0;
    int icol = cast(int)dB;
    ubyte t = cast(ubyte)( (dB - icol) * 256.0 );
    return blendColor(dB_COLORS[icol+1], dB_COLORS[icol], t);
}