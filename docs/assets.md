# Assets

An asset is anything that comes from a file rather than from markup: images,
fonts, audio, scripts, shaders, arbitrary data. This page is the model — the
per-type detail lives with the feature that uses it.

## Every file in the project is an asset

You do not register files. The build scans the project directory and classifies
each one by extension:

| Extension | Becomes | Declared in RML? |
|---|---|---|
| `.luau` | script | **no** — a `ScriptAsset` is created for you |
| `.wgsl` | shader | **no** — a `ShaderAsset` is created for you |
| `.png` `.jpg` `.jpeg` `.webp` | image | yes, `<ImageAsset file="…">` |
| `.rml` | markup | n/a |
| **anything else** | **blob** | yes, `<BlobAsset file="…">` |

`rive.yaml`, `.riv`, `.rev` and `.log` are skipped.

Two things follow that are worth holding on to. **Scripts and shaders need no
markup at all** — dropping a `.luau` or `.wgsl` file in is the whole step.
And **there is no unrecognised-file error**: a `.ttf`, a `.json`, a `.csv` and a
typo'd filename all land in the blob bucket without complaint.

## Three ways an asset gets its bytes

**Scanned.** Scripts and shaders, above. The file is compiled and embedded.

**By `file=`.** Everything else. The path is relative to the project directory
and the bytes are embedded into the built file. It may leave the project
(`file="../../assets/fonts/Inter.ttf"` for a folder several projects share),
with one cost: the watcher only sees the project directory, so a change to a
shared file needs a manual rebuild. A file that is missing, empty, or an
unfetched Git LFS pointer is a build error, not an asset with no bytes.

> `file` is an RML authoring attribute rather than a core property, so
> **`rive schema` never lists it** — on `FontAsset`, `ImageAsset` or any other.
> It is valid on all of them regardless. This is the one place where "look the
> name up rather than guessing" does not work.

```xml
<ImageAsset file="logo.png" name="logo" id="0:60"/>
```

