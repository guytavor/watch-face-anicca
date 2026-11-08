import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

const COLOR_OCHRE = 0xD9A04A;
const COLOR_EMBER = 0xD67054;
//! Colors of the design's translucent greys and ochres, as they look over black
const COLOR_DATE = 0x767168;
const COLOR_DATA = 0x7E786F;
const COLOR_ICON = 0x987034;
const COLOR_WORD = 0x82602C;
const COLOR_BREATH = 0xBDB8AE;
const COLOR_SIT_ALERT = 0xB65F47;
const COLOR_TRACK = 0x222222;
const COLOR_LEAF = 0xC39043;
const COLOR_LEAF_FILL = 0x2E2210;
const COLOR_LEAF_HALO = 0x4A3618;
const COLOR_LEAF_DOTS = 0x333333;
const COLOR_ALWAYS_ON = 0x966E34;

const DAY_NAMES = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
const MONTH_NAMES = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

// Particle budget: how many points of light each element may use at most. Lower these if the animation stutters
// on the watch (the probe, ./build.sh probe, measures frame rates for 200 to 1200 points).
const DIGIT_PARTICLES = 480;
const ARC_PARTICLES = 128;
const RING_PARTICLES = 96;
const FRAME_MS = 50;

//! From 20:00, a day without a sit turns the leaf ember and the date reads TIME TO SIT
const SIT_REMINDER_HOUR = 20;
//! Garmin's stress bands: rest 0-25, low 26-50, medium 51-75, high 76-100. Medium and up count as stressed.
const STRESS_THRESHOLD = 50;

// Layout, in pixels on the 454 x 454 screen
const TIME_CENTER_Y = 219;
const LEAF_Y = 64;
const DATE_Y = 114;
const WORD_Y = 318;
const DATA_Y = 362;
const STEPS_Y = 392;
const HEART_X = 135;
const HEART_RATE_X = 148;
const SUN_X = 273;
const SUN_TIME_X = 288;
// Arcs: angles in radians, clockwise from three o'clock. Steps fill the bottom edge from the left; the move bar
// (one long and four short segments) runs along the top edge.
const STEPS_ARC_START = 2.6179939;
const MOVE_ARC_START = -2.6179939;
const ARC_SPAN = 2.0943951;
const MOVE_SEGMENT_SHARES = [0.4, 0.15, 0.15, 0.15, 0.15];
const MOVE_SEGMENT_GAP = 0.0523599;
const TRACK_DOT_SPACING = 0.0349066;
//! Always-on dots shift up to this many pixels each way, a new offset every minute
const ALWAYS_ON_SHIFT = 8;

enum SitStatus {
    SIT_DONE,
    SIT_PENDING,
    SIT_ALERT,
}

//! Anicca: the time drawn from saffron points of light that arise and pass away
class AniccaView extends WatchUi.WatchFace {

    private var _dateFont as Graphics.FontType;
    private var _dataFont as Graphics.FontType;
    private var _wordFont as Graphics.FontType;
    private var _breathFont as Graphics.FontType;
    private var _glyphs as TimeGlyphs = new TimeGlyphs();
    private var _field as ParticleField;
    private var _meditation as MeditationCheck = new MeditationCheck(false);
    private var _timer as Timer.Timer or Null = null;
    private var _isAwake as Boolean = true;
    //! Flat [low, high, ...] angles of the five move bar segments
    private var _moveSegments as Array<Float>;
    //! Flat [x, y, ...] of the faint dotted tracks under both arcs
    private var _trackDots as Array<Number>;
    private var _leafPolygon as Array<[Numeric, Numeric]>;
    //! 0 shows "anicca", 1 "observe the breath"; eases between them while awake
    private var _cueMix as Float = 0.0;
    private var _lastFrameAt as Number = 0;

