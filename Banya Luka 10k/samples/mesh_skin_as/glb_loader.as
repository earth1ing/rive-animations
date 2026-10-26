// GLB container parsing: the JSON chunk through a small parser and the
// binary chunk read through accessors. A port of the Luau GLBLoader with
// zero based indices and typed records in place of tables.

export const enum JsonKind {
    null_ = 0,
    number = 1,
    string_ = 2,
    boolean = 3,
    array = 4,
    object = 5,
}

export class JsonValue {
    kind: JsonKind = JsonKind.null_;
    num: f64 = 0;
    str: string = "";
    flag: bool = false;
    items: Array<JsonValue> = [];
    keys: Array<string> = [];
    values: Array<JsonValue> = [];

    get length(): i32 {
        return this.items.length;
    }

    at(index: i32): JsonValue {
        return this.items[index];
    }

    get(key: string): JsonValue? {
        let keys = this.keys;
        for (let i = 0; i < keys.length; i++) {
            if (keys[i] == key) {
                return this.values[i];
            }
        }
        return null;
    }

    numberOr(key: string, fallback: f64): f64 {
        let value = this.get(key);
        return value != null && value.kind == JsonKind.number ? value.num : fallback;
    }

    intOr(key: string, fallback: i32): i32 {
        return <i32>this.numberOr(key, <f64>fallback);
    }

    stringOr(key: string, fallback: string): string {
        let value = this.get(key);
        return value != null && value.kind == JsonKind.string_ ? value.str : fallback;
    }

    // A numeric array member as f64s, null when absent or not an array.
    numbers(key: string): Array<f64>? {
        let value = this.get(key);
        if (value == null || value.kind != JsonKind.array) {
            return null;
        }
        let out = new Array<f64>();
        for (let i = 0; i < value.items.length; i++) {
            out.push(value.items[i].num);
        }
        return out;
    }

    ints(key: string): Array<i32>? {
        let value = this.get(key);
        if (value == null || value.kind != JsonKind.array) {
            return null;
        }
        let out = new Array<i32>();
        for (let i = 0; i < value.items.length; i++) {
            out.push(<i32>value.items[i].num);
        }
        return out;
    }
}

class JsonParser {
    text: string;
    pos: i32 = 0;
    len: i32;

    constructor(text: string) {
        this.text = text;
        this.len = text.length;
    }

    peek(): i32 {
        return this.pos < this.len ? this.text.charCodeAt(this.pos) : -1;
    }

