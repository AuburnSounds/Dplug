module derelict.x11.extensions.render;

version(linux):

import derelict.x11.X;

alias XID		Glyph;
alias XID		GlyphSet;
alias XID		Picture;
alias XID		PictFormat;

enum RENDER_NAME	= "RENDER";
enum RENDER_MAJOR	= 0;
enum RENDER_MINOR	= 11;

enum X_RenderQueryVersion		        = 0;
enum X_RenderQueryPictFormats	        = 1;
enum X_RenderQueryPictIndexValues	    = 2	/* 0.7 */;
enum X_RenderQueryDithers		        = 3;
enum X_RenderCreatePicture		        = 4;
enum X_RenderChangePicture		        = 5;
enum X_RenderSetPictureClipRectangles   = 6;
enum X_RenderFreePicture	    	    = 7;
enum X_RenderComposite		            = 8;
enum X_RenderScale			            = 9;
enum X_RenderTrapezoids		            = 10;
enum X_RenderTriangles		            = 11;
enum X_RenderTriStrip		            = 12;
enum X_RenderTriFan			            = 13;
enum X_RenderColorTrapezoids		    = 14;
enum X_RenderColorTriangles		        = 15;
/* enum X_RenderTransform		        = 16 */;
enum X_RenderCreateGlyphSet		        = 17;
enum X_RenderReferenceGlyphSet	        = 18;
enum X_RenderFreeGlyphSet		        = 19;
enum X_RenderAddGlyphs		            = 20;
enum X_RenderAddGlyphsFromPicture	    = 21;
enum X_RenderFreeGlyphs		            = 22;
enum X_RenderCompositeGlyphs8	        = 23;
enum X_RenderCompositeGlyphs16	        = 24;
enum X_RenderCompositeGlyphs32	        = 25;
enum X_RenderFillRectangles		        = 26;
/* 0.5 */
enum X_RenderCreateCursor		        = 27;
/* 0.6 */
enum X_RenderSetPictureTransform	    = 28;
enum X_RenderQueryFilters		        = 29;
enum X_RenderSetPictureFilter	        = 30;
/* 0.8 */
enum X_RenderCreateAnimCursor	        = 31;
/* 0.9 */
enum X_RenderAddTraps		            = 32;
/* 0.10 */
enum X_RenderCreateSolidFill            = 33;
enum X_RenderCreateLinearGradient       = 34;
enum X_RenderCreateRadialGradient       = 35;
enum X_RenderCreateConicalGradient      = 36;
enum RenderNumberRequests		        = (X_RenderCreateConicalGradient+1);

enum BadPictFormat		    = 0;
enum BadPicture			    = 1;
enum BadPictOp			    = 2;
enum BadGlyphSet			= 3;
enum BadGlyph			    = 4;
enum RenderNumberErrors		= (BadGlyph+1);

enum PictTypeIndexed		= 0;
enum PictTypeDirect			= 1;

enum PictOpMinimum			= 0;
enum PictOpClear			= 0;
enum PictOpSrc			    = 1;
enum PictOpDst			    = 2;
enum PictOpOver			    = 3;
enum PictOpOverReverse		= 4;
enum PictOpIn			    = 5;
enum PictOpInReverse		= 6;
enum PictOpOut			    = 7;
enum PictOpOutReverse		= 8;
enum PictOpAtop			    = 9;
enum PictOpAtopReverse		= 10;
enum PictOpXor			    = 11;
enum PictOpAdd			    = 12;
enum PictOpSaturate			= 13;
enum PictOpMaximum			= 13;

/*
 * Operators only available in version 0.2
 */
