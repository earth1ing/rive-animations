// The AnimaScript twin of text_rain: the same phrases shaped once, poured
// down in columns and sheltered by the same artist umbrella, written against
// the rive std for `--bench` comparisons between the two script engines.
import { Layout, Context } from "rive/host";
import { Artboard, NodeData } from "rive/artboard";
import { Vector } from "rive/vector";
import { Mat2D } from "rive/mat2d";
import { Path } from "rive/path";
import { Paint, PaintStyle } from "rive/paint";
import { Renderer } from "rive/renderer";
import { PointerEvent } from "rive/events";
import { Color } from "rive/color";
import { Text, TextRunStyle, TextWrap } from "rive/text";

const COL_SPACING: f32 = 11;
const CHAR_HEIGHT: f32 = 12;
const FONT_SIZE: f32 = 11;
// The open canopy in artboard units, matching the Umbrella artboard.
const CANOPY: f32 = 65;
const CANOPY_I: i32 = 65;
// The underside band, stem and hook in the umbrella's own space, relative
// to the carried point; they block rain as well.
const UNDERSIDE: f32 = 11.38;
const STEM_HALF: f32 = 3.5;
const STEM_TOP: f32 = -53;
const STEM_BOTTOM: f32 = 80;
const HOOK_LEFT: f32 = -24;
const HOOK_TOP: f32 = 78;
const HOOK_BOTTOM: f32 = 94;
// How far above and below the carried point a column is walked, in steps
// of this many pixels, before the hit is bisected.
const REACH_ABOVE: f32 = -60;
const REACH_BELOW: f32 = 100;
const STRIDE: f32 = 2;
// Columns the umbrella may have touched replay its motion this frame in
// this many sub steps, so a fast swipe cuts every row along its path.
const SUBSTEPS: i32 = 3;
const MAX_GAPS: i32 = 6;
// How far the canopy may rise into a stream in one frame and still be
// cutting the same gap; the rows it passed bounce off it.
const SWEEP: f32 = 40;
const NONE: i32 = 0;
const DOME: i32 = 1;
const STEM: i32 = 2;
const HOOK: i32 = 3;
// Where the carried point sits inside the Umbrella artboard.
const ORIGIN_X: f32 = 100;
const ORIGIN_Y: f32 = 60;
const BUCKETS: i32 = 5;
const MAX_SPLASHES: i32 = 150;
const MAX_LOOSE: i32 = 400;
const FADE_STEPS: i32 = 6;
const LOOSE_LIFE: f32 = 1.1;
const GRAVITY: f32 = 520;
const BOUNCE: f32 = 0.85;
// The fall speed a bounce reflects, fixed so the rain's own speed only
// changes how often letters hit, not how far they fly.
const IMPACT: f32 = 125;
// Extra speed away from the surface, so a letter jumps clear like a drop.
const KICK: f32 = 80;
// The canopy's height above the carried point, for the surface normal.
const DOME_HEIGHT: f32 = 41;
// How far below the carried point a loose letter is kept out from under
// the canopy.
const SHELTER_DEPTH: f32 = 140;

const phrases: string[] = [
    "the rain drips on saw erent das",
    "in givialp retaw fo seldeen",
    "htrae ent noqu egnipm niar eht",
    "drust eni fo eno htuorht",
    "a senep nekorb eht fo eno",
    "semas yniar eht ni gruos",
    "transecri eni f ent",
    "givialp retaw fo seldeen",
    "niar ent draeh i senep nekorb",
    "eht ni gruos on saw erent das",
    "htrae ent noqu egnipm niar",
    "drust eni fo eno htuorht senep",
    "a semas yniar eht ni givialp",
    "retaw fo seldeen transecri",
    "niar eht drus on saw erent",
    "das gnimes yniar eht ni gruos",
];

// The dome's top edge in the canopy's unscaled space, one entry per unit of
// x across the canopy, sampled from the two arch curves the artwork draws.
function arch(profile: StaticArray<f32>, x0: f32, y0: f32, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32): void {
    for (let i = 0; i <= 260; i++) {
        let t = <f32>i / 260;
        let u = 1 - t;
        let x = u * u * u * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3;
        let y = u * u * u * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3;
        let k = <i32>Mathf.round(x);
        k = k < -CANOPY_I ? -CANOPY_I : k > CANOPY_I ? CANOPY_I : k;
        k += CANOPY_I;
        if (y < profile[k]) {
            profile[k] = y;
        }
    }
}