    skipWhitespace(): void {
        while (this.pos < this.len) {
            let c = this.text.charCodeAt(this.pos);
            if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
                this.pos++;
            } else {
                break;
            }
        }
    }

    // The characters up to the closing quote; the cursor lands past it.
    readString(): string {
        let start = this.pos;
        while (this.pos < this.len && this.text.charCodeAt(this.pos) != 0x22) {
            this.pos += this.text.charCodeAt(this.pos) == 0x5c ? 2 : 1;
        }
        let out = this.text.substring(start, this.pos);
        this.pos++;
        return out;
    }

    parseValue(): JsonValue? {
        this.skipWhitespace();
        if (this.pos >= this.len) {
            return null;
        }
        let c = this.peek();
        let value = new JsonValue();
        if (c == 0x7b) {
            this.pos++;
            value.kind = JsonKind.object;
            this.skipWhitespace();
            if (this.peek() == 0x7d) {
                this.pos++;
                return value;
            }
            while (true) {
                this.skipWhitespace();
                if (this.peek() != 0x22) {
                    return null;
                }
                this.pos++;
                let key = this.readString();
                this.skipWhitespace();
                if (this.peek() != 0x3a) {
                    return null;
                }
                this.pos++;
                let member = this.parseValue();
                if (member == null) {
                    return null;
                }
                value.keys.push(key);
                value.values.push(member);
                this.skipWhitespace();
                let sep = this.peek();
                this.pos++;
                if (sep == 0x7d) {
                    return value;
                }
                if (sep != 0x2c) {
                    return null;
                }
            }
        }
        if (c == 0x5b) {
            this.pos++;
            value.kind = JsonKind.array;
            this.skipWhitespace();
            if (this.peek() == 0x5d) {
                this.pos++;
                return value;
            }
            while (true) {
                let item = this.parseValue();
                if (item == null) {
                    return null;
                }
                value.items.push(item);
                this.skipWhitespace();
                let sep = this.peek();
                this.pos++;
                if (sep == 0x5d) {
                    return value;
                }
                if (sep != 0x2c) {
                    return null;
                }
            }
        }
        if (c == 0x22) {
            this.pos++;
            value.kind = JsonKind.string_;
            value.str = this.readString();
            return value;
        }
        if (c == 0x74) {
            this.pos += 4;
            value.kind = JsonKind.boolean;
            value.flag = true;
            return value;
        }
        if (c == 0x66) {
            this.pos += 5;
            value.kind = JsonKind.boolean;
            return value;
        }
        if (c == 0x6e) {
            this.pos += 4;
            return value;
        }
        let start = this.pos;
        if (c == 0x2d) {
            this.pos++;
        }
        while (this.pos < this.len) {
            let ch = this.text.charCodeAt(this.pos);
            if ((ch >= 0x30 && ch <= 0x39) || ch == 0x2e || ch == 0x65 ||
                ch == 0x45 || ch == 0x2b || ch == 0x2d) {
                this.pos++;
            } else {
                break;
            }
        }
        value.kind = JsonKind.number;
        value.num = parseFloat(this.text.substring(start, this.pos));
        return value;
    }
}

export function parseJSON(text: string): JsonValue? {
    return new JsonParser(text).parseValue();
}

export class Primitive {
    attributeNames: Array<string> = [];
    attributeAccessors: Array<i32> = [];
    indices: i32 = -1;
    material: i32 = -1;
    mode: i32 = 4;

    // The accessor index of a named attribute, -1 when absent.
    attribute(name: string): i32 {
        let names = this.attributeNames;
        for (let i = 0; i < names.length; i++) {
            if (names[i] == name) {
                return this.attributeAccessors[i];
            }
        }
        return -1;
    }
}

export class Mesh {
    name: string = "";
    primitives: Array<Primitive> = [];
}

export class Accessor {
    bufferView: i32 = 0;
    byteOffset: i32 = 0;
    componentType: i32 = 0;
    count: i32 = 0;
    accessorType: string = "";
    // Integer components map onto -1..1 or 0..1 when set, the way glTF
    // stores byte and short weights.
    normalized: bool = false;
}

export class BufferView {
    byteOffset: i32 = 0;
    byteLength: i32 = 0;
    // Zero when the elements are tightly packed.
    byteStride: i32 = 0;
    target: i32 = 0;
}

export class GlbNode {
    name: string = "";
    children: Array<i32>? = null;
    mesh: i32 = -1;
    skin: i32 = -1;
    translation: Array<f64>? = null;
    rotation: Array<f64>? = null;
    scale: Array<f64>? = null;
    matrix: Array<f64>? = null;
}

export class Skin {
    name: string = "";
    joints: Array<i32> = [];
    inverseBindMatrices: i32 = -1;
    skeleton: i32 = -1;
}

export class AnimationSampler {
    input: i32 = 0;
    output: i32 = 0;
    interpolation: string = "LINEAR";
}

export class AnimationChannel {
    sampler: i32 = 0;
    targetNode: i32 = -1;
    targetPath: string = "";
}

export class Animation {
    name: string = "";
    channels: Array<AnimationChannel> = [];
    samplers: Array<AnimationSampler> = [];
}

export class GLBData {
    version: i32 = 2;
    meshes: Array<Mesh> = [];
    accessors: Array<Accessor> = [];
    bufferViews: Array<BufferView> = [];
    binChunk: ArrayBuffer = new ArrayBuffer(0);
    nodes: Array<GlbNode> = [];
    skins: Array<Skin> = [];
    animations: Array<Animation> = [];
    scene: i32 = -1;
}

