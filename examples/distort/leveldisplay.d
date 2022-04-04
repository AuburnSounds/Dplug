/**
Copyright: Guillaume Piolat 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module leveldisplay;

import gui;

import core.atomic;
import dplug.core;
import dplug.gui;
import dplug.canvas;

/// This widgets demonstrates how to:
/// - do a custom widget
/// - use dplug:canvas
/// - use TimedFIFO for UI feedback with sub-buffer latency
/// - render to both the Raw and PBR layer
/// For more custom widget tips, see "Dplug Tutorials 3 - Anatomy of a custom widget".
final class UILevelDisplay : UIElement
{
public:
nothrow:
@nogc:

    enum READ_OVERSAMPLING = 180;
    enum INPUT_SUBSAMPLING = 16;
    enum SAMPLES_IN_FIFO = 1024;
    enum int MIN_DISPLAYABLE_DB = -100;
    enum int MAX_DISPLAYABLE_DB =  0;

    this(UIContext context)
    {
        super(context, flagRaw | flagPBR | flagAnimated); 
        _timedFIFO.initialize(SAMPLES_IN_FIFO, INPUT_SUBSAMPLING);
        _stateToDisplay[] = -140.0f;
    }

    override void onAnimate(double dt, double time)
    {
        bool needRedraw = false;
        // Note that readOldestDataAndDropSome return the number of samples 
        // stored in _stateToDisplay[0..ret].
        if (_timedFIFO.readOldestDataAndDropSome(_stateToDisplay[], dt, READ_OVERSAMPLING))
        {
            needRedraw = true;
        }

        // Only redraw the Raw layer. This is key to have low-CPU UI widgets that can 
        // still render on the PBR layer.
        // Note: You can further improve CPU usage by not redrawing if the displayed data
        // has been only zeroes for a while.
        if (needRedraw)
            setDirtyWhole(UILayer.rawOnly);
    }

    float mapValueY(float normalized)
    {
        float W = position.width;
        float H = position.height;
        return _B + (H - 2 * _B) * (1 - normalized);
    }

    float mapValueDbY(float dB)
    {
        // clip in order to never exceed visual range
        if (dB > MAX_DISPLAYABLE_DB) dB = MAX_DISPLAYABLE_DB;
        if (dB < MIN_DISPLAYABLE_DB) dB = MIN_DISPLAYABLE_DB;
        float normalized = linmap!float(dB, MIN_DISPLAYABLE_DB, MAX_DISPLAYABLE_DB, 0, 1);
        return mapValueY(normalized);
    }

    override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        // Make a hole
        foreach(dirtyRect; dirtyRects)
        {
            depthMap.cropImageRef(dirtyRect).fillAll(L16(15000));
        }
    }

    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        float W = position.width;
        float H = position.height;

        // detector feedback, integrate to smooth things
        double detectorLevel = 0.0f;

        float openness = 0.0f;
        double squaredSum = 0;
        float GR_linear_sum = 0.0f;
        for (int sample = 0; sample < READ_OVERSAMPLING; ++sample)
        {
            double lvl = _stateToDisplay[sample];
            detectorLevel += lvl;
            squaredSum += lvl*lvl;
        }
        detectorLevel /= READ_OVERSAMPLING;
        double variance = squaredSum / READ_OVERSAMPLING - detectorLevel * detectorLevel;
        if (variance < 0) variance = 0;
        float stddev = fast_sqrt(variance);

        float detectorY = mapValueDbY(detectorLevel);
        float detectorYp1 = mapValueDbY(detectorLevel + stddev);

        foreach(dirtyRect; dirtyRects)
        {
            auto cRaw = rawMap.cropImageRef(dirtyRect);
            canvas.initialize(cRaw);
            canvas.translate(-dirtyRect.min.x, -dirtyRect.min.y);

            // Fill with dark color
            canvas.fillStyle = "rgba(0, 0, 0, 10%)";
            canvas.fillRect(0, 0, position.width, position.height);

            canvas.fillStyle = RGBA(236, 255, 128, 255);
            canvas.fillRect(_B, detectorY, W-2*_B, H-_B - detectorY);

            canvas.fillStyle = RGBA(236, 255, 128, 128);
            canvas.fillRect(_B, detectorYp1, W-2*_B, H-_B - detectorYp1);
        }
    }

    void sendFeedbackToUI(float* measuredLevel_dB, 
                          int frames, 
                          float sampleRate) nothrow @nogc
    {
        if (_storeTemp.length < frames)
            _storeTemp.reallocBuffer(frames);

        for(int n = 0; n < frames; ++n)
        {
            _storeTemp[n] = measuredLevel_dB[n];
        }
        
        _timedFIFO.pushData(_storeTemp[0..frames], sampleRate);
    }

    override void reflow()
    {
        float H = position.height;
        _S = H / 130.0f;
        _B = _S * 10; // border
    }

private:
    float _B, _S;
    Canvas canvas;
    TimedFIFO!float _timedFIFO;
    float[READ_OVERSAMPLING] _stateToDisplay; // samples, integrated for drawing
    float[] _storeTemp; // used for gathering input
}