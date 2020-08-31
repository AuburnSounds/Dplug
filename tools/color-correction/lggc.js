
var image, texture, canvas;


function uploadFile()
{
    var preview = document.getElementById('full-image'); //selects the query named img
    var file    = document.querySelector('input[type=file]').files[0]; //sames as here
    var reader  = new FileReader();

    preview.onload = function() {
        startCorrection();  
    };

    reader.onloadend = function () {
        preview.src = reader.result;
    };

    if (file) {
       reader.readAsDataURL(file); //reads the data as a URL
    } else {
       preview.src = "";
    }
}

function updateImage()
{
    var redTransferTable = new Array(256);
    var greenTransferTable = new Array(256);
    var blueTransferTable = new Array(256);

    function safePow(a, c)
    {
        if (a < 0)
            return Math.pow(0, c);
        return Math.pow(a, c);
    }

    function setColorCorrection(rLift, rGamma, rGain, rContrast,
                            gLift, gGamma, gGain, gContrast,
                            bLift, bGamma, bGain, bContrast)
    {
        for (var b = 0; b < 256; ++b)
        {
            var inp = b / 255.0;
            var outR = safePow( rGain*(inp + rLift*(1-inp)), 1/rGamma);
            var outG = safePow( gGain*(inp + gLift*(1-inp)),1/gGamma);
            var outB = safePow( bGain*(inp + bLift*(1-inp)),1/bGamma);
            if( outR < 0.0) outR = 0.0;
            if( outR > 1.0) outR = 1.0;
            if( outG < 0.0) outG = 0.0;
            if( outG > 1.0) outG = 1.0;
            if( outB < 0.0) outB = 0.0;
            if( outB > 1.0) outB = 1.0;

            function smoothStep(x)
            {
                return 3*x*x-2*x*x*x;
            }
            outR = outR  * (1 - rContrast) + rContrast * smoothStep(outR);
            outG = outG  * (1 - gContrast) + gContrast * smoothStep(outG);
            outB = outB  * (1 - bContrast) + bContrast * smoothStep(outB);

            redTransferTable[b] = [inp, outR];
            greenTransferTable[b] = [inp, outG];
            blueTransferTable[b] = [inp, outB];
        }
    }

    function elem(x) { return document.getElementById(x); }

    var lift =  parseFloat(elem('lift').value);
    var gamma = 1.0 + parseFloat(elem('gamma').value);
    var gain = 1.0 + parseFloat(elem('gain').value);
    var contrast = parseFloat(elem('contrast').value);

    var liftR = parseFloat(elem('liftR').value);
    var gammaR = parseFloat(elem('gammaR').value);
    var gainR = parseFloat(elem('gainR').value);
    var contrastR = parseFloat(elem('contrastR').value);

    var liftG = parseFloat(elem('liftG').value);
    var gammaG = parseFloat(elem('gammaG').value);
    var gainG = parseFloat(elem('gainG').value);
    var contrastG = parseFloat(elem('contrastG').value);

    var liftB = parseFloat(elem('liftB').value);
    var gammaB = parseFloat(elem('gammaB').value);
    var gainB = parseFloat(elem('gainB').value);
    var contrastB = parseFloat(elem('contrastB').value);

    elem('liftV').innerHTML = "Lift&nbsp;=&nbsp;" + lift;
    elem('gammaV').innerHTML = "Gamma&nbsp;=&nbsp;" + gamma;
    elem('gainV').innerHTML = "Gain&nbsp;=&nbsp;" + gain;
    elem('contrastV').innerHTML = "Contrast&nbsp;=&nbsp;" + contrast;

    elem('liftRV').innerHTML = "Lift&nbsp;=&nbsp;" + liftR;
    elem('gammaRV').innerHTML = "Gamma&nbsp;=&nbsp;" + gammaR;
    elem('gainRV').innerHTML = "Gain&nbsp;=&nbsp;" + gainR;
    elem('contrastRV').innerHTML = "Contrast&nbsp;=&nbsp;" + contrastR;

    elem('liftGV').innerHTML = "Lift&nbsp;=&nbsp;" + liftG;
    elem('gammaGV').innerHTML = "Gamma&nbsp;=&nbsp;" + gammaG;
    elem('gainGV').innerHTML = "Gain&nbsp;=&nbsp;" + gainG;
    elem('contrastGV').innerHTML = "Contrast&nbsp;=&nbsp;" + contrastG;

    elem('liftBV').innerHTML = "Lift&nbsp;=&nbsp;" + liftB;
    elem('gammaBV').innerHTML = "Gamma&nbsp;=&nbsp;" + gammaB;
    elem('gainBV').innerHTML = "Gain&nbsp;=&nbsp;" + gainB;
    elem('contrastBV').innerHTML = "Contrast&nbsp;=&nbsp;" + contrastB;

    setColorCorrection(lift + liftR, gamma + gammaR, gain + gainR, contrast + contrastR,
                       lift + liftG, gamma + gammaG, gain + gainG, contrast + contrastG,
                       lift + liftB, gamma + gammaB, gain + gainB, contrast + contrastB);


    // apply the ink filter
    canvas.draw(texture).curves(redTransferTable, greenTransferTable, blueTransferTable).update();

    //

    function updateCurve()
    {
        var curveDisplay = document.getElementById("curve-display");
        var W = curveDisplay.width;
        var H = curveDisplay.height;
        var ctx2d = curveDisplay.getContext('2d');

        ctx2d.globalCompositeOperation = 'copy';
        ctx2d.fillStyle = "rgba(0, 0, 0, 128)";
        ctx2d.fillRect(0, 0, W, H);

        W -= 10;
        H -= 10;

        function drawCurve(color, table)
        {
            ctx2d.lineWidth = 2;
            ctx2d.strokeStyle = color;
            ctx2d.beginPath();
            for(var i = 0; i < 256; ++i)
            {
                var y = 5 + H  - H * table[i][1];
                var x = 5 + W * (i / 255.0);
                if (i === 0)
                    ctx2d.moveTo(x, y);
                else
                    ctx2d.lineTo(x, y);
            }                 
            ctx2d.stroke();
        }

        ctx2d.globalCompositeOperation = 'lighter';
        drawCurve('rgba(128, 0, 0, 1.0)', redTransferTable);
        drawCurve('rgba(0, 128, 0, 1.0)', greenTransferTable);
        drawCurve('rgba(0, 0, 128, 1.0)', blueTransferTable);
    }

    updateCurve();
}