export class ParseResult {
    success: bool = false;
    error: string = "";
    data: GLBData? = null;

    static fail(error: string): ParseResult {
        let result = new ParseResult();
        result.error = error;
        return result;
    }
}

export namespace GLBLoader {
    const GLB_MAGIC: u32 = 0x46546c67;
    const CHUNK_TYPE_JSON: u32 = 0x4e4f534a;
    const CHUNK_TYPE_BIN: u32 = 0x004e4942;

    const COMPONENT_BYTE: i32 = 5120;
    const COMPONENT_UNSIGNED_BYTE: i32 = 5121;
    const COMPONENT_SHORT: i32 = 5122;
    const COMPONENT_UNSIGNED_SHORT: i32 = 5123;
    const COMPONENT_UNSIGNED_INT: i32 = 5125;
    const COMPONENT_FLOAT: i32 = 5126;

    unsafe function readU32(data: ArrayBuffer, offset: i32): u32 {
        return load<u32>(changetype<usize>(data) + <usize>offset);
    }

    unsafe function readU16(data: ArrayBuffer, offset: i32): u32 {
        return <u32>load<u16>(changetype<usize>(data) + <usize>offset);
    }

    unsafe function readU8(data: ArrayBuffer, offset: i32): u32 {
        return <u32>load<u8>(changetype<usize>(data) + <usize>offset);
    }

    unsafe function readF32(data: ArrayBuffer, offset: i32): f32 {
        return load<f32>(changetype<usize>(data) + <usize>offset);
    }

    // The JSON chunk is ASCII, so bytes widen straight to UTF-16 units.
    unsafe function readString(data: ArrayBuffer, offset: i32, length: i32): string {
        let out = new Array<i32>(length);
        for (let i = 0; i < length; i++) {
            out[i] = <i32>load<u8>(changetype<usize>(data) + <usize>(offset + i));
        }
        return String.fromCharCodes(out);
    }

    export function getComponentSize(componentType: i32): i32 {
        if (componentType == COMPONENT_BYTE || componentType == COMPONENT_UNSIGNED_BYTE) {
            return 1;
        }
        if (componentType == COMPONENT_SHORT || componentType == COMPONENT_UNSIGNED_SHORT) {
            return 2;
        }
        if (componentType == COMPONENT_UNSIGNED_INT || componentType == COMPONENT_FLOAT) {
            return 4;
        }
        return 0;
    }

    export function getTypeComponents(accessorType: string): i32 {
        if (accessorType == "SCALAR") {
            return 1;
        }
        if (accessorType == "VEC2") {
            return 2;
        }
        if (accessorType == "VEC3") {
            return 3;
        }
        if (accessorType == "VEC4" || accessorType == "MAT2") {
            return 4;
        }
        if (accessorType == "MAT3") {
            return 9;
        }
        if (accessorType == "MAT4") {
            return 16;
        }
        return 0;
    }

    function parseMeshes(json: JsonValue, data: GLBData): void {
        let meshes = json.get("meshes");
        if (meshes == null) {
            return;
        }
        for (let m = 0; m < meshes.length; m++) {
            let meshJson = meshes.at(m);
            let mesh = new Mesh();
            mesh.name = meshJson.stringOr("name", "");
            let prims = meshJson.get("primitives");
            if (prims != null) {
                for (let p = 0; p < prims.length; p++) {
                    let primJson = prims.at(p);
                    let prim = new Primitive();
                    let attributes = primJson.get("attributes");
                    if (attributes != null) {
                        for (let a = 0; a < attributes.keys.length; a++) {
                            prim.attributeNames.push(attributes.keys[a]);
                            prim.attributeAccessors.push(<i32>attributes.values[a].num);
                        }
                    }
                    prim.indices = primJson.intOr("indices", -1);
                    prim.material = primJson.intOr("material", -1);
                    prim.mode = primJson.intOr("mode", 4);
                    mesh.primitives.push(prim);
                }
            }
            data.meshes.push(mesh);
        }
    }

