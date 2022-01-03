/**
Parameter value hint.

Copyright: Copyright Auburn Sounds 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Guillaume Piolat
*/
module dplug.pbrwidgets.paramhint;

import core.stdc.string;
import core.atomic;

import std.math;
import std.conv;
import std.algorithm.comparison;

import dplug.core;
import dplug.gui.element;
import dplug.gui.bufferedelement;
import dplug.client.params;


/// Widget that monitors the value of a parameter and
/// appears whenever it change to display its value.
class UIParamHint : UIBufferedElementPBR, IParameterListener
{
public:
nothrow:
@nogc:

    @ScriptProperty double fadeinDuration = 0.15f;
    @ScriptProperty double fadeoutDuration = 0.3f;
    @ScriptProperty double holdDuration = 0.85f;

    @ScriptProperty float textSizePx = 9.5f;
    @ScriptProperty RGBA holeDiffuse = RGBA(90, 90, 90, 0);
    
    @ScriptProperty RGBA textDiffuseLow = RGBA(90, 90, 90, 0);
    @ScriptProperty RGBA textDiffuseHigh = RGBA(42, 42, 42, 0);

    @ScriptProperty RGBA diffuseLow = RGBA(90, 90, 90, 0);
    @ScriptProperty RGBA diffuseHigh = RGBA(245, 245, 245, 30);
    @ScriptProperty RGBA material = RGBA(0, 255, 192, 255);

    @ScriptProperty RGBA plasticMaterial = RGBA(155, 240, 69, 255);
    @ScriptProperty float plasticAlpha = 0.05f;

    @ScriptProperty ushort depthLow = 0;
    @ScriptProperty ushort depthHigh = 50000;

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

        float openAnimation = min(1.0f,  _upAnimation * 2.0f);
        float moveUpAnimation = max(0.0f,  _upAnimation * 2.0f - 1.0f);

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
        bool isBeingEdited = atomicLoad(_parameterIsEdited);
        bool wasJustChanged = cas(&_parameterChanged, true, false);

        if (isBeingEdited)
            _timeSinceEdit = 0;

        if (isBeingEdited && wasJustChanged)
            _lastParamString = paramString();

        float targetAnimation = _timeSinceEdit < holdDuration ? 1 : 0;

        bool animationMoved = void;

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
        if ((wasJustChanged && isBeingEdited) || animationMoved)
            setDirtyWhole();

        _timeSinceEdit += dt;
    }

    override void onParameterChanged(Parameter sender) nothrow @nogc
    {
        atomicStore(_parameterChanged, true);
    }

    override void onBeginParameterEdit(Parameter sender)
    {
        atomicStore(_parameterIsEdited, true);
        atomicStore(_parameterChanged, true);
    }

    override void onEndParameterEdit(Parameter sender)
    {
        atomicStore(_parameterIsEdited, false);
    }

private:
    Parameter _param;

    shared(bool) _parameterIsEdited = false; // access to this is through atomic ops
    shared(bool) _parameterChanged = false;  // access to this is through atomic ops

    float _upAnimation = 0;

    double _timeSinceEdit = double.infinity;
    
    const(char)[] _lastParamString;

    Font _font;

    char[256] _pParamStringBuffer;
}

