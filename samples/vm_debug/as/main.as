// The AnimaScript twin of luau/main.luau: circles the Dashboard view model's
// orbs around a centre shape and writes live stats back every frame, so the
// debugger always has values moving.
import { Layout, Context } from "rive/host";
import { Color } from "rive/color";
import { Paint } from "rive/paint";
import { Path } from "rive/path";
import { Renderer } from "rive/renderer";
import { Vector } from "rive/vector";
import {
    PropertyBoolean,
    PropertyColor,
    PropertyEnum,
    PropertyList,
    PropertyNumber,
    PropertyString,
} from "rive/data";

const RING: f64 = 130;
const WHITE: Color = 0xFFFFFFFF;

// One per shape drawn, since a path cannot change until the frame after it
// is drawn.
class Slot {
    path: Path = new Path();
    paint: Paint = new Paint();
}

function polygon(
    path: Path,
    cx: f64,
    cy: f64,
    radius: f64,
    sides: i32,
    turn: f64,
): void {
    path.reset();
    for (let i = 0; i < sides; i++) {
        let a = turn + (Math.PI * 2 * <f64>i) / <f64>sides;
        let point = Vector.xy(
            <f32>(cx + Math.cos(a) * radius),
            <f32>(cy + Math.sin(a) * radius),
        );
        if (i == 0) {
            path.moveTo(point);
        } else {
            path.lineTo(point);
        }
    }
    path.close();
}

export class Orbit extends Layout {
    context: Context? = null;
    speed: PropertyNumber? = null;
    paused: PropertyBoolean? = null;
    tint: PropertyColor? = null;
    shape: PropertyEnum? = null;
    title: PropertyString? = null;
    orbs: PropertyList? = null;
    frames: PropertyNumber? = null;
    spin: PropertyNumber? = null;
    bursts: PropertyNumber? = null;
    angle: f64 = 0;
    pulse: f64 = 0;
    width: f64 = 0;
    height: f64 = 0;
    slots: Slot[] = [];

    override init(context: Context): bool {
        // init runs twice, and the view model is absent the first time.
        let vm = context.viewModel();
        if (vm == null) {
            return true;
        }
        this.context = context;
        this.speed = vm.getNumber("speed");
        this.paused = vm.getBoolean("paused");
        this.tint = vm.getColor("tint");
        this.shape = vm.getEnum("shape");
        this.orbs = vm.getList("orbs");
        let stats = vm.getViewModel("stats");
        if (stats != null) {
            let live = stats.value;
            this.frames = live.getNumber("frames");
            this.spin = live.getNumber("angle");
            this.bursts = live.getNumber("bursts");
        }
        let burst = vm.getTrigger("burst");
        if (burst != null) {
            burst.addListenerWith(this, (self: Orbit): void => {
                self.pulse = 1;
                let bursts = self.bursts;
                if (bursts != null) {
                    bursts.value += 1;
                }
                self.log("burst");
            });
        }
        let title = vm.getString("title");
        if (title != null) {
            this.title = title;
            title.addListenerWith(this, (self: Orbit): void => {
                let title = self.title;
                if (title != null) {
                    self.log("title is now " + title.value);
                }
            });
        }
        return true;
    }

    override resize(width: f64, height: f64, scale: f64): void {
        this.width = width;
        this.height = height;
    }

    override advance(seconds: f64): bool {
        let paused = this.paused;
        if (paused == null || !paused.value) {
            let speed = this.speed;
            this.angle += (speed != null ? speed.value : 1) * seconds;
        }
        this.pulse = Math.max(0, this.pulse - seconds * 2);
        let frames = this.frames;
        if (frames != null) {
            frames.value += 1;
        }
        let spin = this.spin;
        if (spin != null) {
            let degrees = (this.angle * 180) / Math.PI;
            spin.value = Math.floor(degrees % 360);
        }
        return true;
    }

    log(message: string): void {
        let context = this.context;
        if (context != null) {
            context.log(message);
        }
    }

    slotAt(index: i32): Slot {
        while (this.slots.length <= index) {
            this.slots.push(new Slot());
        }
        return this.slots[index];
    }

    override draw(renderer: Renderer): void {
        let cx = this.width / 2;
        let cy = this.height / 2;
        let shape = this.shape;
        let name = shape != null ? shape.value : "circle";
        let sides: i32 = name == "circle" ? 24 : 4;
        let turn: f64 = name == "square" ? Math.PI / 4 : 0;
        let tint = this.tint;

        let core = this.slotAt(0);
        polygon(core.path, cx, cy, 36 + this.pulse * 40, sides, turn + this.angle);
        core.paint.color = tint != null ? tint.value : WHITE;
        renderer.drawPath(core.path, core.paint);

        let orbs = this.orbs;
        if (orbs == null) {
            return;
        }
        let count = orbs.length;
        for (let i = 0; i < count; i++) {
            let orb = orbs.get(i);
            let size = orb.getNumber("size");
            let color = orb.getColor("color");
            let a = this.angle + (Math.PI * 2 * <f64>i) / <f64>count;
            let slot = this.slotAt(i + 1);
            polygon(
                slot.path,
                cx + Math.cos(a) * RING,
                cy + Math.sin(a) * RING,
                size != null ? size.value : 10,
                sides,
                turn - this.angle * 2,
            );
            slot.paint.color = color != null ? color.value : WHITE;
            renderer.drawPath(slot.path, slot.paint);
        }
    }
}
