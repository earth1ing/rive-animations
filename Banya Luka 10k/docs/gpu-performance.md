# GPU and script performance

What made scripted 3D scenes fast or slow when measured on Rive's web runtime
against matched three.js scenes: from spinning cubes and skinned characters
to large textured scenes and a city with live artboards. The percentages show
the size of each effect; your scene will differ.

The order is by how much each one cost.

## Keep `discard` out of opaque pipelines

A `discard` anywhere in a fragment shader changes how the whole pipeline
runs, even on pixels that never reach it. Tile-based GPUs (Apple's, and most
mobile ones) stop rejecting hidden pixels early for that pipeline. Through
WebGPU, the shader compiler also turns `discard` into a flag checked at the
end, so a discarded pixel still runs the whole shader.

In a city scene whose lit shader discarded for a reflection clip and a
dissolve effect, used by a handful of objects, moving both out of the main
entry point cut WebGPU frame time by about 40%. WebGL2 did not change.
Skipping the dissolved objects while leaving `discard` in every pipeline
saved nothing: having a `discard` in the pipeline is the cost, not the pixels
it throws away.

Split the shader into an entry point that never discards and one that does,
and pick the pipeline per object:

```wgsl
@fragment
fn fs_main(i: VOut, @builtin(front_facing) ff: bool) -> @location(0) vec4f {
    return material(i, ff);
}

@fragment
fn fs_clip(i: VOut, @builtin(front_facing) ff: bool) -> @location(0) vec4f {
    if (u.dissolve > 0.0 && noise(i.clip.xy) < u.dissolve) { discard; }
    return material(i, ff);
}

fn material(i: VOut, ff: bool) -> vec4f {
    // the shading, with no discard
}
```

- Build two pipelines from the same module, `"fs_main"` and `"fs_clip"`, and
  bind `fs_clip` only for the pass or the objects that need it.
- Skip an object that is fully hidden instead of drawing it and discarding
  every pixel. A dissolve at 1 is a draw call that produces nothing.
- An alpha-cutout material (foliage, fences) needs `discard`; give it its own
  pipeline and draw it after the opaque ones.

## Shade each pixel once: a depth pre-pass

When the expensive shader covers the screen several times over, draw the big
occluders first with a cheap pipeline that writes only depth, then draw them
again with the real shader. Depth testing then lets only the nearest surface
run the expensive shader. In a city of overlapping facades, the pre-pass
halved GPU time.

The pre-pass pipeline uses the same vertex shader and a fragment shader that
returns a constant, with color writes off or a blend that keeps the
destination. Set the depth state on both pipelines, because a new one tests
nothing and writes nothing:

- **Pre-pass:** writes depth, comparing `lessEqual` (`'less-equal'` in Luau).
- **Main pass:** compares `lessEqual` too, never `less`, which rejects the
  very surfaces the pre-pass wrote at the same depth.
- **One render pass for both.** If they are separate passes, keep the depth
  between them: `depthStoreOp` `store` on the first and `depthLoadOp`
  `load` on the second.

It only helps when the main pipeline does not `discard`.

## The cost of a draw

The usual per-object pattern is `setBindGroup` with a dynamic offset into one
large uniform buffer, then `drawIndexed`. On WebGL2, about two thirds of each
draw's cost is in Chrome's GPU process, because each dynamic offset becomes a
uniform-range bind there. three.js spends most of its per-draw cost on the
page instead.

To spend fewer draws:

- **Instance anything repeated.** Put per-copy data in a vertex buffer with
  `stepMode` `instance` and draw every copy in one call with
  `instanceCount`. Thousands of cars or hundreds of thousands of small boxes
  are one draw each this way.
- **Merge static geometry.** One vertex buffer and one index buffer for the
  whole scene, each object drawing its own index range, made a large scene
  about 15% faster in Rive and 20% in three.js with the same number of draws.
  On a small scene it made little difference to Rive.
- **Point each draw at its own vertices.** `baseVertex` only works when the
  GPU features report `drawBaseInstance`, and WebGL2 does not. Rebase
  instead: add each object's first vertex to its indices once, offline or at
  load, and bind the vertex buffer once for the whole scene, with 32-bit
  indices once the scene passes 65,535 vertices. In AnimaScript you can
  instead bind the shared buffer at each object's byte offset with
  `setVertexBuffer(slot, buffer, offset)`, but that is a vertex buffer bind
  per draw, which WebGL2 pays for on every one. Luau's `setVertexBuffer`
  takes no offset, so there rebasing is the only way. The gains above were
  measured with rebased indices.

## Textures: let the runtime decode them

Put each texture in the project as an image file and ask for it with
`context.image(name)`. The runtime decodes it and the shader samples it
through `image.view()`. The pixels never pass through script memory, and the
runtime uploads them itself. Decoding a blob with `decodeImage` and
building mips in the script costs script memory and main-thread time for
every texture.

