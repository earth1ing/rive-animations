// The AnimaScript twin of the Luau WavyPathEffect: each contour is
// resampled and displaced along its normal by a travelling sine wave. The
// host samples the contour; the displacement and the output path run wide,
// and rive.yaml's wasmSimd: off bakes the scalar side of a `--bench`
// comparison.
import { PathEffect, Context } from "rive/host";
import { Path } from "rive/path";
import { PathEffectNode } from "rive/path_effect";

const TWO_PI: f64 = 6.283185307179586;

export class Main extends PathEffect {
    // How far the wave displaces perpendicular to the path.
    @input amplitude: f64 = 5;
    // Distance along the path for one full sine cycle.
    @input wavelength: f64 = 30;
    // Cycles per second.
    @input speed: f64 = 1;
    // Line segments approximating each contour.
    @input segments: f64 = 100;

    elapsed: f64 = 0;
    outPath: Path = new Path();
    context: Context? = null;
    // Per sample position and tangent, four floats each, then the wave
    // height, both with spare lanes so the wide path can load past the end.
    samples: StaticArray<f32> = new StaticArray<f32>(0);
    waves: StaticArray<f32> = new StaticArray<f32>(0);
    verbs: StaticArray<u8> = new StaticArray<u8>(0);
    points: StaticArray<f32> = new StaticArray<f32>(0);
    sampleCapacity: i32 = 0;

    override init(context: Context): bool {
        this.context = context;
        return true;
    }

    override advance(seconds: f64): bool {
        this.elapsed += seconds;
        let context = this.context;
        if (context != null) {
            context.markNeedsUpdate();
        }
        return true;
    }

    private reserve(count: i32): void {
        if (count <= this.sampleCapacity) {
            return;
        }
        this.sampleCapacity = count;
        this.samples = new StaticArray<f32>(count * 4 + 8);
        this.waves = new StaticArray<f32>(count + 4);
        this.verbs = new StaticArray<u8>(count + 1);
        this.points = new StaticArray<f32>(count * 2 + 4);
    }

    override update(inPath: Path, node: PathEffectNode): Path {
        let outPath = this.outPath;
        outPath.reset();
        let amplitude = this.amplitude;
        let wavelength = Math.max(this.wavelength, 1);
        let segments = <i32>Math.max(Math.floor(this.segments), 4);
        let phase = this.elapsed * this.speed * TWO_PI;
        let count = segments + 1;
        this.reserve(count);
        let contour = inPath.contours();
        while (contour != null) {
            let len = contour.length;
            if (len < 0.001) {
                contour = contour.next;
                continue;
            }
            let step = len / <f64>segments;
            let samples = this.samples;
            let waves = this.waves;
            for (let i = 0; i < count; i++) {
                let dist = <f64>i * step;
                if (dist > len) {
                    dist = len;
                }
                let posTan = contour.positionAndTangent(dist);
                samples[i * 4] = posTan.v0.x;
                samples[i * 4 + 1] = posTan.v0.y;
                samples[i * 4 + 2] = posTan.v1.x;
                samples[i * 4 + 3] = posTan.v1.y;
                waves[i] = <f32>(amplitude * Math.sin((dist / wavelength) * TWO_PI + phase));
            }
            this.displace(count);
            this.emit(count, contour.isClosed);
            contour = contour.next;
        }
        return outPath;
    }

    // Moves every sample along its normal (the tangent turned a quarter
    // turn) by its wave height; two samples per op when wide.
    private unsafe displace(count: i32): void {
        let src = changetype<usize>(this.samples);
        let wave = changetype<usize>(this.waves);
        let dst = changetype<usize>(this.points);
        let i = 0;
        if (ASC_FEATURE_SIMD) {
            let flip = f32x4.replace_lane(f32x4.replace_lane(f32x4.splat(1), 0, -1), 2, -1);
            for (; i + 1 < count; i += 2) {
                let p = v128.load(src + <usize>i * 16);
                let q = v128.load(src + <usize>i * 16, 16);
                let pos = v128.shuffle<f32>(p, q, 0, 1, 4, 5);
                let normal = f32x4.mul(v128.shuffle<f32>(p, q, 3, 2, 7, 6), flip);
                let w = v128.load(wave + <usize>i * 4);
                let heights = v128.shuffle<f32>(w, w, 0, 0, 1, 1);
                v128.store(dst + <usize>i * 8, f32x4.add(pos, f32x4.mul(normal, heights)));
            }
        }
        for (; i < count; i++) {
            let at = src + <usize>i * 16;
            let nx = -load<f32>(at, 12);
            let ny = load<f32>(at, 8);
            let height = load<f32>(wave + <usize>i * 4);
            store<f32>(dst + <usize>i * 8, load<f32>(at) + nx * height);
            store<f32>(dst + <usize>i * 8, load<f32>(at, 4) + ny * height, 4);
        }
    }

    // One move, a line per remaining sample and a close on closed contours,
    // appended to the output in a single call.
    private unsafe emit(count: i32, closed: bool): void {
        let verbs = changetype<usize>(this.verbs);
        store<u8>(verbs, 0);
        memory.fill(verbs + 1, 1, <usize>count - 1);
        let verbCount = count;
        if (closed) {
            store<u8>(verbs + <usize>count, 5);
            verbCount++;
        }
        this.outPath.appendRaw(verbs, <u32>verbCount, changetype<usize>(this.points), <u32>count * 2);
    }
}
