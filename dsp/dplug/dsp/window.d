/**
* Various window types.
*
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.window;

import std.math;

import dplug.core.vec;

// Useful reference:
// https://en.wikipedia.org/wiki/Window_function
// These window generation functions are explicit with the end-points, 
// else it would be very easy to get confused and ignorant of these issues.

enum WindowType
{
    /// Constant window.
    rect,
    
    /// Triangular window. You probably want something better.
    bartlett,

    /// Good default choice if you lack ideas.
    hann,

    hamming,
    
    nuttall,
    
    blackmannNutall, 
    
    blackmannHarris,

    flatTopSR785,    // Flat top window

    // Kaiser-Bessel window, this one need a parameter alpha (typical values: 1.0 to 4.0)
    kaiserBessel,   

    // Older names

    /// Please use the new name instead.
    RECT = rect,

    /// Please use the new name instead.
    BARTLETT = bartlett,

    /// Please use the new name instead.
    HANN = hann,

    /// Please use the new name instead.
    HAMMING = hamming,

    /// Please use the new name instead.
    NUTTALL = nuttall,

    /// Please use the new name instead.
    BLACKMANN_NUTTALL = blackmannNutall,

    /// Please use the new name instead. 
    BLACKMANN_HARRIS = blackmannHarris,

    /// Please use the new name instead.
    FLATTOP_SR785 = flatTopSR785,

    /// Please use the new name instead.
    KAISER_BESSEL = kaiserBessel,
}


/// How "aligned" the window is in its support.
/// Very important, see Issue #236.
/// When choosing a window, you probably want to take a hard look about `WindowSymmetry` 
/// because it has implications for latency and correctness.
enum WindowAlignment
{
    /// The window is asymmetric and if it goes to zero (eg: HANN), it will have one zero 
    /// at the FIRST coefficient output[N-1].
    /// Its center is exactly at output[(N/2)-1] which is an integer delay for even window
    /// lengths.
    /// This loose one sample of latency, however it has the easiest to compute latency
    /// in most usage.
    right,

    /// The window is asymmetric and if it goes to zero (eg: HANN), it will have one zero 
    /// at the LAST coefficient output[N-1].
    /// Its center is exactly at output[(N/2)-1] which is an integer delay for even window
    /// lengths.
    /// This has the best latency characteristics, however this might make the latency
    /// computation itself trickier.
    left,    

    /// The window is symmetric and if it goes to zero (eg: HANN), it will have two zero 
    /// coefficients. 
    /// Its center is exactly between samples at position output[(N - 1)/2] which is NOT 
    /// an integer delay for even window lengths.
    /// Such a window might also break derivativeness.
    /// However FOR HISTORICAL REASONS THIS WAS THE DEFAULT SETTINGS.
    /// IT IS ADVISED NOT TO USE IT, FOR THE CONSEQUENCES ARE SUBTLE AND OFTEN HARMFUL.
    symmetric,
}


struct WindowDesc
{
public:
nothrow:
@nogc:

    /// Construct a window description, with a foolproof constructor.
    this(WindowType type, WindowAlignment alignment, float param = float.nan)
    {
        this.type = type;
        this.alignment = alignment;
        this.param = param;
    }

    /// Construct a window description, for support with previous
    deprecated("Because of subtle issues creeping with window end points, please provide an explicit WindowAlignment. Use the other WindowDesc constructor, see window.d for more information.") 
        this(WindowType type, float param = float.nan)
    {
        this.type = type;
        this.alignment = WindowAlignment.symmetric; // because it was the default before
        this.param = param;
    }

private:
    WindowType type;

    // TODO: this is a bad default! You'll probably want WindowAlignment.right instead.
    // Make sure it isn't used implicitely anymore.
    // Then deprecate WindowAlignment.symmetric.
    WindowAlignment alignment = WindowAlignment.symmetric; 

    float param;
}

/// Generates a window described by `windowDesc`, with periodicity of 
/// `outputWindow.length`.
void generateWindow(T)(WindowDesc desc, T[] outputWindow) pure nothrow @nogc
{
    int N = cast(int)(outputWindow.length);
    for (int i = 0; i < N; ++i)
    {
        outputWindow[i] = cast(T)(evalWindow(desc, i, N));
    }
}

/// Multiplies the given slice in-place by a window described by `windowDesc`,
/// whose periodicity is `inoutImpulse.length`.
void multiplyByWindow(T)(T[] inoutImpulse, WindowDesc windowDesc) pure nothrow @nogc
{
    int N = cast(int)(inoutImpulse.length);
    for (int i = 0; i < N; ++i)
    {
        inoutImpulse[i] *= evalWindow(windowDesc, i, N);
    }
}

deprecated void generateNormalizedWindow(T)(WindowDesc desc, T[] output) pure nothrow @nogc
{
    int N = cast(int)(output.length);
    T sum = 0;
    for (int i = 0; i < N; ++i)
    {
        output[i] = cast(T)(evalWindow(desc, i, N));
        sum += output[i];
    }
    T invSum = 1 / sum;
    for (int i = 0; i < N; ++i)
        output[i] *= invSum;    
}

// Note: N is the number of output samples, not necessarily the periodicity
double evalWindow(WindowDesc desc, int n, int N) pure nothrow @nogc
{
    final switch(desc.alignment) with (WindowAlignment)
    {
        case right:
            return evalWindowInternal(desc, n, N);

        case left:
            // left are just a rotation of the right-aligned window
            if (n == 0)
                return evalWindowInternal(desc, N - 1, N);
            else
                return evalWindowInternal(desc, n + 1, N);

        case symmetric:
            // Symmetric is just a shorter window
            return evalWindowInternal(desc, n, N - 1);
    }
}


struct Window(T) if (is(T == float) || is(T == double))
{
    void initialize(WindowDesc desc, int lengthInSamples) nothrow @nogc
    {
        _lengthInSamples = lengthInSamples;
        _window.reallocBuffer(lengthInSamples);
        generateWindow!T(desc, _window);
    }

    ~this() nothrow @nogc
    {
        _window.reallocBuffer(0);
    }

    double sumOfWindowSamples() pure const nothrow @nogc
    {
        double result = 0;
        foreach(windowValue; _window)
            result += windowValue;
        return result;
    }

    @disable this(this);

    T[] _window = null;
    int _lengthInSamples;
    alias _window this;
}


private:

// Generates WindowAlignment.right window types.
// N is the periodicity.
// Does NOT look at desc.alignment, which is taken care of in `evalWindow`.
double evalWindowInternal(WindowDesc desc, int n, int N) pure nothrow @nogc
{
    static double computeKaiserFunction(double alpha, int n, int N) pure nothrow @nogc
    {
        static double I0(double x) pure nothrow @nogc
        {
            double sum = 1;
            double mx = x * 0.5;
            double denom = 1;
            double numer = 1;
            for (int m = 1; m <= 32; m++) 
            {
                numer *= mx;
                denom *= m;
                double term = numer / denom;
                sum += term * term;
            }
            return sum;
        }

        double piAlpha = PI * alpha;
        double C = 2.0 * n / cast(double)N - 1.0; 
        double result = I0(piAlpha * sqrt(1.0 - C * C)) / I0(piAlpha);
        return result;
    }

    final switch(desc.type)
    {
        case WindowType.RECT:
            return 1.0;

        case WindowType.BARTLETT:
        {
            double nm1 = cast(double)N / 2;
            return 1 - abs(n - nm1) / nm1;
        }

        case WindowType.HANN:
        {
            double phi = (2 * PI * n ) / N;
            return 0.5 - 0.5 * cos(phi);
        }

        case WindowType.HAMMING:
        {
            double phi = (2 * PI * n ) / N;
            return 0.54 - 0.46 * cos(phi);
        }

        case WindowType.NUTTALL:
        {
            double phi = (2 * PI * n ) / N;
            return 0.355768 - 0.487396 * cos(phi) + 0.144232 * cos(2 * phi) - 0.012604 * cos(3 * phi);            
        }

        case WindowType.BLACKMANN_HARRIS:
        {
            double phi = (2 * PI * n ) / N;
            return 0.35875 - 0.48829 * cos(phi) + 0.14128 * cos(2 * phi) - 0.01168 * cos(3 * phi);
        }

        case WindowType.BLACKMANN_NUTTALL:
        {
            double phi = (2 * PI * n ) / N;
            return 0.3635819 - 0.4891775 * cos(phi) + 0.1365995 * cos(2 * phi) - 0.0106411 * cos(3 * phi);
        }

        case WindowType.FLATTOP_SR785:
        {
            double phi = (2 * PI * n ) / cast(double)N;
            return 1 - 1.93 * cos(phi) 
                     + 1.29 * cos(2 * phi) 
                     - 0.388 * cos(3 * phi) 
                     + 0.028 * cos(4 * phi);
        }

        case WindowType.KAISER_BESSEL:
        {
            return computeKaiserFunction(desc.param, n, N);
        }
    }
}


// Tests the general shape of windows.
unittest
{
    void checkIsSymmetric(T)(T[] inp)
    {
        for (int i = 0; i < inp.length/2; ++i)
        {
            // Window generation should be precise
            assert(approxEqual(inp[i], inp[$-1-i], 1e-10));
        }
    }

    void checkMaxInCenter(T)(T[] inp)
    {
        bool odd = (inp.length & 1) != 0;
        if (odd)
        {
            for (int i = 0; i < inp.length/2; ++i)
            {
                assert(inp[i] <= inp[inp.length/2]);
                assert(inp[$-1-i] <= inp[inp.length/2]);
            }
        }
        else
        {
            for (int i = 0; i < inp.length/2-1; ++i)
            {
                // take either of the centers
                assert(inp[i] <= inp[inp.length/2-1]);
                assert(inp[$-1-i] <= inp[inp.length/2-1]);
            }
        }
    }

    void testAllWindows(T)(int size)
    {
        Window!T window;

        foreach(type; WindowType.min..WindowType.max+1)
        {
            foreach(alignment; WindowAlignment.min..WindowAlignment.max+1)
            {
                // Note: only Kaiser-Bessel have a parameter for now, so take 2
                WindowDesc desc = WindowDesc(cast(WindowType)type, 
                                             cast(WindowAlignment)alignment, 
                                             2.0);

                window.initialize(desc, size);

                //import std.stdio;
                //writeln(desc);

                final switch(alignment) with (WindowAlignment)
                {
                    case WindowAlignment.symmetric:
                        checkIsSymmetric(window[0..$]);
                        checkMaxInCenter(window[0..$]);
                        break;

                    case WindowAlignment.right:
                        checkIsSymmetric(window[1..$]);
                        checkMaxInCenter(window[1..$]);
                        break;

                    case WindowAlignment.left:
                        checkIsSymmetric(window[0..$-1]);
                        checkMaxInCenter(window[0..$-1]);
                        break;
                }
            }
        }
    }

    testAllWindows!float(64);
    testAllWindows!double(32);

    // It should be possible to generate odd-sized window, 
    // though in practice with WindowAlignement you don't need them.
    testAllWindows!float(5);
}
