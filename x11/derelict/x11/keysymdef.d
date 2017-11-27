module derelict.x11.keysymdef;

version(linux):

import derelict.x11.keysym;

extern (C) nothrow @nogc:

const int XK_VoidSymbol                 = 0xffffff;  /* Void symbol */

static if( XK_MISCELLANY ){
	/*
	 * TTY function keys, cleverly chosen to map to ASCII, for convenience of
	 * programming, but could have been arbitrary (at the cost of lookup
	 * tables in client code).
	 */

	const int XK_BackSpace                     = 0xff08;  /* Back space, back char */
	const int XK_Tab                           = 0xff09;
	const int XK_Linefeed                      = 0xff0a;  /* Linefeed, LF */
	const int XK_Clear                         = 0xff0b;
	const int XK_Return                        = 0xff0d;  /* Return, enter */
	const int XK_Pause                         = 0xff13;  /* Pause, hold */
	const int XK_Scroll_Lock                   = 0xff14;
	const int XK_Sys_Req                       = 0xff15;
	const int XK_Escape                        = 0xff1b;
	const int XK_Delete                        = 0xffff;  /* Delete, rubout */

	/* International & multi-key character composition */

	const int XK_Multi_key                     = 0xff20;  /* Multi-key character compose */
	const int XK_Codeinput                     = 0xff37;
	const int XK_SingleCandidate               = 0xff3c;
	const int XK_MultipleCandidate             = 0xff3d;
	const int XK_PreviousCandidate             = 0xff3e;

	/* Japanese keyboard support */

	const int XK_Kanji                         = 0xff21;  /* Kanji, Kanji convert */
	const int XK_Muhenkan                      = 0xff22;  /* Cancel Conversion */
	const int XK_Henkan_Mode                   = 0xff23;  /* Start/Stop Conversion */
	const int XK_Henkan                        = 0xff23;  /* Alias for Henkan_Mode */
	const int XK_Romaji                        = 0xff24;  /* to Romaji */
	const int XK_Hiragana                      = 0xff25;  /* to Hiragana */
	const int XK_Katakana                      = 0xff26;  /* to Katakana */
	const int XK_Hiragana_Katakana             = 0xff27;  /* Hiragana/Katakana toggle */
	const int XK_Zenkaku                       = 0xff28;  /* to Zenkaku */
	const int XK_Hankaku                       = 0xff29;  /* to Hankaku */
	const int XK_Zenkaku_Hankaku               = 0xff2a;  /* Zenkaku/Hankaku toggle */
	const int XK_Touroku                       = 0xff2b;  /* Add to Dictionary */
	const int XK_Massyo                        = 0xff2c;  /* Delete from Dictionary */
	const int XK_Kana_Lock                     = 0xff2d;  /* Kana Lock */
	const int XK_Kana_Shift                    = 0xff2e;  /* Kana Shift */
	const int XK_Eisu_Shift                    = 0xff2f;  /* Alphanumeric Shift */
	const int XK_Eisu_toggle                   = 0xff30;  /* Alphanumeric toggle */
	const int XK_Kanji_Bangou                  = 0xff37;  /* Codeinput */
	const int XK_Zen_Koho                      = 0xff3d;  /* Multiple/All Candidate(s) */
	const int XK_Mae_Koho                      = 0xff3e;  /* Previous Candidate */

	/* 0xff31 thru 0xff3f are under XK_KOREAN */

	/* Cursor control & motion */

	const int XK_Home                          = 0xff50;
	const int XK_Left                          = 0xff51;  /* Move left, left arrow */
	const int XK_Up                            = 0xff52;  /* Move up, up arrow */
	const int XK_Right                         = 0xff53;  /* Move right, right arrow */
	const int XK_Down                          = 0xff54;  /* Move down, down arrow */
	const int XK_Prior                         = 0xff55;  /* Prior, previous */
	const int XK_Page_Up                       = 0xff55;
	const int XK_Next                          = 0xff56;  /* Next */
	const int XK_Page_Down                     = 0xff56;
	const int XK_End                           = 0xff57;  /* EOL */
	const int XK_Begin                         = 0xff58;  /* BOL */

	/* Misc functions */

	const int XK_Select                        = 0xff60;  /* Select, mark */
	const int XK_Print                         = 0xff61;
	const int XK_Execute                       = 0xff62;  /* Execute, run, do */
	const int XK_Insert                        = 0xff63;  /* Insert, insert here */
	const int XK_Undo                          = 0xff65;
	const int XK_Redo                          = 0xff66;  /* Redo, again */
	const int XK_Menu                          = 0xff67;
	const int XK_Find                          = 0xff68;  /* Find, search */
	const int XK_Cancel                        = 0xff69;  /* Cancel, stop, abort, exit */
	const int XK_Help                          = 0xff6a;  /* Help */
	const int XK_break                         = 0xff6b;
	const int XK_Mode_switch                   = 0xff7e;  /* Character set switch */
	const int XK_script_switch                 = 0xff7e;  /* Alias for mode_switch */
	const int XK_Num_Lock                      = 0xff7f;

	/* Keypad functions, keypad numbers cleverly chosen to map to ASCII */

	const int XK_KP_Space                      = 0xff80;  /* Space */
	const int XK_KP_Tab                        = 0xff89;
	const int XK_KP_Enter                      = 0xff8d;  /* Enter */
	const int XK_KP_F1                         = 0xff91;  /* PF1, KP_A, ... */
	const int XK_KP_F2                         = 0xff92;
	const int XK_KP_F3                         = 0xff93;
	const int XK_KP_F4                         = 0xff94;
	const int XK_KP_Home                       = 0xff95;
	const int XK_KP_Left                       = 0xff96;
	const int XK_KP_Up                         = 0xff97;
	const int XK_KP_Right                      = 0xff98;
	const int XK_KP_Down                       = 0xff99;
	const int XK_KP_Prior                      = 0xff9a;
	const int XK_KP_Page_Up                    = 0xff9a;
	const int XK_KP_Next                       = 0xff9b;
	const int XK_KP_Page_Down                  = 0xff9b;
	const int XK_KP_End                        = 0xff9c;
	const int XK_KP_Begin                      = 0xff9d;
	const int XK_KP_Insert                     = 0xff9e;
	const int XK_KP_Delete                     = 0xff9f;
	const int XK_KP_Equal                      = 0xffbd;  /* Equals */
	const int XK_KP_Multiply                   = 0xffaa;
	const int XK_KP_Add                        = 0xffab;
	const int XK_KP_Separator                  = 0xffac;  /* Separator, often comma */
	const int XK_KP_Subtract                   = 0xffad;
	const int XK_KP_Decimal                    = 0xffae;
	const int XK_KP_Divide                     = 0xffaf;

	const int XK_KP_0                          = 0xffb0;
	const int XK_KP_1                          = 0xffb1;
	const int XK_KP_2                          = 0xffb2;
	const int XK_KP_3                          = 0xffb3;
	const int XK_KP_4                          = 0xffb4;
	const int XK_KP_5                          = 0xffb5;
	const int XK_KP_6                          = 0xffb6;
	const int XK_KP_7                          = 0xffb7;
	const int XK_KP_8                          = 0xffb8;
	const int XK_KP_9                          = 0xffb9;

	/*
	 * Auxiliary functions; note the duplicate definitions for left and right
	 * function keys;  Sun keyboards and a few other manufacturers have such
	 * function key groups on the left and/or right sides of the keyboard.
	 * We've not found a keyboard with more than 35 function keys total.
	 */

	const int XK_F1                            = 0xffbe;
	const int XK_F2                            = 0xffbf;
	const int XK_F3                            = 0xffc0;
	const int XK_F4                            = 0xffc1;
	const int XK_F5                            = 0xffc2;
	const int XK_F6                            = 0xffc3;
	const int XK_F7                            = 0xffc4;
	const int XK_F8                            = 0xffc5;
	const int XK_F9                            = 0xffc6;
	const int XK_F10                           = 0xffc7;
	const int XK_F11                           = 0xffc8;
	const int XK_L1                            = 0xffc8;
	const int XK_F12                           = 0xffc9;
	const int XK_L2                            = 0xffc9;
	const int XK_F13                           = 0xffca;
	const int XK_L3                            = 0xffca;
	const int XK_F14                           = 0xffcb;
	const int XK_L4                            = 0xffcb;
	const int XK_F15                           = 0xffcc;
	const int XK_L5                            = 0xffcc;
	const int XK_F16                           = 0xffcd;
	const int XK_L6                            = 0xffcd;
	const int XK_F17                           = 0xffce;
	const int XK_L7                            = 0xffce;
	const int XK_F18                           = 0xffcf;
	const int XK_L8                            = 0xffcf;
	const int XK_F19                           = 0xffd0;
	const int XK_L9                            = 0xffd0;
	const int XK_F20                           = 0xffd1;
	const int XK_L10                           = 0xffd1;
	const int XK_F21                           = 0xffd2;
	const int XK_R1                            = 0xffd2;
	const int XK_F22                           = 0xffd3;
	const int XK_R2                            = 0xffd3;
	const int XK_F23                           = 0xffd4;
	const int XK_R3                            = 0xffd4;
	const int XK_F24                           = 0xffd5;
	const int XK_R4                            = 0xffd5;
	const int XK_F25                           = 0xffd6;
	const int XK_R5                            = 0xffd6;
	const int XK_F26                           = 0xffd7;
	const int XK_R6                            = 0xffd7;
	const int XK_F27                           = 0xffd8;
	const int XK_R7                            = 0xffd8;
	const int XK_F28                           = 0xffd9;
	const int XK_R8                            = 0xffd9;
	const int XK_F29                           = 0xffda;
	const int XK_R9                            = 0xffda;
	const int XK_F30                           = 0xffdb;
	const int XK_R10                           = 0xffdb;
	const int XK_F31                           = 0xffdc;
	const int XK_R11                           = 0xffdc;
	const int XK_F32                           = 0xffdd;
	const int XK_R12                           = 0xffdd;
	const int XK_F33                           = 0xffde;
	const int XK_R13                           = 0xffde;
	const int XK_F34                           = 0xffdf;
	const int XK_R14                           = 0xffdf;
	const int XK_F35                           = 0xffe0;
	const int XK_R15                           = 0xffe0;

	/* Modifiers */

	const int XK_Shift_L                       = 0xffe1;  /* Left shift */
	const int XK_Shift_R                       = 0xffe2;  /* Right shift */
	const int XK_Control_L                     = 0xffe3;  /* Left control */
	const int XK_Control_R                     = 0xffe4;  /* Right control */
	const int XK_Caps_Lock                     = 0xffe5;  /* Caps lock */
	const int XK_Shift_Lock                    = 0xffe6;  /* Shift lock */

	const int XK_Meta_L                        = 0xffe7;  /* Left meta */
	const int XK_Meta_R                        = 0xffe8;  /* Right meta */
	const int XK_Alt_L                         = 0xffe9;  /* Left alt */
	const int XK_Alt_R                         = 0xffea;  /* Right alt */
	const int XK_Super_L                       = 0xffeb;  /* Left super */
	const int XK_Super_R                       = 0xffec;  /* Right super */
	const int XK_Hyper_L                       = 0xffed;  /* Left hyper */
	const int XK_Hyper_R                       = 0xffee;  /* Right hyper */
}

