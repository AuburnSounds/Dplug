import dplug.graphics.image;
import dplug.graphics.view;
import dplug.core.nogc;
import dplug.window;
import gfm.math.box;
import std.stdio;

class WindowListener : IWindowListener {
    IWindow window;
    ImageRef!RGBA image;
    ubyte counter;

    nothrow @nogc:
        bool onMouseClick(int x, int y, MouseButton mb, bool isDoubleClick, MouseState mstate) {
            static void func(int x, int y, MouseButton mb, bool isDoubleClick, MouseState mstate) {
                writeln("onMouseClick: ", x, "x", y, " ", mb, " ", isDoubleClick, " ", mstate);
            }

            assumeNothrowNoGC(&func)(x, y, mb, isDoubleClick, mstate);

            return true;
        }

        bool onMouseRelease(int x, int y, MouseButton mb, MouseState mstate) {
            static void func(int x, int y, MouseButton mb, MouseState mstate) {
                writeln("onMouseRelease: ", x, "x", y, " ", mb, " ", mstate);
            }

            assumeNothrowNoGC(&func)(x, y, mb, mstate);

            return true;
        }

        bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate) {
            static void func(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate) {
                writeln("onMouseWheel: ", x, "x", y, " ", wheelDeltaX, " ", wheelDeltaY, " ", mstate);
            }

            assumeNothrowNoGC(&func)(x, y, wheelDeltaX, wheelDeltaY, mstate);

            return true;
        }

        void onMouseMove(int x, int y, int dx, int dy, MouseState mstate) {
            static void func(int x, int y, int dx, int dy, MouseState mstate) {
                writeln("onMouseMove: ", x, "x", y, " ", dx, "x", dy, " ", mstate);
            }

            assumeNothrowNoGC(&func)(x, y, dx, dy, mstate);
        }

        bool onKeyDown(Key key) {
            static void func(Key key) {
                writeln("onKeyDown: ", key);
            }

            assumeNothrowNoGC(&func)(key);

            return true;
        }

        bool onKeyUp(Key key) {
            static void func(Key key) {
                writeln("onKeyUp: ", key);
            }

            assumeNothrowNoGC(&func)(key);

            return true;
        }

        void onDraw(WindowPixelFormat pf) {
            if (image.pixels !is null) {
                foreach(y; 0 .. image.h) {
                    //image.scanline(y)[] = RGBA(255, 255, 255, 255);
                    //image.scanline(y)[] = RGBA(255, 127, 127, 255);
                    //image.scanline(y)[] = RGBA(counter, counter, counter, 255);
                }
            }
        }

        ImageRef!RGBA onResized(int width, int height) {
            if (image.pixels !is null) {
              freeSlice(image.pixels[0 .. image.w*image.h]);
            }

            image.w = width;
            image.h = height;
            image.pixels = mallocSlice!RGBA(width*height).ptr;
            image.pitch = width*RGBA.sizeof;
            return image;
        }

        void recomputeDirtyAreas() { }
        box2i getDirtyRectangle() { return box2i(0, 0, image.w, image.h); }
        void onMouseCaptureCancelled() { }

        void onAnimate(double dt, double time) {
            static void func(double dt, double time) {
                writeln("onAnimate[", time, "]: ", dt);
            }

            counter += cast(ubyte)dt;
            assumeNothrowNoGC(&func)(dt, time);
        }
    }

void main() {
    writeln("Hi!");

    auto listener = mallocNew!WindowListener;

    IWindow window = createWindow(WindowUsage.host, null, null, listener, WindowBackend.autodetect, 800, 600);
    listener.window = window;
    while(!window.terminated) 
        window.waitEventAndDispatch;

    writeln("END");
}
