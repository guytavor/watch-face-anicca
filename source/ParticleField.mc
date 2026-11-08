import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

//! What a group of particles traces
enum ParticleKind {
    KIND_DIGIT,
    KIND_STEPS,
    KIND_MOVE,
    KIND_RING,
    KIND_COUNT,
}

//! Particles are spawned, drawn and fade in cohorts: every particle of a cohort shares its birth, lifetime and size,
//! so a frame needs one color change per cohort. Members land on random points, so the shared timing does not show.
const COHORT_SIZE = 8;
//! Brightness steps over a particle's life: sin(pi * age) * FADE_PLATEAU, capped at full, so a particle fades in,
//! stays at full brightness through the middle of its life, and fades out
const FADE_LEVELS = 16;
const FADE_PLATEAU = 1.6;
const SCREEN_CENTER = 227;
const ARC_RADIUS = 194;
const RING_RADIUS = 206;
const RING_DEPTH = 10;
//! Spawning is the costly part of a frame: at most this many cohorts are spawned per frame, so a frame stays well
//! inside the watchdog's limit; the rest wait (unseen) for the next frame
const SPAWNS_PER_FRAME = 10;

class ParticleField {

    // Per cohort
    private var _born as Array<Number>;
    private var _life as Array<Number>;
    private var _size as Array<Number>;
    private var _kind as Array<Number>;
    //! Index of the cohort within its kind; cohorts at or past the kind's active count are not drawn
    private var _slot as Array<Number>;
    // Per particle: position at birth and velocity in pixels per second
    private var _x as Array<Float>;
    private var _y as Array<Float>;
    private var _velocityX as Array<Float>;
    private var _velocityY as Array<Float>;

    private var _activeCohorts as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    private var _palettes as Array<Array<Number> > = [[], [], [], []] as Array<Array<Number> >;
    //! Color and intensity (in thousandths) each palette was made from
    private var _paletteKeys as Array<Number> = [-1, -1, -1, -1] as Array<Number>;
    private var _glyphs as TimeGlyphs;
    //! Filled stretches of the step and move arcs: flat [low, high, low, high, ...] angles in radians, y pointing down
    private var _ranges as Array<Array<Float> > = [[], [], [], []] as Array<Array<Float> >;
    private var _restlessness as Float = 1.0;
    private var _lifeScale as Float = 1.0;

    //! maxCohorts: the most cohorts each kind can have at once, indexed by ParticleKind
    public function initialize(glyphs as TimeGlyphs, maxCohorts as Array<Number>) {
        _glyphs = glyphs;
        var cohortCount = 0;
        for (var kind = 0; kind < KIND_COUNT; kind++) {
            cohortCount += maxCohorts[kind];
        }
        _born = new [cohortCount] as Array<Number>;
        _life = new [cohortCount] as Array<Number>;
        _size = new [cohortCount] as Array<Number>;
        _kind = new [cohortCount] as Array<Number>;
        _slot = new [cohortCount] as Array<Number>;
        var cohort = 0;
        for (var kind = 0; kind < KIND_COUNT; kind++) {
            for (var slot = 0; slot < maxCohorts[kind]; slot++) {
                _kind[cohort] = kind;
                _slot[cohort] = slot;
                _born[cohort] = -1;
                _life[cohort] = 1;
                _size[cohort] = 2;
                cohort++;
            }
        }
        var particleCount = cohortCount * COHORT_SIZE;
        _x = new [particleCount] as Array<Float>;
        _y = new [particleCount] as Array<Float>;
        _velocityX = new [particleCount] as Array<Float>;
        _velocityY = new [particleCount] as Array<Float>;
        for (var i = 0; i < particleCount; i++) {
            _x[i] = 0.0;
            _y[i] = 0.0;
            _velocityX[i] = 0.0;
            _velocityY[i] = 0.0;
        }
    }

    //! Sets how many cohorts of a kind are drawn, and their color at full brightness
    public function setActive(kind as ParticleKind, cohorts as Number, color as Number, intensity as Float) as Void {
        _activeCohorts[kind] = cohorts;
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
    }

    //! Filled stretches of an arc, as flat [low, high, ...] angles
    public function setRanges(kind as ParticleKind, ranges as Array<Float>) as Void {
        _ranges[kind] = ranges;
    }