function buildProfile(): StaticArray<f32> {
    let profile = new StaticArray<f32>(CANOPY_I * 2 + 1);
    profile.fill(1e9);
    arch(profile, CANOPY, UNDERSIDE, CANOPY + 6.5, -27.3, 19.5, -48.75, 0, -39);
    arch(profile, 0, -39, -19.5, -48.75, -CANOPY - 6.5, -27.3, -CANOPY, UNDERSIDE);
    return profile;
}

const domeProfile: StaticArray<f32> = buildProfile();

// What the point (x, y) in the umbrella's space is inside of, with the
// canopy at the given scale.
function inside(x: f32, y: f32, spread: f32, rise: f32): i32 {
    let xc = x / spread;
    let yc = y / rise;
    if (xc >= -CANOPY && xc <= CANOPY && yc <= UNDERSIDE && yc >= domeProfile[<i32>Mathf.round(xc) + CANOPY_I]) {
        return DOME;
    }
    if (x >= -STEM_HALF && x <= STEM_HALF && y >= STEM_TOP && y <= STEM_BOTTOM) {
        return STEM;
    }
    if (x >= HOOK_LEFT && x <= 0 && y >= HOOK_TOP && y <= HOOK_BOTTOM) {
        return HOOK;
    }
    return NONE;
}

// Narrows a hit found between two steps of the walk to a quarter pixel.
function refine(px: f32, py: f32, dx: f32, dy: f32, spread: f32, rise: f32, lo: f32, hi: f32, kind: i32): f32 {
    for (let i = 0; i < 4; i++) {
        let mid = (lo + hi) / 2;
        let at = inside(px + mid * dx, py + mid * dy, spread, rise);
        if ((kind == DOME && at == DOME) || (kind != DOME && at != NONE && at != DOME)) {
            hi = mid;
        } else {
            lo = mid;
        }
    }
    return hi;
}

// Walks the line p + t*d down through the umbrella's space. Leaves where it
// enters and leaves the canopy, which shelters everything below, in
// canopyAt and canopyEnd, then where it enters and leaves the stem or hook,
// which swallow the rows they cover, in stickAt and stickEnd, MISS when it
// never does, and what the stick hit was in stickKind. A tilt is just a
// leaning line.
const MISS: f32 = 1e9;
let canopyAt: f32 = MISS;
let canopyEnd: f32 = MISS;
let stickAt: f32 = MISS;
let stickEnd: f32 = MISS;
let stickKind: i32 = NONE;
function walk(px: f32, py: f32, dx: f32, dy: f32, spread: f32, rise: f32): void {
    canopyAt = MISS;
    canopyEnd = MISS;
    stickAt = MISS;
    stickEnd = MISS;
    stickKind = NONE;
    let prev = REACH_ABOVE;
    let t = REACH_ABOVE;
    while (t <= REACH_BELOW && (canopyEnd == MISS || stickEnd == MISS)) {
        let kind = inside(px + t * dx, py + t * dy, spread, rise);
        if (kind == DOME && canopyAt == MISS) {
            canopyAt = refine(px, py, dx, dy, spread, rise, prev, t, DOME);
        } else if (kind != DOME && canopyAt != MISS && canopyEnd == MISS) {
            canopyEnd = t;
        }
        if (kind != NONE && kind != DOME && stickAt == MISS) {
            stickAt = refine(px, py, dx, dy, spread, rise, prev, t, kind);
            stickKind = kind;
        } else if ((kind == NONE || kind == DOME) && stickAt != MISS && stickEnd == MISS) {
            stickEnd = t;
        }
        prev = t;
        t += STRIDE;
    }
    if (canopyAt != MISS && canopyEnd == MISS) {
        canopyEnd = REACH_BELOW;
    }
    if (stickAt != MISS && stickEnd == MISS) {
        stickEnd = REACH_BELOW;
    }
}

