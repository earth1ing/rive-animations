// Skeleton hierarchy, keyframe sampling and vertex skinning, a port of the
// Luau SkeletalAnimation module. Matrices are sixteen floats column major
// like glTF, packed one after another so a joint is an offset.

import { GLBLoader, GLBData } from "./glb_loader";

export class JointState {
    translation: StaticArray<f32> = new StaticArray<f32>(3);
    rotation: StaticArray<f32> = new StaticArray<f32>(4);
    scale: StaticArray<f32> = new StaticArray<f32>(3);
}

export class Skeleton {
    jointCount: i32 = 0;
    jointNodes: Array<i32> = [];
    // Sixteen floats per joint in each matrix block.
    inverseBindMatrices: StaticArray<f32> = new StaticArray<f32>(0);
    worldMatrices: StaticArray<f32> = new StaticArray<f32>(0);
    skinMatrices: StaticArray<f32> = new StaticArray<f32>(0);
    // -1 for a root joint.
    jointParents: Array<i32> = [];
    localTransforms: Array<JointState> = [];
    scaleCorrection: f32 = 1;
}

export class AnimationChannel {
    jointIndex: i32 = 0;
    path: string = "";
    times: Array<f32> = [];
    values: Array<f32> = [];
    interpolation: string = "LINEAR";
}

export class AnimationClip {
    name: string = "";
    duration: f32 = 0;
    channels: Array<AnimationChannel> = [];
}

export namespace SkeletalAnimation {
    function mat4Identity(out: StaticArray<f32>, o: i32): void {
        for (let i = 0; i < 16; i++) {
            out[o + i] = 0;
        }
        out[o] = 1;
        out[o + 5] = 1;
        out[o + 10] = 1;
        out[o + 15] = 1;
    }

    // out = a * b over three matrix blocks; out must not alias either input.
    function mat4Multiply(
        out: StaticArray<f32>, o: i32,
        a: StaticArray<f32>, ao: i32,
        b: StaticArray<f32>, bo: i32
    ): void {
        for (let col = 0; col < 4; col++) {
            for (let row = 0; row < 4; row++) {
                let sum: f32 = 0;
                for (let k = 0; k < 4; k++) {
                    sum = sum + a[ao + row + k * 4] * b[bo + k + col * 4];
                }
                out[o + row + col * 4] = sum;
            }
        }
    }

    // T * R * S from a joint's local transform.
    function mat4FromTRS(out: StaticArray<f32>, o: i32, state: JointState): void {
        let q = state.rotation;
        let x = q[0], y = q[1], z = q[2], w = q[3];
        let xx = x * x, yy = y * y, zz = z * z;
        let xy = x * y, xz = x * z, yz = y * z;
        let wx = w * x, wy = w * y, wz = w * z;
        let s = state.scale;
        let t = state.translation;
        out[o] = (1 - 2 * (yy + zz)) * s[0];
        out[o + 1] = (2 * (xy + wz)) * s[0];
        out[o + 2] = (2 * (xz - wy)) * s[0];
        out[o + 3] = 0;
        out[o + 4] = (2 * (xy - wz)) * s[1];
        out[o + 5] = (1 - 2 * (xx + zz)) * s[1];
        out[o + 6] = (2 * (yz + wx)) * s[1];
        out[o + 7] = 0;
        out[o + 8] = (2 * (xz + wy)) * s[2];
        out[o + 9] = (2 * (yz - wx)) * s[2];
        out[o + 10] = (1 - 2 * (xx + yy)) * s[2];
        out[o + 11] = 0;
        out[o + 12] = t[0];
        out[o + 13] = t[1];
        out[o + 14] = t[2];
        out[o + 15] = 1;
    }

    function quatNormalize(q: StaticArray<f32>): void {
        let len = Mathf.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
        if (len < 0.00001) {
            q[0] = 0;
            q[1] = 0;
            q[2] = 0;
            q[3] = 1;
            return;
        }
        let inv: f32 = 1 / len;
        q[0] = q[0] * inv;
        q[1] = q[1] * inv;
        q[2] = q[2] * inv;
        q[3] = q[3] * inv;
    }