enum PictOpDisjointMinimum		    = 0x10;
enum PictOpDisjointClear			= 0x10;
enum PictOpDisjointSrc			    = 0x11;
enum PictOpDisjointDst			    = 0x12;
enum PictOpDisjointOver			    = 0x13;
enum PictOpDisjointOverReverse		= 0x14;
enum PictOpDisjointIn			    = 0x15;
enum PictOpDisjointInReverse		= 0x16;
enum PictOpDisjointOut			    = 0x17;
enum PictOpDisjointOutReverse		= 0x18;
enum PictOpDisjointAtop			    = 0x19;
enum PictOpDisjointAtopReverse		= 0x1a;
enum PictOpDisjointXor			    = 0x1b;
enum PictOpDisjointMaximum			= 0x1b;

enum PictOpConjointMinimum			= 0x20;
enum PictOpConjointClear			= 0x20;
enum PictOpConjointSrc			    = 0x21;
enum PictOpConjointDst			    = 0x22;
enum PictOpConjointOver			    = 0x23;
enum PictOpConjointOverReverse		= 0x24;
enum PictOpConjointIn			    = 0x25;
enum PictOpConjointInReverse		= 0x26;
enum PictOpConjointOut			    = 0x27;
enum PictOpConjointOutReverse		= 0x28;
enum PictOpConjointAtop			    = 0x29;
enum PictOpConjointAtopReverse		= 0x2a;
enum PictOpConjointXor			    = 0x2b;
enum PictOpConjointMaximum			= 0x2b;

/*
 * Operators only available in version 0.11
 */
enum PictOpBlendMinimum			    = 0x30;
enum PictOpMultiply				    = 0x30;
enum PictOpScreen				    = 0x31;
enum PictOpOverlay				    = 0x32;
enum PictOpDarken				    = 0x33;
enum PictOpLighten				    = 0x34;
enum PictOpColorDodge			    = 0x35;
enum PictOpColorBurn				= 0x36;
enum PictOpHardLight				= 0x37;
enum PictOpSoftLight				= 0x38;
enum PictOpDifference			    = 0x39;
enum PictOpExclusion				= 0x3a;
enum PictOpHSLHue				    = 0x3b;
enum PictOpHSLSaturation			= 0x3c;
enum PictOpHSLColor				    = 0x3d;
enum PictOpHSLLuminosity			= 0x3e;
enum PictOpBlendMaximum			    = 0x3e;

enum PolyEdgeSharp			    = 0;
enum PolyEdgeSmooth			    = 1;

enum PolyModePrecise			= 0;
enum PolyModeImprecise		    = 1;

enum CPRepeat			        = (1 << 0);
enum CPAlphaMap			        = (1 << 1);
enum CPAlphaXOrigin			    = (1 << 2);
enum CPAlphaYOrigin			    = (1 << 3);
enum CPClipXOrigin			    = (1 << 4);
enum CPClipYOrigin			    = (1 << 5);
enum CPClipMask			        = (1 << 6);
enum CPGraphicsExposure		    = (1 << 7);
enum CPSubwindowMode			= (1 << 8);
enum CPPolyEdge			        = (1 << 9);
enum CPPolyMode			        = (1 << 10);
enum CPDither			        = (1 << 11);
enum CPComponentAlpha		    = (1 << 12);
enum CPLastBit			        = 12;

/* Filters included in 0.6 */
enum FilterNearest			    = "nearest";
enum FilterBilinear			    = "bilinear";
/* Filters included in 0.10 */
enum FilterConvolution		    = "convolution";

enum FilterFast			        = "fast";
enum FilterGood			        = "good";
enum FilterBest			        = "best";

enum FilterAliasNone			= -1;

/* Subpixel orders included in 0.6 */
enum SubPixelUnknown			= 0;
enum SubPixelHorizontalRGB		= 1;
enum SubPixelHorizontalBGR		= 2;
enum SubPixelVerticalRGB		= 3;
enum SubPixelVerticalBGR		= 4;
enum SubPixelNone			    = 5;

/* Extended repeat attributes included in 0.10 */
enum RepeatNone                 = 0;
enum RepeatNormal               = 1;
enum RepeatPad                  = 2;
enum RepeatReflect              = 3;
