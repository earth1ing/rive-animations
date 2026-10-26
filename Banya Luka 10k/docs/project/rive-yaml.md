# Projects and `rive.yaml`

A project is a directory containing a `rive.yaml`. Everything else in it is
bundled by file extension:

| Extension | Becomes |
|---|---|
| `.luau` | scripts — protocol scripts and importable modules |
| `.as` | AnimaScript, the same; needs `scripting: wasm` |
| `.wgsl` | shaders, compiled to RSTB |
| `.rml` | the scene, in as many files as you like, compiled as one document |
| `.png` `.jpg` `.jpeg` `.webp` | image assets |
| anything else | a blob asset, findable by name from scripts |

**The table is how sources are *discovered*, not a promise that everything in
the directory ends up in the `.riv`.** Assets are embedded when something
references them — a `file=` in the RML, or a `context:image` / blob lookup by
name from a script. A stray `notes.txt`, a font nothing uses, or the generator
script that wrote your scene adds nothing to the output, so `exclude` is for
keeping the *scan* tidy (and for keeping a second `.rml` from being picked up),
not for keeping weight out of the file.

Only `name` is required:

```yaml
name: myproject
```

`rive create <dir>` writes a `rive.yaml` with `name` taken from the directory
and log paths under `build/`, plus a `scene.rml` holding an empty artboard,
timeline and state machine, `AGENTS.md`, a `CLAUDE.md` that imports it, and a
`.gitignore` for `build/`.
Existing files are left alone.

## Starting from an editor file

```bash
rive create demo --from-rev=demo_file.rev    # or omit demo: the .rev's name is used
rive demo
```

`--from-rev` converts an editor `.rev` into a project: `scene.rml` with every
script, shader and asset written as a file and referenced with `file=`, then
the usual scaffold. Files land where the Assets panel had them — the folder
tree in the editor becomes the directory tree on disk:

    Assets panel                demo/
      main                        rive.yaml
      ui/                         scene.rml
        button                    main.luau
      images/                     ui/button.luau
        logo                      images/logo.png
      fonts/                      fonts/Inter.ttf
        Inter

Scripts keep working because a script's path *is* its module path: the editor's
`require('ui/button')` resolves to `ui/button.luau`. The directory must be empty
or new — the conversion writes a tree it cannot check file by file, so it never
merges into one.

The result is an ordinary project: `.luau` and `.wgsl` compile,
`png`/`jpg`/`jpeg`/`webp` are images, and fonts, svg, audio and other binaries
are blobs — still referenced correctly through `file=`, just not typed by the
scanner. Editor-only state (collaboration cursors, diff history) is dropped;
hosted fonts with no embedded bytes stay unresolved, as in any hand-written rml.

`--from-remote-file` runs the same conversion on a file in your Rive account
rather than a `.rev` on disk, and records it under `push:` so `rive push`
sends your edits back. With no value it lists your projects and files to pick
from; `--from-remote-file=<fileId>` goes straight to one. See
[push.md](../push.md).

## Full shape

```yaml
name: myproject
main: main

artboard:
  width: 800
  height: 600
  background: "#1D1D1D"      # quote it -- a bare # starts a YAML comment

artboards:
  main:
    width: 1920
    height: 1080

exclude:
  - docs

excludeFromRev:
  scripts:
    - "*_test"
  artboards:
    - tests/*
  assets:
    - raw_*
  contents:
    - logo

libraries:                   # written by the tool, see Libraries below
  "palette":
    fileId: 4002
    libraryId: 42
    version: 1
    override: ../palette     # optional, and the only part you write

revFlavor: editable          # or "library"

push:
  projectId: 5336
  fileId: 24227

pages:
  teamId: 77
  name: "my-scene"

window:                      # icon on every desktop, see below; the rest is macOS only
  icon:                      # the process icon, or false for the stock one
    color: "#2b6b5e"         # behind the R; default black
    label: MT                # up to three characters; default the name's initials
    artboard: Icon           # or draw this artboard of the project instead
  titleBar: integrated       # or "standard" (default)
  controls:                  # traffic-light position, points from the top-left
    x: 16
    y: 19
  dragHeight: 52             # the strip a press drags the window from

cursor:
  property: cursor

output:
  dir: build

logs:
  file: build/rive.log
  problems: build/problems.log
```

## Keys

**`name`** — required. Also the name other projects use to import this one.