On the web an image decodes after `init` runs, so check `image.width > 0`
each frame and take the view once it is. Count down a frame budget so an
image that never decodes falls back to a plain texture instead of keeping the
scene from ever becoming ready.

## Bulk data: copy once, slice nothing

`context.blob(name)` copies the whole asset into script memory; in Luau,
reading `blob.data` does. Script
memory, like the runtime's own heap, never shrinks, so the largest it ever
gets is what the page keeps. A large geometry blob cost its own size again in
script memory, and the runtime heap grew by nearly twice that while its
buffers were staged for upload.

- **Fill GPU buffers straight from the blob's bytes.** In AnimaScript,
  `buffer.update(dstOffset, data, byteCount, srcOffset)` takes a source
  offset, and in Luau `GPUBuffer:write` does too. Never slice the blob into
  a new `ArrayBuffer` or `buffer` per object.
- **Make static buffers immutable.** Pass the data at creation with
  `immutable` set. The buffer is GPU-only from then on and cannot be written
  again.
- **Pack the blob in its final GPU layout.** Interleaved vertices, indices
  already rebased, everything aligned the way the buffers want it. Whatever
  the script has to rewrite per element at load is time and memory spent
  on every load.
- **Copy the big blob once.** In AnimaScript each `context.blob` call is a
  fresh copy. In Luau `context:blob` returns the asset without copying it,
  but every read of `blob.data` copies the whole asset, so read it once and
  keep the buffer.

## Luau or AnimaScript

The same scenes written in both languages, on the same web runtime, render
the same frames and split cleanly by where the work happens.

- **GPU-bound work costs the same.** A textured scene of about a hundred
  draws ran within 3% in both. The language only matters for what the
  script itself computes.
- **Per-frame maths is where Luau falls behind.** Sampling an animation and
  rebuilding a skeleton for a crowd of characters every frame took about 30
  times as long in Luau, which turned a frame that fit easily into one seven
  times longer.
- **Setup costs more too.** Parsing a scene file and building its buffers in
  `init` took about 12 times as long in Luau, which pushed the first frame
  back by more than half.
- **Each draw's script work costs about three times as much.** Most of a
  draw's cost is outside the script either way, so this adds up to about 17%
  more per draw in total.
- **An empty frame costs about a fifth more.** That is a fixed cost of the
  Luau runtime, not of how the script is written: reusing descriptor tables
  instead of building them each frame changed nothing.

Write scenes with heavy per-frame loops, large crowds or big setup work in
AnimaScript. Where Luau is the right choice for other reasons, move the work
the script repeats out of it: precompute in the packer, sample animation less
often than every frame, or do the per-element maths in a shader.

## Heavy work in `init` can be cut off

Native runtimes stop any single script call that runs longer than 200 ms by
default, `init` included. The browser has no such limit for scripts compiled
to wasm. An `init` that loops over millions of indices can run fine on the
web and fail natively with `script error: execution exceeded 200 millisecond
timeout`. Setup in Luau runs many times longer than the same setup in
AnimaScript, so it reaches the limit first. Do that work in the packer, or
spread it over the first frames of `advance`.

## Live artboards inside a 3D scene

Drawing Rive artboards into GPU canvases, for screens, signs or a HUD, has a
cost of its own on top of the 3D. In a city scene, over a dozen live artboards
added about 80% to the frame time, 60% of that on the page and the rest on
the GPU.

- **Every canvas is its own flush.** Fewer, larger canvases cost less than
  many small ones, and a canvas whose artboard did not change does not need
  redrawing.
- **Stack layouts are not free.** A stack is laid out as a one-cell grid,
  and about twenty of them laid out again on every frame were most of those
  artboards' update time. Where children only need to sit on top of each
  other, a plain group costs nothing to lay out.

## WebGPU rejects what Metal and WebGL allow

These do not cost time; they cost the frame. WebGPU drops a frame that breaks
its rules, and the native preview and WebGL2 run the same code without
complaint. [gotchas.md](gotchas.md#a-shader-that-renders-on-metal-can-fail-on-the-web)
lists what the build log reports. Two that it cannot see:

- **A texture cannot be read in the pass that writes it.** Binding a depth
  texture to a shader in the same pass that renders into it, even through a
  bind group that only clears or never samples it, invalidates the frame.
  Use a separate bind group without that texture for the pass that writes it.
- **`maxAnisotropy` above 1 needs linear filtering.** A sampler with any
  `nearest` filter, mips included, must keep `maxAnisotropy` at 1.

## Measuring

- Measure published builds in the browser, not the preview. The preview
  runs the native runtime, whose costs differ.
- Time a frame to the GPU's finish, not to the end of submission: most of
  the cost of a heavy scene is in the GPU process and on the GPU itself.
- The first run after a browser launches can be about 25% faster than later
  ones. Interleave what you compare, repeat it, and drop that first round.