function startCorrection()
{

    // try to create a WebGL canvas (will fail if WebGL isn't supported)
    try {
        canvas = fx.canvas();
    } catch (e) {
        alert(e);
        return;
    }

    // remove file input
    var fileInput = document.querySelector('input[type=file]');
    var flexContainer = fileInput.parentNode;
    fileInput.parentNode.removeChild(fileInput);

    // convert the image to a texture
    image = document.getElementById('full-image');
    texture = canvas.texture(image);

    canvas.className += "rather-large";

    updateImage();

    // replace the image with the canvas
    flexContainer.appendChild(canvas);
    //image.parentNode.insertBefore(canvas, image);
    image.parentNode.removeChild(image);

    function registerSlider(sliderId)
    {
        var e = document.getElementById(sliderId)
        e.addEventListener('change', updateImage);
        var defaultValue = e.value;
        e.addEventListener('dblclick', (function() 
            { 
                e.value = defaultValue; 
                updateImage();
            }) );
    }

    registerSlider('lift');
    registerSlider('gamma');
    registerSlider('gain');
    registerSlider('contrast');
    registerSlider('liftR');
    registerSlider('gammaR');
    registerSlider('gainR');
    registerSlider('contrastR');
    registerSlider('liftG');
    registerSlider('gammaG');
    registerSlider('gainG');
    registerSlider('contrastG');
    registerSlider('liftB');
    registerSlider('gammaB');
    registerSlider('gainB');
    registerSlider('contrastB');
}