    public function initialize() {
        WatchFace.initialize();
        _dateFont = WatchUi.loadResource(Rez.Fonts.Date) as Graphics.FontType;
        _dataFont = WatchUi.loadResource(Rez.Fonts.Data) as Graphics.FontType;
        _wordFont = WatchUi.loadResource(Rez.Fonts.Word) as Graphics.FontType;
        _breathFont = WatchUi.loadResource(Rez.Fonts.Breath) as Graphics.FontType;
        _field = new ParticleField(_glyphs, [DIGIT_PARTICLES / COHORT_SIZE, ARC_PARTICLES / COHORT_SIZE,
            ARC_PARTICLES / COHORT_SIZE, RING_PARTICLES / COHORT_SIZE] as Array<Number>);

        _moveSegments = [] as Array<Float>;
        var segmentStart = MOVE_ARC_START;
        var segmentCount = MOVE_SEGMENT_SHARES.size();
        for (var i = 0; i < segmentCount; i++) {
            var segmentEnd = segmentStart + ARC_SPAN * (MOVE_SEGMENT_SHARES[i] as Float);
            _moveSegments.add(segmentStart + (i == 0 ? 0 : MOVE_SEGMENT_GAP / 2));
            _moveSegments.add(segmentEnd - (i == segmentCount - 1 ? 0 : MOVE_SEGMENT_GAP / 2));
            segmentStart = segmentEnd;
        }
        _trackDots = [] as Array<Number>;
        addTrackDots(STEPS_ARC_START - ARC_SPAN, STEPS_ARC_START);
        for (var i = 0; i < _moveSegments.size(); i += 2) {
            addTrackDots(_moveSegments[i], _moveSegments[i + 1]);
        }
        _leafPolygon = [] as Array<[Numeric, Numeric]>;
        for (var i = 0; i < LEAF_OUTLINE.size(); i += 2) {
            _leafPolygon.add([SCREEN_CENTER + LEAF_OUTLINE[i], LEAF_Y + LEAF_OUTLINE[i + 1]]);
        }
    }

    private function addTrackDots(low as Float, high as Float) as Void {
        for (var angle = low; angle <= high + 0.0001; angle += TRACK_DOT_SPACING) {
            _trackDots.add(Math.round(SCREEN_CENTER + Math.cos(angle) * ARC_RADIUS).toNumber() - 1);
            _trackDots.add(Math.round(SCREEN_CENTER + Math.sin(angle) * ARC_RADIUS).toNumber() - 1);
        }
    }

    public function onShow() as Void {
        startAnimation();
    }

    public function onHide() as Void {
        stopAnimation();
    }

    public function onExitSleep() as Void {
        _isAwake = true;
        startAnimation();
        WatchUi.requestUpdate();
    }

    public function onEnterSleep() as Void {
        _isAwake = false;
        stopAnimation();
        WatchUi.requestUpdate();
    }

    //! Watch faces may only use timers in high power mode, the few seconds after a wrist raise
    private function startAnimation() as Void {
        if (_timer == null && _isAwake) {
            var timer = new Timer.Timer();
            timer.start(method(:onFrame), FRAME_MS, true);
            _timer = timer;
        }
    }

    private function stopAnimation() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    public function onFrame() as Void {
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        _glyphs.setText(timeText(now), SCREEN_CENTER, TIME_CENTER_Y);
        _meditation.refreshIfDue();

        if (!_isAwake && System.getDeviceSettings().requiresBurnInProtection) {
            drawAlwaysOn(dc, now);
            return;
        }

        var frameAt = System.getTimer();
        var seconds = _lastFrameAt == 0 ? 1.0 : (frameAt - _lastFrameAt) / 1000.0;
        _lastFrameAt = frameAt;

        var activityInfo = ActivityMonitor.getInfo();
        var stress = currentStress(activityInfo);
        var isStressed = stress > STRESS_THRESHOLD;
        var status = sitStatus(now);

        dc.setAntiAlias(true);
        drawDateOrReminder(dc, now, status);
        drawLeaf(dc, status, frameAt);
        drawWord(dc, isStressed, _isAwake ? seconds : 1.0);
        drawReadings(dc, activityInfo, now);
        drawTracks(dc);
        dc.setAntiAlias(false);

        updateParticles(activityInfo, stress);
        _field.draw(dc, frameAt);
    }

    //! Always-on: only sparse, dim, still dots for the time, moved a few pixels every minute; about 1% of pixels lit
    private function drawAlwaysOn(dc as Graphics.Dc, now as Gregorian.Info) as Void {
        var minute = (now.hour as Number) * 60 + (now.min as Number);
        var span = 2 * ALWAYS_ON_SHIFT + 1;
        var shiftX = (minute * 37 + 11) % span - ALWAYS_ON_SHIFT;
        var shiftY = (minute * 53 + 5) % span - ALWAYS_ON_SHIFT;
        dc.setColor(COLOR_ALWAYS_ON, Graphics.COLOR_TRANSPARENT);
        _glyphs.drawSparse(dc, 2, shiftX, shiftY);
        _lastFrameAt = 0;
    }