// The world space unit normal of the piece a point in the umbrella's space
// is on, with the canopy at the given scale and the rig at the given tilt.
// Leaves it in normalX and normalY.
let normalX: f32 = 0;
let normalY: f32 = -1;
function normalAt(kind: i32, lx: f32, ly: f32, halfWidth: f32, rise: f32, cosT: f32, sinT: f32): void {
    let nx: f32 = 0;
    let ny: f32 = -1;
    if (kind == DOME && ly > 0) {
        // Below the arch is the underside band; a letter in there leaves
        // through the nearer rim, never down into the shelter.
        nx = lx < 0 ? -1 : 1;
        ny = 0;
    } else if (kind == DOME) {
        nx = lx / (halfWidth * halfWidth);
        ny = ly / (DOME_HEIGHT * rise * DOME_HEIGHT * rise);
        let len = Mathf.sqrt(nx * nx + ny * ny);
        if (len > 0) {
            nx /= len;
            ny /= len;
        } else {
            nx = 0;
            ny = -1;
        }
    } else if (kind == STEM) {
        nx = lx < 0 ? -1 : 1;
        ny = 0;
    }
    normalX = cosT * nx - sinT * ny;
    normalY = sinT * nx + cosT * ny;
}

// A stretch of a column the canopy has eaten, in world y. It falls with the
// letters around it; while the canopy is still cutting, its top is held at
// the cut.
class Gap {
    top: f32 = 0;
    bottom: f32 = 0;
}

function inGap(gaps: Array<Gap>, y: f32): bool {
    for (let k = 0; k < gaps.length; k++) {
        if (y >= gaps[k].top && y < gaps[k].bottom) {
            return true;
        }
    }
    return false;
}

// Records that the rows from top to bottom are gone, widening a gap they
// touch or opening a new one, dropping the lowest gap when the list is
// full.
function eat(gaps: Array<Gap>, top: f32, bottom: f32): void {
    for (let k = 0; k < gaps.length; k++) {
        let gap = gaps[k];
        if (top <= gap.bottom + 0.5 && bottom >= gap.top - 0.5) {
            gap.top = Mathf.min(gap.top, top);
            gap.bottom = Mathf.max(gap.bottom, bottom);
            return;
        }
    }
    if (gaps.length >= MAX_GAPS) {
        let lowest = 0;
        for (let k = 1; k < gaps.length; k++) {
            if (gaps[k].top > gaps[lowest].top) {
                lowest = k;
            }
        }
        gaps[lowest] = gaps[gaps.length - 1];
        gaps.pop();
    }
    let gap = new Gap();
    gap.top = top;
    gap.bottom = bottom;
    gaps.push(gap);
}

class Column {
    x: f32 = 0;
    // One glyph id per character of the repeated phrase, 0 for a space.
    glyphs: Array<u32> = [];
    y: f32 = 0;
    speed: f32 = 0;
    // Which of the opacity paths this column draws into.
    bucket: i32 = 0;
    gaps: Array<Gap> = [];
}

class Splash {
    x: f32 = 0;
    y: f32 = 0;
    vx: f32 = 0;
    vy: f32 = 0;
    life: f32 = 1;
    size: f32 = 1;
}

// A character knocked out of its column by the umbrella, flying free.
class Loose {
    id: u32 = 0;
    x: f32 = 0;
    y: f32 = 0;
    vx: f32 = 0;
    vy: f32 = 0;
    angle: f32 = 0;
    spin: f32 = 0;
    life: f32 = 1;
}

