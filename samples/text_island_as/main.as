// The AnimaScript twin of text_island: the same blob poured around the
// same circle, written against the rive/text std, for `--bench` comparisons
// between the two script engines.
import { Layout, Context } from "rive/host";
import { Vector } from "rive/vector";
import { Mat2D } from "rive/mat2d";
import { Path } from "rive/path";
import { Paint, PaintStyle } from "rive/paint";
import { Renderer } from "rive/renderer";
import { PointerEvent } from "rive/events";
import { Color } from "rive/color";
import { Text, TextRunStyle, TextWrap } from "rive/text";

const RADIUS: f32 = 90;
const MARGIN: f32 = 16;
const COLUMNS: i32 = 3;
const EDGE: f32 = 40;
const GUTTER: f32 = 28;

const sentences: string[] = [
    "Text in Rive is shaped by the runtime, so a script never has to know how a font joins its letters.",
    "The words below were laid out once, then poured into columns by this script.",
    "Move the pointer and the circle pushes the words aside, line by line.",
    "Every line asks the circle which spans it leaves free and fills them in reading order.",
    "A paragraph break ends the line early and leaves a little extra room.",
    "The glyph outlines are cached per word, so a relayout only moves paths around.",
    "Three columns of text, one circle, and a script that acts as the line breaker.",
    "Nothing here is drawn by a text component; the renderer only ever sees paths.",
];

function blob(): string {
    let parts = new Array<string>();
    for (let paragraph = 1; paragraph <= 9; paragraph++) {
        let words = new Array<string>();
        for (let i = 1; i <= 9; i++) {
            words.push(sentences[(paragraph + i) % sentences.length]);
        }
        parts.push(words.join(" "));
    }
    return parts.join("\n");
}

// Glyph outlines at the word's origin with the baseline at y 0; a negative
// width marks a paragraph break.
class Word {
    path: Path = new Path();
    width: f32 = 0;
}

export class Main extends Layout {
    words: Array<Word> = [];
    spaceWidth: f32 = 0;
    lineHeight: f32 = 0;
    ascent: f32 = 0;
    descent: f32 = 0;
    columns: Array<Path> = [];
    circle: Vector = Vector.xy(500, 350);
    target: Vector = Vector.xy(500, 350);
    laidOut: Vector = Vector.xy(-1, -1);
    ink: Paint = new Paint();
    ring: Paint = new Paint();
    ringPath: Path = new Path();
    width: f32 = 1000;
    height: f32 = 700;
    elapsed: f32 = 0;
    // Until the pointer arrives the circle drifts on its own, so a headless
    // bench relayouts every frame the way a moving pointer would.
    pointerSeen: bool = false;
    source: string = "";

    override init(context: Context): bool {
        this.source = blob();
        let font = context.font("Inter");
        if (font == null) {
            return false;
        }
        let size: f32 = 14;
        let text = new Text();
        let style = new TextRunStyle(font);
        style.size = size;
        text.append(this.source, style);
        text.wrap = TextWrap.noWrap;
        this.lineHeight = font.lineHeight(size) * 1.3;
        this.ascent = font.ascent * size;
        this.descent = font.descent * size;
        this.ink.color = Color.rgb(225, 225, 225);
        this.ring.style = PaintStyle.stroke;
        this.ring.thickness = 2;
        this.ring.color = Color.rgb(255, 150, 60);

        let glyphPaths = new Map<u32, Path>();
        let lines = text.lines();
        for (let l = 0; l < lines.length; l++) {
            let line = lines[l];
            let glyphs = line.glyphs();
            let word: Word? = null;
            let startX: f32 = 0;
            let lastEnd: f32 = 0;
            for (let g = 0; g < glyphs.length; g++) {
                let glyph = glyphs[g];
                if (this.source.charCodeAt(glyph.textIndex) == 32) {
                    if (this.spaceWidth == 0) {
                        this.spaceWidth = glyph.advance;
                    }
                    if (word != null) {
                        word.width = lastEnd - startX;
                        this.words.push(word);
                        word = null;
                    }
                } else {
                    let current: Word;
                    if (word == null) {
                        current = new Word();
                        word = current;
                        startX = glyph.x;
                    } else {
                        current = word;
                    }
                    let outline: Path;
                    if (glyphPaths.has(glyph.id)) {
                        outline = glyphPaths.get(glyph.id);
                    } else {
                        outline = glyph.font.glyphPath(glyph.id);
                        glyphPaths.set(glyph.id, outline);
                    }
                    // The glyph transform is a scale then a translation, so
                    // shifting it moves the glyph to the word's origin.
                    let placement = glyph.transform();
                    placement.tx -= startX;
                    placement.ty -= line.baseline;
                    current.path.add(outline, placement);
                    lastEnd = glyph.x + glyph.advance;
                }
            }
            if (word != null) {
                word.width = lastEnd - startX;
                this.words.push(word);
            }
            let gap = new Word();
            gap.width = -1;
            this.words.push(gap);
        }
        for (let c = 0; c < COLUMNS; c++) {
            this.columns.push(new Path());
        }

        let k: f32 = 0.5522847498 * RADIUS;
        this.ringPath.moveTo(Vector.xy(RADIUS, 0));
        this.ringPath.cubicTo(Vector.xy(RADIUS, k), Vector.xy(k, RADIUS), Vector.xy(0, RADIUS));
        this.ringPath.cubicTo(Vector.xy(-k, RADIUS), Vector.xy(-RADIUS, k), Vector.xy(-RADIUS, 0));
        this.ringPath.cubicTo(Vector.xy(-RADIUS, -k), Vector.xy(-k, -RADIUS), Vector.xy(0, -RADIUS));
        this.ringPath.cubicTo(Vector.xy(k, -RADIUS), Vector.xy(RADIUS, -k), Vector.xy(RADIUS, 0));
        this.ringPath.close();
        return true;
    }

