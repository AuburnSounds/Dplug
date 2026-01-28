/**
Parameter value hint.

Copyright: Copyright Auburn Sounds 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Guillaume Piolat
*/
module dplug.pbrwidgets.paramhint;

import core.stdc.string;
import core.atomic;

import dplug.core;
import dplug.gui.element;
import dplug.gui.bufferedelement;
import dplug.client.params;

/// Old widget that literally spring up from the plugin and displays 
/// a Parameter value when it is changed from the UI.
/// Was a bit ridiculous in PBR but existing plugins are using it.
/// Widget that monitors the value of a parameter and
/// appears whenever it change to display its value.
class UIParamHint : UIBufferedElementPBR, IParameterListener
{
public:
nothrow:
@nogc:

    @ScriptProperty
    {
        double fadeinDuration = 0.15f;
        double fadeoutDuration = 0.3f;
        double holdDuration = 0.85f;

        float textSizePx = 9.5f;
        RGBA holeDiffuse = RGBA(90, 90, 90, 0);
    
        RGBA textDiffuseLow = RGBA(90, 90, 90, 0);
        RGBA textDiffuseHigh = RGBA(42, 42, 42, 0);

        RGBA diffuseLow = RGBA(90, 90, 90, 0);
        RGBA diffuseHigh = RGBA(245, 245, 245, 30);
        RGBA material = RGBA(0, 255, 192, 255);

        RGBA plasticMaterial = RGBA(155, 240, 69, 255);
        float plasticAlpha = 0.05f;

        ushort depthLow = 0;
        ushort depthHigh = 50000;
    }

    this(UIContext context, Parameter param, Font font)
    {
        super(context, flagAnimated | flagPBR);
        _param = param;
        _param.addListener(this);
        _font = font;
    }

    ~this()
    {
        _param.removeListener(this);
    }

    const(char)[] paramString() nothrow @nogc
    {
        _param.toDisplayN(_pParamStringBuffer.ptr, 128);
        size_t len = strlen(_pParamStringBuffer.ptr);
        string label = _param.label();
        assert(label.length < 127);
        _pParamStringBuffer[len] = ' ';
        size_t totalLength = len + 1 + label.length;
        _pParamStringBuffer[len+1..totalLength] = label[];
        return _pParamStringBuffer[0..totalLength];
    }

    override void onDrawBufferedPBR(ImageRef!RGBA diffuseMap, 
                                    ImageRef!L16 depthMap, 
                                    ImageRef!RGBA materialMap, 
                                    ImageRef!L8 diffuseOpacity,
                                    ImageRef!L8 depthOpacity,
                                    ImageRef!L8 materialOpacity) nothrow @nogc
    {
        int W = diffuseMap.w;
        int H = diffuseMap.h;

        assert(_upAnimation >= 0 && _upAnimation <= 1);

        float openAnimation = _upAnimation * 2.0f;
        if (openAnimation > 1.0f)
            openAnimation = 1.0f;

        float moveUpAnimation = _upAnimation * 2.0f - 1.0f;
        if (openAnimation < 0.0f)
            openAnimation = 0.0f;

        box2i fullRect = box2i(0, 0, W, H);

        float holeHeight = H * openAnimation;

        box2f plasticRect = box2f(0, 0, W, H - holeHeight);
        materialMap.aaFillRectFloat(plasticRect.min.x, plasticRect.min.y, plasticRect.max.x, plasticRect.max.y, plasticMaterial, plasticAlpha);


        box2f holeRect = box2f(0, H - holeHeight, W, H);

        if (holeRect.empty)
            return;

        depthMap.aaFillRectFloat(holeRect.min.x, holeRect.min.y, holeRect.max.x, holeRect.max.y, L16(0));
        diffuseMap.aaFillRectFloat(holeRect.min.x, holeRect.min.y, holeRect.max.x, holeRect.max.y, holeDiffuse);        

        ushort labelDepth = cast(ushort)(depthLow + moveUpAnimation * (depthHigh - depthLow));

        float perspectiveAnimation = 0.8f + 0.2f * moveUpAnimation;

        float labelW = W * perspectiveAnimation;
        float labelH = H * perspectiveAnimation;
        float labelMarginW = W - labelW;
        float labelMarginH = H - labelH;

        box2f labelRect = box2f(labelMarginW * 0.5f, labelMarginH  * 0.5f, W - labelMarginW * 0.5f, H - labelMarginH * 0.5f);
        box2f labelRectCrossHole = labelRect.intersection(holeRect);

        box2i ilabelRectCrossHole = box2i(cast(int)(0.5f + labelRectCrossHole.min.x), 
                                          cast(int)(0.5f + labelRectCrossHole.min.y), 
                                          cast(int)(0.5f + labelRectCrossHole.max.x),
                                          cast(int)(0.5f + labelRectCrossHole.max.y));
        if (ilabelRectCrossHole.empty)
            return;

        // Cheating :( because depth animation isn't sufficient
        RGBA diffuse = RGBA(cast(ubyte)(0.5f + lerp!float(diffuseLow.r, diffuseHigh.r, moveUpAnimation)),
                            cast(ubyte)(0.5f + lerp!float(diffuseLow.g, diffuseHigh.g, moveUpAnimation)),
                            cast(ubyte)(0.5f + lerp!float(diffuseLow.b, diffuseHigh.b, moveUpAnimation)),
                            cast(ubyte)(0.5f + lerp!float(diffuseLow.a, diffuseHigh.a, moveUpAnimation)));

        depthMap.aaFillRectFloat(labelRectCrossHole.min.x, labelRectCrossHole.min.y, labelRectCrossHole.max.x, labelRectCrossHole.max.y, L16(labelDepth));
        materialMap.aaFillRectFloat(labelRectCrossHole.min.x, labelRectCrossHole.min.y, labelRectCrossHole.max.x, labelRectCrossHole.max.y, material);
        diffuseMap.aaFillRectFloat(labelRectCrossHole.min.x, labelRectCrossHole.min.y, labelRectCrossHole.max.x, labelRectCrossHole.max.y, diffuse);

        RGBA textDiffuse = RGBA(cast(ubyte)(0.5f + lerp!float(textDiffuseLow.r, textDiffuseHigh.r, moveUpAnimation)),
                                cast(ubyte)(0.5f + lerp!float(textDiffuseLow.g, textDiffuseHigh.g, moveUpAnimation)),
                                cast(ubyte)(0.5f + lerp!float(textDiffuseLow.b, textDiffuseHigh.b, moveUpAnimation)),
                                cast(ubyte)(0.5f + lerp!float(textDiffuseLow.a, textDiffuseHigh.a, moveUpAnimation)));

        // Draw text
        float fontSizePx = textSizePx * perspectiveAnimation;
        float textPositionX = ilabelRectCrossHole.width - labelRectCrossHole.center.x;
        float fontVerticalExtent = _font.getAscent(fontSizePx) - _font.getDescent(fontSizePx);
        float textPositionY = ilabelRectCrossHole.height - labelRect.height * 0.5f + 0.5f * _font.getHeightOfx(fontSizePx);
        diffuseMap.cropImageRef(ilabelRectCrossHole).fillText(_font, _lastParamString, fontSizePx, 0, textDiffuse, 
                                                              textPositionX, textPositionY,
                                                              HorizontalAlignment.center,
                                                              VerticalAlignment.baseline);

        // Fill opacity
        {
            float alpha = openAnimation;
            ubyte balpha = cast(ubyte)(255.0f*openAnimation + 0.5f);
            depthOpacity.fillAll(L8(balpha));
            materialOpacity.fillAll(L8(balpha));
            diffuseOpacity.fillAll(L8(balpha));
        }
    }