    private function updateParticles(activityInfo as ActivityMonitor.Info, stress as Number) as Void {
        var level = stress / 100.0;
        _field.setMood(1 + level * level * 1.3, 1 - level * 0.35);
        _field.setActive(KIND_DIGIT, DIGIT_PARTICLES / COHORT_SIZE, COLOR_OCHRE, 1.0);

        var ringStrength = stress > STRESS_THRESHOLD ? (stress - STRESS_THRESHOLD) / (100.0 - STRESS_THRESHOLD) : 0.0;
        var ringCohorts = Math.round(RING_PARTICLES / COHORT_SIZE * ringStrength).toNumber();
        // Intensity in steps of a tenth, so the ring's palette is rebuilt only when stress moves noticeably
        var ringIntensity = Math.round((0.35 + ringStrength * 0.5) * 10) / 10.0;
        _field.setActive(KIND_RING, ringCohorts, COLOR_OCHRE, ringIntensity);

        var progress = stepProgress(activityInfo);
        _field.setRanges(KIND_STEPS, [STEPS_ARC_START - ARC_SPAN * progress, STEPS_ARC_START] as Array<Float>);
        _field.setActive(KIND_STEPS, Math.round(ARC_PARTICLES / COHORT_SIZE * progress).toNumber(), COLOR_OCHRE, 0.9);

        var moveLevel = moveBarLevel(activityInfo);
        var filled = _moveSegments.slice(0, moveLevel * 2);
        var filledLength = 0.0;
        for (var i = 0; i < filled.size(); i += 2) {
            filledLength += filled[i + 1] - filled[i];
        }
        _field.setRanges(KIND_MOVE, filled);
        _field.setActive(KIND_MOVE, Math.round(ARC_PARTICLES / COHORT_SIZE * filledLength / ARC_SPAN).toNumber(), COLOR_EMBER, 0.9);
    }

