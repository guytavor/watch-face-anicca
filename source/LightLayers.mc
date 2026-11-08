import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

//! What a layer of points traces
enum LightKind {
    KIND_DIGIT,
    KIND_STEPS,
    KIND_MOVE,
    KIND_RING,
    KIND_COUNT,
}

//! Brightness steps over a layer's life: sin(pi * age) * FADE_PLATEAU, capped at full, so a layer fades in, stays at
//! full brightness through the middle of its life, and fades out
const FADE_LEVELS = 16;
const FADE_PLATEAU = 1.6;
const SCREEN_CENTER = 227;
const ARC_RADIUS = 194;
const RING_RADIUS = 206;
const RING_DEPTH = 10;
//! Redrawing a layer's points is the costly part of a frame (one call per point), so at most this many layers are
//! redrawn per frame; the rest stay hidden until a later frame
const REDRAWS_PER_FRAME = 2;
//! Where each kind's bitmap sits on screen, [x, y, width, height]; the time's area has room for the points' drift
const KIND_AREAS = [
    [0, 139, 454, 160],
    [50, 312, 354, 116],
    [50, 26, 354, 116],
    [0, 0, 454, 454],
] as Array<Array<Number> >;

//! Points of light drawn in layers. Each layer is a two-color bitmap (transparent, and the layer's color) holding a
//! scatter of points; it fades in and out by having its palette recolored, and is drawn with one call per frame. On
//! the watch every drawing call is costly (one call per point ran at 3 frames a second), so a frame costs a couple of
//! calls per layer, and only a layer that has faded out is redrawn, with fresh points.
class LightLayers {

    // Per layer
    private var _bitmaps as Array<Graphics.BufferedBitmapReference or Null>;
    private var _kind as Array<Number>;
    private var _born as Array<Number>;
    private var _life as Array<Number>;
    private var _points as Array<Number>;
    //! Fade level the palette was last set to, or -1
    private var _level as Array<Number>;
    //! Drift in pixels per second
    private var _velocityX as Array<Float>;
    private var _velocityY as Array<Float>;

    // Per kind
    private var _pointsPerLayer as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    private var _colors as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    private var _palettes as Array<Array<Number> > = [[], [], [], []] as Array<Array<Number> >;
    //! Color and intensity (in thousandths) each palette was made from
    private var _paletteKeys as Array<Number> = [-1, -1, -1, -1] as Array<Number>;
    //! Filled stretches of the step and move arcs: flat [low, high, low, high, ...] angles in radians, y pointing down
    private var _ranges as Array<Array<Float> > = [[], [], [], []] as Array<Array<Float> >;

    private var _glyphs as TimeGlyphs;
    private var _restlessness as Float = 1.0;
    private var _lifeScale as Float = 1.0;
    //! Layers redrawn so far, for the frame-rate log
    public var redraws as Number = 0;

    //! layerCounts: how many layers each kind has, indexed by LightKind
    public function initialize(glyphs as TimeGlyphs, layerCounts as Array<Number>) {
        _glyphs = glyphs;
        _bitmaps = [] as Array<Graphics.BufferedBitmapReference or Null>;
        _kind = [] as Array<Number>;
        _born = [] as Array<Number>;
        _life = [] as Array<Number>;
        _points = [] as Array<Number>;
        _level = [] as Array<Number>;
        _velocityX = [] as Array<Float>;
        _velocityY = [] as Array<Float>;
        for (var kind = 0; kind < KIND_COUNT; kind++) {
            for (var i = 0; i < layerCounts[kind]; i++) {
                _bitmaps.add(null);
                _kind.add(kind);
                _born.add(-1);
                _life.add(1);
                _points.add(0);
                _level.add(-1);
                _velocityX.add(0.0);
                _velocityY.add(0.0);
            }
        }
    }

    //! Sets how many points each layer of a kind gets when next redrawn (0 hides the kind), and their full color
    public function setKind(kind as LightKind, pointsPerLayer as Number, color as Number, intensity as Float) as Void {
        _pointsPerLayer[kind] = pointsPerLayer;
        var key = color + ((intensity * 1000).toNumber() << 24);
        if (_paletteKeys[kind] == key) {
            return;
        }
        _paletteKeys[kind] = key;
        var palette = new [FADE_LEVELS] as Array<Number>;
        var red = (color >> 16) & 0xFF;
        var green = (color >> 8) & 0xFF;
        var blue = color & 0xFF;
        for (var level = 0; level < FADE_LEVELS; level++) {
            var alpha = Math.sin(Math.PI * (level + 0.5) / FADE_LEVELS) * FADE_PLATEAU;
            alpha = (alpha > 1 ? 1 : alpha) * intensity;
            palette[level] = ((red * alpha).toNumber() << 16) | ((green * alpha).toNumber() << 8) | (blue * alpha).toNumber();
        }
        _palettes[kind] = palette;
        _colors[kind] = color;
        for (var layer = 0; layer < _kind.size(); layer++) {
            if (_kind[layer] == kind) {
                _level[layer] = -1;
            }
        }
    }

    //! Filled stretches of an arc, as flat [low, high, ...] angles
    public function setRanges(kind as LightKind, ranges as Array<Float>) as Void {
        _ranges[kind] = ranges;
    }

    //! restlessness scales how fast the time's layers drift; lifeScale shortens their lives
    public function setMood(restlessness as Float, lifeScale as Float) as Void {
        _restlessness = restlessness;
        _lifeScale = lifeScale;
    }