    function parseAccessors(json: JsonValue, data: GLBData): void {
        let accessors = json.get("accessors");
        if (accessors == null) {
            return;
        }
        for (let i = 0; i < accessors.length; i++) {
            let accJson = accessors.at(i);
            let accessor = new Accessor();
            accessor.bufferView = accJson.intOr("bufferView", 0);
            accessor.byteOffset = accJson.intOr("byteOffset", 0);
            accessor.componentType = accJson.intOr("componentType", 0);
            let normalized = accJson.get("normalized");
            accessor.normalized = normalized != null && normalized.kind == JsonKind.boolean && normalized.flag;
            accessor.count = accJson.intOr("count", 0);
            accessor.accessorType = accJson.stringOr("type", "");
            data.accessors.push(accessor);
        }
    }

    function parseBufferViews(json: JsonValue, data: GLBData): void {
        let views = json.get("bufferViews");
        if (views == null) {
            return;
        }
        for (let i = 0; i < views.length; i++) {
            let viewJson = views.at(i);
            let view = new BufferView();
            view.byteOffset = viewJson.intOr("byteOffset", 0);
            view.byteLength = viewJson.intOr("byteLength", 0);
            view.byteStride = viewJson.intOr("byteStride", 0);
            view.target = viewJson.intOr("target", 0);
            data.bufferViews.push(view);
        }
    }

    function parseNodes(json: JsonValue, data: GLBData): void {
        let nodes = json.get("nodes");
        if (nodes == null) {
            return;
        }
        for (let i = 0; i < nodes.length; i++) {
            let nodeJson = nodes.at(i);
            let node = new GlbNode();
            node.name = nodeJson.stringOr("name", "");
            node.children = nodeJson.ints("children");
            node.mesh = nodeJson.intOr("mesh", -1);
            node.skin = nodeJson.intOr("skin", -1);
            node.translation = nodeJson.numbers("translation");
            node.rotation = nodeJson.numbers("rotation");
            node.scale = nodeJson.numbers("scale");
            node.matrix = nodeJson.numbers("matrix");
            data.nodes.push(node);
        }
    }

    function parseSkins(json: JsonValue, data: GLBData): void {
        let skins = json.get("skins");
        if (skins == null) {
            return;
        }
        for (let i = 0; i < skins.length; i++) {
            let skinJson = skins.at(i);
            let skin = new Skin();
            skin.name = skinJson.stringOr("name", "");
            let joints = skinJson.ints("joints");
            if (joints != null) {
                skin.joints = joints;
            }
            skin.inverseBindMatrices = skinJson.intOr("inverseBindMatrices", -1);
            skin.skeleton = skinJson.intOr("skeleton", -1);
            data.skins.push(skin);
        }
    }

    function parseAnimations(json: JsonValue, data: GLBData): void {
        let animations = json.get("animations");
        if (animations == null) {
            return;
        }
        for (let i = 0; i < animations.length; i++) {
            let animJson = animations.at(i);
            let anim = new Animation();
            anim.name = animJson.stringOr("name", "");
            let samplers = animJson.get("samplers");
            if (samplers != null) {
                for (let s = 0; s < samplers.length; s++) {
                    let samplerJson = samplers.at(s);
                    let sampler = new AnimationSampler();
                    sampler.input = samplerJson.intOr("input", 0);
                    sampler.output = samplerJson.intOr("output", 0);
                    sampler.interpolation = samplerJson.stringOr("interpolation", "LINEAR");
                    anim.samplers.push(sampler);
                }
            }
            let channels = animJson.get("channels");
            if (channels != null) {
                for (let c = 0; c < channels.length; c++) {
                    let channelJson = channels.at(c);
                    let channel = new AnimationChannel();
                    channel.sampler = channelJson.intOr("sampler", 0);
                    let target = channelJson.get("target");
                    if (target != null) {
                        channel.targetNode = target.intOr("node", -1);
                        channel.targetPath = target.stringOr("path", "");
                    }
                    anim.channels.push(channel);
                }
            }
            data.animations.push(anim);
        }
    }