**`main`** — which artboard is the file's default, by name. Without it, the
first artboard declared wins in an RML project, and the first layout script
alphabetically in a script-only one. A name that matches no artboard fails the
build.

**`scripting`** — `bytecode` (default) or `wasm`. `wasm` is required for
`.as` files; see [../animascript/protocols.md](../animascript/protocols.md).

**`wasmSimd`** — which WebAssembly SIMD the AnimaScript module may use: `on`
(default) for fixed-width SIMD, `off` for a scalar module that also runs in
browsers without wasm SIMD (Safari before 16.4), or `relaxed` to also fuse
multiply-adds, whose results can differ by platform; natively those need the
AOT lane, and browsers need relaxed SIMD support. A script that uses no SIMD bakes the same either way. The editor
keeps the same setting on the file's Backboard.

**`debugLevel`**, **`optimizationLevel`** — the editor's publish levels for
scripts, `none`, `medium` or `max`; defaults `none` and `max`.

**`shaderOutputs`** — the shader backends compiled on publish, a list from
`msl`, `glsl`, `wgsl`, `hlsl`, `spirv`; default all of them. These three and
`main` are what the editor keeps on the file's Backboard, which a fragment
never declares; `create --from-rev` writes them here from a rev.

**`artboard`** — default size and background for generated artboards. Applies
only when there is no `.rml`; RML artboards carry their own dimensions.
`background` must be quoted.

**`artboards`** — per-artboard overrides, keyed by name.

**`exclude`** — paths not to bundle at all.

**`excludeFromRev`** — drops matching things from the exported `.rev` only. The
`.riv` and the live window always contain everything. Four categories:

- `scripts` — by module path, Luau and WGSL
- `artboards` — by name
- `assets` — by name
- `contents` — asset *bytes*, keeping the asset referenced but unembedded

Patterns support `*` (any run of characters, including `/`) and `?` (one
character). Excluding a layout script also drops its generated artboard.