Because they are embedded, the `.riv` is self-contained — and building it
**redistributes** whatever you embed, which matters for fonts. To keep the
bytes out of the `.riv`, see [referenced and hosted
assets](#referenced-and-hosted-assets) below.

**Not at all.** Omit `file` and the asset ships as a named, contentless
reference for the host application to satisfy at load time through its
runtime's asset-handler API. Nothing in this toolchain can render that, so the
preview shows nothing. See [text.md](text.md#shipping-without-embedding).

## Referenced and hosted assets

`exportTypeValue` on an `ImageAsset`, `FontAsset`, `AudioAsset` or `BlobAsset`
picks where the runtime gets the bytes. The default, `embedded`, is everything
above. Scripts and shaders ignore the property and always embed. A PSD layer is
an image, so the property on a `LayerImageAsset` applies to its decoded PNG.

**`referenced`.** The `.riv` holds the asset record only. The build writes the
bytes beside it in the output directory, under the name the runtime will look
for: the asset name minus its extension, a dash, the `assetId`, and a fixed
per-type extension (`png`, `ttf`, `wav`, `blob`).

```xml
<ImageAsset file="logo.png" exportTypeValue="referenced" name="logo" id="0:60"/>
```

That builds `build/<project>.riv` and `build/logo-<assetId>.png`. The bytes
come from `file`, from a `FileAssetContents` child, or for a PSD layer from
the PNG decoded out of the owning `LayeredAsset`'s file. On a file-backed
asset a child wins and the `file` is then never read; a PSD layer always
decodes from the PSD, child or not. Without a child, a missing or empty `file`
is a build error, as for any asset, and so is an asset with no source at all,
since the `.riv` would point at a file nothing writes. Leave `assetId`
alone and the build picks one no other asset uses. Set it by hand and it must
be unique; a referenced asset sharing an `assetId` with any other exported
asset is a build error, because the importer would renumber it away from its
sidecar. A name containing a path separator or a colon is an error, because
the runtime resolves it beside the `.riv` and a colon is a Windows drive
prefix.

**`hosted`.** The bytes live on the CDN and the `.riv` never carries them.
A `file` on a hosted asset without a `FileAssetContents` child is still read
and checked, and a hosted PSD layer still decodes its PSD, so omit `file`
where nothing else needs it. The asset
needs a 16-byte `cdnUuid` (base64 in RML) or the build fails. The `.riv` only
carries the uuid on a hosted asset, so a stale one on an embedded or
referenced asset is dropped rather than loaded from the wrong place; the
`--rev` export keeps it as authored.

```xml
<ImageAsset exportTypeValue="hosted" cdnUuid="AAECAwQFBgcICQoLDA0ODw==" name="pic" id="0:60"/>
```

The same asset types can also be kept out of the build entirely:
`exportFlags="2"` (export prevented) drops the asset and its bytes from the
`.riv`, and anything that referenced it renders nothing.

The preview loads referenced sidecars from the output directory, so they
render. It does not fetch from the CDN, so a hosted asset shows nothing here
and only works in a runtime that does.

## What references what

Assets are root elements. Something in the scene names them:

| Asset | Referenced by |
|---|---|
| `ImageAsset` | `Image.assetId` — see [drawing.md](drawing.md#images) |
| `FontAsset` | `TextStylePaint.fontAssetId` — see [text.md](text.md#fonts) |
| `AudioAsset` | `AudioEvent.assetId` |
| `ScriptAsset` | `Scripted*.scriptAssetId`, or nothing in a script-only project |
| `ShaderAsset` | **nothing in RML** — reached from Luau by name |
| `BlobAsset` | **nothing in RML** — reached from Luau by name |

## How an image is sampled

Three properties on `ImageAsset` control sampling, and they ship with the file:

| Property | Values |
|---|---|
| `samplerFilter` | `0` bilinear *(default)*, `1` nearest |
| `samplerWrapX` | `0` clamp *(default)*, `1` repeat, `2` mirror |
| `samplerWrapY` | same as `samplerWrapX` |

They are raw numbers — the names above are not accepted.

```xml
<ImageAsset file="tiles.png" samplerFilter="1" samplerWrapX="1" samplerWrapY="1"
            name="tiles" id="0:60"/>
```

`samplerFilter="1"` is what keeps pixel art crisp; the default bilinear blurs it
at any scale other than 1:1. The wrap modes matter when something samples
outside the image — a tiling texture wants `repeat`, and `clamp` smears the edge
pixel instead.

The other properties you will see on an `ImageAsset` — `format`, `quality`,
`mips`, `astcBlockSize` — are editor and backend encoding settings, marked
editor-only and stripped on export. Setting them here does nothing.

## Shaders

A `.wgsl` file is compiled and registered under its name. No RML property points
at a shader; a script fetches one from its `Context`:

```luau
local shader = context:shader('wave')
```

The name is the asset name — the filename without its extension, namespaced by
folder. **The lookup is by string and unvalidated**, so a typo returns `nil`
rather than failing the build. Check the result before using it.

From there the shader goes into a `GPUPipeline`; the drawing side is in
[luau/api/gpu.md](luau/api/gpu.md).

## Blobs

Any file the build does not recognise becomes a blob, which is how arbitrary
data ships alongside a scene — a JSON table, a binary lookup, level data:

```luau
local levels = context:blob('levels')
```

Same name-based, unvalidated lookup as shaders. `Blob.data` gives you a
`buffer`.

If you meant a file to be an image or a font and mistyped the extension, it
becomes a blob silently and the thing that wanted it renders nothing.

## Audio

Only the previewer window plays sound. `--screenshot` runs audio silently, and
`--test` cannot exercise it: `Audio.play()` returns `nil` there. An
`AudioEvent` fired from a state machine logs a line (`sound ding: triggered`,
or why it did not play), so the wiring is checkable headless; whether the right
sound plays is a listening test in the previewer. Pausing the previewer mutes
sounds started by a script.

An `AudioAsset` plays when an `AudioEvent` fires, so audio is driven from a
state machine like any other event:

```xml
<AudioAsset file="click.wav" name="click" id="0:70"/>
```

`volume` on the asset scales every instance. `AudioAssetClip` is the trimmed
form. Scripts can reach audio directly with `context:audio(name)`.

WAV, MP3 and FLAC all decode. The format is detected from the bytes, not the
extension. An `AudioAsset` holding Ogg, AIFF, MP4/M4A, Matroska/WebM or WMA
fails the build:

```
scene.rml:9 coin: file "coin.ogg" is Ogg, which cannot be decoded; convert it to WAV, MP3 or FLAC
```

A `.riv` build never reads a hosted asset's bytes, so it does not check them.

An audio file with no `AudioAsset` declaring it becomes a blob without any
warning, so `context:audio` finds nothing.

## Organising them

`AssetGroup` is an asset-panel folder, and `folderPath` on a script or shader
sets both its folder and the namespace its name is registered under. Neither
affects the built output — they are for keeping a large project navigable in
the editor.

`folderPath` does change the name a script is imported by: with
`folderPath="widgets"`, a script named `button` is `require('widgets/button')`.
A script that exists to be imported rather than to implement a protocol should
also carry `isModule="true"`, and must be declared **before** anything that
requires it — see [luau/protocols.md](luau/protocols.md#modules).

## PSD layers

A `LayeredAsset` names a PSD file and holds one `LayerImageAsset` per layer;
`Image` drawables reference the layers by id. The build decodes each layer
straight from the PSD in the project directory and bakes it as a plain
image, the way the editor exports them. 8-bit RGB documents with raw or RLE
channels — what design tools write — decode; anything else logs which layers
will not render and the build continues. A layer is matched by its authored
`layer` number (one past the PSD's bottom-first record index) and confirmed
by name, so a reordered PSD still resolves by layer name.

## Not supported here

Two asset types exist in the format but are marked editor-only and are
**stripped on export**, so authoring them from RML produces nothing:

| Type | What it is | Do instead |
|---|---|---|
| `SVGAsset` | an imported SVG | convert to shapes and author them as RML |
| `LottieAsset` | an imported Lottie | as above |

SVG and Lottie are converted to real Rive objects on import — the asset only
retains the source for re-importing. That path does not exist in this tool, so
the conversion has to happen before you get here.

## Checking your work

A missing `file` fails the build, and an `assetId` naming an undeclared id does
too, so neither needs a check of its own. What is left is an asset a script
reaches **by name** (`context:image('backdrop')`): nothing connects that string
to a file, so list what the project actually carries and compare:

```bash
rive inspect . --json | jq -c '[..|objects|select((.type//"")|endswith("Asset"))|{type,name}]'
```