export class Main extends Layout {
    @input umbrella: Artboard? = null;
    instance: Artboard? = null;
    canopy: NodeData? = null;
    handle: NodeData? = null;
    glyphSets: Array<Array<u32>> = [];
    outlines: Map<u32, Path> = new Map<u32, Path>();
    advanceWidth: f32 = 0;
    baseline: f32 = 0;
    columns: Array<Column> = [];
    rain: Array<Path> = [];
    inks: Array<Paint> = [];
    splashes: Array<Splash> = [];
    splashInk: Paint = new Paint();
    loose: Array<Loose> = [];
    // One path and paint per fade step, so a fading letter costs nothing
    // beyond its outline.
    loosePaths: Array<Path> = [];
    looseInks: Array<Paint> = [];
    dot: Path = new Path();
    ground: Path = new Path();
    groundInk: Paint = new Paint();
    label: Text? = null;
    width: f32 = 1000;
    height: f32 = 700;
    builtFor: f32 = -1;
    x: f32 = 600;
    y: f32 = 245;
    targetX: f32 = 600;
    targetY: f32 = 245;
    velocity: f32 = 0;
    // The umbrella as the columns last saw it, the start of this frame's
    // motion.
    prevX: f32 = 600;
    prevY: f32 = 245;
    prevTilt: f32 = 0;
    prevSpread: f32 = 1;
    prevRise: f32 = 1;
    open: bool = true;
    pointerSeen: bool = false;
    elapsed: f32 = 0;
    seed: u32 = 12345;

    // A fixed sequence keeps every run, and the Luau twin, on the same field.
    rand(): f32 {
        this.seed = this.seed * 1664525 + 1013904223;
        return <f32>this.seed / 4294967296.0;
    }

    override init(context: Context): bool {
        let font = context.font("JetBrainsMono");
        if (font == null) {
            return false;
        }
        this.baseline = -font.ascent * FONT_SIZE;

        // One line per phrase; a column is that line's glyphs repeated.
        let source = phrases.join("\n");
        let text = new Text();
        let style = new TextRunStyle(font);
        style.size = FONT_SIZE;
        text.append(source, style);
        text.wrap = TextWrap.noWrap;
        let lines = text.lines();
        for (let l = 0; l < lines.length; l++) {
            let glyphs = lines[l].glyphs();
            let ids = new Array<u32>();
            for (let g = 0; g < glyphs.length; g++) {
                let glyph = glyphs[g];
                let id = glyph.id;
                if (source.charCodeAt(glyph.textIndex) == 32) {
                    id = 0;
                } else if (!this.outlines.has(id)) {
                    this.outlines.set(id, font.glyphPath(id));
                    this.advanceWidth = glyph.advance;
                }
                ids.push(id);
            }
            this.glyphSets.push(ids);
        }

        for (let b = 0; b < BUCKETS; b++) {
            let opacity: f32 = 0.4 + 0.6 * (<f32>b + 0.5) / <f32>BUCKETS;
            this.rain.push(new Path());
            let ink = new Paint();
            ink.color = Color.rgba(74, 142, 212, <u32>(0.85 * opacity * 255));
            this.inks.push(ink);
        }
        for (let k = 0; k < FADE_STEPS; k++) {
            this.loosePaths.push(new Path());
            let ink = new Paint();
            ink.color = Color.rgba(120, 178, 240, <u32>(0.9 * 255 * (<f32>k + 0.5) / <f32>FADE_STEPS));
            this.looseInks.push(ink);
        }

        let k: f32 = 0.5522847498;
        this.dot.moveTo(Vector.xy(1, 0));
        this.dot.cubicTo(Vector.xy(1, k), Vector.xy(k, 1), Vector.xy(0, 1));
        this.dot.cubicTo(Vector.xy(-k, 1), Vector.xy(-1, k), Vector.xy(-1, 0));
        this.dot.cubicTo(Vector.xy(-1, -k), Vector.xy(-k, -1), Vector.xy(0, -1));
        this.dot.cubicTo(Vector.xy(k, -1), Vector.xy(1, -k), Vector.xy(1, 0));
        this.dot.close();

        this.groundInk.style = PaintStyle.stroke;
        this.groundInk.thickness = 1.5;
        this.groundInk.color = Color.rgba(26, 58, 92, 102);

        let label = new Text();
        let labelStyle = new TextRunStyle(font);
        labelStyle.size = 12;
        let labelInk = new Paint();
        labelInk.color = Color.rgba(120, 140, 170, 255);
        labelStyle.paint = labelInk;
        label.append("move to carry the umbrella, click to open or close it", labelStyle);
        this.label = label;

        let umbrella = this.umbrella;
        if (umbrella == null) {
            return false;
        }
        let instance = umbrella.instance();
        this.canopy = instance.node("Canopy");
        this.handle = instance.node("Rig");
        instance.advance(0);
        this.instance = instance;
        this.setOpen(this.open);
        return true;
    }