    //! Draws one frame at system time `now` (milliseconds); returns the number of points drawn
    public function draw(dc as Graphics.Dc, now as Number) as Number {
        var drawn = 0;
        var redrawBudget = REDRAWS_PER_FRAME;
        for (var layer = 0; layer < _kind.size(); layer++) {
            var kind = _kind[layer];
            if (_pointsPerLayer[kind] == 0) {
                _born[layer] = -1;
                continue;
            }
            var reference = _bitmaps[layer];
            var bitmap = reference != null ? reference.get() as Graphics.BufferedBitmap or Null : null;
            var isNew = _born[layer] < 0;
            if (bitmap == null || isNew || now - _born[layer] >= _life[layer]) {
                if (redrawBudget == 0) {
                    continue;
                }
                redrawBudget--;
                bitmap = redraw(layer, now);
                if (bitmap == null) {
                    continue;
                }
                if (isNew) {
                    // Newly shown: start part-way through a life, so the layers don't all fade in together
                    _born[layer] = now - Math.rand() % _life[layer];
                }
            }
            var age = now - _born[layer];
            var level = age * FADE_LEVELS / _life[layer];
            if (level != _level[layer]) {
                bitmap.setPalette([Graphics.COLOR_TRANSPARENT, _palettes[kind][level]] as Array<Graphics.ColorType>);
                _level[layer] = level;
            }
            var area = KIND_AREAS[kind];
            var seconds = age / 1000.0;
            dc.drawBitmap(area[0] + (_velocityX[layer] * seconds).toNumber(), area[1] + (_velocityY[layer] * seconds).toNumber(),
                bitmap);
            drawn += _points[layer];
        }
        return drawn;
    }

    //! Draws fresh points into a layer and starts its life; null when there is no graphics memory for it
    private function redraw(layer as Number, now as Number) as Graphics.BufferedBitmap or Null {
        var kind = _kind[layer];
        var area = KIND_AREAS[kind];
        var color = _colors[kind];
        // A palette bitmap can't be cleared back to transparent (clear() paints it in the opaque color), so each redraw
        // starts from a new bitmap, which starts out transparent
        _bitmaps[layer] = null;
        var bitmap;
        try {
            var reference = Graphics.createBufferedBitmap({
                :width => area[2],
                :height => area[3],
                :palette => [Graphics.COLOR_TRANSPARENT, color] as Array<Graphics.ColorType>,
            });
            bitmap = reference.get() as Graphics.BufferedBitmap or Null;
            _bitmaps[layer] = reference;
        } catch (exception) {
            return null;
        }
        if (bitmap == null) {
            return null;
        }
        redraws++;
        _level[layer] = -1;
        var dc = bitmap.getDc();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);

        var count = _pointsPerLayer[kind];
        _points[layer] = count;
        _born[layer] = now;
        _velocityX[layer] = 0.0;
        _velocityY[layer] = 0.0;
        if (kind == KIND_DIGIT) {
            _life[layer] = ((1200 + random() * 1800) * _lifeScale).toNumber();
            var angle = random() * 2 * Math.PI;
            var speed = (2.5 + random() * 3.5) * _restlessness;
            _velocityX[layer] = Math.cos(angle) * speed;
            _velocityY[layer] = Math.sin(angle) * speed - 1.6;
            if (_glyphs.isEmpty()) {
                return bitmap;
            }
            for (var i = 0; i < count; i++) {
                _glyphs.pickRandomPoint();
                var size = 2 + Math.rand() % 2;
                dc.fillRectangle(_glyphs.pointX - area[0] + Math.rand() % 3 - 1, _glyphs.pointY - area[1] + Math.rand() % 3 - 1,
                    size, size);
            }
        } else if (kind == KIND_RING) {
            _life[layer] = (2500 + random() * 3000).toNumber();
            for (var i = 0; i < count; i++) {
                var angle = random() * 2 * Math.PI;
                var radius = RING_RADIUS + random() * RING_DEPTH;
                var size = 2 + Math.rand() % 2;
                dc.fillRectangle(SCREEN_CENTER + Math.cos(angle) * radius, SCREEN_CENTER + Math.sin(angle) * radius, size, size);
            }
        } else {
            _life[layer] = (2600 * (0.6 + random() * 0.8)).toNumber();
            var ranges = _ranges[kind];
            var total = 0.0;
            for (var r = 0; r < ranges.size(); r += 2) {
                total += ranges[r + 1] - ranges[r];
            }
            if (total <= 0) {
                _points[layer] = 0;
                return bitmap;
            }
            for (var i = 0; i < count; i++) {
                var pick = random() * total;
                var angle = ranges[0];
                for (var r = 0; r < ranges.size(); r += 2) {
                    var length = ranges[r + 1] - ranges[r];
                    if (pick <= length) {
                        angle = ranges[r] + pick;
                        break;
                    }
                    pick -= length;
                }
                var radius = ARC_RADIUS + random() * 3 - 1.5;
                dc.fillRectangle(SCREEN_CENTER + Math.cos(angle) * radius - 1 - area[0],
                    SCREEN_CENTER + Math.sin(angle) * radius - 1 - area[1], 2, 2);
            }
        }
        return bitmap;
    }

    private function random() as Float {
        return (Math.rand() % 10000) / 10000.0;
    }
}
