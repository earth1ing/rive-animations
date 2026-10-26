# Luau protocols

A Luau file becomes part of a Rive file by returning a **protocol** — a table of
lifecycle functions plus your own state. The protocol you return determines what
the script is and when it runs.

| Protocol | Returned as | What it is | Attached with |
|---|---|---|---|
| `Layout<T>` | `function(context: Context): Layout<T>` | a drawable that fills a layout box | `ScriptedLayout` |
| `Node<T>` | `function(): Node<T>` | a drawable in the artboard tree | `ScriptedDrawable` |
| `PathEffect<T>` | `function(): PathEffect<T>` | rewrites a shape's geometry | `ScriptedPathEffect` |
| `Converter<T, I, O>` | `function(): Converter<T, I, O>` | transforms a value in a data bind | `ScriptedDataConverter` |
| `ListenerAction<T>` | `function(): ListenerAction<T>` | runs when a listener fires | `ScriptedListenerAction` |
| `TransitionCondition<T>` | `function(): TransitionCondition<T>` | decides whether a transition may take | `ScriptedTransitionCondition` |
| `Tests` | `function(): Tests`, returning `function(test: Tester)` | unit tests, run headless | — |

Only the first two are whole drawables. The rest are **hooks into markup you
have already authored** — a script is not all-or-nothing, and reaching for one
does not mean rebuilding the scene in code. See
[Scripts as effects](#scripts-as-effects).

Full API reference — `Renderer`, `Path`, `Paint`, `Vector`, `Color` and the rest
— is generated per type. Use it rather than guessing method names.

## Type checking is strict, and it fails the build

Read this before writing anything. Scripts are checked in **strict mode**, and
**type errors are build errors, not warnings.** A script that would run
perfectly will not ship if it does not type-check.

The one rule that matters: **annotate every function parameter.** An
unannotated parameter infers as `unknown`, and `unknown` supports no operators
at all — so a single missing annotation turns every arithmetic expression
downstream of it into an error:

```luau
-- WRONG: cfg is `unknown`, so cfg.lifetime * 2 is an error, and so is
-- everything computed from it. One omission, dozens of errors.
function Sparks.capacityFor(cfg): number
    return math.ceil(cfg.emissionRate * cfg.lifetime)
end

-- RIGHT: name the shape, annotate the parameter.
type Config = { emissionRate: number, lifetime: number }

function Sparks.capacityFor(cfg: Config): number
    return math.ceil(cfg.emissionRate * cfg.lifetime)
end
```

This bites hardest on module tables — `function M.foo(state, x: number)` is easy
to write with the first parameter bare. Every method needs its `self`/state
parameter typed, exactly as the protocol examples below type theirs as
`self: Hello`.

Two more that produce large error cascades from one mistake:

- **A field that starts `nil`.** If your state type says `cfg: Config` but the
  constructor sets `cfg = nil` and fills it in later, every read of `cfg`
  reports against `nil`. Either build the table complete, or type the field
  `cfg: Config?` and narrow before use.
- **Dynamic keys on a typed table.** Assigning `self[name] = v` to a table with
  a declared type gives "Cannot add indexer". Use an explicit map field.

Errors nest deeply — you will see types like `add<a, mul<b, number>>` several
lines long. **Fix the first error in the first file and re-run**; the rest are
usually cascade from it.

## Checking a script

```bash
rive <dir> --verify
```

This is the loop. It runs the whole local build — RML, Luau type checking,
WGSL — and checks that the `.riv` it produces can be loaded, without writing
one. **No login, no network, no file on disk.**

**It type-checks; it does not run.** Nothing in `--verify` calls your script, so
every failure that needs execution is invisible to it: a hook whose signature is
wrong for the protocol, a `require` that cannot resolve at run time, an error
thrown on the first call. All of them compile clean and then silently do
nothing, which looks exactly like a script that was never attached.

The first time you wire a script up, render it — `--screenshot` drains the
console, so a runtime error appears there and nowhere else. `--test` is the
repeatable version once the shape is right.

Note that `rive inspect` does *not* check Luau. A script of pure nonsense
inspects clean with `problems: []`, and for a script-only project `inspect` has
no resolved tree to report on at all. `inspect` answers "is the scene wired
correctly"; `--verify` answers "does this compile". You want both, and only one
of them reads your code.

Run it after every few edits. Type errors cascade — one unannotated parameter
becomes dozens of downstream errors — so a small script checked often is far
easier to fix than a large one checked once.

## A misspelled hook is silently ignored

The protocol table is matched by key name, and **unknown keys are dropped
without complaint**. Add `zzzBogus = something` to a returned `Layout` and it
builds clean. So `pointerdown` instead of `pointerDown`, or `Advance` instead of
`advance`, produces a script that compiles, runs, and never receives that
callback.

The type checker cannot help here — the protocol's hooks are all optional, so an
absent one is legal. Check the exact spelling in
[api/interfaces.md](api/interfaces.md) against `Layout<T>` and `Node<T>`, and
confirm with a `print` in the handler the first time you wire one up.

## What to put in a script

Scripts are for **things that are computed**: simulations, particles, physics,
procedural geometry, per-frame maths, data-driven drawing.

They are not for interfaces. A script can draw a button and a score readout, and
the result will work, but you will be reimplementing things the scene format
already has — and one of them you cannot reimplement at all:

- **There is no text API.** `Renderer` draws paths and images. `Font` is an
  opaque handle with no drawing method, so a script cannot render a string. Any
  lettering has to be hand-built from paths, glyph by glyph.
- **No layout**, so every element is positioned by hand in code.
- **No state machines or listeners**, so interaction becomes bespoke hit-testing.

Build the UI in RML — layouts, text, state machines — and attach the script to a
`LayoutComponent` for the part that actually needs computing. In a game that
means the playfield is a script and the score, menus and buttons are markup.
See [../README.md](../README.md#use-each-for-what-it-is-good-at).

## Scripts as effects

The section above is about a script that owns a region. The more common case is
smaller: the scene is fine, one *effect* is missing.

Reach for the format first. `Feather` softens a stroke, `blendModeValue`
composites a drawable or an individual paint, `ClippingShape` masks, and strokes
carry `Trim` and `Dash` — see [../drawing.md](../drawing.md#effects-and-clipping).
Those are hardware paths and cost nothing to reach for.

When the effect you want has no element, a script supplies it **without taking
the scene over**:

- **`ScriptedPathEffect`** nests inside a shape's `Fill` or `Stroke`, like
  `TrimPath` and `DashPath`, and rewrites the geometry that paint draws.
  `update(self, path, node)` receives the path the markup produced and
  returns the one to draw, so the authored `Rectangle` or `PointsPath` is the
  input rather than something you rebuild. Everything else about the shape --
  its fills, strokes, feather, clip, its slot in a layout -- is untouched
  markup.
- **`ScriptedDrawable`** is a `Drawable`: it has `x`/`y`, a transform and its
  own `blendModeValue`, so it sits among ordinary siblings and composites with
  them under the same paint order (earlier siblings draw on top).
- **`ScriptedLayout`** is a flex item like any other, so a computed effect can
  be one cell of a layout with text and shapes either side of it.
- **`ScriptedDataConverter`** transforms a value already flowing through a
  bind. It draws nothing.

So the pattern is one scripted piece among markup, not a scripted scene; see
[Path effect](#path-effect) for the markup. An effect on type is built around a
real `Text`, since a script cannot draw one.

For an effect the renderer has no concept of at all, the GPU API compiles WGSL
and runs render passes: see [api/gpu.md](api/gpu.md).

## What a script can reach

The VM opens a fixed set of Luau standard libraries. These are available:

`math` · `table` · `string` · `os` · `utf8` · `buffer` · `bit32`, plus the base
library — `print`, `type`, `pairs`, `ipairs`, `pcall`, `select`, `tonumber`,
`tostring`, `assert`, `error`.

So `math.random`, `os.clock`, `table.create` and `bit32` all work.
`math.random` is seeded from the clock in the window, and with a fixed seed in
`--screenshot`, `--semantics` and `--data-dump` runs, so a capture draws the same
"random" positions every time. `--seed=<N>` picks a different fixed sequence. There is **no
`io`, no `coroutine` library, and no `debug`** — a script cannot touch the
filesystem. To wait on something, use `async` and `await` from the
[promise API](api/promise.md).

`print` writes to the build log, which is the only way to observe a running
script. Everything Rive-specific — `Renderer`, `Path`, `Paint`, `Vector`,
`Color`, `Context` — is documented in [api/](api/README.md).

## Drawing: four things the API reference does not say

**Paths use the clockwise fill rule.** Every `Path` a script builds is created
with it. So when several contours go into one path, **winding direction decides
fill versus hole** — a contour wound the other way is subtracted. If you are
batching many shapes into one path, make sure they wind consistently, or build
each from a rotation of the same basis so they cannot disagree.

**A `Paint` is safe to mutate after drawing with it.** `drawPath` copies the
paint's state into the draw, so changing a colour and drawing again in the same
frame is fine, and reusing one `Paint` across a whole frame is fine. This is the
opposite of `Path`, which the renderer holds by reference until replay and which
must not be mutated after being drawn — see
[api/path.md](api/path.md). The asymmetry is easy to get backwards, and
assuming the `Path` rule applies to `Paint` costs you a lot of pre-built paints.

**`feather` is a radius in path units.** It scales with the transform, and works
on fills and strokes alike. Below about a pixel of *effective* radius — feather
times the current scale — it is skipped entirely, so a small feather on a
scaled-down drawing does nothing at all.

**An image's `width` and `height` are `0` until it decodes, and on the web
that is after `init`.** The previewer and captures do the same: an image reads
`0x0` through `init` and the first frame's `advance`, and its real size from the
first draw on. A board or path sized from an image in `init` is built from `0`
and draws nothing, without an error. Compute from the size in `advance` once it
is non-zero, and guard `draw` on the same flag. The `Image` you got in `init`
is the one that grows, so keep it rather than asking for it again.

## Layout

The workhorse. Takes a `Context`, receives a size, and draws.

```luau
type Hello = { paint: Paint, path: Path, size: Vector, elapsed: number }

function init(self: Hello, context: Context): boolean return true end
function resize(self: Hello, size: Vector, scale: number) self.size = size end
function advance(self: Hello, seconds: number): boolean
    self.elapsed += seconds
    return true
end
function draw(self: Hello, renderer: Renderer)
    renderer:drawPath(self.path, self.paint)
end

return function(context: Context): Layout<Hello>
    return {
        paint = Paint.with({ color = Color.rgb(255, 100, 50) }),
        path = Path.new(),
        size = Vector.xy(0, 0),
        elapsed = 0,
        init = init, resize = resize, advance = advance, draw = draw,
    }
end
```

`advance` returning `true` means "I changed, draw me again". Returning `false`
stops redraws — a static frame is almost always this.

**`resize` takes a third parameter: `scale`** — the presenting surface's device
pixels per point, `2` on a Retina display and `1` on a standard one. Ignore it
while you only draw through the `Renderer`, which is resolution independent. The
moment you allocate a surface yourself it is the difference between sharp and
blurry:

```luau
function resize(self: Glass, size: Vector, scale: number)
    self.size = size
    -- Points x scale = device pixels. Sizing this in points renders the effect
    -- at half resolution on a Retina display and leaves the runtime to upscale
    -- it, while text and shapes beside it stay sharp.
    self.canvas = self.context:canvas({
        width = size.x * scale,
        height = size.y * scale,
    })
end
```

Nothing warns you when you drop it, and **`--screenshot` cannot catch it**: the
headless capture always runs at `@1x`, so a scene that is soft on every real
Retina device is pixel-perfect in the PNG you verified with. Check this one in
the live window, which logs the scale it presents at (`viewport 1880x1130 @2x`).

In a project with no `.rml`, every Layout script gets its own artboard
automatically. In an RML project, attach it explicitly:

```xml
<Artboard defaultStateMachineId="0:7" width="500" height="500" styleId="0:5" name="Artboard" id="0:2">
    <LayoutComponentStyle name="Artboard Style" id="0:5"/>
    <LayoutComponent width="500" height="500" styleId="0:11" name="Root" id="0:10">
        <LayoutComponentStyle layoutWidthScaleType="fill" layoutHeightScaleType="fill"
            widthUnitsValue="auto" heightUnitsValue="auto" name="Style" id="0:11"/>
        <ScriptedLayout scriptAssetId="0:80" name="Spin" id="0:12"/>
    </LayoutComponent>
</Artboard>
```

The fill-sized layout parent is what gives `resize` the artboard's size. Without
it the script receives nothing useful.

**The artboard needs its own `LayoutComponentStyle` too** — the `styleId="0:5"`
above and the matching child. An `Artboard` *is* a `LayoutComponent`, and the
editor gives every artboard a style on creation; a `ScriptedLayout` has nothing
to lay it out against without one. The CLI renders the scene anyway; the editor
does not. See [../layout.md](../layout.md).

## Node

A component in the tree rather than a layout box. Note it takes **no `Context`**:

```luau
type Oval = { path: Path, paint: Paint }

function update(self: Oval) end
function draw(self: Oval, renderer: Renderer)
    renderer:drawPath(self.path, self.paint)
end

return function(): Node<Oval>
    return {
        path = Path.new(),
        paint = Paint.with({ color = Color.rgb(255, 100, 50) }),
        update = update,
        draw = draw,
    }
end
```

Attach it with a `ScriptedDrawable`:

```xml
<ScriptedDrawable x="120" y="20" scriptAssetId="0:83" name="Orbit" id="0:12"/>
```

## Path effect

Rewrites one shape's geometry. `update` receives the path the markup produced
and returns the one to draw, so the authored `Rectangle` or `PointsPath` is the
input — see [Scripts as effects](#scripts-as-effects).

The effect is a child of the `Fill` or `Stroke` it applies to, not of the
`Shape`. Placed directly under the shape it builds, then fails to load
(`rive inspect` reports `scripted-path-effect-not-under-paint`).

```xml
<Shape x="10" y="10" name="Panel" id="0:10">
    <Rectangle width="180" height="100" originX="0" originY="0" name="Path"/>
    <Fill name="Fill">
        <SolidColor colorValue="FF7DB8A9" name="C"/>
        <ScriptedPathEffect scriptAssetId="0:80" name="Ripple" id="0:11"/>
    </Fill>
</Shape>
```

## Converter

Note the **three** type parameters — the state, the input type and the output
type — and that `reverseConvert` is **not optional**. A converter that only
goes one way still has to declare the way back.

```luau
type Half = {}

local function convert(self: Half, input: number): number
    return input * 0.5
end
local function reverseConvert(self: Half, input: number): number
    return input * 2
end

return function(): Converter<Half, number, number>
    return { convert = convert, reverseConvert = reverseConvert }
end
```

`ScriptedDataConverter` is a `DataConverter`, so it is a root element named
from the bind by `converterId` exactly as the built-in converters are
([../data.md](../data.md#converters)):

```xml
<Shape name="Box" id="0:10">
    <DataBindContext sourcePathIds="0:40-0:45" propertyKey="20" converterId="0:82"/>
</Shape>

<ScriptedDataConverter scriptAssetId="0:86" name="Half" id="0:82"/>
```

## Listener action

Runs when a state machine listener fires, beside actions like
`ListenerViewModelChange`. `performAction` returns **nothing** — it is called
for its effect.

```luau
type Act = {}

local function performAction(self: Act, listenerContext: ListenerContext)
    if listenerContext:isPointerEvent() then
        print('clicked')
    end
end

return function(): ListenerAction<Act>
    return { performAction = performAction }
end
```

```xml
<StateMachineListenerSingle targetId="0:10" listenerTypeValue="click" name="Tap" id="0:50">
    <ScriptedListenerAction scriptAssetId="0:85" id="0:51"/>
</StateMachineListenerSingle>
```

`ListenerContext` says what fired the listener: `isPointerEvent`,
`isKeyboardEvent`, `isGamepadEvent`, `isViewModelChange` and so on. The older
`perform(self, pointerEvent)` hook still works but is deprecated. Both are
optional, so a script with neither compiles and does nothing.

## Transition condition

Gates a state transition, beside `TransitionViewModelCondition`. `evaluate`
returns whether the transition may take.

```xml
<StateTransition stateToId="0:14" duration="100">
    <ScriptedTransitionCondition scriptAssetId="0:84" id="0:15"/>
</StateTransition>
```

### Two of these take no `name`

`ScriptedListenerAction` and `ScriptedTransitionCondition` are not
`Component`s, so they have no `name` attribute and adding one fails the build
with *"has no property name"*.
`ScriptedDrawable`, `ScriptedPathEffect` and `ScriptedDataConverter` do take
one.

## Pointer and gamepad input

A `Layout` or `Node` receives input by putting a handler on the returned table,
under the exact key the protocol declares:

```luau
function pointerDown(self: Board, event: PointerEvent)
    self.paddleX = event.position.x
end

return function(context: Context): Layout<Board>
    return {
        -- state ...
        init = init, resize = resize, advance = advance, draw = draw,
        pointerDown = pointerDown,
        pointerMove = pointerMove,
        pointerUp = pointerUp,
        pointerExit = pointerExit,
    }
end
```

The pointer set — `pointerDown`, `pointerMove`, `pointerUp`, `pointerExit`,
`pointerScroll` — plus `gamepadConnected`, `gamepadDisconnected` and
`gamepadEvent` is declared on `Node<T>` in [api/interfaces.md](api/interfaces.md),
with the `PointerEvent` and `ScrollEvent` types in
[api/artboards.md](api/artboards.md). `event.position` is in the
script's local coordinates. Keyboard is a separate hook, below; it is not in
that listing.

All of them are optional, so omitting one is legal and misspelling one is
silent. See the note above.

`event.position` is in the script's local coordinates — but the script is handed
**every** pointer event in the artboard, not only those inside its own bounds.
A layout 100x80 at artboard (150,40) sees a click at (20,20) arrive as
`(-130,-20)`. Bounds-check against the size handed to `resize` if a script
sitting beside other content should not react to it; a scripted viewport with a
control panel next to it otherwise treats the panel as part of itself.

### Claim the pointer or something above you takes it

Handling an event does not consume it. `event:hit()` does, and a script that
acts on a press must call it on **every** event it owns — the `pointerDown`,
each `pointerMove` of the drag, and the `pointerUp`:

```lua
function pointerMove(self: Slider, event: PointerEvent)
    if self.down then
        write(self, event)
        event:hit()
    end
end
```

Without it the event keeps travelling outward, and an enclosing hit target
claims the gesture. A `ScrollConstraint` viewport is the one that bites: drag a
slider inside a scroll view and the page scrolls instead, and because an engaged
drag turns the viewport opaque, clicks under it stop firing too. Claiming only
the `pointerDown` is the same bug one frame later — the scroll engages on the
move.

The argument inverts: bare `event:hit()` is opaque and stops there, while
`event:hit(true)` marks this target translucent so the event continues to
whatever is behind. Claim nothing on events you do not own; a press-outside
watcher, for instance, has to stay transparent.

### Scroll: mouse wheel and trackpad

`pointerScroll` receives a `ScrollEvent` for a mouse wheel or a two finger
trackpad scroll over the script. `event.delta` is how far the content should
travel, in local coordinates, with the same sign as a `ScrollConstraint`:
revealing content further down reads as a negative `y`. `event.precise` is
`true` for a trackpad, and `event.phase` is one of `begin`, `update`, `end`,
`momentum` or `inertiaCancel`; a wheel only ever reports `update`.

```lua
function pointerScroll(self: ZoomView, event: ScrollEvent)
    -- Zoom around the pointer.
    local factor = math.exp(-event.delta.y * 0.01)
    self.offset = event.position - (event.position - self.offset) * factor
    self.zoom *= factor
    event:hit()
end
```

Unlike pointer events, scroll only reaches a script under the pointer: a
`Layout` inside its box, a `Node` anywhere in its artboard. `event:hit()`
claims it; without the call the scroll passes to whatever lies behind, so a
`ScrollConstraint` view under the script still scrolls. A claimed trackpad
gesture stays with the script until it ends, even if the pointer leaves it.

Implementing `pointerScroll` makes that area a scroll target for the host, as a
scroll view is: a host such as a Flutter page then hands the wheel to the scene
there rather than scrolling itself, even when the script declines it.

### Gamepad indices are 1-based here and 0-based everywhere else

`GamepadEvent.changeIndex` is a **1-based** W3C index, so the bottom face button
(W3C `south`, index 0) arrives as `1`. Every reference table you will reach for
is 0-based, and so are the two other places the same slot is written:
`GamepadInput.inputIndex` in the scene format, and the embedder wire format.

|  | south / A | west / X | dpadLeft | left stick X |
|---|---|---|---|---|
| Luau `changeIndex` | 1 | 3 | 15 | 1 |
| `GamepadInput.inputIndex` | 0 | 2 | 14 | 0 |
| `--gamepad=` name | `south` | `west` | `dpadLeft` | `leftX` |

Use the names with `--gamepad` and the question does not arise.

### Testing a gamepad handler

`--gamepad` synthesises pad input headlessly, delivered through the runtime's
own dispatch so scripts and state machine listeners both see it:

```bash
rive <dir> --screenshot=pad.png \
    --gamepad=axis@leftX:-0.9 --gamepad=button@west:down --advance=20
```

The capture mode is not optional. Synthesised input needs a scene to go into,
and a trailing `--advance` only says how long to settle before the shot; without
`--screenshot` or `--semantics` the command is a usage error.

See [workflow.md](../workflow.md#gamepad). Note that gamepad events bubble from
the focused node upward and **the first handler stops the bubble** — a script
with a `gamepadEvent` handler consumes the event before a listener on an
ancestor sees it.

### Driving markup from the pointer

The common shape for "make the scene react to the mouse" is a `ScriptedLayout`
that fills the artboard, converting pointer position into view model properties
that the markup is bound to. The script writes; data binding does the rest.

```luau
type Track = { vm: ViewModel?, tiltX: Property<number>? }

function init(self: Track, context: Context): boolean
    -- init runs twice, and the view model is absent the first time.
    local vm = context:viewModel()
    if vm == nil then
        return true
    end
    self.vm = vm
    self.tiltX = vm:getNumber('tiltX')
    return true
end

function pointerMove(self: Track, event: PointerEvent)
    if self.tiltX ~= nil then
        self.tiltX.value = event.position.x
    end
end
```

```xml
<Node name="Card" id="0:30">
    <DataBindContext sourcePathIds="0:40-0:41" propertyKey="15"/>
</Node>
```

Three things about this are worth stating outright, because none is obvious:

- **A script can write the view model the artboard is bound to.** That is the
  return path from script to markup; [data.md](../data.md) documents the other
  direction. `context:viewModel()` is the bound instance.
- **`init` is called twice, and `context:viewModel()` is `nil` on the first
  call.** Cache a property handle without guarding for that and it stays `nil`
  forever, leaving a scene that builds clean and never moves.
- **A fill-sized `ScriptedLayout` at the artboard root gets the whole artboard**,
  and its local coordinates equal artboard coordinates — which is what lets the
  numbers it computes line up with hand-placed markup.

A `ScriptedDrawable` (`Node<T>`) has no `resize` and is told nothing about its
surroundings — no parent bounds, no sibling geometry. Anything it needs about
the scene around it has to come in as a `ScriptInput*`, or be duplicated as
constants and kept in step by hand.

## Keyboard and text input

A `Layout` or `Node` receives keys via `keyboardEvent` / `textEvent`. Those
only fire if the scripted object has a **direct `FocusData` child** and that
node is focused. Pointer and gamepad script callbacks do not need this.
Script-only projects inject that child; **RML does not** — add a bare
`<FocusData/>` under the `ScriptedLayout`, not the artboard or the fill parent.
The CLI player focuses the first `FocusData` on the shown artboard; clicking
the playfield does not.

```xml
<ScriptedLayout scriptAssetId="0:80" name="Game" id="0:16">
    <FocusData/>
</ScriptedLayout>
```

The `KeyboardEvent` and `TextInput` types are in
[api/artboards.md](api/artboards.md). A state-machine keyboard listener uses
the same `FocusData` rule; see
[gotchas.md](../gotchas.md#keyboard-events-need-a-focusdata-child).

## Inputs and outputs

Scripts declare typed fields that the scene fills in:

```luau
type Spin = {
    speed: Input<number>,
    title: Input<string>,
    visible: Input<boolean>,
    onReset: Input<Trigger>,     -- a function the scene calls
    settings: Input<Data.Settings>?,   -- a whole view model
    distance: Output<number>,    -- read back by the scene
}
```

Every `<ViewModel>` in the markup is declared as `Data.<Name>` and every named
`<DataEnumCustom>` as a string union, so view model inputs type check against
the shapes the file actually has. A name must be a plain identifier that
shadows no built-in type, first occurrence wins on duplicates, and an empty
enum declares nothing — a skipped element just stays untyped. `Input<any>`
still works, it just forgoes the checking.

RML supplies each with a matching `ScriptInput*` child, **matched by name**:

```xml
<ScriptedLayout scriptAssetId="0:80" name="Spin" id="0:12">
    <ScriptInputNumber propertyValue="3" name="speed"/>
    <ScriptInputViewModelProperty dataBindPathIds="0:40-0:45" name="settings"/>
</ScriptedLayout>
```

| Field type | RML element |
|---|---|
| `Input<number>` | `ScriptInputNumber` |
| `Input<boolean>` | `ScriptInputBoolean` |
| `Input<string>` | `ScriptInputString` |
| `Input<Color>` | `ScriptInputColor` |
| `Input<Trigger>` | `ScriptInputTrigger` |
| `Input<Data.X>?` (a view model) | `ScriptInputViewModelProperty` |

Names must match exactly. Nothing checks them at build time — a mismatch leaves
the field at its default and reports nothing. Verify with `rive inspect`.

An `Input<Trigger>` is the odd one: the field is a **function**, and firing the
input calls it with `self`. The name matches the same way, so a
`ScriptInputTrigger` named `onReset` calls `self.onReset(self)`. If the field is
missing or is not a function, the call is dropped silently.

View model inputs are handed over whole. Read through `.value`, and guard for
`nil` — the input may not be bound yet when `init` runs, which is why the
field above is declared `?`:

```luau
local function speedOf(self: Spin): number
    local settings = self.settings
    if settings == nil then return 0.5 end
    return settings.speed.value
end
```

### An input is a custom property

`ScriptInput*` is not a family of its own. Each one **extends the matching
`CustomProperty*`** — a `ScriptInputNumber` is a `CustomPropertyNumber`, a
`ScriptInputTrigger` is a `CustomPropertyTrigger` — and what makes it an input
rather than a stray value is being a child of the `Scripted*` object.

That inheritance is where its capabilities come from. `rive schema` marks the
value `AB`:

```
ScriptInputNumber  (typeKey 611)
extends CustomPropertyNumber > CustomProperty > Component

inherited from CustomPropertyNumber:
  propertyValue                 AB   double       key 243     = 0
```

**A**nimatable and **b**indable, which is to say an input is not only a constant
you write once.

**Bind one** by nesting a `DataBindContext` in it, exactly as anywhere else. The
target is the input's own `propertyValue`, so a view model number can drive a
script's `speed` without the script knowing anything about view models:

```xml
<ScriptedLayout scriptAssetId="0:80" name="Spin" id="0:12">
    <ScriptInputNumber propertyValue="1" name="speed">
        <DataBindContext sourcePathIds="0:40-0:45" propertyKey="243"/>
    </ScriptInputNumber>
</ScriptedLayout>
```

Unlike the name matching, this half **is** checked: a wrong `propertyKey` or a
mismatched type is reported as `bind-target-missing-property` or
`incompatible-bind-types`.

**Key one** on a timeline, by id like any other object, and the script's input
animates:

```xml
<KeyedObject objectId="0:14">
    <KeyedProperty propertyKey="243">
        <KeyFrameDouble value="1" frame="0" interpolationType="linear"/>
        <KeyFrameDouble value="8" frame="120" interpolationType="linear"/>
    </KeyedProperty>
</KeyedObject>
```

`update` fires each time a bound or keyed input changes.

#### The trigger has two keys

`ScriptInputTrigger` carries **two** properties, and which one you use depends
on whether you are binding or keying:

| | Property | Key | Element |
|---|---|---|---|
| bind | `propertyValue` | `870` | any `BindablePropertyTrigger` source |
| keyframe | `fire` | `869` | `KeyFrameCallback` |

```xml
<KeyedObject objectId="0:15">
    <KeyedProperty propertyKey="869">
        <KeyFrameCallback frame="60"/>
    </KeyedProperty>
</KeyedObject>
```

`fire` is a `callback` property — animatable but **not** bindable. Firing it
increments `propertyValue`, and it is that change to a non-zero value which
calls the script. So `fire` is the keyframe form: a `KeyFrameCallback` fires on
the frame it sits at and again on every loop, with no value to keep track of.
Bind `fire` and there is nothing to bind to. `rive schema ScriptInputTrigger`
shows which is which — `fire` is `A`, `propertyValue` is `AB`.

The rest of the family — `CustomPropertyNumber`, `...Boolean`, `...Color`,
`...String`, `...Enum`, `...Trigger`, gathered under a `CustomPropertyGroup` —
is the editor's own custom-properties feature, and is covered in
[data.md](../data.md#custom-properties). A script input is the one place the
runtime reads a custom property, and the one place the group does not appear:
inputs are children of the `Scripted*` object itself, never of a group.

## Tests

A test script returns a **factory**, exactly like `Layout` and `Node` — a
function that returns the `Tests` function:

```luau
local mathutil = require('mathutil')

return function(): Tests
    return function(test: Tester)
        test.group('clamp', function()
            test.case('clamps high', function(expect)
                expect(mathutil.clamp(10, 0, 5)).is(5)
            end)
        end)
    end
end
```

**A bare `function setup(test: Tester)` does not work** — it reports "no Tests
scripts found" and the file is skipped. Nor does returning the inner function
directly. The double wrapper is the shape, and it matches every other protocol:
the outer function constructs, the inner one is the protocol value.

```bash
rive <dir> --test        # headless, non-zero exit on failure
```

Matchers: `is`, `lessThan`, `lessThanOrEqual`, `greaterThan`,
`greaterThanOrEqual`, each negatable as `expect(x).never.is(y)`.
`test.blob(name)` reads a project blob asset.

## Modules

Any `.luau` file that returns a value is importable by name:

```luau
local mathutil = require('mathutil')
```

### Declare the module before whatever requires it

Modules are registered in the order their `ScriptAsset`s appear in the document,
and `require` only finds one that is **already registered**. So a module must be
declared *above* every script that imports it:

```xml
<ScriptAsset file="mathutil.luau" isModule="true" name="mathutil" id="0:91"/>
<ScriptAsset file="half.luau" name="half" id="0:90"/>
```

Put those two the other way round and the build is still clean — `--verify`
type-checks both files and reports `0 errors` — but the moment the scene runs
you get:

```
half:1: require could not find a script named mathutil
```

The script then does nothing at all, which for a converter or an effect looks
exactly like a bind that never fired. This is one of the few errors that appears
*only* in the console during `--screenshot` or a live preview, so a `--verify`
loop will never show it to you.

`isModule="true"` marks a file as a plain module rather than a protocol
implementation. The name `require` matches is the asset's `name`, prefixed by
`folderPath` when it has one — a script named `button` with
`folderPath="widgets"` is `require('widgets/button')`.

A library this project imports exposes its modules under the library's name,
which is the key under `libraries:` in rive.yaml:

```luau
local ink = require('lib:palette/ink')
```

See [project/rive-yaml.md](../project/rive-yaml.md#libraries) for where that
name comes from.