/*
 * Latin 1
 * (ISO/IEC 8859-1 = Unicode U+0020..U+00FF)
 * Byte 3 = 0
 */
static if( XK_LATIN1 ){
	const int XK_space                         = 0x0020;  /* U+0020 SPACE */
	const int XK_exclam                        = 0x0021;  /* U+0021 EXCLAMATION MARK */
	const int XK_quotedbl                      = 0x0022;  /* U+0022 QUOTATION MARK */
	const int XK_numbersign                    = 0x0023;  /* U+0023 NUMBER SIGN */
	const int XK_dollar                        = 0x0024;  /* U+0024 DOLLAR SIGN */
	const int XK_percent                       = 0x0025;  /* U+0025 PERCENT SIGN */
	const int XK_ampersand                     = 0x0026;  /* U+0026 AMPERSAND */
	const int XK_apostrophe                    = 0x0027;  /* U+0027 APOSTROPHE */
	const int XK_quoteright                    = 0x0027;  /* deprecated */
	const int XK_parenleft                     = 0x0028;  /* U+0028 LEFT PARENTHESIS */
	const int XK_parenright                    = 0x0029;  /* U+0029 RIGHT PARENTHESIS */
	const int XK_asterisk                      = 0x002a;  /* U+002A ASTERISK */
	const int XK_plus                          = 0x002b;  /* U+002B PLUS SIGN */
	const int XK_comma                         = 0x002c;  /* U+002C COMMA */
	const int XK_minus                         = 0x002d;  /* U+002D HYPHEN-MINUS */
	const int XK_period                        = 0x002e;  /* U+002E FULL STOP */
	const int XK_slash                         = 0x002f;  /* U+002F SOLIDUS */
	const int XK_0                             = 0x0030;  /* U+0030 DIGIT ZERO */
	const int XK_1                             = 0x0031;  /* U+0031 DIGIT ONE */
	const int XK_2                             = 0x0032;  /* U+0032 DIGIT TWO */
	const int XK_3                             = 0x0033;  /* U+0033 DIGIT THREE */
	const int XK_4                             = 0x0034;  /* U+0034 DIGIT FOUR */
	const int XK_5                             = 0x0035;  /* U+0035 DIGIT FIVE */
	const int XK_6                             = 0x0036;  /* U+0036 DIGIT SIX */
	const int XK_7                             = 0x0037;  /* U+0037 DIGIT SEVEN */
	const int XK_8                             = 0x0038;  /* U+0038 DIGIT EIGHT */
	const int XK_9                             = 0x0039;  /* U+0039 DIGIT NINE */
	const int XK_colon                         = 0x003a;  /* U+003A COLON */
	const int XK_semicolon                     = 0x003b;  /* U+003B SEMICOLON */
	const int XK_less                          = 0x003c;  /* U+003C LESS-THAN SIGN */
	const int XK_equal                         = 0x003d;  /* U+003D EQUALS SIGN */
	const int XK_greater                       = 0x003e;  /* U+003E GREATER-THAN SIGN */
	const int XK_question                      = 0x003f;  /* U+003F QUESTION MARK */
	const int XK_at                            = 0x0040;  /* U+0040 COMMERCIAL AT */
	const int XK_A                             = 0x0041;  /* U+0041 LATIN CAPITAL LETTER A */
	const int XK_B                             = 0x0042;  /* U+0042 LATIN CAPITAL LETTER B */
	const int XK_C                             = 0x0043;  /* U+0043 LATIN CAPITAL LETTER C */
	const int XK_D                             = 0x0044;  /* U+0044 LATIN CAPITAL LETTER D */
	const int XK_E                             = 0x0045;  /* U+0045 LATIN CAPITAL LETTER E */
	const int XK_F                             = 0x0046;  /* U+0046 LATIN CAPITAL LETTER F */
	const int XK_G                             = 0x0047;  /* U+0047 LATIN CAPITAL LETTER G */
	const int XK_H                             = 0x0048;  /* U+0048 LATIN CAPITAL LETTER H */
	const int XK_I                             = 0x0049;  /* U+0049 LATIN CAPITAL LETTER I */
	const int XK_J                             = 0x004a;  /* U+004A LATIN CAPITAL LETTER J */
	const int XK_K                             = 0x004b;  /* U+004B LATIN CAPITAL LETTER K */
	const int XK_L                             = 0x004c;  /* U+004C LATIN CAPITAL LETTER L */
	const int XK_M                             = 0x004d;  /* U+004D LATIN CAPITAL LETTER M */
	const int XK_N                             = 0x004e;  /* U+004E LATIN CAPITAL LETTER N */
	const int XK_O                             = 0x004f;  /* U+004F LATIN CAPITAL LETTER O */
	const int XK_P                             = 0x0050;  /* U+0050 LATIN CAPITAL LETTER P */
	const int XK_Q                             = 0x0051;  /* U+0051 LATIN CAPITAL LETTER Q */
	const int XK_R                             = 0x0052;  /* U+0052 LATIN CAPITAL LETTER R */
	const int XK_S                             = 0x0053;  /* U+0053 LATIN CAPITAL LETTER S */
	const int XK_T                             = 0x0054;  /* U+0054 LATIN CAPITAL LETTER T */
	const int XK_U                             = 0x0055;  /* U+0055 LATIN CAPITAL LETTER U */
	const int XK_V                             = 0x0056;  /* U+0056 LATIN CAPITAL LETTER V */
	const int XK_W                             = 0x0057;  /* U+0057 LATIN CAPITAL LETTER W */
	const int XK_X                             = 0x0058;  /* U+0058 LATIN CAPITAL LETTER X */
	const int XK_Y                             = 0x0059;  /* U+0059 LATIN CAPITAL LETTER Y */
	const int XK_Z                             = 0x005a;  /* U+005A LATIN CAPITAL LETTER Z */
	const int XK_bracketleft                   = 0x005b;  /* U+005B LEFT SQUARE BRACKET */
	const int XK_backslash                     = 0x005c;  /* U+005C REVERSE SOLIDUS */
	const int XK_bracketright                  = 0x005d;  /* U+005D RIGHT SQUARE BRACKET */
	const int XK_asciicircum                   = 0x005e;  /* U+005E CIRCUMFLEX ACCENT */
	const int XK_underscore                    = 0x005f;  /* U+005F LOW LINE */
	const int XK_grave                         = 0x0060;  /* U+0060 GRAVE ACCENT */
	const int XK_quoteleft                     = 0x0060;  /* deprecated */
	const int XK_a                             = 0x0061;  /* U+0061 LATIN SMALL LETTER A */
	const int XK_b                             = 0x0062;  /* U+0062 LATIN SMALL LETTER B */
	const int XK_c                             = 0x0063;  /* U+0063 LATIN SMALL LETTER C */
	const int XK_d                             = 0x0064;  /* U+0064 LATIN SMALL LETTER D */
	const int XK_e                             = 0x0065;  /* U+0065 LATIN SMALL LETTER E */
	const int XK_f                             = 0x0066;  /* U+0066 LATIN SMALL LETTER F */
	const int XK_g                             = 0x0067;  /* U+0067 LATIN SMALL LETTER G */
	const int XK_h                             = 0x0068;  /* U+0068 LATIN SMALL LETTER H */
	const int XK_i                             = 0x0069;  /* U+0069 LATIN SMALL LETTER I */
	const int XK_j                             = 0x006a;  /* U+006A LATIN SMALL LETTER J */
	const int XK_k                             = 0x006b;  /* U+006B LATIN SMALL LETTER K */
	const int XK_l                             = 0x006c;  /* U+006C LATIN SMALL LETTER L */
	const int XK_m                             = 0x006d;  /* U+006D LATIN SMALL LETTER M */
	const int XK_n                             = 0x006e;  /* U+006E LATIN SMALL LETTER N */
	const int XK_o                             = 0x006f;  /* U+006F LATIN SMALL LETTER O */
	const int XK_p                             = 0x0070;  /* U+0070 LATIN SMALL LETTER P */
	const int XK_q                             = 0x0071;  /* U+0071 LATIN SMALL LETTER Q */
	const int XK_r                             = 0x0072;  /* U+0072 LATIN SMALL LETTER R */
	const int XK_s                             = 0x0073;  /* U+0073 LATIN SMALL LETTER S */
	const int XK_t                             = 0x0074;  /* U+0074 LATIN SMALL LETTER T */
	const int XK_u                             = 0x0075;  /* U+0075 LATIN SMALL LETTER U */
	const int XK_v                             = 0x0076;  /* U+0076 LATIN SMALL LETTER V */
	const int XK_w                             = 0x0077;  /* U+0077 LATIN SMALL LETTER W */
	const int XK_x                             = 0x0078;  /* U+0078 LATIN SMALL LETTER X */
	const int XK_y                             = 0x0079;  /* U+0079 LATIN SMALL LETTER Y */
	const int XK_z                             = 0x007a;  /* U+007A LATIN SMALL LETTER Z */
	const int XK_braceleft                     = 0x007b;  /* U+007B LEFT CURLY BRACKET */
	const int XK_bar                           = 0x007c;  /* U+007C VERTICAL LINE */
	const int XK_braceright                    = 0x007d;  /* U+007D RIGHT CURLY BRACKET */
	const int XK_asciitilde                    = 0x007e;  /* U+007E TILDE */

	const int XK_nobreakspace                  = 0x00a0;  /* U+00A0 NO-//~ break SPACE */
	const int XK_exclamdown                    = 0x00a1;  /* U+00A1 INVERTED EXCLAMATION MARK */
	const int XK_cent                          = 0x00a2;  /* U+00A2 CENT SIGN */
	const int XK_sterling                      = 0x00a3;  /* U+00A3 POUND SIGN */
	const int XK_currency                      = 0x00a4;  /* U+00A4 CURRENCY SIGN */
	const int XK_yen                           = 0x00a5;  /* U+00A5 YEN SIGN */
	const int XK_brokenbar                     = 0x00a6;  /* U+00A6 BROKEN BAR */
	const int XK_section                       = 0x00a7;  /* U+00A7 SECTION SIGN */
	const int XK_diaeresis                     = 0x00a8;  /* U+00A8 DIAERESIS */
	const int XK_copyright                     = 0x00a9;  /* U+00A9 COPYRIGHT SIGN */
	const int XK_ordfeminine                   = 0x00aa;  /* U+00AA FEMININE ORDINAL INDICATOR */
	const int XK_guillemotleft                 = 0x00ab;  /* U+00AB LEFT-POINTING DOUBLE ANGLE QUOTATION MARK */
	const int XK_notsign                       = 0x00ac;  /* U+00AC NOT SIGN */
	const int XK_hyphen                        = 0x00ad;  /* U+00AD SOFT HYPHEN */
	const int XK_registered                    = 0x00ae;  /* U+00AE REGISTERED SIGN */
	const int XK_macron                        = 0x00af;  /* U+00AF MACRON */
	const int XK_degree                        = 0x00b0;  /* U+00B0 DEGREE SIGN */
	const int XK_plusminus                     = 0x00b1;  /* U+00B1 PLUS-MINUS SIGN */
	const int XK_twosuperior                   = 0x00b2;  /* U+00B2 SUPERSCRIPT TWO */
	const int XK_threesuperior                 = 0x00b3;  /* U+00B3 SUPERSCRIPT THREE */
	const int XK_acute                         = 0x00b4;  /* U+00B4 ACUTE ACCENT */
	const int XK_mu                            = 0x00b5;  /* U+00B5 MICRO SIGN */
	const int XK_paragraph                     = 0x00b6;  /* U+00B6 PILCROW SIGN */
	const int XK_periodcentered                = 0x00b7;  /* U+00B7 MIDDLE DOT */
	const int XK_cedilla                       = 0x00b8;  /* U+00B8 CEDILLA */
	const int XK_onesuperior                   = 0x00b9;  /* U+00B9 SUPERSCRIPT ONE */
	const int XK_masculine                     = 0x00ba;  /* U+00BA MASCULINE ORDINAL INDICATOR */
	const int XK_guillemotright                = 0x00bb;  /* U+00BB RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK */
	const int XK_onequarter                    = 0x00bc;  /* U+00BC VULGAR FRACTION ONE QUARTER */
	const int XK_onehalf                       = 0x00bd;  /* U+00BD VULGAR FRACTION ONE HALF */
	const int XK_threequarters                 = 0x00be;  /* U+00BE VULGAR FRACTION THREE QUARTERS */
	const int XK_questiondown                  = 0x00bf;  /* U+00BF INVERTED QUESTION MARK */
	const int XK_Agrave                        = 0x00c0;  /* U+00C0 LATIN CAPITAL LETTER A WITH GRAVE */
	const int XK_Aacute                        = 0x00c1;  /* U+00C1 LATIN CAPITAL LETTER A WITH ACUTE */
	const int XK_Acircumflex                   = 0x00c2;  /* U+00C2 LATIN CAPITAL LETTER A WITH CIRCUMFLEX */
	const int XK_Atilde                        = 0x00c3;  /* U+00C3 LATIN CAPITAL LETTER A WITH TILDE */
	const int XK_Adiaeresis                    = 0x00c4;  /* U+00C4 LATIN CAPITAL LETTER A WITH DIAERESIS */
	const int XK_Aring                         = 0x00c5;  /* U+00C5 LATIN CAPITAL LETTER A WITH RING ABOVE */
	const int XK_AE                            = 0x00c6;  /* U+00C6 LATIN CAPITAL LETTER AE */
	const int XK_Ccedilla                      = 0x00c7;  /* U+00C7 LATIN CAPITAL LETTER C WITH CEDILLA */
	const int XK_Egrave                        = 0x00c8;  /* U+00C8 LATIN CAPITAL LETTER E WITH GRAVE */
	const int XK_Eacute                        = 0x00c9;  /* U+00C9 LATIN CAPITAL LETTER E WITH ACUTE */
	const int XK_Ecircumflex                   = 0x00ca;  /* U+00CA LATIN CAPITAL LETTER E WITH CIRCUMFLEX */
	const int XK_Ediaeresis                    = 0x00cb;  /* U+00CB LATIN CAPITAL LETTER E WITH DIAERESIS */
	const int XK_Igrave                        = 0x00cc;  /* U+00CC LATIN CAPITAL LETTER I WITH GRAVE */
	const int XK_Iacute                        = 0x00cd;  /* U+00CD LATIN CAPITAL LETTER I WITH ACUTE */
	const int XK_Icircumflex                   = 0x00ce;  /* U+00CE LATIN CAPITAL LETTER I WITH CIRCUMFLEX */
	const int XK_Idiaeresis                    = 0x00cf;  /* U+00CF LATIN CAPITAL LETTER I WITH DIAERESIS */
	const int XK_ETH                           = 0x00d0;  /* U+00D0 LATIN CAPITAL LETTER ETH */
	const int XK_Eth                           = 0x00d0;  /* deprecated */
	const int XK_Ntilde                        = 0x00d1;  /* U+00D1 LATIN CAPITAL LETTER N WITH TILDE */
	const int XK_Ograve                        = 0x00d2;  /* U+00D2 LATIN CAPITAL LETTER O WITH GRAVE */
	const int XK_Oacute                        = 0x00d3;  /* U+00D3 LATIN CAPITAL LETTER O WITH ACUTE */
	const int XK_Ocircumflex                   = 0x00d4;  /* U+00D4 LATIN CAPITAL LETTER O WITH CIRCUMFLEX */
	const int XK_Otilde                        = 0x00d5;  /* U+00D5 LATIN CAPITAL LETTER O WITH TILDE */
	const int XK_Odiaeresis                    = 0x00d6;  /* U+00D6 LATIN CAPITAL LETTER O WITH DIAERESIS */
	const int XK_multiply                      = 0x00d7;  /* U+00D7 MULTIPLICATION SIGN */
	const int XK_Oslash                        = 0x00d8;  /* U+00D8 LATIN CAPITAL LETTER O WITH STROKE */
	const int XK_Ooblique                      = 0x00d8;  /* U+00D8 LATIN CAPITAL LETTER O WITH STROKE */
	const int XK_Ugrave                        = 0x00d9;  /* U+00D9 LATIN CAPITAL LETTER U WITH GRAVE */
	const int XK_Uacute                        = 0x00da;  /* U+00DA LATIN CAPITAL LETTER U WITH ACUTE */
	const int XK_Ucircumflex                   = 0x00db;  /* U+00DB LATIN CAPITAL LETTER U WITH CIRCUMFLEX */
	const int XK_Udiaeresis                    = 0x00dc;  /* U+00DC LATIN CAPITAL LETTER U WITH DIAERESIS */
	const int XK_Yacute                        = 0x00dd;  /* U+00DD LATIN CAPITAL LETTER Y WITH ACUTE */
	const int XK_THORN                         = 0x00de;  /* U+00DE LATIN CAPITAL LETTER THORN */
	const int XK_Thorn                         = 0x00de;  /* deprecated */
	const int XK_ssharp                        = 0x00df;  /* U+00DF LATIN SMALL LETTER SHARP S */
	const int XK_agrave                        = 0x00e0;  /* U+00E0 LATIN SMALL LETTER A WITH GRAVE */
	const int XK_aacute                        = 0x00e1;  /* U+00E1 LATIN SMALL LETTER A WITH ACUTE */
	const int XK_acircumflex                   = 0x00e2;  /* U+00E2 LATIN SMALL LETTER A WITH CIRCUMFLEX */
	const int XK_atilde                        = 0x00e3;  /* U+00E3 LATIN SMALL LETTER A WITH TILDE */
	const int XK_adiaeresis                    = 0x00e4;  /* U+00E4 LATIN SMALL LETTER A WITH DIAERESIS */
	const int XK_aring                         = 0x00e5;  /* U+00E5 LATIN SMALL LETTER A WITH RING ABOVE */
	const int XK_ae                            = 0x00e6;  /* U+00E6 LATIN SMALL LETTER AE */
	const int XK_ccedilla                      = 0x00e7;  /* U+00E7 LATIN SMALL LETTER C WITH CEDILLA */
	const int XK_egrave                        = 0x00e8;  /* U+00E8 LATIN SMALL LETTER E WITH GRAVE */
	const int XK_eacute                        = 0x00e9;  /* U+00E9 LATIN SMALL LETTER E WITH ACUTE */
	const int XK_ecircumflex                   = 0x00ea;  /* U+00EA LATIN SMALL LETTER E WITH CIRCUMFLEX */
	const int XK_ediaeresis                    = 0x00eb;  /* U+00EB LATIN SMALL LETTER E WITH DIAERESIS */
	const int XK_igrave                        = 0x00ec;  /* U+00EC LATIN SMALL LETTER I WITH GRAVE */
	const int XK_iacute                        = 0x00ed;  /* U+00ED LATIN SMALL LETTER I WITH ACUTE */
	const int XK_icircumflex                   = 0x00ee;  /* U+00EE LATIN SMALL LETTER I WITH CIRCUMFLEX */
	const int XK_idiaeresis                    = 0x00ef;  /* U+00EF LATIN SMALL LETTER I WITH DIAERESIS */
	const int XK_eth                           = 0x00f0;  /* U+00F0 LATIN SMALL LETTER ETH */
	const int XK_ntilde                        = 0x00f1;  /* U+00F1 LATIN SMALL LETTER N WITH TILDE */
	const int XK_ograve                        = 0x00f2;  /* U+00F2 LATIN SMALL LETTER O WITH GRAVE */
	const int XK_oacute                        = 0x00f3;  /* U+00F3 LATIN SMALL LETTER O WITH ACUTE */
	const int XK_ocircumflex                   = 0x00f4;  /* U+00F4 LATIN SMALL LETTER O WITH CIRCUMFLEX */
	const int XK_otilde                        = 0x00f5;  /* U+00F5 LATIN SMALL LETTER O WITH TILDE */
	const int XK_odiaeresis                    = 0x00f6;  /* U+00F6 LATIN SMALL LETTER O WITH DIAERESIS */
	const int XK_division                      = 0x00f7;  /* U+00F7 DIVISION SIGN */
	const int XK_oslash                        = 0x00f8;  /* U+00F8 LATIN SMALL LETTER O WITH STROKE */
	const int XK_ooblique                      = 0x00f8;  /* U+00F8 LATIN SMALL LETTER O WITH STROKE */
	const int XK_ugrave                        = 0x00f9;  /* U+00F9 LATIN SMALL LETTER U WITH GRAVE */
	const int XK_uacute                        = 0x00fa;  /* U+00FA LATIN SMALL LETTER U WITH ACUTE */
	const int XK_ucircumflex                   = 0x00fb;  /* U+00FB LATIN SMALL LETTER U WITH CIRCUMFLEX */
	const int XK_udiaeresis                    = 0x00fc;  /* U+00FC LATIN SMALL LETTER U WITH DIAERESIS */
	const int XK_yacute                        = 0x00fd;  /* U+00FD LATIN SMALL LETTER Y WITH ACUTE */
	const int XK_thorn                         = 0x00fe;  /* U+00FE LATIN SMALL LETTER THORN */
	const int XK_ydiaeresis                    = 0x00ff;  /* U+00FF LATIN SMALL LETTER Y WITH DIAERESIS */
}
/*
 * Latin 2
 * Byte 3 = 1
 */
