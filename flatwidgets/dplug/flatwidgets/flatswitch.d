/**
* Film-strip on/off switch.
* Copyright: Copyright Cut Through Recordings 2017
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Ethan Reker
*/
module dplug.flatwidgets.flatswitch;

import std.math;
import dplug.core.math;
import dplug.graphics.drawex;
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

    Orientation orientation = Orientation.vertical;

    this(UIContext context, BoolParameter param, OwnedImage!RGBA onImage, OwnedImage!RGBA offImage)
    {
        super(context);
        _param = param;
        _param.addListener(this);

        _onImage = onImage;
        _offImage = offImage;
        assert(_onImage.h == _offImage.h);
        assert(_onImage.w == _offImage.w);
        _width = _onImage.w;
        _height = _onImage.h;

    }

    ~this()
    {
        _param.removeListener(this);
    }

    bool getState(){
      return unsafeObjectCast!BoolParameter(_param).valueAtomic();
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
          auto _currentImage = getState() ? _onImage : _offImage;
          foreach(dirtyRect; dirtyRects){

              auto croppedDiffuseIn = _currentImage.crop(dirtyRect);
              auto croppedDiffuseOut = diffuseMap.crop(dirtyRect);

              int w = dirtyRect.width;
              int h = dirtyRect.height;

              for(int j = 0; j < h; ++j){

                  RGBA[] input = croppedDiffuseIn.scanline(j);
                  RGBA[] output = croppedDiffuseOut.scanline(j);


                  for(int i = 0; i < w; ++i){
                      ubyte alpha = input[i].a;

                      RGBA color = RGBA.op!q{.blend(a, b, c)} (input[i], output[i], alpha);
                      output[i] = color;
                  }
              }

          }
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        // double-click => set to default
        _param.beginParamEdit();
        _param.setFromGUI(!_param.value());
        _param.endParamEdit();
        return true;
    }

    override void onMouseEnter()
    {
        setDirtyWhole();
    }

    override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
        
    }

    override void onMouseExit()
    {
        setDirtyWhole();
    }

    override void onBeginDrag()
    {

    }

    override void onStopDrag()
    {

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

protected:

    BoolParameter _param;
    bool _state;
    OwnedImage!RGBA _onImage;
    OwnedImage!RGBA _offImage;
    int _width;
    int _height;
}