    export unsafe function parse(data: ArrayBuffer): ParseResult {
        let dataLen = data.byteLength;
        if (dataLen < 12) {
            return ParseResult.fail("Failed to parse GLB header");
        }
        let magic = readU32(data, 0);
        let version = readU32(data, 4);
        if (magic != GLB_MAGIC) {
            return ParseResult.fail("Invalid GLB magic number");
        }
        if (version != 2) {
            return ParseResult.fail("Unsupported GLB version (only version 2 supported)");
        }
        let offset = 12;
        let json: JsonValue? = null;
        let glb = new GLBData();
        while (offset + 8 <= dataLen) {
            let chunkLength = <i32>readU32(data, offset);
            let chunkType = readU32(data, offset + 4);
            offset += 8;
            if (offset + chunkLength > dataLen) {
                return ParseResult.fail("Chunk extends beyond file");
            }
            if (chunkType == CHUNK_TYPE_JSON) {
                json = parseJSON(readString(data, offset, chunkLength));
                if (json == null) {
                    return ParseResult.fail("Failed to parse JSON chunk");
                }
            } else if (chunkType == CHUNK_TYPE_BIN) {
                let bin = new ArrayBuffer(chunkLength);
                memory.copy(
                    changetype<usize>(bin),
                    changetype<usize>(data) + <usize>offset,
                    <usize>chunkLength
                );
                glb.binChunk = bin;
            }
            offset += chunkLength;
        }
        if (json == null) {
            return ParseResult.fail("No JSON chunk found");
        }
        parseMeshes(json, glb);
        parseAccessors(json, glb);
        parseBufferViews(json, glb);
        parseNodes(json, glb);
        parseSkins(json, glb);
        parseAnimations(json, glb);
        glb.scene = json.intOr("scene", -1);
        let result = new ParseResult();
        result.success = true;
        result.data = glb;
        return result;
    }

    // One component as a float, whatever the accessor's storage.
    unsafe function readComponent(bin: ArrayBuffer, componentType: i32, offset: i32, normalized: bool): f32 {
        if (componentType == COMPONENT_FLOAT) {
            return readF32(bin, offset);
        }
        if (componentType == COMPONENT_UNSIGNED_SHORT) {
            let value = <f32>readU16(bin, offset);
            return normalized ? value / 65535 : value;
        }
        if (componentType == COMPONENT_UNSIGNED_INT) {
            return <f32>readU32(bin, offset);
        }
        if (componentType == COMPONENT_UNSIGNED_BYTE) {
            let value = <f32>readU8(bin, offset);
            return normalized ? value / 255 : value;
        }
        if (componentType == COMPONENT_SHORT) {
            let value = <f32>load<i16>(changetype<usize>(bin) + <usize>offset);
            return normalized ? Mathf.max(value / 32767, -1) : value;
        }
        if (componentType == COMPONENT_BYTE) {
            let value = <f32>load<i8>(changetype<usize>(bin) + <usize>offset);
            return normalized ? Mathf.max(value / 127, -1) : value;
        }
        return 0;
    }

    // Accessor and view offsets come from the file, so every read is fenced
    // against the binary chunk before the first load.
    function checkAccessorBounds(glb: GLBData, accessorIndex: i32, base: i32, stride: i32, count: i32): void {
        let end = <i64>base + <i64>count * <i64>stride;
        if (base < 0 || stride <= 0 || count < 0 || end > <i64>glb.binChunk.byteLength) {
            throw new Error("accessor " + accessorIndex.toString() + " reads past the binary chunk");
        }
    }

