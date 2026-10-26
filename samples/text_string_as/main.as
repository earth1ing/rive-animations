// The AnimaScript twin of text_string: the same paragraph on the same
// rope, written against the rive std for `--bench` comparisons between the
// two script engines.
import { Layout, Context } from "rive/host";
import { Vector } from "rive/vector";
import { Mat2D } from "rive/mat2d";
import { Path } from "rive/path";
import { Paint } from "rive/paint";
import { Renderer } from "rive/renderer";
import { PointerEvent, KeyboardEvent } from "rive/events";
import { Color } from "rive/color";
import { Font, Text, TextRunStyle, TextSizing } from "rive/text";

const TEXT: string = "Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, “and what is the use of a book,” thought Alice “without pictures or conversations?” So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her. There was nothing so very remarkable in that; nor did Alice think it so very much out of the way to hear the Rabbit say to itself, “Oh dear! Oh dear! I shall be late!”";

const FONT_SIZE: f32 = 20;
const LINE_HEIGHT: f32 = 28;
const CONTAINER: f32 = 600;
const MARGIN: f32 = 20;
const CONSTRAINT_DIST: f32 = 1.2;
const UNLOCK_THRESHOLD: f32 = 1;
const ITERATIONS: i32 = 12;
const DAMPING: f32 = 0.97;
const GRAVITY: f32 = 0.15;
const RADIUS: f32 = 7;
const BOUNCE: f32 = 0.4;
const FREE_TAIL: i32 = 6;
const FIXED_DT: f32 = 1.0 / 120.0;
const MAX_STEPS: f32 = 4;
const KEY_F: f64 = 70;
const CELL: f32 = RADIUS * 2;
const BUTTON_WIDTH: f32 = 84;
const BUTTON_HEIGHT: f32 = 32;
const BUTTON_INSET: f32 = 16;

class Letter {
    id: u32 = 0;
    w: f32 = 0;
    x: f32 = 0;
    y: f32 = 0;
    // Where the layout put it and what a relayout moves it to.
    ox: f32 = 0;
    oy: f32 = 0;
    // The previous position, for the Verlet step.
    px: f32 = 0;
    py: f32 = 0;
    reading: i32 = 0;
    locked: bool = true;
}

// One glyph as the layout placed it, in reading order.
class Slot {
    id: u32 = 0;
    x: f32 = 0;
    y: f32 = 0;
    w: f32 = 0;
}

export class Main extends Layout {
    font: Font? = null;
    letters: Array<Letter> = [];
    rests: Array<f32> = [];
    outlines: Map<u32, Path> = new Map<u32, Path>();
    baseline: f32 = 0;
    lockedPath: Path = new Path();
    lockedDirty: bool = true;
    loose: Path = new Path();
    ink: Paint = new Paint();
    looseInk: Paint = new Paint();
    hint: Text? = null;
    hintShown: bool = true;
    button: Path = new Path();
    buttonInk: Paint = new Paint();
    buttonLabel: Text? = null;
    buttonHover: bool = false;
    width: f32 = 900;
    height: f32 = 640;
    left: f32 = 0;
    laidOutFor: f32 = -1;
    gravityOn: bool = true;
    unraveling: bool = false;
    unravelIdx: i32 = -1;
    dragIdx: i32 = -1;
    dragX: f32 = 0;
    dragY: f32 = 0;
    accumulator: f32 = 0;
    // Grid broadphase for letter collision, rebuilt every step.
    heads: Int32Array = new Int32Array(0);
    next: Int32Array = new Int32Array(0);
    gridWidth: i32 = 1;
    gridHeight: i32 = 1;
    // The reading indices of each line of the last layout.
    lines: Array<Array<i32>> = [];

    containerWidth(): f32 {
        return Mathf.min(CONTAINER, this.width);
    }

