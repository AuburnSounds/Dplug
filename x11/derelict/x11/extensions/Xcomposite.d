module derelict.x11.extensions.Xcomposite;

version(linux):

public import
	derelict.x11.X,
	derelict.x11.Xlib;

extern(C):

	alias XserverRegion = XID;

	Bool XCompositeQueryExtension (Display *dpy,
	                               int *event_base_return,
	                               int *error_base_return);

	Status XCompositeQueryVersion (Display *dpy,
	                               int     *major_version_return,
	                               int     *minor_version_return);

	int XCompositeVersion();

	void
	XCompositeRedirectWindow (Display *dpy, Window window, int update);

	void
	XCompositeRedirectSubwindows (Display *dpy, Window window, int update);

	void
	XCompositeUnredirectWindow (Display *dpy, Window window, int update);

	void
	XCompositeUnredirectSubwindows (Display *dpy, Window window, int update);

	XserverRegion
	XCompositeCreateRegionFromBorderClip (Display *dpy, Window window);

	Pixmap
	XCompositeNameWindowPixmap (Display *dpy, Window window);

	Window
	XCompositeGetOverlayWindow (Display *dpy, Window window);

	void
	XCompositeReleaseOverlayWindow (Display *dpy, Window window);