    private function drawDateOrReminder(dc as Graphics.Dc, now as Gregorian.Info, status as SitStatus) as Void {
        var isAlert = status == SIT_ALERT;
        dc.setColor(isAlert ? COLOR_SIT_ALERT : COLOR_DATE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(SCREEN_CENTER, DATE_Y, _dateFont, isAlert ? "TIME TO SIT" : dateText(now),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! The bodhi leaf above the date: glowing once today's sit is recorded, a faint dotted outline until then, and from
    //! 20:00 without a sit, ember and pulsing
    private function drawLeaf(dc as Graphics.Dc, status as SitStatus, frameAt as Number) as Void {
        if (status == SIT_PENDING) {
            dc.setColor(COLOR_LEAF_DOTS, Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < LEAF_DOTS.size(); i += 2) {
                dc.fillRectangle(SCREEN_CENTER + LEAF_DOTS[i] - 1, LEAF_Y + LEAF_DOTS[i + 1] - 1, 2, 2);
            }
            return;
        }
        var lineColor = COLOR_LEAF;
        var veinColor = scaleColor(COLOR_LEAF, 0.55);
        if (status == SIT_DONE) {
            dc.setColor(COLOR_LEAF_FILL, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(_leafPolygon);
            dc.setPenWidth(4);
            dc.setColor(COLOR_LEAF_HALO, Graphics.COLOR_TRANSPARENT);
            drawPolyline(dc, LEAF_OUTLINE);
        } else {
            var pulse = _isAwake ? 0.55 + 0.35 * Math.sin(frameAt / 1000.0 * 2.2) : 0.75;
            lineColor = scaleColor(COLOR_EMBER, pulse);
            veinColor = scaleColor(COLOR_EMBER, pulse * 0.55);
        }
        dc.setPenWidth(1);
        dc.setColor(veinColor, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < LEAF_VEINS.size(); i++) {
            drawPolyline(dc, LEAF_VEINS[i]);
        }
        dc.setPenWidth(2);
        dc.setColor(lineColor, Graphics.COLOR_TRANSPARENT);
        drawPolyline(dc, LEAF_OUTLINE);
        drawPolyline(dc, LEAF_MIDRIB);
        dc.setPenWidth(1);
    }

    private function drawPolyline(dc as Graphics.Dc, points as Array<Float>) as Void {
        for (var i = 2; i < points.size(); i += 2) {
            dc.drawLine(SCREEN_CENTER + points[i - 2], LEAF_Y + points[i - 1], SCREEN_CENTER + points[i], LEAF_Y + points[i + 1]);
        }
    }

    //! "anicca" below the time, giving way to "observe the breath" while stress is above 50
    private function drawWord(dc as Graphics.Dc, isStressed as Boolean, seconds as Float) as Void {
        var target = isStressed ? 1.0 : 0.0;
        var step = seconds * 1.5;
        _cueMix += (target - _cueMix) * (step > 1 ? 1.0 : step);
        var justify = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        if (_cueMix < 0.98) {
            dc.setColor(scaleColor(COLOR_WORD, 1 - _cueMix), Graphics.COLOR_TRANSPARENT);
            dc.drawText(SCREEN_CENTER, WORD_Y, _wordFont, "anicca", justify);
        }
        if (_cueMix > 0.02) {
            dc.setColor(scaleColor(COLOR_BREATH, _cueMix), Graphics.COLOR_TRANSPARENT);
            dc.drawText(SCREEN_CENTER, WORD_Y, _breathFont, "observe the breath", justify);
        }
    }

    //! Heart rate (left), the next sunrise or sunset (right) and today's steps below
    private function drawReadings(dc as Graphics.Dc, activityInfo as ActivityMonitor.Info, now as Gregorian.Info) as Void {
        var justifyLeft = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setPenWidth(2);
        dc.setColor(COLOR_ICON, Graphics.COLOR_TRANSPARENT);
        for (var i = 2; i < HEART_OUTLINE.size(); i += 2) {
            dc.drawLine(HEART_X + HEART_OUTLINE[i - 2], DATA_Y + HEART_OUTLINE[i - 1], HEART_X + HEART_OUTLINE[i], DATA_Y + HEART_OUTLINE[i + 1]);
        }
        var sunEvent = nextSunEvent(now);
        drawSunIcon(dc, SUN_X, DATA_Y - 1, sunEvent[0] as Boolean);
        dc.setPenWidth(1);

        dc.setColor(COLOR_DATA, Graphics.COLOR_TRANSPARENT);
        var heartRate = currentHeartRate();
        dc.drawText(HEART_RATE_X, DATA_Y, _dataFont, heartRate != null ? heartRate.format("%d") : "--", justifyLeft);
        dc.drawText(SUN_TIME_X, DATA_Y, _dataFont, sunEvent[1] as String, justifyLeft);
        var steps = activityInfo.steps;
        dc.drawText(SCREEN_CENTER, STEPS_Y, _dataFont, steps != null ? withThousands(steps) : "--",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! A horizon with half a sun on it and an arrow above, up for sunrise and down for sunset
    private function drawSunIcon(dc as Graphics.Dc, x as Number, y as Number, isSunrise as Boolean) as Void {
        dc.drawLine(x - 10, y + 4, x + 10, y + 4);
        dc.drawArc(x, y + 4, 6, Graphics.ARC_COUNTER_CLOCKWISE, 0, 180);
        var tipY = isSunrise ? y - 13 : y - 6;
        var baseY = isSunrise ? y - 9 : y - 10;
        dc.drawLine(x - 4, baseY, x, tipY);
        dc.drawLine(x, tipY, x + 4, baseY);
    }

    private function drawTracks(dc as Graphics.Dc) as Void {
        dc.setColor(COLOR_TRACK, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < _trackDots.size(); i += 2) {
            dc.fillRectangle(_trackDots[i], _trackDots[i + 1], 2, 2);
        }
    }

    private function sitStatus(now as Gregorian.Info) as SitStatus {
        if (_meditation.sitToday) {
            return SIT_DONE;
        }
        return (now.hour as Number) >= SIT_REMINDER_HOUR ? SIT_ALERT : SIT_PENDING;
    }

    private function timeText(now as Gregorian.Info) as String {
        var hour = now.hour as Number;
        if (System.getDeviceSettings().is24Hour) {
            return hour.format("%02d") + ":" + (now.min as Number).format("%02d");
        }
        hour = hour % 12;
        return (hour == 0 ? 12 : hour).format("%d") + ":" + (now.min as Number).format("%02d");
    }

    private function dateText(now as Gregorian.Info) as String {
        return DAY_NAMES[(now.day_of_week as Number) - 1] + " " + (now.day as Number).format("%d") + " " +
            MONTH_NAMES[(now.month as Number) - 1];
    }

    private function withThousands(value as Number) as String {
        if (value < 1000) {
            return value.format("%d");
        }
        return withThousands(value / 1000) + "," + (value % 1000).format("%03d");
    }

    //! Stress score 0-100 from the watch's own measurement, 0 when unknown
    private function currentStress(activityInfo as ActivityMonitor.Info) as Number {
        var stress = activityInfo has :stressScore ? activityInfo.stressScore : null;
        if (stress == null && Toybox has :SensorHistory && SensorHistory has :getStressHistory) {
            var sample = SensorHistory.getStressHistory({:period => 1}).next();
            if (sample != null && sample.data != null) {
                stress = (sample.data as Numeric).toNumber();
            }
        }
        return stress != null ? stress : 0;
    }

    private function currentHeartRate() as Number or Null {
        var heartRate = Activity.getActivityInfo().currentHeartRate;
        if (heartRate != null) {
            return heartRate;
        }
        var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
        if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
            return sample.heartRate;
        }
        return null;
    }

    private function stepProgress(activityInfo as ActivityMonitor.Info) as Float {
        var steps = activityInfo.steps;
        var goal = activityInfo.stepGoal;
        if (steps == null || goal == null || goal == 0) {
            return 0.0;
        }
        var progress = steps.toFloat() / goal;
        return progress > 1 ? 1.0 : progress;
    }

    private function moveBarLevel(activityInfo as ActivityMonitor.Info) as Number {
        var level = activityInfo.moveBarLevel;
        if (level == null || level < ActivityMonitor.MOVE_BAR_LEVEL_MIN) {
            return ActivityMonitor.MOVE_BAR_LEVEL_MIN;
        }
        return level > ActivityMonitor.MOVE_BAR_LEVEL_MAX ? ActivityMonitor.MOVE_BAR_LEVEL_MAX : level;
    }

    //! [is sunrise, time] of the next sunrise or sunset, from the watch's own sunrise and sunset; after today's
    //! sunset, today's sunrise time stands in for tomorrow's
    private function nextSunEvent(now as Gregorian.Info) as [Boolean, String] {
        var sunrise = complicationValue(Complications.COMPLICATION_TYPE_SUNRISE);
        var sunset = complicationValue(Complications.COMPLICATION_TYPE_SUNSET);
        if (!(sunrise instanceof Number) || !(sunset instanceof Number)) {
            return [true, clockText(sunrise)];
        }
        // Whichever comes first going around the clock from now, so it holds even if sunset falls after midnight
        var secondsToday = (now.hour as Number) * 3600 + (now.min as Number) * 60;
        var untilSunrise = (sunrise - secondsToday + 86400) % 86400;
        var untilSunset = (sunset - secondsToday + 86400) % 86400;
        return untilSunrise <= untilSunset ? [true, clockText(sunrise)] : [false, clockText(sunset)];
    }

    private function complicationValue(complicationType as Complications.Type) as Complications.Value or Null {
        try {
            return Complications.getComplication(new Complications.Id(complicationType)).value;
        } catch (exception) {
            return null;
        }
    }

    //! Seconds since midnight as the watch shows times: "06:12", or "6:12" on a 12-hour watch
    private function clockText(seconds as Complications.Value or Null) as String {
        if (!(seconds instanceof Number)) {
            return "--:--";
        }
        var hour = seconds / 3600;
        var minutes = (seconds % 3600 / 60).format("%02d");
        if (System.getDeviceSettings().is24Hour) {
            return hour.format("%02d") + ":" + minutes;
        }
        hour = hour % 12;
        return (hour == 0 ? 12 : hour).format("%d") + ":" + minutes;
    }

    private function scaleColor(color as Number, factor as Float) as Number {
        var red = (((color >> 16) & 0xFF) * factor).toNumber();
        var green = (((color >> 8) & 0xFF) * factor).toNumber();
        var blue = ((color & 0xFF) * factor).toNumber();
        return (red << 16) | (green << 8) | blue;
    }
}