    // Shapes and wraps the paragraph for the current width. Returns every
    // glyph in reading order and fills `lines` with each line's indices.
    layoutText(): Array<Slot> {
        let slots = new Array<Slot>();
        this.lines = [];
        let font = this.font;
        if (font == null) {
            return slots;
        }
        let text = new Text();
        let style = new TextRunStyle(font);
        style.size = FONT_SIZE;
        style.lineHeight = LINE_HEIGHT;
        text.append(TEXT, style);
        text.sizing = TextSizing.fixed;
        text.maxWidth = this.containerWidth() - MARGIN * 2;
        text.maxHeight = 100000;
        let offsetY = Mathf.max(0, (this.height - <f32>text.lineCount * LINE_HEIGHT) * 0.3);
        let lines = text.lines();
        for (let l = 0; l < lines.length; l++) {
            let line = lines[l];
            this.baseline = line.baseline - line.top;
            let indices = new Array<i32>();
            let glyphs = line.glyphs();
            for (let g = 0; g < glyphs.length; g++) {
                let glyph = glyphs[g];
                let slot = new Slot();
                slot.id = glyph.id;
                slot.x = MARGIN + glyph.x;
                slot.y = line.top + offsetY;
                slot.w = glyph.advance;
                indices.push(slots.length);
                slots.push(slot);
                if (!this.outlines.has(glyph.id)) {
                    this.outlines.set(glyph.id, font.glyphPath(glyph.id));
                }
            }
            this.lines.push(indices);
        }
        return slots;
    }

    buildRope(): void {
        let slots = this.layoutText();
        let lines = this.lines;
        // Snake through the lines so the last one reads left to right.
        let flip = (lines.length - 1) % 2 == 1;
        let order = new Array<i32>();
        for (let li = 0; li < lines.length; li++) {
            let indices = lines[li];
            let reversed = flip ? li % 2 == 0 : li % 2 == 1;
            if (reversed) {
                for (let k = indices.length - 1; k >= 0; k--) {
                    order.push(indices[k]);
                }
            } else {
                for (let k = 0; k < indices.length; k++) {
                    order.push(indices[k]);
                }
            }
        }
        this.letters = [];
        for (let i = 0; i < order.length; i++) {
            let s = slots[order[i]];
            let l = new Letter();
            l.id = s.id;
            l.w = s.w;
            l.x = s.x;
            l.y = s.y;
            l.ox = s.x;
            l.oy = s.y;
            l.px = s.x;
            l.py = s.y;
            l.reading = order[i];
            l.locked = true;
            this.letters.push(l);
        }
        let letters = this.letters;
        let n = letters.length;
        this.rests = [];
        for (let i = 0; i < n - 1; i++) {
            let a = letters[i];
            let b = letters[i + 1];
            let dx = (b.ox + b.w / 2) - (a.ox + a.w / 2);
            let dy = b.oy - a.oy;
            this.rests.push(Mathf.sqrt(dx * dx + dy * dy) * CONSTRAINT_DIST);
        }
        for (let i = n - 1; i >= 0 && i > n - 1 - FREE_TAIL; i--) {
            letters[i].locked = false;
        }
        this.next = new Int32Array(n);
        this.lockedDirty = true;
    }

    // A resize moves the locked letters to their new slots; the rope keeps
    // its rest lengths, so it never changes length.
    relayout(): void {
        let slots = this.layoutText();
        for (let i = 0; i < this.letters.length; i++) {
            let l = this.letters[i];
            if (l.reading >= slots.length) {
                continue;
            }
            let s = slots[l.reading];
            l.ox = s.x;
            l.oy = s.y;
            if (l.locked) {
                l.x = s.x;
                l.y = s.y;
                l.px = s.x;
                l.py = s.y;
            }
        }
        this.lockedDirty = true;
    }

    startUnravel(): void {
        this.unraveling = true;
        this.hintShown = false;
        let idx = this.letters.length - 1;
        while (idx >= 0 && !this.letters[idx].locked) {
            idx--;
        }
        this.unravelIdx = idx;
    }

    cellX(x: f32): i32 {
        let c = <i32>Mathf.floor((x + this.left) / CELL);
        return c < 0 ? 0 : c >= this.gridWidth ? this.gridWidth - 1 : c;
    }

    cellY(y: f32): i32 {
        let c = <i32>Mathf.floor(y / CELL);
        return c < 0 ? 0 : c >= this.gridHeight ? this.gridHeight - 1 : c;
    }