    function quatSlerp(out: StaticArray<f32>, a: StaticArray<f32>, b: StaticArray<f32>, t: f32): void {
        let dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
        let bx = b[0], by = b[1], bz = b[2], bw = b[3];
        if (dot < 0) {
            dot = -dot;
            bx = -bx;
            by = -by;
            bz = -bz;
            bw = -bw;
        }
        if (dot > 0.9995) {
            out[0] = a[0] + t * (bx - a[0]);
            out[1] = a[1] + t * (by - a[1]);
            out[2] = a[2] + t * (bz - a[2]);
            out[3] = a[3] + t * (bw - a[3]);
            quatNormalize(out);
            return;
        }
        dot = Mathf.min(1, Mathf.max(-1, dot));
        let theta = Mathf.acos(dot);
        let sinTheta = Mathf.sin(theta);
        let s0 = Mathf.sin((1 - t) * theta) / sinTheta;
        let s1 = Mathf.sin(t * theta) / sinTheta;
        out[0] = s0 * a[0] + s1 * bx;
        out[1] = s0 * a[1] + s1 * by;
        out[2] = s0 * a[2] + s1 * bz;
        out[3] = s0 * a[3] + s1 * bw;
    }

    function jointForNode(skeleton: Skeleton, nodeIndex: i32): i32 {
        let nodes = skeleton.jointNodes;
        for (let i = 0; i < nodes.length; i++) {
            if (nodes[i] == nodeIndex) {
                return i;
            }
        }
        return -1;
    }

    export unsafe function buildSkeleton(glb: GLBData, skinIndex: i32): Skeleton? {
        if (skinIndex < 0 || skinIndex >= glb.skins.length) {
            return null;
        }
        let skin = glb.skins[skinIndex];
        let nodes = glb.nodes;
        let jointCount = skin.joints.length;
        let skeleton = new Skeleton();
        skeleton.jointCount = jointCount;
        for (let i = 0; i < jointCount; i++) {
            skeleton.jointNodes.push(skin.joints[i]);
        }
        let ibms = new StaticArray<f32>(jointCount * 16);
        let loaded = false;
        if (skin.inverseBindMatrices >= 0) {
            let data = GLBLoader.readMat4Array(glb, skin.inverseBindMatrices);
            if (data != null) {
                loaded = true;
                for (let i = 0; i < jointCount * 16; i++) {
                    ibms[i] = i < data.length ? data[i] : 0;
                }
            }
        }
        if (!loaded) {
            for (let i = 0; i < jointCount; i++) {
                mat4Identity(ibms, i * 16);
            }
        }
        // Joint translations far past ten units mean centimetres against a
        // metre mesh, the Luau module's heuristic.
        let scaleCorrection: f32 = 1;
        let maxMagnitude: f64 = 0;
        for (let j = 0; j < jointCount; j++) {
            let nodeIndex = skeleton.jointNodes[j];
            if (nodeIndex < 0 || nodeIndex >= nodes.length) {
                continue;
            }
            let translation = nodes[nodeIndex].translation;
            if (translation != null && translation.length >= 3) {
                let magnitude = Math.abs(translation[0]) + Math.abs(translation[1]) + Math.abs(translation[2]);
                if (magnitude > maxMagnitude) {
                    maxMagnitude = magnitude;
                }
            }
        }
        if (maxMagnitude > 10) {
            scaleCorrection = 0.01;
        }
        skeleton.scaleCorrection = scaleCorrection;
        for (let i = 0; i < jointCount; i++) {
            let o = i * 16;
            let col0 = Mathf.sqrt(ibms[o] * ibms[o] + ibms[o + 1] * ibms[o + 1] + ibms[o + 2] * ibms[o + 2]);
            if (col0 > 10) {
                let col1 = Mathf.sqrt(ibms[o + 4] * ibms[o + 4] + ibms[o + 5] * ibms[o + 5] + ibms[o + 6] * ibms[o + 6]);
                let col2 = Mathf.sqrt(ibms[o + 8] * ibms[o + 8] + ibms[o + 9] * ibms[o + 9] + ibms[o + 10] * ibms[o + 10]);
                ibms[o] = ibms[o] / col0;
                ibms[o + 1] = ibms[o + 1] / col0;
                ibms[o + 2] = ibms[o + 2] / col0;
                ibms[o + 4] = ibms[o + 4] / col1;
                ibms[o + 5] = ibms[o + 5] / col1;
                ibms[o + 6] = ibms[o + 6] / col1;
                ibms[o + 8] = ibms[o + 8] / col2;
                ibms[o + 9] = ibms[o + 9] / col2;
                ibms[o + 10] = ibms[o + 10] / col2;
            }
            ibms[o + 12] = ibms[o + 12] * scaleCorrection;
            ibms[o + 13] = ibms[o + 13] * scaleCorrection;
            ibms[o + 14] = ibms[o + 14] * scaleCorrection;
        }
        skeleton.inverseBindMatrices = ibms;
        skeleton.worldMatrices = new StaticArray<f32>(jointCount * 16);
        skeleton.skinMatrices = new StaticArray<f32>(jointCount * 16);
        for (let j = 0; j < jointCount; j++) {
            let nodeIndex = skeleton.jointNodes[j];
            let state = new JointState();
            state.rotation[3] = 1;
            state.scale[0] = 1;
            state.scale[1] = 1;
            state.scale[2] = 1;
            if (nodeIndex >= 0 && nodeIndex < nodes.length) {
                let node = nodes[nodeIndex];
                let translation = node.translation;
                if (translation != null && translation.length >= 3) {
                    state.translation[0] = <f32>translation[0] * scaleCorrection;
                    state.translation[1] = <f32>translation[1] * scaleCorrection;
                    state.translation[2] = <f32>translation[2] * scaleCorrection;
                }
                let rotation = node.rotation;
                if (rotation != null && rotation.length >= 4) {
                    state.rotation[0] = <f32>rotation[0];
                    state.rotation[1] = <f32>rotation[1];
                    state.rotation[2] = <f32>rotation[2];
                    state.rotation[3] = <f32>rotation[3];
                }
                let scale = node.scale;
                if (scale != null && scale.length >= 3) {
                    state.scale[0] = <f32>scale[0];
                    state.scale[1] = <f32>scale[1];
                    state.scale[2] = <f32>scale[2];
                }
            }
            skeleton.localTransforms.push(state);
            // The parent is whichever node lists this one as a child.
            let parent = -1;
            for (let n = 0; n < nodes.length && parent < 0; n++) {
                let children = nodes[n].children;
                if (children == null) {
                    continue;
                }
                for (let c = 0; c < children.length; c++) {
                    if (children[c] == nodeIndex) {
                        parent = jointForNode(skeleton, n);
                        break;
                    }
                }
            }
            skeleton.jointParents.push(parent);
            mat4Identity(skeleton.worldMatrices, j * 16);
            mat4Identity(skeleton.skinMatrices, j * 16);
        }
        return skeleton;
    }