    override resize(width: f64, height: f64, scale: f64): void {
        this.width = <f32>width;
        this.height = <f32>height;
        this.laidOut = Vector.xy(-1, -1);
    }

    // The free spans of a line whose baseline sits at y, as start and end
    // pairs.
    segments(y: f32, left: f32, right: f32): Array<f32> {
        let top = y + this.ascent;
        let bottom = y + this.descent;
        let cy = this.circle.y;
        let dy: f32 = cy < top ? top - cy : cy > bottom ? cy - bottom : 0;
        let r = RADIUS + MARGIN;
        let out = new Array<f32>();
        if (dy >= r) {
            out.push(left);
            out.push(right);
            return out;
        }
        let w = Mathf.sqrt(r * r - dy * dy);
        let a = this.circle.x - w;
        let b = this.circle.x + w;
        if (b <= left || a >= right) {
            out.push(left);
            out.push(right);
            return out;
        }
        if (a - left > 30) {
            out.push(left);
            out.push(a);
        }
        if (right - b > 30) {
            out.push(b);
            out.push(right);
        }
        return out;
    }

    layout(): void {
        let colWidth = (this.width - EDGE * 2 - GUTTER * <f32>(COLUMNS - 1)) / <f32>COLUMNS;
        let bottom = this.height - EDGE;
        let wordIndex = 0;
        for (let c = 0; c < COLUMNS; c++) {
            let column = this.columns[c];
            column.reset();
            let left = EDGE + <f32>c * (colWidth + GUTTER);
            let right = left + colWidth;
            let y = EDGE - this.ascent;
            while (y + this.descent <= bottom && wordIndex < this.words.length) {
                let segs = this.segments(y, left, right);
                let s = 0;
                while (s + 1 < segs.length && wordIndex < this.words.length) {
                    let x = segs[s];
                    let segEnd = segs[s + 1];
                    while (wordIndex < this.words.length) {
                        let word = this.words[wordIndex];
                        if (word.width < 0) {
                            // A paragraph ends the line and opens a small gap.
                            wordIndex++;
                            s = segs.length;
                            y += this.lineHeight * 0.5;
                            break;
                        }
                        let fits = x + word.width <= segEnd;
                        // A word wider than a whole line still has to land
                        // somewhere.
                        if (!fits && !(x == segs[s] && segEnd - x >= colWidth - 1)) {
                            break;
                        }
                        column.add(word.path, Mat2D.withTranslation(x, y));
                        x += word.width + this.spaceWidth;
                        wordIndex++;
                    }
                    s += 2;
                }
                y += this.lineHeight;
            }
        }
        this.laidOut = this.circle;
    }

    override advance(seconds: f64): bool {
        let dt = <f32>seconds;
        this.elapsed += dt;
        if (!this.pointerSeen) {
            let t = this.elapsed * 0.7;
            this.target = Vector.xy(
                this.width * (0.5 + 0.3 * Mathf.cos(t)),
                this.height * (0.5 + 0.3 * Mathf.sin(t * 1.3)));
        }
        let ease = Mathf.min(1, dt * 10);
        this.circle = Vector.xy(
            this.circle.x + (this.target.x - this.circle.x) * ease,
            this.circle.y + (this.target.y - this.circle.y) * ease);
        if (Mathf.abs(this.circle.x - this.laidOut.x) + Mathf.abs(this.circle.y - this.laidOut.y) > 0.2) {
            this.layout();
        }
        return true;
    }

    override draw(renderer: Renderer): void {
        for (let c = 0; c < this.columns.length; c++) {
            renderer.drawPath(this.columns[c], this.ink);
        }
        renderer.save();
        renderer.transform(Mat2D.withTranslation(this.circle.x, this.circle.y));
        renderer.drawPath(this.ringPath, this.ring);
        renderer.restore();
    }

    override pointerMove(event: PointerEvent): void {
        this.pointerSeen = true;
        this.target = event.position;
    }
}