    //! restlessness scales how fast digit particles wander; lifeScale shortens their lives
    public function setMood(restlessness as Float, lifeScale as Float) as Void {
        _restlessness = restlessness;
        _lifeScale = lifeScale;
    }

    //! Draws one frame at system time `now` (milliseconds); returns the number of particles drawn
    public function draw(dc as Graphics.Dc, now as Number) as Number {
        var drawn = 0;
        var spawnBudget = SPAWNS_PER_FRAME;
        var cohortCount = _born.size();
        for (var cohort = 0; cohort < cohortCount; cohort++) {
            var kind = _kind[cohort];
            if (_slot[cohort] >= _activeCohorts[kind]) {
                _born[cohort] = -1;
                continue;
            }
            if (_born[cohort] < 0) {
                if (spawnBudget == 0) {
                    continue;
                }
                spawnBudget--;
                // Newly active: start part-way through a life, so cohorts don't all appear together
                spawn(cohort, now);
                _born[cohort] = now - Math.rand() % _life[cohort];
            } else if (now - _born[cohort] >= _life[cohort]) {
                if (spawnBudget == 0) {
                    continue;
                }
                spawnBudget--;
                spawn(cohort, now);
            }
            var age = now - _born[cohort];
            dc.setColor(_palettes[kind][age * FADE_LEVELS / _life[cohort]], Graphics.COLOR_TRANSPARENT);
            var seconds = age / 1000.0;
            var size = _size[cohort];
            var first = cohort * COHORT_SIZE;
            for (var i = first; i < first + COHORT_SIZE; i++) {
                dc.fillRectangle(_x[i] + _velocityX[i] * seconds, _y[i] + _velocityY[i] * seconds, size, size);
            }
            drawn += COHORT_SIZE;
        }
        return drawn;
    }

    private function spawn(cohort as Number, now as Number) as Void {
        var kind = _kind[cohort];
        var first = cohort * COHORT_SIZE;
        _born[cohort] = now;
        if (kind == KIND_DIGIT) {
            _life[cohort] = ((1200 + random() * 1800) * _lifeScale).toNumber();
            _size[cohort] = 2 + Math.rand() % 2;
            if (_glyphs.isEmpty()) {
                return;
            }
            for (var i = first; i < first + COHORT_SIZE; i++) {
                _glyphs.pickRandomPoint();
                var angle = random() * 2 * Math.PI;
                var speed = (3 + random() * 6) * _restlessness;
                _x[i] = _glyphs.pointX + random() * 3 - 1.5;
                _y[i] = _glyphs.pointY + random() * 3 - 1.5;
                _velocityX[i] = Math.cos(angle) * speed;
                _velocityY[i] = Math.sin(angle) * speed - 2.4;
            }
        } else if (kind == KIND_RING) {
            _life[cohort] = (2500 + random() * 3000).toNumber();
            _size[cohort] = 2 + Math.rand() % 2;
            // The ring turns 0.08 radians over a particle's life
            var tangentialSpeed = 0.08 * (RING_RADIUS + RING_DEPTH / 2) / (_life[cohort] / 1000.0);
            for (var i = first; i < first + COHORT_SIZE; i++) {
                var angle = random() * 2 * Math.PI;
                var radius = RING_RADIUS + random() * RING_DEPTH;
                _x[i] = SCREEN_CENTER + Math.cos(angle) * radius;
                _y[i] = SCREEN_CENTER + Math.sin(angle) * radius;
                _velocityX[i] = -Math.sin(angle) * tangentialSpeed;
                _velocityY[i] = Math.cos(angle) * tangentialSpeed;
            }
        } else {
            _life[cohort] = (2600 * (0.6 + random() * 0.8)).toNumber();
            _size[cohort] = 2;
            var ranges = _ranges[kind];
            var total = 0.0;
            for (var r = 0; r < ranges.size(); r += 2) {
                total += ranges[r + 1] - ranges[r];
            }
            if (total <= 0) {
                return;
            }
            for (var i = first; i < first + COHORT_SIZE; i++) {
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
                _x[i] = SCREEN_CENTER + Math.cos(angle) * radius - 1;
                _y[i] = SCREEN_CENTER + Math.sin(angle) * radius - 1;
                _velocityX[i] = 0.0;
                _velocityY[i] = 0.0;
            }
        }
    }

    private function random() as Float {
        return (Math.rand() % 10000) / 10000.0;
    }
}