    export unsafe function loadAnimation(glb: GLBData, animIndex: i32, skeleton: Skeleton): AnimationClip? {
        if (animIndex < 0 || animIndex >= glb.animations.length) {
            return null;
        }
        let anim = glb.animations[animIndex];
        let clip = new AnimationClip();
        clip.name = anim.name.length > 0 ? anim.name : "Animation" + (animIndex + 1).toString();
        for (let c = 0; c < anim.channels.length; c++) {
            let channel = anim.channels[c];
            if (channel.targetNode < 0) {
                continue;
            }
            let jointIndex = jointForNode(skeleton, channel.targetNode);
            if (jointIndex < 0 || channel.sampler < 0 || channel.sampler >= anim.samplers.length) {
                continue;
            }
            let sampler = anim.samplers[channel.sampler];
            let times = GLBLoader.readAccessorFloats(glb, sampler.input);
            let values = GLBLoader.readAccessorFloats(glb, sampler.output);
            if (times == null || values == null) {
                continue;
            }
            if (times.length > 0) {
                let last = times[times.length - 1];
                if (last > clip.duration) {
                    clip.duration = last;
                }
            }
            if (channel.targetPath == "translation" && skeleton.scaleCorrection != 1) {
                for (let v = 0; v < values.length; v++) {
                    values[v] = values[v] * skeleton.scaleCorrection;
                }
            }
            let out = new AnimationChannel();
            out.jointIndex = jointIndex;
            out.path = channel.targetPath;
            out.times = times;
            out.values = values;
            out.interpolation = sampler.interpolation;
            clip.channels.push(out);
        }
        return clip;
    }

