module derelict.x11.Xproto_undef;
import derelict.x11.Xmd;

version(linux):

alias CARD32    Window;
alias CARD32    Drawable;
alias CARD32    Font;
alias CARD32    Pixmap;
alias CARD32    Cursor;
alias CARD32    Colormap;
alias CARD32    GContext;
alias CARD32    Atom;
alias CARD32    VisualID;
alias CARD32    Time;
alias CARD8     KeyCode;
alias CARD32    KeySym;