    override void onAnimate(double dt, double time) nothrow @nogc
    {
        bool valueChangedDueToUserEdit = cas(&_showHint, true, false);

        if (valueChangedDueToUserEdit)
        {
            _timeSinceUserEdit = 0;        
            _lastParamString = paramString();
        }

        bool beingEdited = atomicLoad(_editCount) > 0;
        bool valueHasChangedRecently = (_timeSinceUserEdit < holdDuration);

        float targetAnimation = (beingEdited || valueHasChangedRecently) ? 1.0f : 0.0f;

        bool animationMoved;

        if (_upAnimation < targetAnimation)
        {
            _upAnimation += dt / fadeinDuration;
            if (_upAnimation > targetAnimation)
                _upAnimation = targetAnimation;
            animationMoved = true;
        }
        else if (_upAnimation > targetAnimation)
        {
            _upAnimation -= dt / fadeoutDuration;
            if (_upAnimation < targetAnimation)
                _upAnimation = targetAnimation;
            animationMoved = true;
        }
        else
            animationMoved = false;
        
        // redraw if:
        // - parameter changed
        // - animation changed
        if (valueChangedDueToUserEdit || animationMoved)
            setDirtyWhole();

        _timeSinceUserEdit += dt;
    }

    override void onParameterChanged(Parameter sender) nothrow @nogc
    {
        // If the parameter change, but this without being "edited",
        // then this is probably a change from automation, and we 
        // don't need to show hints.
        int editCount = atomicLoad(_editCount);

        if (editCount > 0)
        {
            atomicStore(_showHint, true);
        }
    }

    override void onBeginParameterEdit(Parameter sender)
    {
        atomicOp!"+="(_editCount, 1);
    }

    override void onEndParameterEdit(Parameter sender)
    {
        atomicOp!"+="(_editCount, -1);
    }

    override void onBeginParameterHover(Parameter sender)
    {
        // I think it was tried to show the parameter if 
        // just hovered, and that wasn't convincing
    }

    override void onEndParameterHover(Parameter sender)
    {
    }

private:
    Parameter _param;

    shared(int) _editCount = 0;
    shared(bool) _showHint = false;

    float _upAnimation = 0;

    double _timeSinceUserEdit = double.infinity;
    
    const(char)[] _lastParamString;

    Font _font;

    char[256] _pParamStringBuffer;
}

