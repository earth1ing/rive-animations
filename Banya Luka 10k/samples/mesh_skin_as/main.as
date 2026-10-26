// The AnimaScript twin of the Luau GLBAnimationExample: loads a skinned
// .glb blob, plays its first animation and draws the mesh as a wireframe.
// The per vertex skinning and the screen projection run wide; rive.yaml's
// wasmSimd: off bakes the scalar side of a `--bench` comparison.
import { Layout, Context } from "rive/host";
import { Path } from "rive/path";
import { Paint, PaintStyle, StrokeCap, StrokeJoin } from "rive/paint";
import { Renderer } from "rive/renderer";
import { Color } from "rive/color";
import { GLBLoader, GLBData } from "./glb_loader";
import { SkeletalAnimation, Skeleton, AnimationClip } from "./skeletal_animation";

export class Main extends Layout {
    // The blob asset name, the file's basename.
    @input blobName: string = "character";
    // Which animation to play, one based like the Luau input.
    @input animationIndex: f64 = 1;

    vertexCount: i32 = 0;
    // Three floats per vertex plus spare lanes so wide loads and stores at
    // stride three never run past the buffer.
    positions: StaticArray<f32> = new StaticArray<f32>(0);
    skinned: StaticArray<f32> = new StaticArray<f32>(0);
    // Two floats per vertex on screen.
    projected: StaticArray<f32> = new StaticArray<f32>(0);
    indices: Array<i32> = [];
    joints: Array<i32> = [];
    weights: Array<f32> = [];
    hasSkin: bool = false;
    skeleton: Skeleton? = null;
    clip: AnimationClip? = null;
    animationTime: f32 = 0;

    // The wireframe verbs never change: move, line, line, close per triangle.
    verbs: StaticArray<u8> = new StaticArray<u8>(0);
    pathPoints: StaticArray<f32> = new StaticArray<f32>(0);
    path: Path = new Path();
    paint: Paint = new Paint();
    scale: f32 = 100;
    offsetX: f32 = 0;
    offsetY: f32 = 0;
    offsetZ: f32 = 0;
    width: f32 = 500;
    height: f32 = 500;

    override init(context: Context): bool {
        this.paint.style = PaintStyle.stroke;
        this.paint.thickness = 1;
        this.paint.color = Color.rgba(100, 200, 255, 200);
        this.paint.cap = StrokeCap.round;
        this.paint.join = StrokeJoin.round;
        let asset = context.blob(this.blobName);
        if (asset == null) {
            return false;
        }
        let result = GLBLoader.parse(asset);
        if (!result.success) {
            return false;
        }
        let glb = result.data!;
        if (glb.meshes.length == 0 || glb.meshes[0].primitives.length == 0) {
            return false;
        }
        let prim = glb.meshes[0].primitives[0];
        let posIndex = prim.attribute("POSITION");
        if (posIndex < 0) {
            return false;
        }
        let loaded = GLBLoader.readAccessorFloats(glb, posIndex);
        if (loaded == null) {
            return false;
        }
        let count = loaded.length / 3;
        this.vertexCount = count;
        this.positions = new StaticArray<f32>(count * 3 + 4);
        this.skinned = new StaticArray<f32>(count * 3 + 4);
        this.projected = new StaticArray<f32>(count * 2 + 4);
        for (let i = 0; i < count * 3; i++) {
            this.positions[i] = loaded[i];
            this.skinned[i] = loaded[i];
        }
        let indices: Array<i32>? = null;
        if (prim.indices >= 0) {
            indices = GLBLoader.readIndices(glb, prim.indices);
        }
        if (indices == null) {
            indices = new Array<i32>(count);
            for (let i = 0; i < count; i++) {
                indices[i] = i;
            }
        }
        this.indices = indices;
        let triangles = indices.length / 3;
        this.verbs = new StaticArray<u8>(triangles * 4);
        this.pathPoints = new StaticArray<f32>(triangles * 6);
        for (let t = 0; t < triangles; t++) {
            this.verbs[t * 4] = 0;
            this.verbs[t * 4 + 1] = 1;
            this.verbs[t * 4 + 2] = 1;
            this.verbs[t * 4 + 3] = 5;
        }
        this.loadSkin(glb, prim.attribute("JOINTS_0"), prim.attribute("WEIGHTS_0"));
        this.center();
        return true;
    }

    private loadSkin(glb: GLBData, jointsIndex: i32, weightsIndex: i32): void {
        if (jointsIndex < 0 || weightsIndex < 0) {
            return;
        }
        let joints = GLBLoader.readJoints(glb, jointsIndex);
        let weights = GLBLoader.readAccessorFloats(glb, weightsIndex);
        if (joints == null || weights == null) {
            return;
        }
        this.joints = joints;
        this.weights = weights;
        let skinIndex = -1;
        for (let i = 0; i < glb.nodes.length; i++) {
            let node = glb.nodes[i];
            if (node.mesh == 0 && node.skin >= 0) {
                skinIndex = node.skin;
                break;
            }
        }
        if (skinIndex < 0) {
            return;
        }
        let skeleton = SkeletalAnimation.buildSkeleton(glb, skinIndex);
        if (skeleton == null) {
            return;
        }
        this.skeleton = skeleton;
        if (glb.animations.length > 0) {
            let wanted = <i32>this.animationIndex - 1;
            let animIndex = wanted < 0 ? 0 : (wanted >= glb.animations.length ? glb.animations.length - 1 : wanted);
            this.clip = SkeletalAnimation.loadAnimation(glb, animIndex, skeleton);
        }
        this.hasSkin = this.clip != null;
    }