    setOpen(open: bool): void {
        this.open = open;
        let instance = this.instance;
        if (instance == null) {
            return;
        }
        let data = instance.data();
        if (data == null) {
            return;
        }
        let property = data.getBoolean("open");
        if (property != null) {
            property.value = open;
        }
    }

    override resize(width: f64, height: f64, scale: f64): void {
        this.width = <f32>width;
        this.height = <f32>height;
    }

    buildColumns(): void {
        this.columns = [];
        let count = <i32>Mathf.floor(this.width / COL_SPACING);
        let needed = <i32>Mathf.ceil(2 * this.height / CHAR_HEIGHT) + 10;
        for (let c = 0; c < count; c++) {
            let set = this.glyphSets[c % this.glyphSets.length];
            let ids = new Array<u32>();
            while (ids.length < needed) {
                for (let i = 0; i < set.length; i++) {
                    ids.push(set[i]);
                }
                ids.push(0);
            }
            let column = new Column();
            column.x = <f32>c * COL_SPACING + COL_SPACING / 2;
            column.glyphs = ids;
            column.y = this.rand() * this.height;
            column.speed = 140 + 100 * this.rand();
            column.bucket = <i32>Mathf.floor(this.rand() * <f32>BUCKETS);
            this.columns.push(column);
        }
        this.builtFor = this.width * 4096 + this.height;
    }

    splash(x: f32): void {
        if (this.splashes.length >= MAX_SPLASHES) {
            return;
        }
        let count = 2 + <i32>Mathf.floor(2 * this.rand());
        for (let i = 0; i < count; i++) {
            let s = new Splash();
            s.x = x + (this.rand() - 0.5) * 6;
            s.y = this.height - 4 - 4 * this.rand();
            s.vx = (this.rand() - 0.5) * 30;
            s.vy = -(20 + 40 * this.rand());
            s.life = 1;
            s.size = 1 + 1.5 * this.rand();
            this.splashes.push(s);
        }
    }

    // A character falling at this speed meets the surface with unit normal
    // (nx, ny) and reflects off it, keeping its speed and jumping clear.
    bounce(id: u32, x: f32, y: f32, nx: f32, ny: f32, speed: f32): void {
        if (this.loose.length >= MAX_LOOSE) {
            return;
        }
        let along = speed * ny;
        let kick = KICK * (0.7 + 0.6 * this.rand());
        let l = new Loose();
        l.id = id;
        l.x = x;
        l.y = y;
        l.vx = -2 * along * nx * BOUNCE + nx * kick + (this.rand() - 0.5) * 60;
        l.vy = (speed - 2 * along * ny) * BOUNCE + ny * kick;
        l.angle = 0;
        // Tumbles the way it flies.
        l.spin = (l.vx < 0 ? <f32>-1 : <f32>1) * (3 + 7 * this.rand());
        l.life = 1;
        this.loose.push(l);
    }