static if( XK_LATIN2 ){
	const int XK_Aogonek                       = 0x01a1;  /* U+0104 LATIN CAPITAL LETTER A WITH OGONEK */
	const int XK_breve                         = 0x01a2;  /* U+02D8 BREVE */
	const int XK_Lstroke                       = 0x01a3;  /* U+0141 LATIN CAPITAL LETTER L WITH STROKE */
	const int XK_Lcaron                        = 0x01a5;  /* U+013D LATIN CAPITAL LETTER L WITH CARON */
	const int XK_Sacute                        = 0x01a6;  /* U+015A LATIN CAPITAL LETTER S WITH ACUTE */
	const int XK_Scaron                        = 0x01a9;  /* U+0160 LATIN CAPITAL LETTER S WITH CARON */
	const int XK_Scedilla                      = 0x01aa;  /* U+015E LATIN CAPITAL LETTER S WITH CEDILLA */
	const int XK_Tcaron                        = 0x01ab;  /* U+0164 LATIN CAPITAL LETTER T WITH CARON */
	const int XK_Zacute                        = 0x01ac;  /* U+0179 LATIN CAPITAL LETTER Z WITH ACUTE */
	const int XK_Zcaron                        = 0x01ae;  /* U+017D LATIN CAPITAL LETTER Z WITH CARON */
	const int XK_Zabovedot                     = 0x01af;  /* U+017B LATIN CAPITAL LETTER Z WITH DOT ABOVE */
	const int XK_aogonek                       = 0x01b1;  /* U+0105 LATIN SMALL LETTER A WITH OGONEK */
	const int XK_ogonek                        = 0x01b2;  /* U+02DB OGONEK */
	const int XK_lstroke                       = 0x01b3;  /* U+0142 LATIN SMALL LETTER L WITH STROKE */
	const int XK_lcaron                        = 0x01b5;  /* U+013E LATIN SMALL LETTER L WITH CARON */
	const int XK_sacute                        = 0x01b6;  /* U+015B LATIN SMALL LETTER S WITH ACUTE */
	const int XK_caron                         = 0x01b7;  /* U+02C7 CARON */
	const int XK_scaron                        = 0x01b9;  /* U+0161 LATIN SMALL LETTER S WITH CARON */
	const int XK_scedilla                      = 0x01ba;  /* U+015F LATIN SMALL LETTER S WITH CEDILLA */
	const int XK_tcaron                        = 0x01bb;  /* U+0165 LATIN SMALL LETTER T WITH CARON */
	const int XK_zacute                        = 0x01bc;  /* U+017A LATIN SMALL LETTER Z WITH ACUTE */
	const int XK_doubleacute                   = 0x01bd;  /* U+02DD DOUBLE ACUTE ACCENT */
	const int XK_zcaron                        = 0x01be;  /* U+017E LATIN SMALL LETTER Z WITH CARON */
	const int XK_zabovedot                     = 0x01bf;  /* U+017C LATIN SMALL LETTER Z WITH DOT ABOVE */
	const int XK_Racute                        = 0x01c0;  /* U+0154 LATIN CAPITAL LETTER R WITH ACUTE */
	const int XK_Abreve                        = 0x01c3;  /* U+0102 LATIN CAPITAL LETTER A WITH BREVE */
	const int XK_Lacute                        = 0x01c5;  /* U+0139 LATIN CAPITAL LETTER L WITH ACUTE */
	const int XK_Cacute                        = 0x01c6;  /* U+0106 LATIN CAPITAL LETTER C WITH ACUTE */
	const int XK_Ccaron                        = 0x01c8;  /* U+010C LATIN CAPITAL LETTER C WITH CARON */
	const int XK_Eogonek                       = 0x01ca;  /* U+0118 LATIN CAPITAL LETTER E WITH OGONEK */
	const int XK_Ecaron                        = 0x01cc;  /* U+011A LATIN CAPITAL LETTER E WITH CARON */
	const int XK_Dcaron                        = 0x01cf;  /* U+010E LATIN CAPITAL LETTER D WITH CARON */
	const int XK_Dstroke                       = 0x01d0;  /* U+0110 LATIN CAPITAL LETTER D WITH STROKE */
	const int XK_Nacute                        = 0x01d1;  /* U+0143 LATIN CAPITAL LETTER N WITH ACUTE */
	const int XK_Ncaron                        = 0x01d2;  /* U+0147 LATIN CAPITAL LETTER N WITH CARON */
	const int XK_Odoubleacute                  = 0x01d5;  /* U+0150 LATIN CAPITAL LETTER O WITH DOUBLE ACUTE */
	const int XK_Rcaron                        = 0x01d8;  /* U+0158 LATIN CAPITAL LETTER R WITH CARON */
	const int XK_Uring                         = 0x01d9;  /* U+016E LATIN CAPITAL LETTER U WITH RING ABOVE */
	const int XK_Udoubleacute                  = 0x01db;  /* U+0170 LATIN CAPITAL LETTER U WITH DOUBLE ACUTE */
	const int XK_Tcedilla                      = 0x01de;  /* U+0162 LATIN CAPITAL LETTER T WITH CEDILLA */
	const int XK_racute                        = 0x01e0;  /* U+0155 LATIN SMALL LETTER R WITH ACUTE */
	const int XK_abreve                        = 0x01e3;  /* U+0103 LATIN SMALL LETTER A WITH BREVE */
	const int XK_lacute                        = 0x01e5;  /* U+013A LATIN SMALL LETTER L WITH ACUTE */
	const int XK_cacute                        = 0x01e6;  /* U+0107 LATIN SMALL LETTER C WITH ACUTE */
	const int XK_ccaron                        = 0x01e8;  /* U+010D LATIN SMALL LETTER C WITH CARON */
	const int XK_eogonek                       = 0x01ea;  /* U+0119 LATIN SMALL LETTER E WITH OGONEK */
	const int XK_ecaron                        = 0x01ec;  /* U+011B LATIN SMALL LETTER E WITH CARON */
	const int XK_dcaron                        = 0x01ef;  /* U+010F LATIN SMALL LETTER D WITH CARON */
	const int XK_dstroke                       = 0x01f0;  /* U+0111 LATIN SMALL LETTER D WITH STROKE */
	const int XK_nacute                        = 0x01f1;  /* U+0144 LATIN SMALL LETTER N WITH ACUTE */
	const int XK_ncaron                        = 0x01f2;  /* U+0148 LATIN SMALL LETTER N WITH CARON */
	const int XK_odoubleacute                  = 0x01f5;  /* U+0151 LATIN SMALL LETTER O WITH DOUBLE ACUTE */
	const int XK_rcaron                        = 0x01f8;  /* U+0159 LATIN SMALL LETTER R WITH CARON */
	const int XK_uring                         = 0x01f9;  /* U+016F LATIN SMALL LETTER U WITH RING ABOVE */
	const int XK_udoubleacute                  = 0x01fb;  /* U+0171 LATIN SMALL LETTER U WITH DOUBLE ACUTE */
	const int XK_tcedilla                      = 0x01fe;  /* U+0163 LATIN SMALL LETTER T WITH CEDILLA */
	const int XK_abovedot                      = 0x01ff;  /* U+02D9 DOT ABOVE */
}