    // Centers on the mesh bounds and fits it into the layout.
    private center(): void {
        let positions = this.positions;
        let minX: f32 = Infinity, maxX: f32 = -Infinity;
        let minY: f32 = Infinity, maxY: f32 = -Infinity;
        let minZ: f32 = Infinity, maxZ: f32 = -Infinity;
        for (let i = 0; i < this.vertexCount; i++) {
            let x = positions[i * 3];
            let y = positions[i * 3 + 1];
            let z = positions[i * 3 + 2];
            minX = Mathf.min(minX, x);
            maxX = Mathf.max(maxX, x);
            minY = Mathf.min(minY, y);
            maxY = Mathf.max(maxY, y);
            minZ = Mathf.min(minZ, z);
            maxZ = Mathf.max(maxZ, z);
        }
        this.offsetX = (minX + maxX) / 2;
        this.offsetY = (minY + maxY) / 2;
        this.offsetZ = (minZ + maxZ) / 2;
        this.fit(minX, maxX, minY, maxY);
    }

    private fit(minX: f32, maxX: f32, minY: f32, maxY: f32): void {
        let width = maxX - minX;
        let height = maxY - minY;
        if (width > 0 && height > 0 && this.width > 0 && this.height > 0) {
            let scaleX = this.width / (width * 1.5);
            let scaleY = this.height / (height * 1.5);
            this.scale = Mathf.min(scaleX, scaleY);
        }
    }

    override resize(width: f64, height: f64, scale: f64): void {
        this.width = <f32>width;
        this.height = <f32>height;
        let positions = this.skinned;
        let minX: f32 = Infinity, maxX: f32 = -Infinity;
        let minY: f32 = Infinity, maxY: f32 = -Infinity;
        for (let i = 0; i < this.vertexCount; i++) {
            let x = positions[i * 3];
            let y = positions[i * 3 + 1];
            minX = Mathf.min(minX, x);
            maxX = Mathf.max(maxX, x);
            minY = Mathf.min(minY, y);
            maxY = Mathf.max(maxY, y);
        }
        this.fit(minX, maxX, minY, maxY);
    }

    override advance(seconds: f64): bool {
        let skeleton = this.skeleton;
        let clip = this.clip;
        if (skeleton != null && clip != null && this.hasSkin) {
            this.animationTime += <f32>seconds;
            SkeletalAnimation.sampleAnimation(skeleton, clip, this.animationTime);
            SkeletalAnimation.updateSkeleton(skeleton);
            SkeletalAnimation.skinVertices(
                skeleton, this.positions, this.vertexCount, this.joints, this.weights, this.skinned);
            let root = skeleton.worldMatrices;
            this.offsetX = root[12];
            this.offsetY = root[13];
            this.offsetZ = root[14];
        }
        this.project();
        this.buildPath();
        return true;
    }

    // Orthographic projection of every skinned vertex, y flipped for the
    // screen; two vertices per op when wide.
    private unsafe project(): void {
        let src = changetype<usize>(this.skinned);
        let dst = changetype<usize>(this.projected);
        let count = this.vertexCount;
        let scale = this.scale;
        let cx = this.offsetX;
        let cy = this.offsetY;
        let screenCX = this.width / 2;
        let screenCY = this.height / 2;
        let i = 0;
        if (ASC_FEATURE_SIMD) {
            let centre = f32x4.replace_lane(f32x4.replace_lane(f32x4.splat(cx), 1, cy), 3, cy);
            let scales = f32x4.replace_lane(f32x4.replace_lane(f32x4.splat(scale), 1, -scale), 3, -scale);
            let screen = f32x4.replace_lane(f32x4.replace_lane(f32x4.splat(screenCX), 1, screenCY), 3, screenCY);
            for (; i + 1 < count; i += 2) {
                let a = v128.load(src + <usize>i * 12);
                let b = v128.load(src + <usize>i * 12, 16);
                let xy = v128.shuffle<f32>(a, b, 0, 1, 3, 4);
                v128.store(dst + <usize>i * 8, f32x4.add(f32x4.mul(f32x4.sub(xy, centre), scales), screen));
            }
        }
        for (; i < count; i++) {
            let x = load<f32>(src + <usize>i * 12);
            let y = load<f32>(src + <usize>i * 12 + 4);
            store<f32>(dst + <usize>i * 8, (x - cx) * scale + screenCX);
            store<f32>(dst + <usize>i * 8 + 4, (y - cy) * -scale + screenCY);
        }
    }

    // The wireframe: one closed triangle per index triple, appended in bulk.
    private unsafe buildPath(): void {
        let path = this.path;
        path.reset();
        let indices = this.indices;
        let triangles = indices.length / 3;
        let projected = changetype<usize>(this.projected);
        let points = changetype<usize>(this.pathPoints);
        for (let t = 0; t < triangles; t++) {
            let i0 = <usize>indices[t * 3] * 8;
            let i1 = <usize>indices[t * 3 + 1] * 8;
            let i2 = <usize>indices[t * 3 + 2] * 8;
            let at = points + <usize>t * 24;
            store<f32>(at, load<f32>(projected + i0));
            store<f32>(at, load<f32>(projected + i0, 4), 4);
            store<f32>(at, load<f32>(projected + i1), 8);
            store<f32>(at, load<f32>(projected + i1, 4), 12);
            store<f32>(at, load<f32>(projected + i2), 16);
            store<f32>(at, load<f32>(projected + i2, 4), 20);
        }
        path.appendRaw(changetype<usize>(this.verbs), <u32>triangles * 4, points, <u32>triangles * 6);
    }

    override draw(renderer: Renderer): void {
        renderer.drawPath(this.path, this.paint);
    }
}
