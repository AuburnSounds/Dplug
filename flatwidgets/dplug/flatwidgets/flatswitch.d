/**
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

    float animationTimeConstant = 40.0f;

    int _width;
    int _height;

    Orientation orientation = Orientation.vertical;

    this(UIContext context, BoolParameter param, OwnedImage!RGBA onImage, OwnedImage!RGBA offImage)
    {
        super(context);
        _param = param;
        _param.addListener(this);
        _animation = 0.0f;

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

    override void onAnimate(double dt, double time) nothrow @nogc
    {
        float target = _param.value() ? 1 : 0;

        float newAnimation = lerp(_animation, target, 1.0 - exp(-dt * animationTimeConstant));

        if (abs(newAnimation - _animation) > 0.001f)
        {
            _animation = newAnimation;
            setDirtyWhole();
        }
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
  		auto _currentImage = getState() ? _onImage : _offImage;
  		foreach(dirtyRect; dirtyRects){

  			//float radius = getRadius();
  			//vec2f center = getCenter();

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
        //_shouldBeHighlighted = containsPoint(x, y);
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

    /// The parameter this switch is linked with.
    BoolParameter _param;
    bool _state;
    OwnedImage!RGBA _onImage;
    OwnedImage!RGBA _offImage;

private:
    float _animation;
}