    override advance(seconds: f64): bool {
        let dt = Mathf.min(<f32>seconds, 0.05);
        this.elapsed += <f32>seconds;
        if (this.builtFor != this.width * 4096 + this.height) {
            this.buildColumns();
        }

        // The umbrella follows the pointer, or sways on its own until one
        // arrives.
        if (!this.pointerSeen) {
            let t = this.elapsed * 0.3;
            this.targetX = this.width * (0.5 + 0.2 * Mathf.sin(t));
            this.targetY = this.height * (0.35 + 0.08 * Mathf.sin(1.7 * t));
        }
        let ease = Mathf.min(1, dt * 3);
        let beforeX = this.x;
        this.x += (this.targetX - this.x) * ease;
        this.y += (this.targetY - this.y) * ease;
        let vx = (this.x - beforeX) / Mathf.max(dt, 0.001);
        this.velocity += (vx - this.velocity) * Mathf.min(1, dt * 6);
        let handle = this.handle;
        if (handle != null) {
            handle.rotation = Mathf.max(-0.3, Mathf.min(0.3, this.velocity * 0.0008));
        }
        let instance = this.instance;
        if (instance != null) {
            instance.advance(dt);
        }

        // The shelter is whatever the artwork says it is right now: a
        // column stops at the first thing it hits, dome, stem or hook, and
        // stays dry all the way down. The umbrella moved from where the
        // columns last saw it to here; the columns it may have touched
        // replay that motion in sub steps, each against the umbrella
        // interpolated to that moment.
        let canopy = this.canopy;
        let spread: f32 = canopy != null ? <f32>canopy.scaleX : 1;
        let rise: f32 = canopy != null ? <f32>canopy.scaleY : 1;
        let tilt: f32 = handle != null ? <f32>handle.rotation : 0;
        let endX = this.x;
        let endY = this.y;
        let reach = CANOPY + REACH_BELOW;
        // Rows the umbrella slides into are shoved the way it is moving.
        let plowSign: f32 = this.velocity < 0 ? -1 : 1;

        for (let b = 0; b < this.rain.length; b++) {
            this.rain[b].reset();
        }
        let h = this.height;
        let half = this.advanceWidth / 2;
        let splashLine = h - CHAR_HEIGHT * 2;
        for (let c = 0; c < this.columns.length; c++) {
            let column = this.columns[c];
            let glyphs = column.glyphs;
            let step = column.speed * dt;
            let block = CHAR_HEIGHT * <f32>glyphs.length;
            let gaps = column.gaps;
            let near = Mathf.abs(column.x - endX) < reach || Mathf.abs(column.x - this.prevX) < reach;
            let subs = near ? SUBSTEPS : 1;
            let sub = step / <f32>subs;
            for (let k = 1; k <= subs; k++) {
                column.y += sub;
                if (column.y >= block) {
                    column.y -= block;
                }
                // The gaps fall with the stream.
                let g = 0;
                while (g < gaps.length) {
                    let gap = gaps[g];
                    gap.top += sub;
                    gap.bottom += sub;
                    if (gap.top >= h || gap.bottom <= gap.top) {
                        gaps[g] = gaps[gaps.length - 1];
                        gaps.pop();
                    } else {
                        g++;
                    }
                }
                if (!near) {
                    continue;
                }
                let f = <f32>k / <f32>subs;
                let ux = this.prevX + (endX - this.prevX) * f;
                let uy = this.prevY + (endY - this.prevY) * f;
                let t = this.prevTilt + (tilt - this.prevTilt) * f;
                let sp = this.prevSpread + (spread - this.prevSpread) * f;
                let ri = this.prevRise + (rise - this.prevRise) * f;
                let cosT = Mathf.cos(t);
                let sinT = Mathf.sin(t);
                let halfWidth = CANOPY * sp;
                let plowNx = plowSign * cosT;
                let plowNy = plowSign * sinT;
                let off = column.x - ux;
                let stop: f32 = h + CHAR_HEIGHT;
                let canopyBottom: f32 = h + CHAR_HEIGHT;
                let stick: f32 = h + CHAR_HEIGHT;
                let stickBottom: f32 = h + CHAR_HEIGHT;
                let canopyNx: f32 = 0;
                let canopyNy: f32 = -1;
                let stickNx: f32 = 0;
                let stickNy: f32 = -1;
                if (Mathf.abs(off) < reach) {
                    let px = cosT * off;
                    let py = -sinT * off;
                    walk(px, py, sinT, cosT, sp, ri);
                    if (canopyAt != MISS) {
                        stop = uy + canopyAt;
                        canopyBottom = uy + canopyEnd;
                        normalAt(DOME, px + canopyAt * sinT, py + canopyAt * cosT, halfWidth, ri, cosT, sinT);
                        canopyNx = normalX;
                        canopyNy = normalY;
                    }
                    // The stick only counts when the column reaches it
                    // before the canopy catches the row.
                    if (stickAt != MISS && uy + stickAt < stop) {
                        stick = uy + stickAt;
                        stickBottom = uy + stickEnd;
                        normalAt(stickKind, px + stickAt * sinT, py + stickAt * cosT, halfWidth, ri, cosT, sinT);
                        stickNx = normalX;
                        stickNy = normalY;
                    }
                }
                // The gap the canopy is cutting keeps its top at the cut,
                // even when the canopy rose a few rows into the stream, and
                // covers the canopy body, so rows the umbrella slid into are
                // plowed.
                let sweptTo = stop;
                let plowFrom = canopyBottom;
                let plowTo = canopyBottom;
                if (stop < h) {
                    let cut: Gap? = null;
                    for (let q = 0; q < gaps.length; q++) {
                        let gap = gaps[q];
                        if (gap.bottom >= stop && (cut == null || gap.top < cut.top)) {
                            cut = gap;
                        }
                    }
                    if (cut != null && cut.top <= stop + SWEEP) {
                        if (cut.top > stop) {
                            sweptTo = cut.top;
                        }
                        cut.top = stop;
                        if (cut.bottom < canopyBottom) {
                            plowFrom = cut.bottom;
                            cut.bottom = canopyBottom;
                        }
                    } else {
                        plowFrom = stop + sub;
                        eat(gaps, stop, canopyBottom);
                    }
                }
                let x = column.x - half;
                for (let i = 0; i < glyphs.length; i++) {
                    let id = glyphs[i];
                    if (id == 0) {
                        continue;
                    }
                    let y = <f32>i * CHAR_HEIGHT + column.y;
                    if (y >= block) {
                        y -= block;
                    }
                    if (y < -CHAR_HEIGHT || y > h) {
                        continue;
                    }
                    if (y >= stick && y < stickBottom) {
                        // A row on the stem or hook bounces off it, at the
                        // entry when it fell in, sideways when the stick
                        // slid into it.
                        if (!inGap(gaps, y)) {
                            if (y - sub < stick) {
                                this.bounce(id, x, stick - CHAR_HEIGHT, stickNx, stickNy, IMPACT);
                            } else {
                                this.bounce(id, x, y, plowNx, plowNy, IMPACT);
                            }
                            eat(gaps, y, y + CHAR_HEIGHT);
                        }
                    } else if (y >= stop && (y - sub < stop || y < sweptTo)) {
                        this.bounce(id, x, stop - CHAR_HEIGHT, canopyNx, canopyNy, IMPACT);
                    } else if (y >= plowFrom && y < plowTo) {
                        this.bounce(id, x, y, plowNx, plowNy, IMPACT);
                    }
                }
            }
            let path = this.rain[column.bucket];
            let x = column.x - half;
            for (let i = 0; i < glyphs.length; i++) {
                let id = glyphs[i];
                if (id == 0) {
                    continue;
                }
                let y = <f32>i * CHAR_HEIGHT + column.y;
                if (y >= block) {
                    y -= block;
                }
                if (y >= -CHAR_HEIGHT && y <= h && !inGap(gaps, y)) {
                    if (y > splashLine && this.rand() < 0.02) {
                        this.splash(column.x);
                    }
                    path.add(this.outlines.get(id), Mat2D.values(FONT_SIZE, 0, 0, FONT_SIZE, x, y + this.baseline));
                }
            }
        }
        this.prevX = endX;
        this.prevY = endY;
        this.prevTilt = tilt;
        this.prevSpread = spread;
        this.prevRise = rise;

        for (let k = 0; k < this.loosePaths.length; k++) {
            this.loosePaths[k].reset();
        }
        let ux = endX;
        let uy = endY;
        let cosT = Mathf.cos(tilt);
        let sinT = Mathf.sin(tilt);
        let halfWidth = CANOPY * spread;
        let loose = this.loose;
        let n = 0;
        while (n < loose.length) {
            let l = loose[n];
            l.x += l.vx * dt;
            l.y += l.vy * dt;
            l.vy += GRAVITY * dt;
            l.angle += l.spin * dt;
            l.life -= dt / LOOSE_LIFE;
            // A letter inside the umbrella, plowed out of a column or
            // landing back on it, bounces again and is walked out until it
            // is clear.
            for (let w = 0; w < 24; w++) {
                let dx = l.x + half - ux;
                let dy = l.y + CHAR_HEIGHT / 2 - uy;
                let lx = cosT * dx + sinT * dy;
                let ly = cosT * dy - sinT * dx;
                let kind = inside(lx, ly, spread, rise);
                // The shelter under the canopy stays dry too: a letter
                // drifting in there is walked out through the nearer rim.
                if (kind == NONE && ly > 0 && ly < SHELTER_DEPTH && lx > -halfWidth && lx < halfWidth) {
                    kind = DOME;
                }
                if (kind == NONE) {
                    break;
                }
                normalAt(kind, lx, ly, halfWidth, rise, cosT, sinT);
                let into = l.vx * normalX + l.vy * normalY;
                if (into < 0) {
                    l.vx = (l.vx - 2 * into * normalX) * 0.7;
                    l.vy = (l.vy - 2 * into * normalY) * 0.7;
                }
                l.x += normalX * 4;
                l.y += normalY * 4;
            }
            if (l.life <= 0 || l.y > h) {
                loose[n] = loose[loose.length - 1];
                loose.pop();
            } else {
                let k = <i32>Mathf.floor(l.life * <f32>FADE_STEPS);
                if (k >= FADE_STEPS) {
                    k = FADE_STEPS - 1;
                }
                // The glyph placed as in its column, then turned about its
                // centre.
                let c = Mathf.cos(l.angle);
                let sn = Mathf.sin(l.angle);
                let ox = -half;
                let oy = this.baseline - CHAR_HEIGHT / 2;
                this.loosePaths[k].add(this.outlines.get(l.id), Mat2D.values(
                    FONT_SIZE * c,
                    FONT_SIZE * sn,
                    -FONT_SIZE * sn,
                    FONT_SIZE * c,
                    l.x + half + c * ox - sn * oy,
                    l.y + CHAR_HEIGHT / 2 + sn * ox + c * oy));
                n++;
            }
        }

        let splashes = this.splashes;
        let i = 0;
        while (i < splashes.length) {
            let s = splashes[i];
            s.x += s.vx * dt;
            s.y += s.vy * dt;
            s.vy += 120 * dt;
            s.life -= 2.5 * dt;
            if (s.life <= 0) {
                splashes[i] = splashes[splashes.length - 1];
                splashes.pop();
            } else {
                i++;
            }
        }

        this.ground.reset();
        let w = this.width;
        for (let gx: f32 = 0; gx <= w; gx += 2) {
            let point = Vector.xy(gx, h - 8 + 3 * Mathf.sin(0.05 * gx + 2 * this.elapsed));
            if (gx == 0) {
                this.ground.moveTo(point);
            } else {
                this.ground.lineTo(point);
            }
        }
        return true;
    }

