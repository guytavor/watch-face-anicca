import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

//! Particle counts tried in turn after each wrist raise
const PROBE_LEVELS = [200, 400, 800, 1200] as Array<Number>;
//! Each level runs this long; the first PROBE_WARM_UP_MS (while new particles phase in) are not measured
const PROBE_LEVEL_MS = 2200;
const PROBE_WARM_UP_MS = 800;
const PROBE_FRAME_MS = 50;
const PROBE_STORAGE_KEY = "results";
const PROBE_OCHRE = 0xD9A04A;
const PROBE_TEXT = 0xBBBBBB;

//! Feasibility probe: shows whether a meditation was recorded today, and how fast the watch draws N points of light.
//! On every wrist raise it animates the time with each particle count of PROBE_LEVELS for 2.2 seconds and lists the
//! frame rate and drawing time each one reached; the last results are kept when the watch face restarts.
class ProbeView extends WatchUi.WatchFace {

    private var _glyphs as TimeGlyphs = new TimeGlyphs();
    private var _field as ParticleField or Null = null;
    private var _meditation as MeditationCheck = new MeditationCheck(true);
    private var _timer as Timer.Timer or Null = null;
    private var _levelIndex as Number = -1;
    private var _levelStartedAt as Number = 0;
    private var _frames as Number = 0;
    private var _drawMilliseconds as Number = 0;
    //! [particles, frames per second x 10, average milliseconds per frame] for each level
    private var _results as Array<Array<Number> > = [] as Array<Array<Number> >;

    public function initialize() {
        WatchFace.initialize();
        var saved = Application.Storage.getValue(PROBE_STORAGE_KEY);
        if (saved instanceof Array) {
            _results = saved as Array<Array<Number> >;
        }
    }

    public function onShow() as Void {
        startSweep();
    }

    public function onHide() as Void {
        stopTimer();
    }

    public function onExitSleep() as Void {
        startSweep();
    }

    public function onEnterSleep() as Void {
        stopTimer();
        _levelIndex = -1;
        _field = null;
        WatchUi.requestUpdate();
    }

    private function startSweep() as Void {
        _results = [] as Array<Array<Number> >;
        startLevel(0);
        if (_timer == null) {
            var timer = new Timer.Timer();
            timer.start(method(:onFrameTimer), PROBE_FRAME_MS, true);
            _timer = timer;
        }
    }

    private function stopTimer() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    public function onFrameTimer() as Void {
        WatchUi.requestUpdate();
    }

    private function startLevel(index as Number) as Void {
        _levelIndex = index;
        _field = null;
        var cohorts = PROBE_LEVELS[index] / COHORT_SIZE;
        var field = new ParticleField(_glyphs, [cohorts, 0, 0, 0] as Array<Number>);
        field.setActive(KIND_DIGIT, cohorts, PROBE_OCHRE, 0.85);
        _field = field;
        _levelStartedAt = System.getTimer();
        _frames = 0;
        _drawMilliseconds = 0;
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        _glyphs.setText((now.hour as Number).format("%02d") + ":" + (now.min as Number).format("%02d"), 227, 222);

        var field = _field;
        if (field != null) {
            var started = System.getTimer();
            field.draw(dc, started);
            var finished = System.getTimer();
            var elapsed = finished - _levelStartedAt - PROBE_WARM_UP_MS;
            if (elapsed > 0) {
                _frames++;
                _drawMilliseconds += finished - started;
            }
            if (elapsed >= PROBE_LEVEL_MS - PROBE_WARM_UP_MS) {
                var frames = _frames > 0 ? _frames : 1;
                _results.add([PROBE_LEVELS[_levelIndex], _frames * 10000 / elapsed, _drawMilliseconds / frames] as Array<Number>);
                if (_levelIndex + 1 < PROBE_LEVELS.size()) {
                    startLevel(_levelIndex + 1);
                } else {
                    Application.Storage.setValue(PROBE_STORAGE_KEY, _results);
                    _levelIndex = -1;
                    _field = null;
                    stopTimer();
                }
            }
        } else {
            dc.setColor(0x6A4E24, Graphics.COLOR_TRANSPARENT);
            _glyphs.drawSparse(dc, 2, 0, 0);
        }

        drawMeditation(dc);
        drawResults(dc);
    }

    private function drawMeditation(dc as Graphics.Dc) as Void {
        _meditation.refreshIfDue();
        var font = Graphics.FONT_XTINY;
        dc.setColor(_meditation.sitToday ? PROBE_OCHRE : 0xD67054, Graphics.COLOR_TRANSPARENT);
        dc.drawText(227, 30, Graphics.FONT_TINY, "SIT TODAY: " + (_meditation.sitToday ? "YES" : "NO"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(PROBE_TEXT, Graphics.COLOR_TRANSPARENT);
        var checkedAt = _meditation.checkedAt;
        var checked = "not checked";
        if (checkedAt != null) {
            var info = Gregorian.info(new Time.Moment(checkedAt), Time.FORMAT_SHORT);
            checked = (info.hour as Number).format("%02d") + ":" + (info.min as Number).format("%02d") + ":" +
                (info.sec as Number).format("%02d") + "  " + _meditation.queryMilliseconds + " ms  " + _meditation.entryCount + " found";
        }
        dc.drawText(227, 70, font, checked, Graphics.TEXT_JUSTIFY_CENTER);
        if (_meditation.error != null) {
            dc.drawText(227, 98, font, "error: " + _meditation.error, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        for (var i = 0; i < _meditation.entries.size() && i < 2; i++) {
            dc.drawText(227, 98 + i * 26, font, _meditation.entries[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function drawResults(dc as Graphics.Dc) as Void {
        var font = Graphics.FONT_XTINY;
        dc.setColor(PROBE_TEXT, Graphics.COLOR_TRANSPARENT);
        var heading = _levelIndex >= 0 ? "measuring " + PROBE_LEVELS[_levelIndex] + " points" : "points: fps, ms per frame";
        dc.drawText(227, 296, font, heading, Graphics.TEXT_JUSTIFY_CENTER);
        for (var i = 0; i < _results.size(); i++) {
            var result = _results[i];
            var text = result[0] + ": " + (result[1] / 10) + "." + (result[1] % 10) + ", " + result[2];
            dc.drawText(i % 2 == 0 ? 138 : 316, 324 + i / 2 * 26, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        }
        var stats = System.getSystemStats();
        dc.drawText(227, 382, font, "memory " + (stats.usedMemory / 1024) + " / " + (stats.totalMemory / 1024) + " KB",
            Graphics.TEXT_JUSTIFY_CENTER);
    }
}
