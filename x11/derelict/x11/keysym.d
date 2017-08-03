module derelict.x11.keysym;

version(linux):

/* default keysyms */
enum bool XK_MISCELLANY     = true;
enum bool XK_XKB_KEYS       = true;
enum bool XK_3270           = false;
enum bool XK_LATIN1         = true;
enum bool XK_LATIN2         = true;
enum bool XK_LATIN3         = true;
enum bool XK_LATIN4         = true;
enum bool XK_LATIN8         = true;
enum bool XK_LATIN9         = true;
enum bool XK_CAUCASUS       = true;
enum bool XK_GREEK          = true;
enum bool XK_TECHNICAL      = false;
enum bool XK_SPECIAL        = false;
enum bool XK_PUBLISHING     = false;
enum bool XK_APL            = false;
enum bool XK_KATAKANA       = true;
enum bool XK_ARABIC         = true;
enum bool XK_CYRILLIC       = true;
enum bool XK_HEBREW         = true;
enum bool XK_THAI           = true;
enum bool XK_KOREAN         = true;
enum bool XK_ARMENIAN       = true;
enum bool XK_GEORGIAN       = true;
enum bool XK_VIETNAMESE     = true;
enum bool XK_CURRENCY       = true;
enum bool XK_MATHEMATICAL   = true;
enum bool XK_BRAILLE        = true;
enum bool XK_SINHALA        = true;

public import derelict.x11.keysymdef;