    collide(): void {
        let letters = this.letters;
        let gw = this.gridWidth;
        let gh = this.gridHeight;
        let heads = this.heads;
        let next = this.next;
        heads.fill(-1);
        for (let i = 0; i < letters.length; i++) {
            let l = letters[i];
            if (l.locked) {
                continue;
            }
            let c = this.cellY(l.y + LINE_HEIGHT / 2) * gw + this.cellX(l.x + l.w / 2);
            next[i] = heads[c];
            heads[c] = i;
        }
        let minDist = RADIUS * 2;
        let drag = this.dragIdx;
        for (let i = 0; i < letters.length; i++) {
            let a = letters[i];
            if (a.locked) {
                continue;
            }
            let acx = a.x + a.w / 2;
            let acy = a.y + LINE_HEIGHT / 2;
            let cx = this.cellX(acx);
            let cy = this.cellY(acy);
            let y0 = cy > 0 ? cy - 1 : 0;
            let y1 = cy < gh - 1 ? cy + 1 : gh - 1;
            let x0 = cx > 0 ? cx - 1 : 0;
            let x1 = cx < gw - 1 ? cx + 1 : gw - 1;
            for (let yy = y0; yy <= y1; yy++) {
                for (let xx = x0; xx <= x1; xx++) {
                    let j = heads[yy * gw + xx];
                    while (j >= 0) {
                        // Each pair once, and never the rope neighbour.
                        if (j > i + 1) {
                            let b = letters[j];
                            let dx = (b.x + b.w / 2) - acx;
                            let dy = (b.y + LINE_HEIGHT / 2) - acy;
                            let dist = Mathf.sqrt(dx * dx + dy * dy);
                            if (dist == 0) {
                                dist = 0.001;
                            }
                            if (dist < minDist) {
                                let overlap = (minDist - dist) / dist * 0.5;
                                if (i == drag) {
                                    b.x += dx * overlap;
                                    b.y += dy * overlap;
                                } else if (j == drag) {
                                    a.x -= dx * overlap;
                                    a.y -= dy * overlap;
                                } else {
                                    a.x -= dx * overlap;
                                    a.y -= dy * overlap;
                                    b.x += dx * overlap;
                                    b.y += dy * overlap;
                                }
                            }
                        }
                        j = next[j];
                    }
                }
            }
        }
    }

    simulate(): void {
        let letters = this.letters;
        let n = letters.length;
        if (this.unraveling) {
            if (!this.gravityOn || this.unravelIdx < 0) {
                this.unraveling = false;
            } else if (letters[this.unravelIdx].locked) {
                let l = letters[this.unravelIdx];
                l.locked = false;
                l.px = l.x;
                l.py = l.y - 0.5;
                this.unravelIdx--;
                this.lockedDirty = true;
            } else {
                this.unravelIdx--;
            }
        }
        // A free letter pulled past its rest length unlocks the one before
        // it.
        for (let i = n - 2; i >= 0; i--) {
            let a = letters[i];
            let b = letters[i + 1];
            if (a.locked && !b.locked) {
                let dx = (b.x + b.w / 2) - (a.ox + a.w / 2);
                let dy = b.y - a.oy;
                if (Mathf.sqrt(dx * dx + dy * dy) > this.rests[i] + UNLOCK_THRESHOLD) {
                    a.locked = false;
                    a.px = a.x;
                    a.py = a.y;
                    this.lockedDirty = true;
                    this.hintShown = false;
                }
            }
        }
        let gravity: f32 = this.gravityOn ? GRAVITY : 0;
        let drag = this.dragIdx;
        for (let i = 0; i < n; i++) {
            let l = letters[i];
            if (l.locked || i == drag) {
                continue;
            }
            let vx = (l.x - l.px) * DAMPING;
            let vy = (l.y - l.py) * DAMPING;
            l.px = l.x;
            l.py = l.y;
            l.x += vx;
            l.y += vy + gravity;
        }
        for (let iter = 0; iter < ITERATIONS; iter++) {
            for (let i = 0; i < n - 1; i++) {
                let a = letters[i];
                let b = letters[i + 1];
                if (a.locked && b.locked) {
                    continue;
                }
                let dx = (b.x + b.w / 2) - (a.x + a.w / 2);
                let dy = b.y - a.y;
                let dist = Mathf.sqrt(dx * dx + dy * dy);
                if (dist == 0) {
                    dist = 0.001;
                }
                let diff = (dist - this.rests[i]) / dist;
                let aFixed = a.locked || i == drag;
                let bFixed = b.locked || i + 1 == drag;
                if (aFixed && !bFixed) {
                    b.x -= dx * diff;
                    b.y -= dy * diff;
                } else if (bFixed && !aFixed) {
                    a.x += dx * diff;
                    a.y += dy * diff;
                } else if (!aFixed) {
                    a.x += dx * diff * 0.5;
                    a.y += dy * diff * 0.5;
                    b.x -= dx * diff * 0.5;
                    b.y -= dy * diff * 0.5;
                }
            }
        }
        this.collide();
        let minX = -this.left;
        let maxX = this.width - this.left;
        let maxY = this.height;
        for (let i = 0; i < n; i++) {
            let l = letters[i];
            if (l.locked || i == drag) {
                continue;
            }
            if (l.x < minX) {
                l.x = minX;
                l.px = l.x + (l.x - l.px) * BOUNCE;
            }
            if (l.x + l.w > maxX) {
                l.x = maxX - l.w;
                l.px = l.x + (l.x - l.px) * BOUNCE;
            }
            if (l.y < 0) {
                l.y = 0;
                l.py = l.y + (l.y - l.py) * BOUNCE;
            }
            if (l.y + LINE_HEIGHT > maxY) {
                l.y = maxY - LINE_HEIGHT;
                l.py = l.y + (l.y - l.py) * BOUNCE;
            }
        }
    }

