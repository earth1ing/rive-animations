# Building Rive files with `rive`

`rive` turns a directory of plain source files — Luau scripts, WGSL shaders, RML
markup, images, fonts — into a `.riv` (the runtime format) and a `.rev` (which
opens in the Rive editor).

Everything here is what you need to author those files without access to the
Rive codebase.

Read any topic below with `rive docs <topic>` — the link target minus the
`.md`, so [drawing.md](drawing.md) is `rive docs drawing` and
[luau/protocols.md](luau/protocols.md) is `rive docs luau/protocols`.
`rive docs` on its own prints this index, and `rive docs --search <text>`
lists every line, in every topic, that mentions `<text>`, as
`topic:line: text`.

The RML in these topics is excerpted: every file wraps its elements in a
`<Rive version="1" kind="fragment">` root, which the examples leave out. See
[format.md](format.md) for the document shape.

## Seeing the result

There are exactly two ways to look at what you built:

| Who is looking | Run |
|---|---|
| the user | `rive <project-dir>` — the previewer: a window that rebuilds on every save |
| you | `rive <project-dir> --screenshot --advance=1` — a png at `build/<name>.png` |

`rive <project-dir>` does not exit until its window is closed. Start it in the
background, once, and leave it running; every later edit shows up in it on
its own.

Nothing else is a preview:

- **Not `rive push`.** It uploads the project to a file in the user's Rive
  account and adds a revision. Push only when asked to.
- **Not an HTML page or a web runtime.** Local builds carry unsigned scripts,
  which web runtimes reject, so a scripted file shows nothing there. The one
  command that does produce a web page is `rive <project-dir> --publish=web`,
  which signs the build first; it ships the work, it is not the authoring
  loop. See [publishing.md](publishing.md) and [publish-web.md](publish-web.md).
- **Not a `.riv` on its own.** `rive` opens project directories; there is no
  command that opens a built `.riv` by itself.

## The loop

```bash
rive <project-dir> --verify
```

Compiles everything — RML, Luau, shaders — and exits non-zero on errors,
without writing a `.riv`. This is the command to run after every edit.

`--once` and `--publish` also build, but they produce output; `--verify` is the
check. Of the three only `--publish` needs a login. **A file with scripts that is destined for the
web must be built with `--publish`** — unsigned scripts are rejected by the CDN
and web runtimes, and nothing local will warn you. See
[publishing.md](publishing.md).

```bash
rive inspect <project-dir> --summary
rive inspect <project-dir> --json
```

`--summary` prints the `problems` list and a count of objects per type, per
artboard and for the other roots; `--json` prints the whole resolved tree.

It works offline too, and reports *both* kinds of failure — the misspellings
that stop a build, and the wiring mistakes that do not:

```json
{"severity": "error",   "kind": "syntax", "line": 21,
 "message": "unknown element <Elipse>; did you mean <Ellipse>?"}
{"severity": "warning", "kind": "no-default-state-machine", "line": 3,
 "message": "artboard \"A\" has animations or state machines but no defaultStateMachineId; ..."}
```

Every entry has `severity` (`error` or `warning`), `kind`, `line` and
`message`, and `inspect` exits non-zero when there is an error.

**Run both — neither is a superset of the other.** They share only syntax
checking; beyond that they cover different ground:

| | `--verify` | `inspect` |
|---|---|---|
| syntax, unknown names | yes | yes |
| Luau type checking | **yes** | no |
| shaders | **yes** | no |
| bind paths, state machines, the rest of `problems` | no | **yes** |

So a scene can pass `--verify` cleanly and still be wired to nothing, and a
script with type errors will not show up in `inspect` at all. If your project is
pure RML, `inspect` is doing nearly all the work; the moment there is a `.luau`
file, `--verify` is the only thing reading it.

**Neither of them looks at a pixel.** An invisible shape, a collapsed icon, text
in the wrong place, a shader reading black — every one of those builds clean and
inspects clean. The third check is to render:

```bash
rive <dir> --screenshot=out.png             # one frame, headless, no window
rive <dir> --screenshot=t.png --advance=60  # 60 frames in, for animation
rive <dir> --screenshot=h.png --pointer=click@120,60   # drive it first
```

See [workflow.md](workflow.md) for the full sequence.

One thing the capture cannot see: it always renders at `@1x`, so a script that
sizes its own canvas in points rather than device pixels looks perfect here and
soft on every Retina screen. That one needs the live window — see
[gotchas.md](gotchas.md#dropping-resizes-scale-renders-your-effect-at-half-resolution).

The rest of the output is worth knowing:

| Key | Holds |
|---|---|
| `artboards` | the resolved scene trees |
| `defaultArtboard` | which artboard actually got picked |
| `backboard` | file-level metadata, synthesized from `rive.yaml` for a project |
| `roots` | root elements: view models, assets, converters |
| `problems` | the list above |
| `schema` | type information for what was built |

`defaultArtboard` answers a question you will otherwise guess at: with several
artboards, the choice is `main` in `rive.yaml`, then the first declared.

### What `problems` does and does not cover

Knowing the boundary matters more than any single check, because an empty
`problems` is otherwise easy to read as "this file is correct".

**Checked:**

| Kind | Catches |
|---|---|
| `syntax` | unknown elements, unknown attributes, bad value types |
| `unresolved-bind-path` | a `sourcePathIds` that leads nowhere |
| `bind-target-missing-property` | a bind whose target has no such property |
| `incompatible-bind-types` | source and target types that cannot connect |
| `missing-reference` | a required id left **unset**, on a fixed list of types |
| `no-default-state-machine` | an artboard with animations or state machines but no `defaultStateMachineId`, so which one runs is left to each host |
| `no-artboards` / `no-default-artboard` | file-level structure |
| `derived-property-authored` | setting a `D` property that is computed |
| `incomparable-condition` | a transition condition that cannot evaluate |
| `duplicate-script-name` | two scripts claiming one name |
| `paint-without-shape-paint` | a `SolidColor` or gradient outside a `Fill`/`Stroke` |
| `reference-wrong-type` | an id that resolves, but to the wrong kind of thing: `stateToId` naming a shape rather than a state. Only on properties whose def declares a referent |
| `implied-reference-authored` | a reference the nesting always sets, written out anyway, so the value never reaches the file |
| `wrong-parent` | an element nested where it cannot work, from the def's `parents` — a `LayoutParticipant` beside its shape, a `GridTrack` inside the style, a `GridItemPlacement` inside the participant |
| `library-component-outside-asset` | a `LibraryViewModel` or `LibraryDataEnum` outside the `LibraryAsset` it was imported through |
| `duplicate-sibling` | a value repeated within its scope, from the def's `unique`. Both this and `wrong-parent` are fallbacks: a def may name its own kind instead |
| `scroll-without-physics` | a `ScrollConstraint` with no physics, so it scrolls without momentum |
| `scroll-physics-parent` | a scroll physics with a `parentId`; physics belong to the file and are reached only through `physicsId` |
| `semantic-listener-target-without-data` | a semantic listener whose target is not the node holding the `SemanticData` |
| `semantic-listener-without-input-type` | a `semanticAction` trigger that is not a `ListenerInputTypeSemantic` |
| `draw-target-not-child-of-rules` | a `DrawRules` whose `DrawTarget` is not nested inside it |
| `artboards-overlap` | two artboards sharing stage space, so they stack when opened in the editor |
| `states-overlap` | two states of a layer at the same graph position, so they stack in the editor |
| `listener-converter-on-write` | a from-property listener change with its converter on the write bind, where the editor does not look |
| `artboard-without-style` | an artboard with no linked `LayoutComponentStyle` |
| `rotation-looks-like-degrees` | a `rotation` past a full turn, which is almost always degrees |
| `component-without-asset` / `nested-artboard-not-component` | a component with no `ComponentAsset`, or a nested artboard that is not a component |
| `stateful-instance-not-exported` / `stateful-instance-view-model-mismatch` / `instance-on-plain-nested-artboard` | a per-placement view model instance that the runtime will ignore |
| mesh, skin and bone kinds | malformed rigging; see [rigging.md](rigging.md) |

Two more mistakes fail the **build** rather than landing in `problems`: an id
attribute naming an id no element declares (`stateToId="0:99"`), and an asset
`file` that is missing, empty or an unfetched Git LFS pointer.

**Not checked — all of these build and inspect completely clean:**

- **Id lists.** `sourcePathIds`, `dataBindPathIds` and `tagIds` are not checked
  for dangling entries; bind paths are checked separately, above.
- **An asset a script asks for by name** (`context:image('backdrop')`) that the
  project does not have.
- **A state that covers a transition.** `states-overlap` compares exact
  positions only, so a state sitting on the line between two others passes.
  See [gotchas.md](gotchas.md#unpositioned-states-and-artboards-all-land-on-the-same-point).
- **A keyframe whose type does not match its property.**
- **A modifier value with no matching `modify*` flag.**
- **Anything about appearance** — size, overflow, spacing, colour.
- **Anything at all in a `.luau` script.** `inspect` does not read Luau at all.
  Scripts are type-checked in strict mode and type errors fail the build — run
  `rive <dir> --verify` for those. See
  [luau/protocols.md](luau/protocols.md#checking-a-script).

So `problems: []` means "nothing on the left-hand list is wrong". Confirming the
rest means querying the tree for what you intended, which is why every doc here
ends with a `jq` check rather than a build command.

**One thing the tree cannot tell you: bind paths.** `inspect` omits `List<Id>`
properties, so a `DataBindContext` reads back as
`{"type":"DataBindContext","propertyKey":268,"flags":0}` — the `sourcePathIds`
you authored are not there. Editor-only properties are absent too, so
`defaultInstanceId`, `exports` and `viewModelInstanceId` never appear either.

For those, `problems` is the only readback there is, and it is good as far as
it goes: `unresolved-bind-path` and `bind-target-missing-property` both fire
with precise messages.

**But do not read the absence of a problem as "the bind is wired."**
`unresolved-bind-path` walks the path inside the view model the path *names*;
it never checks that the artboard is bound to that view model. A bind copied
between artboards can name a perfectly valid path in the wrong view model,
resolve nothing at runtime, and report clean.

```bash
rive schema <Type>              # properties, defaults, enum names, propertyKeys
rive schema --search <text>     # find the type name in the first place
```

There are 417 core types. Do not guess names — search for them. On a terminal
`--search` opens a picker over the matches, and enter describes the type the
row belongs to; piped or in CI it prints them under `types:` and `properties:`
as it always has.

## Where to look

| You need | Read |
|---|---|
| Installing, signing in, making a first project | [getting-started.md](getting-started.md) |
| What Rive is and what you can build | [overview.md](overview.md) |
| How to sequence a build, and what to check | [workflow.md](workflow.md) |
| Groups, transforms, opacity, draw order | [transforms.md](transforms.md) |
| Images, fonts, audio, shaders, blobs of bulk data (3D meshes, vertex arrays) | [assets.md](assets.md) |
| Shapes, paint, gradients, images | [drawing.md](drawing.md) |
| Text and fonts | [text.md](text.md) |
| Responsive layout: flex, grid, stack, layout participants, scrolling | [layout.md](layout.md) |
| View models, data binding, enums, custom properties | [data.md](data.md) |
| Interactivity: states, transitions, conditions | [state-machines.md](state-machines.md) |
| Keyboard focus: which node gets the keys, and moving between them | [focus.md](focus.md) |
| Easing curves, blend states, joysticks | [easing.md](easing.md) |
| Constraints, bones, skinning, image meshes, Solo, tags | [rigging.md](rigging.md) |
| Accessibility: roles, labels, states, semantic listeners | [semantics.md](semantics.md) |
| Asking the window for an OS cursor: hand, resize, I-beam | [cursor.md](cursor.md) |
| How RML works at all | [format.md](format.md) |
| A complete file to start from | [skeleton.md](skeleton.md) |
| Things that will silently bite you | [gotchas.md](gotchas.md) |
| Making scripted 3D and shaders fast: draws, `discard`, textures, bulk data | [gpu-performance.md](gpu-performance.md) |
| Writing Luau that runs in a Rive file | [luau/protocols.md](luau/protocols.md) |
| Writing AnimaScript (`.as`) that runs in a Rive file | [animascript/protocols.md](animascript/protocols.md) |
| Breakpoints and stepping through scripts in VS Code | [debugging.md](debugging.md) |
| Project layout, `rive.yaml`, starting from an editor file | [project/rive-yaml.md](project/rive-yaml.md) |
| What `rive pull` leaves in `.libraries`, for reading not editing | [project/libraries-folder.md](project/libraries-folder.md) |
| Building, signing and shipping a `.riv` | [publishing.md](publishing.md) |
| Pushing the project to a Rive file | [push.md](push.md) |
| Publishing the project to the web | [publish-web.md](publish-web.md) |
| A specific type's properties | `rive schema <Type>` |
| A complete project that already works | `rive samples` |
| Starting from an existing editor file | `rive create <dir> --from-rev=<file.rev>` |

Setting the tool up by hand for the first time? Read
[getting-started.md](getting-started.md) — install, login, first project.

New to Rive? Read [overview.md](overview.md) first — it is the mental model
the rest assumes.

`rive samples` picks one of the runnable example projects that ship with the
CLI and copies it into a directory you name. Starting from one is often
faster than starting from an empty scene.

Read [format.md](format.md) before writing any RML. It is short, and nearly
every mistake this tool sees comes from skipping it.

## Two ways to put something on screen

**A script alone.** Any Luau file returning the `Layout` protocol, or `.as`
file exporting a class that extends `Layout`, gets its own artboard
automatically. A project can be one script and a `rive.yaml`.
Good for procedural drawing and generative work.

**RML markup.** A `.rml` file describes the whole document — artboards, shapes,
text, animations, state machines, view models, data binding. When one is
present it replaces the automatic artboards; scripts still compile and attach by
reference. Good for anything with structure, and the only way to produce a file
a designer can meaningfully edit afterwards.

The two combine: RML scenes can attach scripts to objects and pass them typed
inputs.

### Use each for what it is good at

A script *can* draw an entire interface — buttons, panels, score readouts — and
it will work. It is almost always the wrong choice, and it is the most common
structural mistake in generated projects.

| Build it in | When |
|---|---|
| **RML** | anything with a fixed structure: screens, panels, buttons, labels, HUDs, menus, cards, lists |
| **Luau** | a simulation or a generated image: particles, physics, procedural geometry, data-driven drawing, per-frame maths |

The rule of thumb: **if you could draw it in a design tool, build it in RML.**
If it only exists because something is being computed each frame, script it.

A game is the clearest case. Put the playfield — the simulation, the collision,
the moving pieces — in a script, and build the surrounding UI (score, lives,
menus, buttons, game-over panel) in RML with layouts, text and a state machine.
Doing the UI in the script instead costs you:

- **layout**, so every panel and label is hand-positioned in code and nothing
  responds to the artboard's size
- **text**, which scripts cannot draw at all — there is no font API on
  `Renderer`, so lettering has to be hand-built from paths
- **state machines and listeners**, so buttons and screen transitions become
  bespoke hit-testing and flags
- **editability**, since a designer can change an RML scene and cannot change
  your script

Scripts and RML compose, so this is not a trade-off: attach the script to a
`LayoutComponent` in the scene and let markup own everything around it. See
[layout.md](layout.md) and [luau/protocols.md](luau/protocols.md#what-to-put-in-a-script).

## Verifying your work

Run the checks above after every pass, not at the end — see
[workflow.md](workflow.md). A build that succeeds proves little; query the tree
for what you meant to build:

```bash
rive inspect . --json | jq '[..|objects|select(.type=="KeyedProperty")|.propertyKey]'
```

Empty after keying a rotation means nothing is animated.
