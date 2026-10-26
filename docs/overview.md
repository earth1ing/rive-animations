# What Rive is

Rive is a format for **real-time interactive vector graphics**. A `.riv` file is
loaded by a runtime — in a web page, an iOS or Android app, a game engine — and
rendered live at frame rate. Unlike an exported video or a Lottie animation, it
is not a fixed sequence: it reacts to pointer input, to state, and to data the
host application feeds it.

That is the part worth internalising before authoring anything. You are not
describing a picture. You are describing a small program whose output happens to
be graphics.

## What people build with it

- **UI components** — buttons, toggles, tab bars that animate between states
- **Icons and loaders** — small looping or reactive graphics
- **Characters and mascots** — rigged, animated, sometimes following the cursor
- **Data-driven displays** — gauges, charts, battery and progress indicators
  whose values come from the host app
- **Onboarding and illustration** — scenes that respond to scroll or input
- **Game and HUD elements** — health bars, menus, simple interactive scenes

A single `.riv` can hold several of these; a file is a library of artboards, not
one image.

## The building blocks

Roughly in the order you compose them:

**Artboard** — one scene, with a size and an origin. The unit a runtime displays.
A file can contain many; one is the default.

**Shapes, text, images** — what is drawn. Shapes are a container plus geometry
plus paint: a `Shape` holds position and transform, a `Rectangle` inside it holds
size, and a `Fill` holds colour. The first drawable declared paints on top.

**Layout** — optional flex, grid or stack arrangement, so content responds to
the size it is given rather than sitting at fixed coordinates. A
`LayoutComponent` blocks out an area (its visual size and position); a
`LayoutParticipant` nested in a shape, text or image decides how that leaf is
sized and positioned within the area, with no wrapper box. Necessary for
anything meant to resize.

**Animation** (`LinearAnimation`) — keyframed change over time. A timeline sets
property values at frames and interpolates between them. On its own an animation
does not play; something has to run it.

**State machine** — the logic layer, and what makes a file interactive. It holds
states (each playing an animation), transitions between them, conditions that
gate those transitions, and inputs the host app or a pointer can set. This is
what runs animations, so a file with no state machine loads and sits still.

**View models and data binding** — a typed data model attached to an artboard,
whose properties drive component properties. This is how a battery indicator
learns the charge level: the host sets a number on the view model, and a bind
pushes it into a shape's width or a text run's string.

**Scripts** (Luau) — procedural drawing and behaviour when the declarative
pieces are not enough. A script can draw directly, or read inputs and compute.

## How they fit together

A worked example, the shape most real files take:

> A **battery indicator** is an *artboard* containing a *layout* row: a battery
> outline *shape*, a fill *shape* whose width is *data bound* to a `level`
> number on a *view model*, and a *text* run bound to the same number through a
> *converter*. A *state machine* watches an `isCharging` boolean and plays a
> pulse *animation* while it is true.

Each layer is optional. A static icon is one artboard and some shapes. Adding
motion means an animation and a state machine to run it. Making it respond to the
host means a view model and some binds.

## What this tool does

`rive` builds these files from **text**: RML markup for the scene, Luau for
scripts, plus your images and fonts. It produces both outputs from the same
source — the `.riv` a runtime loads, and a `.rev` that opens in the Rive editor,
so a file authored here can be handed to a designer and edited by hand
afterwards.

While authoring, the file is viewed in the CLI's own previewer,
`rive <project-dir>`, not in a web page or the editor. See
[README.md](README.md#seeing-the-result).

The editor is the other way in. Same format, same capabilities; a GUI instead of
markup. Nothing here is a lesser subset — RML is a direct projection of the same
object model, which is why the type names in this documentation are the type
names the editor uses.

Because it is the same object model, an editor file can also be the starting
point: `rive create <dir> --from-rev=<file.rev>` turns a `.rev` into a project,
with the scene as RML and its scripts and assets as files, laid out as the
editor's Assets panel. From there it is an ordinary project — edit, build,
export a `.rev` back. See
[project/rive-yaml.md](project/rive-yaml.md#starting-from-an-editor-file).

## Where to go next

Read [format.md](format.md) before writing markup — it is short, and most
mistakes come from skipping it. [skeleton.md](skeleton.md) is a complete working
file to start from. [README.md](README.md) has the build-and-verify loop.
