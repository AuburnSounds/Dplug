import std.stdio;
import std.algorithm;
import std.math;
import std.string;
import std.array;
import std.conv;
import std.file;
import std.complex;

import dplug.core;
import dplug.graphics;
import dplug.dsp;
import dplug.fft;
import consolecolors;
import audioformats;


void usage()
{
    void flag(string arg, string desc, string possibleValues, string defaultDesc)
    {
        string argStr = format("        %s", arg);
        cwrite(argStr.lcyan);
        for(size_t i = argStr.length; i < 28; ++i)
            write(" ");
        cwritefln("%s".white, desc);
        if (possibleValues)
            cwritefln("                            Possible values: ".grey ~ "%s".yellow, possibleValues);
        if (defaultDesc)
            cwritefln("                            Default: ".grey ~ "%s".lcyan, defaultDesc);
        cwriteln;
    }

    cwriteln();
    cwriteln( "This is the ".white ~ "wav-compare".lcyan ~ " tool: it compares audio files for small differences.".white);
    cwriteln();
    cwriteln("FLAGS".white);
    cwriteln();
    flag("-o --output", "Write output spectrogram", "PNG file path", "no");
    flag("-ow --output-width", "Spectrogram PNG width", null, "length / 512");
    flag("-oh --output-height", "Spectrogram PNG height", null, "800");
    flag("-s  --skip", "Skip seconds of the input start Avoid initialization conditions", "seconds", "0.0");
    flag("-d  --duration", "Strip to a certain duration", "seconds", "max");
    flag("-q  --quiet", "Just output RMS error", null, "verbose");
    flag("-h --help", "Shows this help", null, null);

    cwriteln();
    cwriteln("EXAMPLES".white);
    cwriteln();
    cwriteln("        # Compare two WAV files, display RMS and comment".green);
    cwriteln("        wav-compare A.wav B.wav".lcyan);
    cwriteln();
    cwriteln("        # Compare two WAV files, quietly make an output spectrogram of the difference".green);
    cwriteln("        wav-compare A.wav B.wav -o spectrogram.png --quiet".lcyan);
    cwriteln();
    cwriteln("        # Compare two WAV files, skip the first 3 seconds, take 8 seconds of sound".green);
    cwriteln("        wav-compare A.wav B.wav --skip 3 --duration 8".lcyan);

    cwriteln();
    cwriteln("NOTES".white);
    cwriteln();
    cwriteln("      The palette of the spectrogram is as follow:".grey);
    cwriteln("      - white   means    0dB difference".white);
    cwriteln("      - red     means  -20dB difference".red);
    cwriteln("      - yellow  means  -40dB difference".yellow);
    cwriteln("      - green   means  -60dB difference".green);
    cwriteln("      - cyan    means  -80dB difference".lcyan);
    cwriteln("      - blue    means -100dB difference".blue);
    cwriteln("      - magenta means -120dB difference".magenta);
    cwriteln("      - black   means -140dB difference or below".grey);
    cwriteln();
    cwriteln();
}