**`libraries`** — the libraries published in Rive that this project's scene
imports directly. The tool writes it; `override` on an entry is the one part
that is yours. See [Libraries](#libraries) below.

**`revFlavor`** — `editable` (default) or `library`. Controls whether the
exported `.rev` opens as a normal editor file or as a library others import.

**`push`** — the Rive file `rive push` updates. Written back automatically by
the first push (`projectId` picks where the file is created, `fileId` binds
later pushes to it), and by `rive create --from-remote-file`, which binds the
project to the file it was made from; edit or remove it to retarget.

**`pages`** — the hosted page `rive <dir> --publish=web` replaces. Written
back by the first publish and not touched after: `teamId` is the team that
owns the page, `name` the slug it answers to. Edit `name` to publish to a
different page; remove the block to be asked again. See
[publish-web.md](../publish-web.md).

**`window`** — how the live window frames the scene. `icon` reaches every
desktop; the rest is macOS only, and every other desktop keeps its ordinary
frame. `--screenshot` and the other headless runs never open a
window and ignore the block entirely.

- `icon` — the process icon while the project is open, in the Dock and
  Cmd-Tab on macOS and the taskbar and window switcher on Windows and
  Linux, so several previews tell apart. By default the R carries the
  project name's initials in a badge: the first letter of the first two
  words, or the first two letters of a single word. `label` sets up to three
  characters of `A-Z` and `0-9` instead and `color` a hex colour behind the
  R. `icon: false` keeps the stock icon. `artboard` names an artboard of the
  project to draw as the icon instead, clipped to the icon shape and redrawn
  on every build, with its default state machine and view model instance
  advanced once. The window title leads with the name either way; the
  Dock's hover label and the Cmd-Tab caption are the executable's file
  name, which macOS never lets a process change. On Wayland only
  compositors with `xdg-toplevel-icon` show the icon; the rest keep the app
  id's.
- `titleBar` — macOS only. `standard` (default) keeps the usual title bar
  strip above the scene. `integrated` draws the scene across the whole
  window, under the native close, minimize and zoom controls, with no strip
  of its own: the artboard is laid out to the full window height and the
  title text is hidden. The controls stay native, so their hover,
  accessibility and full-screen behaviour is the system's. Edits to the
  block apply to the running window on the next build, like any other edit.
  These settings apply to standalone preview windows. On macOS, `rive editor`
  always uses its own integrated header (controls at `16, 18`, drag height
  `52`), including detached pane windows; the preview stays inside its pane.
- `controls` — where the native controls sit, `x` and `y` in points from the
  window's top-left corner. Only read with `titleBar: integrated`; leave the
  block out for the stock placement. A `y` deeper than the stock strip grows
  the strip, so a 52pt header centres its controls with `y: 19`.
- `dragHeight` — the strip along the top, in points, where a press on nothing
  interactive drags the window. A listener target, a text input or a scripted
  layout with pointer handlers keeps its presses. Left out, the strip is the
  height of the native controls; zero turns dragging off.

The scene learns where the chrome is through two numbers written into the
artboard's bound view model instance when it declares them: `titleBarHeight`
and `titleBarControlsWidth`, in points, both zero in full screen. Bind a
header's height and a spacer's width to them. The
[integrated_titlebar](../../samples/integrated_titlebar) sample is the
worked example: `rive "$(rive samples --path)/integrated_titlebar"`.

**`cursor.property`** — opt in to native cursors: the string or enum
property (a path on the artboard's bound view model, as `--data` spells one)
the scene writes cursor names into. The previewer shows what it names; without the key the OS cursor is never touched. See
[../cursor.md](../cursor.md).

**`output.dir`** — where the `.riv` is written. Defaults to `build`.

**`logs.file`** — append-only interleave of compiler problems, script `print`
output and system messages.

**`logs.problems`** — rewritten atomically per build with a generation header,
so it always reflects exactly one build. This is the file to read when
scripting around the tool.

## Libraries

A library is content published in the Rive editor that other files import:
artboards, state machines, view models, enums, scripts and shaders. A project
made from a file that imports one arrives with everything it needs, and
`rive pull` keeps it current.

### The `libraries` block

```yaml
libraries:
  "palette":
    fileId: 4002
    libraryId: 42
    version: 1
```

Only the libraries this project's scene imports **directly**. A library that
another library imports is not listed: it arrives through that library, and
the project never names it.

The block mirrors what the remote file currently depends on. `rive create
--from-remote-file` writes it, and every `rive pull` rewrites it: entries
appear as the file gains dependencies and disappear as it loses them, and
`version` follows the newest version the file reaches for.

**Do not hand-edit the three fields.** `fileId`, `libraryId` and `version` are
the tool's, and the next pull overwrites whatever is there. Comments and any
other key inside an entry survive a rewrite untouched.

The key is the library's name, lowercased with anything outside
`[a-z0-9_-.]` replaced by `_`, quoted so a library called `123` stays a name
rather than becoming a number. It is also the label a `require` writes after
`lib:`:

```luau
local ink = require('lib:palette/ink')
```

Two libraries whose names reduce to the same key get `#` and the library id
appended to tell them apart, as in `"face_mesh#42"`. The require label follows
the key.

Changing which libraries a file imports, or which version it uses, is editor
work today. A later CLI will do it from here: updating a dependency to a newer
published version, adding one, and publishing a new version of a project whose
own file is a library.

### The `.libraries` folder

A project that imports libraries holds a `.libraries/` folder beside its
markup. `create --from-remote-file` and `pull` download into it every library
the file reaches, directly and indirectly, and the build reads it to assemble
the `.riv` (or the `.rev` with `--rev`). Nothing at play time looks at it: by
then the library content is inside the file.

It is committed with the project rather than ignored, so a teammate who clones
can build without pulling, and without needing access to the libraries
themselves.

**Treat it as read-only.** Edits inside it are picked up by a running build,
which makes it tempting, but they are lost the moment that content is fetched
again, with nothing reporting it. The folder is derived and disposable:
deleting it costs one `rive pull`. Its contents are described in
[libraries-folder.md](libraries-folder.md) as background, not as something to
maintain.

### Libraries the editor bundles

The editor's TextInput component does not come from a library published in
Rive. The editor ships that library inside itself and marks what it places
with reserved ids: `libraryId="592"` and `assetId="1"`, with no
`libraryVersionId`. The backend has no snapshot by that id, so there is
nothing for `rive pull` to download.

The CLI carries the same markup the editor instances and resolves those
assets from it. Such a library never appears in `.libraries/` or the lock,
and needs no `libraries` entry in `rive.yaml`. A folder under `.libraries/`
named for the same snapshot, `@1`, still wins, for checking a change to the
component before the editor ships it.

### Working on a library locally

An `override` points the build at a local rive-cli project instead of the
snapshots `rive pull` downloaded into `.libraries/`, so a library and a file
that imports it can be edited together without publishing between every
change:

```yaml
libraries:
  "palette":
    fileId: 4002
    libraryId: 42
    version: 1
    # resolve from the project next door while I work on it
    override: ../palette
```

It is yours, unlike the three fields above it. A pull rewrites those and
leaves this and any comment beside it alone.

The override has to be a rive-cli project whose own `push.fileId` is the
library's `fileId`, which is what stops a path typo resolving against some
unrelated project. If it is not, the build says so and falls back to those
snapshots:

```
warning  rive.yaml:1:1  [lint] for library palette, the override ../palette
pushes to file 7701, not the library's 4002; falling back to the downloaded
library in .libraries/
```

The same line, with a different reason in the middle, covers a path that is
not a project, a `rive.yaml` that cannot be read, and a project holding no
markup.

**An override changes what the build resolves, never the markup.** The scene
still names the library and the version it always did, and the file you push
is unchanged by it. The project builds as before the moment you remove the
key.

A component the override no longer carries falls back to the downloaded
snapshot, so a half-finished local copy still builds. Each build says what it
got:

```
library override ../palette provides all 3 components the host needs from
the library
```

and says `provides none of the 3` when the fileId check refused it, which is
the quickest way to notice that the warning above scrolled past.

The override's own libraries are not overridden in turn: a library you edit
locally still imports its own dependencies from `.libraries/`.

Editing a file under the override triggers a rebuild, the same as editing the
project's own sources.

### What the build tells you

A library the project does not hold is a warning, not an error. The file
builds without what that library supplies, which is the same partial state the
editor shows, and a `rive pull` that reaches the library fixes it.

A project that imports **two versions of one library** can lose a script or a
shader that the newer version did not republish. The build says so, naming the
snapshot and both versions. There is no way to avoid it from the project
side: import a single version where you can, or have the library republish
that script in the newer version.

### Pushing

`rive push` sends the project's own content. A library's artboards and scripts
stay out of the `.rev` it writes, because they belong to the library's file
rather than to this one.

## Layout on disk

Nothing is enforced beyond `rive.yaml` being at the root. A conventional
project:

```
myproject/
  rive.yaml
  scene.rml
  main.luau
  mathutil.luau
  mathutil_test.luau
  Montserrat.ttf
  logo.png
  build/
```

A project that imports published libraries has one more, holding what `rive
pull` downloaded:

```
myproject/
  rive.yaml
  scene.rml
  .libraries/
```

What is inside it is the tool's, and
[libraries-folder.md](libraries-folder.md) describes it for anyone who wants
to know. Nothing in a project should depend on that shape.

Asset paths in RML are project-relative:

```xml
<FontAsset file="Montserrat.ttf" name="Montserrat" id="0:30"/>
<ScriptAsset file="main.luau" name="main" id="0:80"/>
```

## Commands

```bash
rive create <dir>                 # scaffold yaml, scene.rml, AGENTS.md, CLAUDE.md, .gitignore
rive create <dir> --from-rev=f.rev  # the same, but scene.rml and its files come from an editor .rev
rive create <dir> --from-remote-file[=<fileId>]  # the same, from a file in your Rive account
rive <dir> --once                 # build once, exit non-zero on errors
rive <dir> --test                 # build, run every Tests script, exit non-zero on failures
rive <dir> --once --rev=out.rev   # also export an editor .rev
rive inspect <dir> --json         # dump the built scene and any ignored input
rive <dir> --artboard=<name>      # choose the artboard shown on launch
rive <dir> --optimize             # compile scripts at Luau O2 instead of O1, and AnimaScript without debugger line probes (several times faster, for timing and long tests)
```

A directory literally named `create` or `login` must be passed as `./create`
or `./login`, so it is not read as the subcommand.

In macOS **editor mode**, the workspace always uses an integrated title bar,
with controls at `(16, 18)` and a 52-point drag strip. Project `window.titleBar`,
`controls`, and `dragHeight` settings apply to standalone previews; they do not
change the editor workspace header. Detached editor windows use the same header.

**RML editor formatting** — controls the built-in editor's format action (F4)
and format-on-save (Cmd+S on macOS):

```yaml
editor:
  rml:
    indentSize: 2
    printWidth: 80
    multilineAttributes: auto
```

- `indentSize`: positive integer spaces per nesting level (default `4`). Also controls
  RML indent guides, Tab, Shift+Tab, and automatic indentation.
- `printWidth`: positive integer character target (default `80`). Includes the
  opening tag's indentation, attributes, spaces, and closing `>` or `/>`.
  When explicitly set, a faint vertical guide marks that column in RML code
  panes and follows horizontal scrolling. Omitting it hides the guide while
  retaining the default formatting target.
- `multilineAttributes`: `false` (default) keeps attributes inline; `true`
  always puts each attribute on its own line; `auto` does so only when the
  complete opening tag would exceed `printWidth`. Tags exactly at the limit
  remain inline. Previously wrapped tags collapse again when they fit.

With `auto`, a short tag stays inline:

```xml
<Shape name="Background" />
```

A tag exceeding the target places each property on its own line, one indent
level deeper, and aligns the closing bracket with the opening tag:

```xml
<Shape
  name="Background"
  x="12"
  y="24"
/>
```

`printWidth` is a formatting target, not a hard limit or visual word-wrap:
individual values, comments, and text are never split. UTF-8 characters count
as one character each. Attribute values containing literal newlines use
multiline layout in `auto` mode.

Save `rive.yaml` first; formatting reads these preferences without a restart.
Indent guides also refresh when the project rebuilds. Formatting normalizes
existing element indentation in element-only content. It preserves attribute
order, quote styles, entity spellings, comments, CDATA, mixed text, and
whitespace in `xml:space="preserve"` content. It does not add line breaks between
inline elements. Malformed XML and unsupported declarations (such as DOCTYPE)
are left untouched, with a Console message. These settings apply to RML in the
built-in editor; other languages and external LSP clients retain their existing
formatting behavior.

## Personal code editor settings

Appearance and typography are configured per user in `$RIVE_HOME/settings.yaml`, defaulting to
`~/.rive/settings.yaml` (using `USERPROFILE` on Windows when `HOME` is unset).
When signed in, click your titlebar avatar and choose **Editor settings** to open
Settings on any platform. The same menu includes **Account settings**, which opens
your account page in the browser, and **Sign out**.
On macOS, you can also choose **Rive → Settings…** (`⌘,`); on Windows and Linux, press
**Ctrl+,**. This opens the file in Hydrogen, creating its directory and commented
defaults if needed. It applies across CLI editor projects;
these preferences are not stored in `rive.yaml` or sent by `rive push`.

```yaml
editor:
  theme: dark # light or dark
  code:
    fontSize: 16
    lineHeight: 24
    font:
      path: fonts/MyMono.ttf
```

`fontSize` accepts numbers from 6 to 96, and `lineHeight` from 6 to 192.
Both are logical pixels; line height is an absolute height, not a multiplier.
Omitted values use the defaults shown above. Omit `font`, or use an empty
`path`, to use the embedded font. Custom TTF and OTF files use a single face
for all syntax scopes. Installed family names and weight selection are not
yet supported.

Font paths may be absolute or relative to the directory containing
`settings.yaml`. Home-directory (`~`) and environment-variable expansion are
not performed. Keeping personal fonts alongside this settings file keeps them
out of project asset collection.

The running editor checks settings and the selected font file approximately
once per second. Changes apply to open and newly opened text panes, including
detached panes. Invalid settings keep the last valid preferences and report a
Console message. An unreadable or invalid font falls back to the embedded font
with a Console message. Deleting the settings file restores defaults.

`editor.theme` accepts `light` or `dark` (default). Saving a change updates the entire
editor, including detached panes. The titlebar appearance button writes the
same setting, replacing the old per-layout `.theme` preference. With an open,
unsaved settings tab, the button changes that buffer and previews the theme;
save the tab to persist it. It never silently saves unrelated edits.
The button preserves comments in ordinary block YAML. Unusual flow mappings
or quoted theme keys may be reserialized while retaining their setting values.

### Console typography

The Console inherits each omitted typography field from `editor.code`.
Override any of the same fields independently:

```yaml
editor:
  console:
    fontSize: 14
    lineHeight: 20
    font:
      path: fonts/MyConsoleFont.ttf
```

The same numeric limits and path resolution rules apply. Removing an override
restores inheritance; an explicit `font.path: ""` selects the embedded font
instead of inheriting a custom code font. Missing or invalid font files fall
back to the embedded font with a Console message. Changes apply to existing
log rows without clearing output, retaining tail-following or the visible row
when scrolled back. Console settings do not change the Problems pane.