    export unsafe function readAccessorFloats(glb: GLBData, accessorIndex: i32): Array<f32>? {
        if (accessorIndex < 0 || accessorIndex >= glb.accessors.length) {
            return null;
        }
        let accessor = glb.accessors[accessorIndex];
        if (accessor.bufferView < 0 || accessor.bufferView >= glb.bufferViews.length) {
            return null;
        }
        let view = glb.bufferViews[accessor.bufferView];
        let componentSize = getComponentSize(accessor.componentType);
        let componentCount = getTypeComponents(accessor.accessorType);
        if (componentSize == 0 || componentCount == 0) {
            return null;
        }
        let stride = view.byteStride != 0 ? view.byteStride : componentSize * componentCount;
        let base = view.byteOffset + accessor.byteOffset;
        checkAccessorBounds(glb, accessorIndex, base, stride, accessor.count);
        let result = new Array<f32>(accessor.count * componentCount);
        let bin = glb.binChunk;
        for (let i = 0; i < accessor.count; i++) {
            let element = base + i * stride;
            for (let j = 0; j < componentCount; j++) {
                result[i * componentCount + j] =
                    readComponent(bin, accessor.componentType, element + j * componentSize, accessor.normalized);
            }
        }
        return result;
    }

    unsafe function readIntegers(glb: GLBData, accessorIndex: i32, packed: bool): Array<i32>? {
        if (accessorIndex < 0 || accessorIndex >= glb.accessors.length) {
            return null;
        }
        let accessor = glb.accessors[accessorIndex];
        if (accessor.bufferView < 0 || accessor.bufferView >= glb.bufferViews.length) {
            return null;
        }
        let view = glb.bufferViews[accessor.bufferView];
        let componentSize = getComponentSize(accessor.componentType);
        let componentCount = packed ? 1 : getTypeComponents(accessor.accessorType);
        if (componentSize == 0 || componentCount == 0) {
            return null;
        }
        let stride = view.byteStride != 0 && !packed ? view.byteStride : componentSize * componentCount;
        let base = view.byteOffset + accessor.byteOffset;
        checkAccessorBounds(glb, accessorIndex, base, stride, accessor.count);
        let result = new Array<i32>(accessor.count * componentCount);
        let bin = glb.binChunk;
        for (let i = 0; i < accessor.count; i++) {
            let element = base + i * stride;
            for (let j = 0; j < componentCount; j++) {
                let at = element + j * componentSize;
                let value: i32 = 0;
                if (accessor.componentType == COMPONENT_UNSIGNED_SHORT) {
                    value = <i32>readU16(bin, at);
                } else if (accessor.componentType == COMPONENT_UNSIGNED_INT) {
                    value = <i32>readU32(bin, at);
                } else if (accessor.componentType == COMPONENT_UNSIGNED_BYTE) {
                    value = <i32>readU8(bin, at);
                }
                result[i * componentCount + j] = value;
            }
        }
        return result;
    }

    export unsafe function readIndices(glb: GLBData, accessorIndex: i32): Array<i32>? {
        return readIntegers(glb, accessorIndex, true);
    }

    // Joint indices, four per vertex.
    export unsafe function readJoints(glb: GLBData, accessorIndex: i32): Array<i32>? {
        return readIntegers(glb, accessorIndex, false);
    }

    // Sixteen floats per matrix, column major.
    export unsafe function readMat4Array(glb: GLBData, accessorIndex: i32): Array<f32>? {
        return readAccessorFloats(glb, accessorIndex);
    }

    export unsafe function getAnimationDuration(glb: GLBData, animIndex: i32): f32 {
        if (animIndex < 0 || animIndex >= glb.animations.length) {
            return 0;
        }
        let anim = glb.animations[animIndex];
        let maxTime: f32 = 0;
        for (let i = 0; i < anim.samplers.length; i++) {
            let times = readAccessorFloats(glb, anim.samplers[i].input);
            if (times != null && times.length > 0) {
                let last = times[times.length - 1];
                if (last > maxTime) {
                    maxTime = last;
                }
            }
        }
        return maxTime;
    }
}
