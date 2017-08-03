module derelict.x11.extensions.damagewire;

version(linux):

/*
 * Copyright © 2003 Keith Packard
 *
 * Permission to use, copy, modify, distribute, and sell this software and its
 * documentation for any purpose is hereby granted without fee, provided that
 * the above copyright notice appear in all copies and that both that
 * copyright notice and this permission notice appear in supporting
 * documentation, and that the name of Keith Packard not be used in
 * advertising or publicity pertaining to distribution of the software without
 * specific, written prior permission.  Keith Packard makes no
 * representations about the suitability of this software for any purpose.  It
 * is provided "as is" without express or implied warranty.
 *
 * KEITH PACKARD DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
 * INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS, IN NO
 * EVENT SHALL KEITH PACKARD BE LIABLE FOR ANY SPECIAL, INDIRECT OR
 * CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE,
 * DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
 * TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
 * PERFORMANCE OF THIS SOFTWARE.
 */

enum DAMAGE_NAME                    = "DAMAGE";
enum DAMAGE_MAJOR                   = 1;
enum DAMAGE_MINOR                   = 1;

/************* Version 1 ****************/

/* Constants */
enum XDamageReportRawRectangles     = 0;
enum XDamageReportDeltaRectangles   = 1;
enum XDamageReportBoundingBox       = 2;
enum XDamageReportNonEmpty          = 3;

/* Requests */
enum X_DamageQueryVersion           = 0;
enum X_DamageCreate                 = 1;
enum X_DamageDestroy                = 2;
enum X_DamageSubtract               = 3;
enum X_DamageAdd                    = 4;

enum XDamageNumberRequests          = (X_DamageAdd + 1);

/* Events */
enum XDamageNotify                  = 0;

enum XDamageNumberEvents            = (XDamageNotify + 1);

/* Errors */
enum BadDamage                      = 0;
enum XDamageNumberErrors            = (BadDamage + 1);