    // The keyframe at or before time plus the blend toward the next.
    function findKeyframe(times: Array<f32>, time: f32, blend: StaticArray<f32>): i32 {
        blend[0] = 0;
        let count = times.length;
        if (count == 0) {
            return 0;
        }
        if (time <= times[0]) {
            return 0;
        }
        if (time >= times[count - 1]) {
            blend[0] = 1;
            return count - 1;
        }
        let lo = 0;
        let hi = count - 1;
        while (lo < hi - 1) {
            let mid = (lo + hi) / 2;
            if (times[mid] <= time) {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        let t0 = times[lo];
        let t1 = times[hi];
        if (t1 > t0) {
            blend[0] = (time - t0) / (t1 - t0);
        }
        return lo;
    }

    function hermite(p0: f32, m0: f32, p1: f32, m1: f32, t: f32): f32 {
        let t2 = t * t;
        let t3 = t2 * t;
        let h00 = 2 * t3 - 3 * t2 + 1;
        let h10 = t3 - 2 * t2 + t;
        let h01 = -2 * t3 + 3 * t2;
        let h11 = t3 - t2;
        return h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1;
    }

    let blendScratch: StaticArray<f32> = new StaticArray<f32>(1);
    let quatScratch: StaticArray<f32> = new StaticArray<f32>(4);
    let quatScratchNext: StaticArray<f32> = new StaticArray<f32>(4);

    // Fills out with the channel's components at time; cubic splines
    // carry in tangent, value and out tangent per keyframe.
    function sampleChannel(channel: AnimationChannel, time: f32, out: StaticArray<f32>, size: i32): void {
        let times = channel.times;
        let values = channel.values;
        let idx = findKeyframe(times, time, blendScratch);
        let t = blendScratch[0];
        if (channel.interpolation == "CUBICSPLINE") {
            let stride = size * 3;
            let i0 = idx * stride;
            let last = t == 0 || idx >= times.length - 1;
            if (last) {
                for (let c = 0; c < size; c++) {
                    out[c] = values[i0 + size + c];
                }
                return;
            }
            let i1 = (idx + 1) * stride;
            let dt = times[idx + 1] - times[idx];
            for (let c = 0; c < size; c++) {
                out[c] = hermite(
                    values[i0 + size + c],
                    values[i0 + size * 2 + c] * dt,
                    values[i1 + size + c],
                    values[i1 + c] * dt,
                    t
                );
            }
            return;
        }
        let i0 = idx * size;
        let hold = t == 0 || idx >= times.length - 1 || channel.interpolation == "STEP";
        if (hold) {
            for (let c = 0; c < size; c++) {
                out[c] = values[i0 + c];
            }
            return;
        }
        let i1 = (idx + 1) * size;
        if (size == 4) {
            let a = quatScratch;
            for (let c = 0; c < 4; c++) {
                a[c] = values[i0 + c];
            }
            let b = quatScratchNext;
            for (let c = 0; c < 4; c++) {
                b[c] = values[i1 + c];
            }
            quatSlerp(out, a, b, t);
            return;
        }
        for (let c = 0; c < size; c++) {
            out[c] = values[i0 + c] + t * (values[i1 + c] - values[i0 + c]);
        }
    }

    export function sampleAnimation(skeleton: Skeleton, clip: AnimationClip, time: f32): void {
        if (clip.duration > 0) {
            time = time % clip.duration;
        }
        let channels = clip.channels;
        for (let i = 0; i < channels.length; i++) {
            let channel = channels[i];
            let state = skeleton.localTransforms[channel.jointIndex];
            if (channel.path == "translation") {
                sampleChannel(channel, time, state.translation, 3);
            } else if (channel.path == "rotation") {
                sampleChannel(channel, time, state.rotation, 4);
                if (channel.interpolation == "CUBICSPLINE") {
                    quatNormalize(state.rotation);
                }
            } else if (channel.path == "scale") {
                sampleChannel(channel, time, state.scale, 3);
            }
        }
    }

    let localScratch: StaticArray<f32> = new StaticArray<f32>(16);

    // Parents come before children in glTF exports, so one pass suffices.
    export function updateSkeleton(skeleton: Skeleton): void {
        let world = skeleton.worldMatrices;
        let local = localScratch;
        for (let j = 0; j < skeleton.jointCount; j++) {
            mat4FromTRS(local, 0, skeleton.localTransforms[j]);
            let parent = skeleton.jointParents[j];
            if (parent >= 0) {
                mat4Multiply(world, j * 16, world, parent * 16, local, 0);
            } else {
                for (let i = 0; i < 16; i++) {
                    world[j * 16 + i] = local[i];
                }
            }
            mat4Multiply(skeleton.skinMatrices, j * 16, world, j * 16, skeleton.inverseBindMatrices, j * 16);
        }
    }

    // Skins every vertex into out, a weighted sum of skin matrices times the
    // position. out must not alias positions: the wide path stores a whole
    // vector at stride three, so lane three lands on the next vertex's x, and
    // both buffers carry a spare lane past the last vertex for that reason.
    export unsafe function skinVertices(
        skeleton: Skeleton,
        positions: StaticArray<f32>,
        vertexCount: i32,
        joints: Array<i32>,
        weights: Array<f32>,
        out: StaticArray<f32>
    ): void {
        let matrices = changetype<usize>(skeleton.skinMatrices);
        let src = changetype<usize>(positions);
        let dst = changetype<usize>(out);
        assert(src != dst, "skinVertices cannot skin in place");
        let jointPtr = joints.dataStart;
        let weightPtr = weights.dataStart;
        if (ASC_FEATURE_SIMD) {
            let zero = f32x4.splat(0);
            for (let i = 0; i < vertexCount; i++) {
                let p = v128.load(src + <usize>i * 12);
                let xs = v128.shuffle<f32>(p, p, 0, 0, 0, 0);
                let ys = v128.shuffle<f32>(p, p, 1, 1, 1, 1);
                let zs = v128.shuffle<f32>(p, p, 2, 2, 2, 2);
                let acc = zero;
                let wi = <usize>i * 16;
                for (let k: usize = 0; k < 4; k++) {
                    let weight = load<f32>(weightPtr + wi + k * 4);
                    if (weight > 0) {
                        let m = matrices + <usize>load<i32>(jointPtr + wi + k * 4) * 64;
                        let v = f32x4.add(
                            f32x4.add(
                                f32x4.add(f32x4.mul(v128.load(m), xs), f32x4.mul(v128.load(m, 16), ys)),
                                f32x4.mul(v128.load(m, 32), zs)
                            ),
                            v128.load(m, 48)
                        );
                        let invW: f32 = 1 / f32x4.extract_lane(v, 3);
                        v = f32x4.mul(v, f32x4.splat(invW));
                        acc = f32x4.add(acc, f32x4.mul(v, f32x4.splat(weight)));
                    }
                }
                v128.store(dst + <usize>i * 12, acc);
            }
            return;
        }
        for (let i = 0; i < vertexCount; i++) {
            let pi = <usize>i * 12;
            let x = load<f32>(src + pi);
            let y = load<f32>(src + pi + 4);
            let z = load<f32>(src + pi + 8);
            let outX: f32 = 0, outY: f32 = 0, outZ: f32 = 0;
            let wi = <usize>i * 16;
            for (let k: usize = 0; k < 4; k++) {
                let weight = load<f32>(weightPtr + wi + k * 4);
                if (weight > 0) {
                    let m = matrices + <usize>load<i32>(jointPtr + wi + k * 4) * 64;
                    let w = load<f32>(m, 12) * x + load<f32>(m, 28) * y + load<f32>(m, 44) * z + load<f32>(m, 60);
                    let invW: f32 = 1 / w;
                    let tx = (load<f32>(m, 0) * x + load<f32>(m, 16) * y + load<f32>(m, 32) * z + load<f32>(m, 48)) * invW;
                    let ty = (load<f32>(m, 4) * x + load<f32>(m, 20) * y + load<f32>(m, 36) * z + load<f32>(m, 52)) * invW;
                    let tz = (load<f32>(m, 8) * x + load<f32>(m, 24) * y + load<f32>(m, 40) * z + load<f32>(m, 56)) * invW;
                    outX = outX + tx * weight;
                    outY = outY + ty * weight;
                    outZ = outZ + tz * weight;
                }
            }
            store<f32>(dst + pi, outX);
            store<f32>(dst + pi + 4, outY);
            store<f32>(dst + pi + 8, outZ);
        }
    }
}
