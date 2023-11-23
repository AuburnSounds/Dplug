/**
Film-strip on/off switch.

Copyright: Ethan Reker 2017.
Copyright: Guillaume Piolat 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/

module dplug.flatwidgets.flatswitch;

import std.math;
import dplug.core.math;
import dplug.gui.element;
import dplug.client.params;

class UIImageSwitch : UIElement, IParameterListener
{
public:
nothrow:
@nogc:

    enum Orientation
    {
        vertical,
        horizontal
    }

    @ScriptProperty
    {
        Orientation orientation = Orientation.vertical;
    }

    this(UIContext context, BoolParameter param, OwnedImage!RGBA onImage, OwnedImage!RGBA offImage)
    {
        super(context, flagRaw);
        _param = param;
        _param.addListener(this);

        _onImage = onImage;
        _offImage = offImage;
        assert(_onImage.h == _offImage.h);
        assert(_onImage.w == _offImage.w);
        _width = _onImage.w;
        _height = _onImage.h;

        _onImageScaled = mallocNew!(OwnedImage!RGBA)();
        _offImageScaled = mallocNew!(OwnedImage!RGBA)();

    }

    ~this()
    {
        _param.removeListener(this);
        _onImageScaled.destroyFree();
        _offImageScaled.destroyFree();
    }

    bool getState()
    {
      return unsafeObjectCast!BoolParameter(_param).valueAtomic();
    }

    override void reflow()
    {
        _onImageScaled.size(position.width, position.height);
        _offImageScaled.size(position.width, position.height);
        context.globalImageResizer.resizeImage_sRGBWithAlpha(_onImage.toRef, _onImageScaled.toRef);
        context.globalImageResizer.resizeImage_sRGBWithAlpha(_offImage.toRef, _offImageScaled.toRef);
    }

    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
          auto _currentImage = getState() ? _onImageScaled : _offImageScaled;
          foreach(dirtyRect; dirtyRects)
          {
              auto croppedRawIn = _currentImage.toRef.cropImageRef(dirtyRect);
              auto croppedRawOut = rawMap.cropImageRef(dirtyRect);

              int w = dirtyRect.width;
              int h = dirtyRect.height;

              for(int j = 0; j < h; ++j)
              {
                  RGBA[] input = croppedRawIn.scanline(j);
                  RGBA[] output = croppedRawOut.scanline(j);

                  for(int i = 0; i < w; ++i)
                  {
                      ubyte alpha = input[i].a;

                      RGBA color = blendColor(input[i], output[i], alpha);
                      output[i] = color;
                  }
              }
          }
    }

    override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        if (!_canBeDragged)
        {
            // inside gesture, refuse new clicks that could call
            // excess beginParamEdit()/endParamEdit()
            return Click.unhandled;
        }

        if (mstate.altPressed) // reset on ALT + click
        {
            _param.beginParamEdit();
            _param.setFromGUI(_param.defaultValue());
        }
        else
        {
            // Any click => invert
            // Note: double-click doesn't reset to default, would be annoying
            _param.beginParamEdit();
            _param.setFromGUI(!_param.value());
        }
        _canBeDragged = false;
        return Click.startDrag; 
    }

    override void onMouseEnter()
    {
        _param.beginParamHover();
        setDirtyWhole();
    }

    override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {        
    }

    override void onMouseExit()
    {
        _param.endParamHover();
        setDirtyWhole();
    }

    override void onBeginDrag()
    {
    }

    override void onStopDrag()
    {
        // End parameter edit at end of dragging, even if no parameter change happen,
        // so that touch automation restore previous parameter value at the end of the mouse 
        // gesture.
        _param.endParamEdit();
        _canBeDragged = true;
    }
    
    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {        
    }

    override void onParameterChanged(Parameter sender) nothrow @nogc
    {
        setDirtyWhole();
    }

    override void onBeginParameterEdit(Parameter sender)
    {
    }

    override void onEndParameterEdit(Parameter sender)
    {
    }

    override void onBeginParameterHover(Parameter sender)
    {
    }

    override void onEndParameterHover(Parameter sender)
    {
    }

protected:

    BoolParameter _param;
    bool _state;
    OwnedImage!RGBA _onImage;
    OwnedImage!RGBA _offImage;
    OwnedImage!RGBA _onImageScaled;
    OwnedImage!RGBA _offImageScaled;
    int _width;
    int _height;

    /// To prevent multiple-clicks having an adverse effect on automation.
    bool _canBeDragged = true;
}