    // Every letter back on its slot, locked, and the rope at rest.
    reset(): void {
        let letters = this.letters;
        for (let i = 0; i < letters.length; i++) {
            let l = letters[i];
            l.locked = true;
            l.x = l.ox;
            l.y = l.oy;
            l.px = l.ox;
            l.py = l.oy;
        }
        let n = letters.length;
        for (let i = n - 1; i >= 0 && i > n - 1 - FREE_TAIL; i--) {
            letters[i].locked = false;
        }
        this.dragIdx = -1;
        this.unraveling = false;
        this.gravityOn = true;
        this.hintShown = true;
        this.accumulator = 0;
        this.lockedDirty = true;
    }

    buttonX(): f32 {
        return this.width - BUTTON_WIDTH - BUTTON_INSET;
    }

    overButton(x: f32, y: f32): bool {
        let bx = this.buttonX();
        return x >= bx && x <= bx + BUTTON_WIDTH && y >= BUTTON_INSET && y <= BUTTON_INSET + BUTTON_HEIGHT;
    }

    place(path: Path, l: Letter): void {
        path.add(this.outlines.get(l.id), Mat2D.values(FONT_SIZE, 0, 0, FONT_SIZE, l.x, l.y + this.baseline));
    }

    override init(context: Context): bool {
        let font = context.font("Lora");
        if (font == null) {
            return false;
        }
        this.font = font;
        this.ink.color = Color.rgba(74, 74, 74, 255);
        this.looseInk.color = Color.rgba(178, 76, 48, 255);
        let hint = new Text();
        let style = new TextRunStyle(font);
        style.size = 12;
        let hintInk = new Paint();
        hintInk.color = Color.rgba(150, 140, 130, 255);
        style.paint = hintInk;
        hint.append("drag the last letters, F toggles gravity", style);
        this.hint = hint;

        let r = BUTTON_HEIGHT / 2;
        let k: f32 = 0.5522847498 * r;
        let w = BUTTON_WIDTH;
        this.button.moveTo(Vector.xy(r, 0));
        this.button.lineTo(Vector.xy(w - r, 0));
        this.button.cubicTo(Vector.xy(w - r + k, 0), Vector.xy(w, r - k), Vector.xy(w, r));
        this.button.cubicTo(Vector.xy(w, r + k), Vector.xy(w - r + k, r * 2), Vector.xy(w - r, r * 2));
        this.button.lineTo(Vector.xy(r, r * 2));
        this.button.cubicTo(Vector.xy(r - k, r * 2), Vector.xy(0, r + k), Vector.xy(0, r));
        this.button.cubicTo(Vector.xy(0, r - k), Vector.xy(r - k, 0), Vector.xy(r, 0));
        this.button.close();
        let label = new Text();
        let labelStyle = new TextRunStyle(font);
        labelStyle.size = 14;
        let labelInk = new Paint();
        labelInk.color = Color.rgba(245, 240, 232, 255);
        labelStyle.paint = labelInk;
        label.append("reset", labelStyle);
        this.buttonLabel = label;
        return true;
    }

