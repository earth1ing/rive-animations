// A flat particle field: twenty thousand positions and velocities in plain
// float arrays, one Euler step and a wall bounce per frame. The integrate
// runs four particles per op unless rive.yaml says wasmSimd: off, the
// cleanest A/B against the scalar bake since one wide op replaces four
// dispatches.
import { Layout, Context } from "rive/host";
import { Path } from "rive/path";
import { Paint } from "rive/paint";
import { Renderer } from "rive/renderer";
import { Color } from "rive/color";

const DRAW_EVERY: i32 = 20;
const HALF: f32 = 1.5;

export class Main extends Layout {
    @input count: f64 = 20000;
    @input speed: f64 = 80;

    // Positions and velocities, one array per axis with spare lanes so the
    // wide path can run past the last full group.
    xs: StaticArray<f32> = new StaticArray<f32>(0);
    ys: StaticArray<f32> = new StaticArray<f32>(0);
    vxs: StaticArray<f32> = new StaticArray<f32>(0);
    vys: StaticArray<f32> = new StaticArray<f32>(0);
    total: i32 = 0;
    width: f32 = 800;
    height: f32 = 600;
    // A square per drawn particle: move, three lines and a close.
    verbs: StaticArray<u8> = new StaticArray<u8>(0);
    points: StaticArray<f32> = new StaticArray<f32>(0);
    drawn: i32 = 0;
    path: Path = new Path();
    paint: Paint = new Paint();

    override init(context: Context): bool {
        this.paint.color = Color.rgba(255, 180, 90, 255);
        let total = <i32>this.count;
        this.total = total;
        this.xs = new StaticArray<f32>(total + 4);
        this.ys = new StaticArray<f32>(total + 4);
        this.vxs = new StaticArray<f32>(total + 4);
        this.vys = new StaticArray<f32>(total + 4);
        // A fixed seed keeps every bake on the same field.
        let seed: u32 = 12345;
        let speed = <f32>this.speed;
        for (let i = 0; i < total; i++) {
            seed = seed * 1664525 + 1013904223;
            this.xs[i] = <f32>(seed >>> 8) / 16777216.0 * this.width;
            seed = seed * 1664525 + 1013904223;
            this.ys[i] = <f32>(seed >>> 8) / 16777216.0 * this.height;
            seed = seed * 1664525 + 1013904223;
            this.vxs[i] = (<f32>(seed >>> 8) / 16777216.0 - 0.5) * speed;
            seed = seed * 1664525 + 1013904223;
            this.vys[i] = (<f32>(seed >>> 8) / 16777216.0 - 0.5) * speed;
        }
        let drawn = (total + DRAW_EVERY - 1) / DRAW_EVERY;
        this.drawn = drawn;
        this.verbs = new StaticArray<u8>(drawn * 5);
        this.points = new StaticArray<f32>(drawn * 8);
        for (let d = 0; d < drawn; d++) {
            this.verbs[d * 5] = 0;
            this.verbs[d * 5 + 1] = 1;
            this.verbs[d * 5 + 2] = 1;
            this.verbs[d * 5 + 3] = 1;
            this.verbs[d * 5 + 4] = 5;
        }
        return true;
    }

    override resize(width: f64, height: f64, scale: f64): void {
        this.width = <f32>width;
        this.height = <f32>height;
    }

    override advance(seconds: f64): bool {
        this.integrate(<f32>seconds);
        return true;
    }

    // One Euler step; a particle past a wall turns its velocity around.
    private unsafe integrate(dt: f32): void {
        let xs = changetype<usize>(this.xs);
        let ys = changetype<usize>(this.ys);
        let vxs = changetype<usize>(this.vxs);
        let vys = changetype<usize>(this.vys);
        let total = this.total;
        let width = this.width;
        let height = this.height;
        let i = 0;
        if (ASC_FEATURE_SIMD) {
            let step = f32x4.splat(dt);
            let zero = f32x4.splat(0);
            let right = f32x4.splat(width);
            let bottom = f32x4.splat(height);
            for (; i + 3 < total; i += 4) {
                let at = <usize>i * 4;
                let vx = v128.load(vxs + at);
                let vy = v128.load(vys + at);
                let x = f32x4.add(v128.load(xs + at), f32x4.mul(vx, step));
                let y = f32x4.add(v128.load(ys + at), f32x4.mul(vy, step));
                let outX = v128.or(f32x4.lt(x, zero), f32x4.gt(x, right));
                let outY = v128.or(f32x4.lt(y, zero), f32x4.gt(y, bottom));
                v128.store(xs + at, x);
                v128.store(ys + at, y);
                v128.store(vxs + at, v128.bitselect(f32x4.neg(vx), vx, outX));
                v128.store(vys + at, v128.bitselect(f32x4.neg(vy), vy, outY));
            }
        }
        for (; i < total; i++) {
            let at = <usize>i * 4;
            let vx = load<f32>(vxs + at);
            let vy = load<f32>(vys + at);
            let x = load<f32>(xs + at) + vx * dt;
            let y = load<f32>(ys + at) + vy * dt;
            store<f32>(xs + at, x);
            store<f32>(ys + at, y);
            if (x < 0 || x > width) {
                store<f32>(vxs + at, -vx);
            }
            if (y < 0 || y > height) {
                store<f32>(vys + at, -vy);
            }
        }
    }

    // Every twentieth particle as a small square, appended in one call.
    private unsafe buildPath(): void {
        let path = this.path;
        path.reset();
        let points = changetype<usize>(this.points);
        let drawn = this.drawn;
        for (let d = 0; d < drawn; d++) {
            let x = this.xs[d * DRAW_EVERY];
            let y = this.ys[d * DRAW_EVERY];
            let at = points + <usize>d * 32;
            store<f32>(at, x - HALF);
            store<f32>(at, y - HALF, 4);
            store<f32>(at, x + HALF, 8);
            store<f32>(at, y - HALF, 12);
            store<f32>(at, x + HALF, 16);
            store<f32>(at, y + HALF, 20);
            store<f32>(at, x - HALF, 24);
            store<f32>(at, y + HALF, 28);
        }
        path.appendRaw(changetype<usize>(this.verbs), <u32>drawn * 5, points, <u32>drawn * 8);
    }

    override draw(renderer: Renderer): void {
        this.buildPath();
        renderer.drawPath(this.path, this.paint);
    }
}