int main(string[] args)
{
    try
    {
        bool help = false;
        string[] files = null;
        bool quiet = false;
        double skipSecs = 0.0;
        double durationSecs = -1.0;
        string spectrogramPath = null;
        int sh = 800;
        int sw = 0;

        for (int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "-h" || arg == "--help")
            {
                help = true;
            }
            else if (arg == "-q" || arg == "--quiet")
            {
                quiet = true;
            }
            else if (arg == "-o" || arg == "--output")
            {
                i += 1;
                spectrogramPath = args[i];
                if (spectrogramPath.length < 4 || spectrogramPath[$-4..$] != ".png")
                    throw new Exception(format("Expected a PNG file path after %s", arg));
            }
            else if (arg == "-s" || arg == "--strip")
            {
                i += 1;
                skipSecs = to!double(args[i]);
            }
            else if (arg == "-ow" || arg == "--output-width")
            {
                i += 1;
                sw = to!int(args[i]);
            }
            else if (arg == "-oh" || arg == "--output-height")
            {
                i += 1;
                sh = to!int(args[i]);
            }
            else if (arg == "-d" || arg == "--duration")
            {
                i += 1;
                if (args[i] == "max")
                    durationSecs = -1;
                else
                    durationSecs = to!double(args[i]);
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
            cwriteln(format("warning: comparing %s with itself, do you mean that?", fileA).yellow);

        if (soundA.channels != soundB.channels)
            throw new Exception(format("%s and %s have different channel count", fileA, fileB));

        if (soundA.sampleRate != soundB.sampleRate)
            throw new Exception(format("%s and %s have different sample rate", fileA, fileB));

        if (soundA.samples.length != soundB.samples.length)
            throw new Exception(format("%s and %s have different length", fileA, fileB));

        // Strip inpujt
        {
            if (durationSecs < 0)
                durationSecs = soundA.lengthInSeconds() + 1;

            int startSample = cast(int)(skipSecs * soundA.sampleRate);
            int stopSample  = cast(int)((skipSecs + durationSecs) * soundA.sampleRate);

            if (startSample < 0) startSample = 0;
            if (stopSample > soundA.lengthInFrames) stopSample = soundA.lengthInFrames();
            if (stopSample < startSample) stopSample = startSample;

            int sampleDuration = stopSample - startSample;
            if (sampleDuration == 0)
            {
                throw new Exception(format("Selected input has zero length. Use --skip and --duration differently"));
            }

            soundA = soundA.stripSound(startSample, stopSample);
            soundB = soundB.stripSound(startSample, stopSample);
        }


        if (sw == 0)
            sw = (soundB.lengthInFrames() / 512);

        // Normalize both sounds by the same amount
        // However we don't apply this factor yet to avoid introducing noise.
        // TODO: harmonic square root?
        // Note: normalization factor is considered for the whole input, not the stripped input.
        real nFactor = (normalizeFactor(soundA) + normalizeFactor(soundB)) * 0.5f;
        int channels = soundA.channels;

        int N = cast(int)(soundA.samples.length);

        // No need to deinterleave stereo, since the peak difference is what interest us
        real[] difference = new real[N];

        // Note: the WAV output is an absolute value (simply A minus B)
        // while the RMS and peak numbers are given against normalized A and B
        for (int i = 0; i < N; ++i)
        {
            real diff = cast(real)soundA.samples[i] - soundB.samples[i];
            difference[i] = nFactor * abs(diff);
        }

        real maxPeakDifference = reduce!max(difference[0..$]);//!("a > b")(difference).front;

        real rms = 0;
        for (int i = 0; i < N; ++i)
            rms +=  difference[i] * difference[i];
        rms = sqrt(rms / N);

        real peak_dB = convertLinearGainToDecibel(maxPeakDifference);
        real rms_dB = convertLinearGainToDecibel(rms);

        if (!quiet)
        {
            cwriteln;
            cwritefln(" Comparing %s vs %s", fileA.white, fileB.white);
            cwriteln();
            cwriteln ("    =================================".white);
            cwritefln("        RMS difference = %s", format("%.2f dB", rms_dB).yellow);
            cwriteln ("    =================================".white);
            cwriteln();

            cwriteln(" An opinion from the comparison program:");
            cwriteln(format("    \"%s\"", getComment(rms_dB, peak_dB)).lcyan);
            cwriteln();
        }
        else
        {
            writefln(format("%.2f dB", rms_dB));
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
        cwritefln(format("error: %s", escapeCCL(e.msg)).lred);
        usage();
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

alias CoeffType = double;

void outputSpectrumOfDifferences(Sound soundA, Sound soundB, string spectrogramPath, int sw, int sh, real nFactor, bool quiet)
{
    if (!quiet)
    {
        cwriteln;
        cwritef(" Create a difference PNG in %s", spectrogramPath.white);        
    }

    assert(soundA.sampleRate == soundB.sampleRate);
    assert(soundA.lengthInFrames == soundB. lengthInFrames);

    float sampleRate = soundA.sampleRate;
    int N = cast(int) soundA.lengthInFrames();
    CoeffType[] diff = new CoeffType[N];
    double[] A = soundA.channel(0);
    double[] B = soundB.channel(0);
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
    int minWindowSize = cast(int)(0.5f + sampleRate * 0.020);
    if (windowSize < minWindowSize)
        windowSize = minWindowSize;

    int fftSize = nextPow2HigherOrEqual(windowSize) * 2;
    bool zeroPhaseWindowing = false;
    FFTAnalyzer!CoeffType fft;
    fft.initialize(windowSize, fftSize, analysisPeriod, WindowDesc(WindowType.hann, WindowAlignment.right), zeroPhaseWindowing);

    int half = fftSize/2 + 1;

    // Create an intermediate image
    int iheight = half;
    int iwidth = (N + analysisPeriod - 1) / analysisPeriod; // max number of analysis

    OwnedImage!RGBA temp = new OwnedImage!RGBA(iwidth, iheight);
    auto coeffs = new Complex!CoeffType[half];

    int hops = 0;
    foreach(n; 0..N)
    {
        if (fft.feed(diff[n], coeffs))
        {
            for (int c = 0; c < half; ++c)
            {
                temp[hops, c] = coeff2Color(coeffs[c]);
            }
            hops++;
        }
    }

    if (!quiet)
    {
        cwriteln;
        cwritef(" * Resize to %s x %s...".grey, sw, sh);
    }

    // Remap image in log-frequency.
    OwnedImage!RGBA temp2 = new OwnedImage!RGBA(iwidth, iheight);
    for (int y = 0; y < iheight; ++y)
    {
        // Sample temp in ERB scale, linearly.
        int lowestBin = 0;
        int nyquistBin = half-1;
        double lowestBinFreq = convertFFTBinToFrequency(lowestBin, fftSize, sampleRate);
        double nyquistBinFreq = convertFFTBinToFrequency(nyquistBin, fftSize, sampleRate);
        double lowestBinERB = convertHzToERBS(lowestBinFreq);
        double nyquistBinERB = convertHzToERBS(nyquistBinFreq);
        double thisBinERB = lowestBinERB + (nyquistBinERB - lowestBinERB) * (y / (iheight - 1.0));
        double thisBinHz = convertERBSToHz(thisBinERB);
        float hereBin = convertFrequencyToFFTBin(thisBinHz, sampleRate, fftSize);
        if (hereBin < 0) hereBin = 0;
        if (hereBin > nyquistBin - 0.01f) hereBin = nyquistBin - 0.01f;
        int ibin = cast(int)hereBin;
        ubyte t = cast(ubyte)( (hereBin - ibin) * 256.0 );
        for (int x = 0; x < iwidth; ++x)
        {
            temp2[x, iheight-1-y] = blendColor(temp[x, ibin+1], temp[x, ibin], t);
        }
    }

    OwnedImage!RGBA spectrumImage = new OwnedImage!RGBA(sw, sh);
    ImageResizer resizer;
    resizer.resizeImageGeneric(temp2.toRef, spectrumImage.toRef);

    if (!quiet)
    {
        cwriteln;
        cwritef(" * Convert to PNG...".grey);
    }
    ubyte[] png = convertImageRefToPNG(spectrumImage.toRef());
    scope(exit) freeSlice(png);
    std.file.write(spectrogramPath, png);

    if (!quiet) writeln;
}

 static immutable RGBA[8] dB_COLORS =
 [
    RGBA(255, 255, 255, 255), // 0db => white
    RGBA(255, 128, 128, 255), // -20db => red
    RGBA(255, 255,   0, 255), // -40db => yellow
    RGBA(64,   255, 64, 255), // -60db => green
    RGBA(0,   200, 200, 255), // -80db => cyan
    RGBA(16,   16, 255, 255), // -100db => blue
    RGBA(128,   0, 128, 255), // -120db => magenta
    RGBA(0,   0, 0, 255), // -140db or below => black
];

RGBA coeff2Color(Complex!CoeffType c)
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

/// Returns: Another Sound with stripped input.
Sound stripSound(const(Sound) input, int start, int end) pure nothrow
{
    Sound output;
    int N = input.lengthInFrames();
    assert(start >= 0);
    assert(end >= start);
    assert(N >= end);
    int M = end - start;
    output.sampleRate = input.sampleRate;
    output.samples = new double[M * input.channels];
    output.channels = input.channels;
    for (int ch = 0; ch < input.channels; ++ch)
    {
        for (int n = 0; n < M; ++n)
            output.sample(ch, n) = input.sample(ch, n + start);
    }
    return output;
}

// https://en.wikipedia.org/wiki/Equivalent_rectangular_bandwidth
double convertHzToERBS(double hz)
{
    return 11.17268 * log(1.0 +  (hz * 46.06538) / (hz + 14678.49) );
}

double convertERBSToHz(double erbs)
{
    return 676170.4 / (47.06538 - exp(0.08950404 * erbs)) - 14678.49;
}

// Compatibility with former wave-d API
struct Sound
{   
    float sampleRate;
    int channels;
    double[] samples;

    int lengthInFrames() pure const nothrow @nogc
    {
        return cast(int)( cast(long)(samples.length) / channels);
    }

    /// Returns: Length in seconds.
    double lengthInSeconds() pure const nothrow
    {
        return lengthInFrames() / cast(double)sampleRate;
    }

    /// Direct sample access.
    ref inout(double) sample(int chan, int frame) pure inout nothrow @nogc
    {
        assert(cast(uint)chan < channels);
        return samples[frame * channels + chan];
    }

    /// Allocates a new array and put deinterleaved channel samples inside.
    double[] channel(int chan) pure const nothrow
    {
        int N = lengthInFrames();
        double[] c = new double[N];
        foreach(frame; 0..N)
            c[frame] = this.sample(chan, frame);
        return c;
    }
}


// Decode a whole stream at once.
Sound decodeSound(string file)
{
    AudioStream input;
    input.openFromFile(file);

    int channels = input.getNumChannels();
    float sampleRate = input.getSamplerate();

    double[] samples; 

    double[] buf = new double[1024 * channels];

    // Chunked encode/decode
    int totalFrames = 0;
    int framesRead;
    do
    {
        framesRead = input.readSamplesDouble(buf);
        samples ~= buf[0..framesRead*channels]; 
        totalFrames += framesRead;
    } while(framesRead > 0);

    Sound sound;
    sound.samples = samples;
    sound.sampleRate = sampleRate;
    sound.channels = channels;

    return sound;
}