    override resize(width: f64, height: f64, scale: f64): void {
        this.width = <f32>width;
        this.height = <f32>height;
    }

    override advance(seconds: f64): bool {
        let dt = <f32>seconds;
        let key = this.width * 4096 + this.height;
        if (this.laidOutFor != key) {
            this.left = (this.width - this.containerWidth()) / 2;
            this.gridWidth = <i32>Mathf.ceil(this.width / CELL) + 1;
            this.gridHeight = <i32>Mathf.ceil(this.height / CELL) + 1;
            this.heads = new Int32Array(this.gridWidth * this.gridHeight);
            if (this.letters.length == 0) {
                this.buildRope();
            } else {
                this.relayout();
            }
            this.laidOutFor = key;
        }
        this.accumulator += Mathf.min(dt, MAX_STEPS * FIXED_DT);
        while (this.accumulator >= FIXED_DT) {
            this.simulate();
            this.accumulator -= FIXED_DT;
        }
        let letters = this.letters;
        if (this.lockedDirty) {
            this.lockedPath.reset();
            for (let i = 0; i < letters.length; i++) {
                if (letters[i].locked) {
                    this.place(this.lockedPath, letters[i]);
                }
            }
            this.lockedDirty = false;
        }
        this.loose.reset();
        for (let i = 0; i < letters.length; i++) {
            if (!letters[i].locked) {
                this.place(this.loose, letters[i]);
            }
        }
        return true;
    }

    override draw(renderer: Renderer): void {
        renderer.save();
        renderer.transform(Mat2D.withTranslation(this.left, 0));
        renderer.drawPath(this.lockedPath, this.ink);
        renderer.drawPath(this.loose, this.looseInk);
        let hint = this.hint;
        if (hint != null && this.hintShown && this.letters.length > 0) {
            let last = this.letters[this.letters.length - 1];
            renderer.save();
            renderer.transform(Mat2D.withTranslation(last.ox - 40, last.oy + LINE_HEIGHT + 4));
            hint.draw(renderer);
            renderer.restore();
        }
        renderer.restore();

        this.buttonInk.color = this.buttonHover ? Color.rgba(178, 76, 48, 255) : Color.rgba(74, 74, 74, 255);
        renderer.save();
        renderer.transform(Mat2D.withTranslation(this.buttonX(), BUTTON_INSET));
        renderer.drawPath(this.button, this.buttonInk);
        let label = this.buttonLabel;
        if (label != null) {
            let bounds = label.bounds();
            let min = bounds.v0;
            let max = bounds.v1;
            renderer.transform(Mat2D.withTranslation(
                (BUTTON_WIDTH - (max.x - min.x)) / 2 - min.x,
                (BUTTON_HEIGHT - (max.y - min.y)) / 2 - min.y));
            label.draw(renderer);
        }
        renderer.restore();
    }

    override pointerDown(event: PointerEvent): void {
        if (this.overButton(event.position.x, event.position.y)) {
            this.reset();
            return;
        }
        let px = event.position.x - this.left;
        let py = event.position.y;
        for (let i = this.letters.length - 1; i >= 0; i--) {
            let l = this.letters[i];
            if (!l.locked && px >= l.x - 4 && px <= l.x + l.w + 4 && py >= l.y - 4 && py <= l.y + LINE_HEIGHT + 4) {
                this.dragIdx = i;
                this.dragX = px - l.x;
                this.dragY = py - l.y;
                return;
            }
        }
    }

    override pointerMove(event: PointerEvent): void {
        this.buttonHover = this.overButton(event.position.x, event.position.y);
        if (this.dragIdx < 0) {
            return;
        }
        let l = this.letters[this.dragIdx];
        l.x = event.position.x - this.left - this.dragX;
        l.y = event.position.y - this.dragY;
        l.px = l.x;
        l.py = l.y;
        l.locked = false;
    }

    override pointerUp(event: PointerEvent): void {
        this.dragIdx = -1;
    }

    override keyboardEvent(event: KeyboardEvent): bool {
        if (event.phase != "down" || event.key != KEY_F) {
            return false;
        }
        this.gravityOn = !this.gravityOn;
        if (this.gravityOn && !this.unraveling) {
            this.startUnravel();
        }
        return true;
    }
}
