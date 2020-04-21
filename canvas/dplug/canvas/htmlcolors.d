/**
* Copyright: Copyright Chris Jones 2020.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.canvas.htmlcolors;

import std.math: PI, floor;
import core.stdc.stdio : sscanf;
public import dplug.graphics.color;

/// Parses a HTML color and gives back a RGBA color.
///
/// Params:
///     htmlColorString = A CSS string describing a color.
///
/// Returns:
///     A 32-bit RGBA color, with each component between 0 and 255.
///
/// See_also: https://www.w3.org/TR/css-color-4/
///
///
/// Example:
/// ---
/// import dplug.canvas.htmlcolors;
/// parseHTMLColor("black", color, error);                      // all HTML named colors
/// parseHTMLColor("#fe85dc", color, error);                    // hex colors including alpha versions
/// parseHTMLColor("rgba(64, 255, 128, 0.24)", color, error);   // alpha
/// parseHTMLColor("rgb(9e-1, 50%, 128)", color, error);        // percentage, floating-point
/// parseHTMLColor("hsl(120deg, 25%, 75%)", color, error);      // hsv colors
/// parseHTMLColor("gray(0.5)", color, error);                  // gray colors
/// parseHTMLColor(" rgb ( 245 , 112 , 74 )  ", color, error);  // strips whitespace
/// ---
///
bool parseHTMLColor(const(char)[] htmlColorString, out RGBA color, out string error) nothrow @nogc @safe
{
    error = null; // indicate success


    const(char)[] s = htmlColorString;   
    int index = 0;    

    char peek() nothrow @nogc @safe
    {
        if (index >= htmlColorString.length)
            return '\0';
        else
            return s[index];
    }

    void next() nothrow @nogc @safe
    {
        index++;
    }

    bool parseChar(char ch) nothrow @nogc @safe
    {
        if (peek() == ch)
        {
            next;
            return true;
        }
        return false;
    }

    bool expectChar(char ch) nothrow @nogc @safe // senantic difference, "expect" returning false is an input error
    {
        if (!parseChar(ch))
            return false;
        return true;
    }

    bool parseString(string s) nothrow @nogc @safe
    {
        int save = index;

        for (int i = 0; i < s.length; ++i)
        {
            if (!parseChar(s[i]))
            {
                index = save;
                return false;
            }
        }
        return true;
    }

    bool isWhite(char ch) nothrow @nogc @safe
    {
        return ch == ' ';
    }

    bool isDigit(char ch) nothrow @nogc @safe
    {
        return ch >= '0' && ch <= '9';
    }

    bool expectDigit(out char digit) nothrow @nogc @safe
    {
        char ch = peek();
        if (isDigit(ch))
        {            
            next;
            digit = ch;
            return true;
        }
        else
            return false;
    }

    bool parseHexDigit(out int digit) nothrow @nogc @safe
    {
        char ch = peek();
        if (isDigit(ch))
        {
            next;
            digit = ch - '0';
            return true;
        }
        else if (ch >= 'a' && ch <= 'f')
        {
            next;
            digit = 10 + (ch - 'a');
            return true;
        }
        else if (ch >= 'A' && ch <= 'F')
        {
            next;
            digit = 10 + (ch - 'A');
            return true;
        }
        else
            return false;
    }

    void skipWhiteSpace() nothrow @nogc @safe
    {       
        while (isWhite(peek()))
            next;
    }

    bool expectPunct(char ch) nothrow @nogc @safe
    {
        skipWhiteSpace();
        if (!expectChar(ch))
            return false;
        skipWhiteSpace();
        return true;
    }

    ubyte clamp0to255(int a) nothrow @nogc @safe
    {
        if (a < 0) return 0;
        if (a > 255) return 255;
        return cast(ubyte)a;
    }

    // See: https://www.w3.org/TR/css-syntax/#consume-a-number
    bool parseNumber(double* number, out string error) nothrow @nogc @trusted
    {
        char[32] repr;
        int repr_len = 0;

        if (parseChar('+'))
        {}
        else if (parseChar('-'))
        {
            if (repr_len >= 31) return false;
            repr[repr_len++] = '-';
        }
        while(isDigit(peek()))
        {
            if (repr_len >= 31) return false;
            repr[repr_len++] = peek();
            next;
        }
        if (peek() == '.')
        {
            if (repr_len >= 31) return false;
            repr[repr_len++] = '.';
            next;
            char digit;
            bool parsedDigit = expectDigit(digit);
            if (!parsedDigit)
                return false;

            if (repr_len >= 31) return false;
            repr[repr_len++] = digit;

            while(isDigit(peek()))
            {
                if (repr_len >= 31) return false;
                repr[repr_len++] = peek();
                next;
            }
        }
        if (peek() == 'e' || peek() == 'E')
        {
            if (repr_len >= 31) return false;
            repr[repr_len++] = 'e';
            next;
            if (parseChar('+'))
            {}
            else if (parseChar('-'))
            {
                if (repr_len >= 31) return false;
                repr[repr_len++] = '-';
            }
            while(isDigit(peek()))
            {
                if (repr_len >= 31) return false;
                repr[repr_len++] = peek();
                next;
            }
        }
        repr[repr_len++] = '\0'; // force a '\0' to be there, hence rendering sscanf bounded.
        assert(repr_len <= 32);

        double scanned;
        if (sscanf(repr.ptr, "%lf", &scanned) == 1)
        {
            *number = scanned;
            error = "";
            return true;
        }
        else
        {
            error = "Couln't parse number";
            return false;
        }
    }

    bool parseColorValue(out ubyte result, out string error) nothrow @nogc @trusted
    {
        double number;
        if (!parseNumber(&number, error))
        {
            return false;
        }
        bool isPercentage = parseChar('%');
        if (isPercentage)
            number *= (255.0 / 100.0);
        int c = cast(int)(0.5 + number); // round
        result = clamp0to255(c);
        return true; 
    }

    bool parseOpacity(out ubyte result, out string error) nothrow @nogc @trusted
    {
        double number;
        if (!parseNumber(&number, error))
        {
            return false;
        }
        bool isPercentage = parseChar('%');
        if (isPercentage)
            number *= 0.01;
        int c = cast(int)(0.5 + number * 255.0);
        result = clamp0to255(c);
        return true;
    }

    bool parsePercentage(out double result, out string error) nothrow @nogc @trusted
    {
        double number;
        if (!parseNumber(&number, error))
            return false;
        if (!expectChar('%'))
        {
            error = "Expected % in color string";
            return false;
        }
        result = number * 0.01;
        return true;
    }

    bool parseHueInDegrees(out double result, out string error) nothrow @nogc @trusted
    {
        double num;
        if (!parseNumber(&num, error))
            return false;

        if (parseString("deg"))
        {
            result = num;
            return true;
        }
        else if (parseString("rad"))
        {
            result = num * 360.0 / (2 * PI);
            return true;
        }
        else if (parseString("turn"))
        {
            result = num * 360.0;
            return true;
        }
        else if (parseString("grad"))
        {
            result = num * 360.0 / 400.0;
            return true;
        }
        else
        {
            // assume degrees
            result = num;
            return true;
        }
    }

    skipWhiteSpace();

    ubyte red, green, blue, alpha = 255;

    if (parseChar('#'))
    {
       int[8] digits;
       int numDigits = 0;
       for (int i = 0; i < 8; ++i)
       {
          if (parseHexDigit(digits[i]))
              numDigits++;
          else
            break;
       }
       switch(numDigits)
       {
       case 4:
           alpha  = cast(ubyte)( (digits[3] << 4) | digits[3]);
           goto case 3;
       case 3:
           red   = cast(ubyte)( (digits[0] << 4) | digits[0]);
           green = cast(ubyte)( (digits[1] << 4) | digits[1]);
           blue  = cast(ubyte)( (digits[2] << 4) | digits[2]);
           break;
       case 8:
           alpha  = cast(ubyte)( (digits[6] << 4) | digits[7]);
           goto case 6;
       case 6:
           red   = cast(ubyte)( (digits[0] << 4) | digits[1]);
           green = cast(ubyte)( (digits[2] << 4) | digits[3]);
           blue  = cast(ubyte)( (digits[4] << 4) | digits[5]);
           break;
       default:
           error = "Expected 3, 4, 6 or 8 digit in hexadecimal color literal";
           return false;
       }
    }
    else if (parseString("gray"))
    {
        
        skipWhiteSpace();
        if (!parseChar('('))
        {
            // This is named color "gray"
            red = green = blue = 128;
        }
        else
        {
            skipWhiteSpace();
            ubyte v;
            if (!parseColorValue(v, error))
                return false;
            red = green = blue = v;
            skipWhiteSpace();
            if (parseChar(','))
            {
                // there is an alpha value
                skipWhiteSpace();
                if (!parseOpacity(alpha, error))
                    return false;
            }
            if (!expectPunct(')'))
            {
                error = "Expected ) in color string";
                return false;
            }
        }
    }
    else if (parseString("rgb"))
    {
        bool hasAlpha = parseChar('a');
        if (!expectPunct('('))
        {
            error = "Expected ( in color string";
            return false;
        }
        if (!parseColorValue(red, error))
            return false;
        if (!expectPunct(','))
        {
            error = "Expected , in color string";
            return false;
        }
        if (!parseColorValue(green, error))
            return false;
        if (!expectPunct(','))
        {
            error = "Expected , in color string";
            return false;
        }
        if (!parseColorValue(blue, error))
            return false;
        if (hasAlpha)
        {
            if (!expectPunct(','))
            {
                error = "Expected , in color string";
                return false;
            }
            if (!parseOpacity(alpha, error))
                return false;
        }
        if (!expectPunct(')'))
        {
            error = "Expected , in color string";
            return false;
        }
    }
    else if (parseString("hsl"))
    {
        bool hasAlpha = parseChar('a');
        expectPunct('(');

        double hueDegrees;
        if (!parseHueInDegrees(hueDegrees, error))
            return false;
        
        // Convert to turns
        double hueTurns = hueDegrees / 360.0;
        hueTurns -= floor(hueTurns); // take remainder
        double hue = 6.0 * hueTurns;        
        if (!expectPunct(','))
        {
            error = "Expected , in color string";
            return false;
        }
        double sat;
        if (!parsePercentage(sat, error))
            return false;
        if (!expectPunct(','))
        {
            error = "Expected , in color string";
            return false;
        }
        double light;
        if (!parsePercentage(light, error))
            return false;
        if (hasAlpha)
        {
            if (!expectPunct(','))
            {
                error = "Expected , in color string";
                return false;
            }
            if (!parseOpacity(alpha, error))
                return false;
        }
        expectPunct(')');
        double[3] rgb = convertHSLtoRGB(hue, sat, light);
        red   = clamp0to255( cast(int)(0.5 + 255.0 * rgb[0]) );
        green = clamp0to255( cast(int)(0.5 + 255.0 * rgb[1]) );
        blue  = clamp0to255( cast(int)(0.5 + 255.0 * rgb[2]) );
    }
    else
    {
        // Initiate a binary search inside the sorted named color array
        // See_also: https://en.wikipedia.org/wiki/Binary_search_algorithm

        // Current search range
        // this range will only reduce because the color names are sorted
        int L = 0;
        int R = cast(int)(namedColorKeywords.length); 
        int charPos = 0;

        matchloop:
        while (true)
        {
            // Expect 
            char ch = peek();
            if (ch >= 'A' && ch <= 'Z')
                ch += ('a' - 'A');
            if (ch < 'a' || ch > 'z') // not alpha?
            {
                // Examine all alive cases. Select the one which have matched entirely.               
                foreach(candidate; L..R)
                {
                    if (namedColorKeywords[candidate].length == charPos)// found it, return as there are no duplicates
                    {
                        // If we have matched all the alpha of the only remaining candidate, we have found a named color
                        uint rgba = namedColorValues[candidate];
                        red   = (rgba >> 24) & 0xff;
                        green = (rgba >> 16) & 0xff;
                        blue  = (rgba >>  8) & 0xff;
                        alpha = (rgba >>  0) & 0xff;
                        break matchloop;
                    }
                }
                error = "Unexpected char in named color";
                return false;
            }
            next;

            // PERF: there could be something better with a dichotomy
            // PERF: can elid search once we've passed the last match
            bool firstFound = false;
            int firstFoundIndex = R;
            int lastFoundIndex = -1;
            foreach(candindex; L..R)
            {
                // Have we found ch in name[charPos] position?
                string candidate = namedColorKeywords[candindex];
                bool charIsMatching = (candidate.length > charPos) && (candidate[charPos] == ch);
                if (!firstFound && charIsMatching)
                {
                    firstFound = true;
                    firstFoundIndex = candindex;
                }
                if (charIsMatching)
                    lastFoundIndex = candindex;
            }

            // Zero candidate remain
            if (lastFoundIndex < firstFoundIndex)
            {
                error = "Can't recognize color string";
                return false;
            }
            else
            {
                // Several candidate remain, go on and reduce the search range
                L = firstFoundIndex;
                R = lastFoundIndex + 1;
                charPos += 1;
            }
        }
    }

    skipWhiteSpace();
    if (!parseChar('\0'))
    {
        error = "Expected end of input at the end of color string";
        return false;
    }
    color = RGBA(red, green, blue, alpha);
    return true;
}

RGBA parseHTMLColor(const(char)[] htmlColorString) nothrow @nogc @safe
{
    RGBA res;
    string error;
    if (parseHTMLColor(htmlColorString, res, error))
        return res;
    else
        assert(false);
}

private:

// 147 predefined color + "transparent"
static immutable string[147 + 1] namedColorKeywords =
[
    "aliceblue", "antiquewhite", "aqua", "aquamarine",     "azure", "beige", "bisque", "black",
    "blanchedalmond", "blue", "blueviolet", "brown",       "burlywood", "cadetblue", "chartreuse", "chocolate",
    "coral", "cornflowerblue", "cornsilk", "crimson",      "cyan", "darkblue", "darkcyan", "darkgoldenrod",
    "darkgray", "darkgreen", "darkgrey", "darkkhaki",      "darkmagenta", "darkolivegreen", "darkorange", "darkorchid",
    "darkred","darksalmon","darkseagreen","darkslateblue", "darkslategray", "darkslategrey", "darkturquoise", "darkviolet",
    "deeppink", "deepskyblue", "dimgray", "dimgrey",       "dodgerblue", "firebrick", "floralwhite", "forestgreen",
    "fuchsia", "gainsboro", "ghostwhite", "gold",          "goldenrod", "gray", "green", "greenyellow",
    "grey", "honeydew", "hotpink", "indianred",            "indigo", "ivory", "khaki", "lavender",
    "lavenderblush","lawngreen","lemonchiffon","lightblue","lightcoral", "lightcyan", "lightgoldenrodyellow", "lightgray",
    "lightgreen", "lightgrey", "lightpink", "lightsalmon", "lightseagreen", "lightskyblue", "lightslategray", "lightslategrey",
    "lightsteelblue", "lightyellow", "lime", "limegreen",  "linen", "magenta", "maroon", "mediumaquamarine",
    "mediumblue", "mediumorchid", "mediumpurple", "mediumseagreen", "mediumslateblue", "mediumspringgreen", "mediumturquoise", "mediumvioletred",
    "midnightblue", "mintcream", "mistyrose", "moccasin",  "navajowhite", "navy", "oldlace", "olive",
    "olivedrab", "orange", "orangered",  "orchid",         "palegoldenrod", "palegreen", "paleturquoise", "palevioletred",
    "papayawhip", "peachpuff", "peru", "pink",             "plum", "powderblue", "purple", "red",
    "rosybrown", "royalblue", "saddlebrown", "salmon",     "sandybrown", "seagreen", "seashell", "sienna",
    "silver", "skyblue", "slateblue", "slategray",         "slategrey", "snow", "springgreen", "steelblue",
    "tan", "teal", "thistle", "tomato",                    "transparent", "turquoise", "violet", "wheat", 
    "white", "whitesmoke", "yellow", "yellowgreen"
];

immutable static uint[147 + 1] namedColorValues =
[
    0xf0f8ffff, 0xfaebd7ff, 0x00ffffff, 0x7fffd4ff, 0xf0ffffff, 0xf5f5dcff, 0xffe4c4ff, 0x000000ff, 
    0xffebcdff, 0x0000ffff, 0x8a2be2ff, 0xa52a2aff, 0xdeb887ff, 0x5f9ea0ff, 0x7fff00ff, 0xd2691eff, 
    0xff7f50ff, 0x6495edff, 0xfff8dcff, 0xdc143cff, 0x00ffffff, 0x00008bff, 0x008b8bff, 0xb8860bff, 
    0xa9a9a9ff, 0x006400ff, 0xa9a9a9ff, 0xbdb76bff, 0x8b008bff, 0x556b2fff, 0xff8c00ff, 0x9932ccff, 
    0x8b0000ff, 0xe9967aff, 0x8fbc8fff, 0x483d8bff, 0x2f4f4fff, 0x2f4f4fff, 0x00ced1ff, 0x9400d3ff, 
    0xff1493ff, 0x00bfffff, 0x696969ff, 0x696969ff, 0x1e90ffff, 0xb22222ff, 0xfffaf0ff, 0x228b22ff, 
    0xff00ffff, 0xdcdcdcff, 0xf8f8ffff, 0xffd700ff, 0xdaa520ff, 0x808080ff, 0x008000ff, 0xadff2fff, 
    0x808080ff, 0xf0fff0ff, 0xff69b4ff, 0xcd5c5cff, 0x4b0082ff, 0xfffff0ff, 0xf0e68cff, 0xe6e6faff, 
    0xfff0f5ff, 0x7cfc00ff, 0xfffacdff, 0xadd8e6ff, 0xf08080ff, 0xe0ffffff, 0xfafad2ff, 0xd3d3d3ff, 
    0x90ee90ff, 0xd3d3d3ff, 0xffb6c1ff, 0xffa07aff, 0x20b2aaff, 0x87cefaff, 0x778899ff, 0x778899ff, 
    0xb0c4deff, 0xffffe0ff, 0x00ff00ff, 0x32cd32ff, 0xfaf0e6ff, 0xff00ffff, 0x800000ff, 0x66cdaaff, 
    0x0000cdff, 0xba55d3ff, 0x9370dbff, 0x3cb371ff, 0x7b68eeff, 0x00fa9aff, 0x48d1ccff, 0xc71585ff, 
    0x191970ff, 0xf5fffaff, 0xffe4e1ff, 0xffe4b5ff, 0xffdeadff, 0x000080ff, 0xfdf5e6ff, 0x808000ff, 
    0x6b8e23ff, 0xffa500ff, 0xff4500ff, 0xda70d6ff, 0xeee8aaff, 0x98fb98ff, 0xafeeeeff, 0xdb7093ff, 
    0xffefd5ff, 0xffdab9ff, 0xcd853fff, 0xffc0cbff, 0xdda0ddff, 0xb0e0e6ff, 0x800080ff, 0xff0000ff, 
    0xbc8f8fff, 0x4169e1ff, 0x8b4513ff, 0xfa8072ff, 0xf4a460ff, 0x2e8b57ff, 0xfff5eeff, 0xa0522dff,
    0xc0c0c0ff, 0x87ceebff, 0x6a5acdff, 0x708090ff, 0x708090ff, 0xfffafaff, 0x00ff7fff, 0x4682b4ff, 
    0xd2b48cff, 0x008080ff, 0xd8bfd8ff, 0xff6347ff, 0x00000000,  0x40e0d0ff, 0xee82eeff, 0xf5deb3ff, 
    0xffffffff, 0xf5f5f5ff, 0xffff00ff, 0x9acd32ff,
];


// Reference: https://www.w3.org/TR/css-color-4/#hsl-to-rgb
// this algorithm assumes that the hue has been normalized to a number in the half-open range [0, 6), 
// and the saturation and lightness have been normalized to the range [0, 1]. 
double[3] convertHSLtoRGB(double hue, double sat, double light) pure nothrow @nogc @safe
{
    double t2;
    if( light <= .5 ) 
        t2 = light * (sat + 1);
    else 
        t2 = light + sat - (light * sat);
    double t1 = light * 2 - t2;
    double r = convertHueToRGB(t1, t2, hue + 2);
    double g = convertHueToRGB(t1, t2, hue);
    double b = convertHueToRGB(t1, t2, hue - 2);
    return [r, g, b];
}

double convertHueToRGB(double t1, double t2, double hue) pure nothrow @nogc @safe
{
    if (hue < 0) 
        hue = hue + 6;
    if (hue >= 6) 
        hue = hue - 6;
    if (hue < 1) 
        return (t2 - t1) * hue + t1;
    else if(hue < 3) 
        return t2;
    else if(hue < 4) 
        return (t2 - t1) * (4 - hue) + t1;
    else 
        return t1;
}

unittest
{
    bool doesntParse(string color)
    {
        RGBA parsed;
        string error;
        if (parseHTMLColor(color, parsed, error))
        {
            return false;
        }
        else
            return true;
    }

    bool testParse(string color, ubyte[4] correct)
    {
        RGBA parsed;
        RGBA correctC = RGBA(correct[0], correct[1], correct[2], correct[3]);
        string error;
        

        if (parseHTMLColor(color, parsed, error))
        {
            return parsed == correctC;
        }
        else
            return false;
    }

    assert(doesntParse(""));

    // #hex colors    
    assert(testParse("#aB9" , [0xaa, 0xBB, 0x99, 255]));
    assert(testParse("#aB98" , [0xaa, 0xBB, 0x99, 0x88]));
    assert(doesntParse("#"));
    assert(doesntParse("#ab"));
    assert(testParse(" #0f1c4A " , [0x0f, 0x1c, 0x4a, 255]));    
    assert(testParse(" #0f1c4A43 " , [0x0f, 0x1c, 0x4A, 0x43]));
    assert(doesntParse("#0123456"));
    assert(doesntParse("#012345678"));

    // rgb() and rgba()
    assert(testParse("  rgba( 14.01, 25.0e+0%, 16, 0.5)  " , [14, 64, 16, 128]));
    assert(testParse("rgb(10e3,112,-3.4e-2)"               , [255, 112, 0, 255]));

    // hsl() and hsla()
    assert(testParse("hsl(0   ,  100%, 50%)"         , [255, 0, 0, 255]));
    assert(testParse("hsl(720,  100%, 50%)"          , [255, 0, 0, 255]));
    assert(testParse("hsl(180deg,  100%, 50%)"       , [0, 255, 255, 255]));
    assert(testParse("hsl(0grad, 100%, 50%)"         , [255, 0, 0, 255]));
    assert(testParse("hsl(0rad,  100%, 50%)"         , [255, 0, 0, 255]));
    assert(testParse("hsl(0turn, 100%, 50%)"         , [255, 0, 0, 255]));
    assert(testParse("hsl(120deg, 100%, 50%)"        , [0, 255, 0, 255]));
    assert(testParse("hsl(123deg,   2.5%, 0%)"       , [0, 0, 0, 255]));
    assert(testParse("hsl(5.4e-5rad, 25%, 100%)"     , [255, 255, 255, 255]));
    assert(testParse("hsla(0turn, 100%, 50%, 0.25)"  , [255, 0, 0, 64]));

    // gray values
    assert(testParse(" gray( +0.0% )"       , [0, 0, 0, 255]));
    assert(testParse(" gray "               , [128, 128, 128, 255]));
    assert(testParse(" gray( 100%, 50% ) "  , [255, 255, 255, 128]));

    // Named colors
    assert(testParse("tRaNsPaREnt"  , [0, 0, 0, 0]));
    assert(testParse(" navy "  , [0, 0, 128, 255]));
    assert(testParse("lightgoldenrodyellow"  , [250, 250, 210, 255]));
    assert(doesntParse("animaginarycolorname")); // unknown named color
    assert(doesntParse("navyblahblah")); // too much chars
    assert(doesntParse("blac")); // incomplete color
    assert(testParse("lime"  , [0, 255, 0, 255])); // termination with 2 candidate alive
    assert(testParse("limegreen"  , [50, 205, 50, 255]));    
}

unittest
{
    // should work in CTFE
    static immutable RGBA color = parseHTMLColor("red");
}