import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

//! The time's glyphs laid out on screen as clouds of points (see tools/generate_resources.py).
//! Each glyph resource is [advance, pair, pair, ...], a pair packing two points as (x << 7 | y) << 14 | (x << 7 | y).
class TimeGlyphs {

    private var _text as String = "";
    private var _glyphs as Array<Array<Number> > = [] as Array<Array<Number> >;
    //! Screen x of each glyph's point origin
    private var _lefts as Array<Number> = [] as Array<Number>;
    //! Running total of point pairs up to and including each glyph
    private var _pairTotals as Array<Number> = [] as Array<Number>;
    private var _top as Number = 0;

    //! The point chosen by the last pickRandomPoint()
    public var pointX as Number = 0;
    public var pointY as Number = 0;

    public function initialize() {
    }

    //! Lays out `text` (digits and ":") centered on centerX, with the capitals centered on capCenterY
    public function setText(text as String, centerX as Number, capCenterY as Number) as Void {
        if (text.equals(_text)) {
            return;
        }
        _text = text;
        var characters = text.toCharArray();
        var loaded = {} as Dictionary<Char, Array<Number> >;
        _glyphs = [] as Array<Array<Number> >;
        var width = 0;
        for (var i = 0; i < characters.size(); i++) {
            var character = characters[i];
            var glyph = loaded[character];
            if (glyph == null) {
                glyph = WatchUi.loadResource(glyphResource(character)) as Array<Number>;
                loaded[character] = glyph;
            }
            _glyphs.add(glyph);
            width += glyph[0];
        }

        _lefts = [] as Array<Number>;
        _pairTotals = [] as Array<Number>;
        var penX = centerX - width / 2;
        var pairs = 0;
        for (var i = 0; i < _glyphs.size(); i++) {
            var glyph = _glyphs[i];
            _lefts.add(penX - TIME_X_PAD);
            pairs += glyph.size() - 1;
            _pairTotals.add(pairs);
            penX += glyph[0];
        }
        _top = capCenterY - TIME_CAP_HEIGHT / 2 - TIME_Y_PAD;
    }

    public function isEmpty() as Boolean {
        return _glyphs.size() == 0;
    }

    //! Sets pointX and pointY to a random point of the current time
    public function pickRandomPoint() as Void {
        var pairCount = _pairTotals[_pairTotals.size() - 1];
        var pick = Math.rand() % (pairCount * 2);
        var pair = pick >> 1;
        var index = 0;
        while (pair >= _pairTotals[index]) {
            index++;
        }
        var before = index == 0 ? 0 : _pairTotals[index - 1];
        var packed = _glyphs[index][1 + pair - before];
        var point = (pick & 1) == 0 ? packed >> 14 : packed & 0x3FFF;
        pointX = _lefts[index] + (point >> 7);
        pointY = _top + (point & 0x7F);
    }

    //! Draws every other grid point of the time as a size x size dot, offset by (shiftX, shiftY): the sparse always-on time
    public function drawSparse(dc as Graphics.Dc, size as Number, shiftX as Number, shiftY as Number) as Number {
        var count = 0;
        for (var index = 0; index < _glyphs.size(); index++) {
            var glyph = _glyphs[index];
            var left = _lefts[index] + shiftX;
            var top = _top + shiftY;
            for (var i = 1; i < glyph.size(); i++) {
                var packed = glyph[i];
                var first = packed >> 14;
                var second = packed & 0x3FFF;
                if (isSparse(first)) {
                    dc.fillRectangle(left + (first >> 7), top + (first & 0x7F), size, size);
                    count++;
                }
                if (second != first && isSparse(second)) {
                    dc.fillRectangle(left + (second >> 7), top + (second & 0x7F), size, size);
                    count++;
                }
            }
        }
        return count;
    }

    private function isSparse(point as Number) as Boolean {
        return ((point >> 7) / TIME_GRID) % 2 == 0 && ((point & 0x7F) / TIME_GRID) % 2 == 0;
    }

    private function glyphResource(character as Char) as ResourceId {
        switch (character) {
            case '0': return Rez.JsonData.Glyph0;
            case '1': return Rez.JsonData.Glyph1;
            case '2': return Rez.JsonData.Glyph2;
            case '3': return Rez.JsonData.Glyph3;
            case '4': return Rez.JsonData.Glyph4;
            case '5': return Rez.JsonData.Glyph5;
            case '6': return Rez.JsonData.Glyph6;
            case '7': return Rez.JsonData.Glyph7;
            case '8': return Rez.JsonData.Glyph8;
            case '9': return Rez.JsonData.Glyph9;
            default: return Rez.JsonData.GlyphColon;
        }
    }
}