    override draw(renderer: Renderer): void {
        for (let b = 0; b < this.rain.length; b++) {
            renderer.drawPath(this.rain[b], this.inks[b]);
        }
        renderer.drawPath(this.ground, this.groundInk);
        let instance = this.instance;
        if (instance != null) {
            renderer.save();
            renderer.transform(Mat2D.withTranslation(this.x - ORIGIN_X, this.y - ORIGIN_Y));
            instance.draw(renderer);
            renderer.restore();
        }
        for (let k = 0; k < this.loosePaths.length; k++) {
            renderer.drawPath(this.loosePaths[k], this.looseInks[k]);
        }
        for (let i = 0; i < this.splashes.length; i++) {
            let s = this.splashes[i];
            this.splashInk.color = Color.rgba(74, 142, 212, <u32>(0.7 * s.life * 255));
            renderer.save();
            renderer.transform(Mat2D.values(s.size, 0, 0, s.size, s.x, s.y));
            renderer.drawPath(this.dot, this.splashInk);
            renderer.restore();
        }
        let label = this.label;
        if (label != null) {
            renderer.save();
            renderer.transform(Mat2D.withTranslation(16, this.height - 34));
            label.draw(renderer);
            renderer.restore();
        }
    }

    override pointerMove(event: PointerEvent): void {
        this.pointerSeen = true;
        this.targetX = event.position.x;
        this.targetY = event.position.y;
    }

    override pointerExit(event: PointerEvent): void {
        this.pointerSeen = false;
    }

    override pointerDown(event: PointerEvent): void {
        this.setOpen(!this.open);
    }
}
