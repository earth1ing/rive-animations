# Things that fail quietly

Roughly ordered by how much they cost, worst first. Everything here **compiles cleanly** —
that is what makes it expensive. A zero exit code means no name was misspelled;
it does not mean the file does what you asked.

## What the compiler does catch

Names are checked. A misspelled element or attribute is a build error with a
suggestion, so you never have to guess whether a name landed:

```
unknown element <Rect>; did you mean <Rectangle>?
Rectangle has no property "radius"; did you mean "cornerRadiusTL"?
ArtboardProvider is abstract and cannot be authored as an element
```

Everything below is the opposite: every name is real, and the wiring is wrong.
Those are only visible through `rive inspect`.

## Enum values are the exception

Enums *are* validated. An unrecognised name is a real error listing the accepted
values. So prefer symbolic names over integers — it is the one place a typo gets
caught for you.

```xml
<LayoutComponentStyle layoutWidthScaleType="fill"/>   <!-- checked -->
<LayoutComponentStyle layoutWidthScaleType="1"/>      <!-- equivalent, unchecked -->
```

## Without a state machine, an artboard is half alive

In the CLI previewer and captures, an artboard with no `defaultStateMachineId`
still draws, and still plays a timeline — but it receives nothing. This one
omission breaks three unrelated features at once, and each looks like a
separate bug. (Runtimes that pick a default scene fall back to the first state
machine instead, so the same file can work elsewhere and not here, or the
reverse if the first machine is the wrong one.)

<!-- rml:skip -->
```xml
<Artboard viewModelId="0:40" name="Chart" id="0:2">
```

| | Without a state machine |
|---|---|
| **Data binds** | never applied. Bound text shows its authored literal, bound colours and sizes stay as drawn, and an `ArtboardComponentList` produces **no rows at all**. |
| **Pointer input** | never routed. Listeners are present in the tree and nothing reaches them, so no button, toggle or scroll view responds. |
| **Animations** | *these still play.* With no machine the previewer falls back to the first animation on the artboard, which is why a file can look alive and still be inert. |

That last row is what makes it hard to spot: something moves, so the file does
not look dead. Meanwhile the build succeeds, every bind path resolves, every
list item is in the tree, and every listener reads back correctly with `jq`.
`rive inspect` does warn with `no-default-state-machine` when the artboard has
an animation or a state machine, so check `problems` for it before anything
else.

**Detect:** a literal probe. Set a bound text run's authored `text` to something
unmistakable like `LITERAL-HERE` and render. If you see it, the bind is inert; if
you see the view model's value, it is live. An inert bind and a working one are
otherwise indistinguishable whenever the authored value resembles the data.

For input, click it — `--pointer=click@x,y` twice and compare the captures. See
[workflow.md](workflow.md#prove-the-interaction-works).

**Fix:** give the artboard a state machine. One layer with a single
`AnimationState` is enough; it does not have to animate anything.

```xml
<StateMachine name="SM" id="0:70">
    <StateMachineLayer name="L" id="0:71">
        <AnyState/>
        <ExitState/>
        <EntryState><StateTransition stateToId="0:73"/></EntryState>
        <AnimationState animationId="0:80" id="0:73"/>
    </StateMachineLayer>
</StateMachine>
```

## A clean build is not a correct file

The through-line for everything above. `--verify` exiting 0 means the project
compiles and the `.riv` it produces can be loaded — a real claim, and a
narrower one than it sounds.

What it does not mean:

- **that anything ran.** Scripts are type-checked, not executed. A converter
  with the wrong signature, or a `require` that cannot resolve at run time,
  compiles clean and then does nothing.
- **that the data arrived.** Binds resolve at build time; whether they ever
  fire is a run-time question. See
  [data.md](data.md#checking-your-work).
- **that it looks right.** Nothing in `--verify` or `inspect` renders a pixel,
  so neither catches an appearance bug.

So follow it with `rive inspect` and query for what you intended to build, then
with `--screenshot` and *look*. The three checks are cumulative, not
alternatives — see [workflow.md](workflow.md#what-each-one-actually-proves).

## Every layer needs an EntryState

Every `StateMachineLayer` needs an `EntryState`; missing one, the layer does
not import. `AnyState` and `ExitState` are added for you when omitted, and
written into your `.rml`, since older runtimes and the editor refuse a layer
without them.

An `EntryState` with no `StateTransition` inside means nothing ever starts.

## Bind the property that exists on the target

`width` lives on `Rectangle`, not on the enclosing `Shape`.

```xml
<Shape>
    <DataBindContext propertyKey="20"/>      <!-- Shape has no width; does nothing -->
    <Rectangle>
        <DataBindContext propertyKey="20"/>  <!-- correct -->
    </Rectangle>
</Shape>
```

**Detect:** `rive schema Shape` — if the property is not listed, the bind is dead.

## Dangling bind paths compile

A `sourcePathIds` naming a view model property that does not exist loads, runs,
and does nothing. This is common enough that real editor-exported files contain
it.

**Detect:** `rive inspect . --json` resolves the paths and flags unresolved ones.

## Bind paths you author here are absolute

`sourcePathIds` starts at a view model id and walks property ids. Bind the
deepest concrete property directly rather than expecting context to be
inherited.

**The format does have a relative form. This toolchain cannot author it**, and
the flag that turns it on is accepted without complaint, which is the trap.

Setting `nameBased="true"` on a `DataBindContext` changes what `sourcePathIds`
*means*: instead of a chain of ids it becomes a **single index** into a table of
names, which the runtime resolves against whatever instance is bound at the
time. That is the point of it — a component bound by name accepts any view model
with a matching shape, rather than the one view model it was authored against.
It is what the editor writes when a file is set to create relative binds, so
files that arrive from there are full of it.

The table it indexes is a `ManifestAsset`: a small binary blob — a list of
names, then a list of paths built from those name ids — that the editor's
exporter produces. Nothing in this toolchain generates one.

So a hand-written `nameBased="true"` builds clean and then does nothing: there
is no manifest, the index resolves to no path, and the bind is inert with the
target left at its authored value.

**And `problems` cannot help you here.** It walks `sourcePathIds` as ids whether
the flag is set or not, so on a name-based bind its verdict is meaningless in
both directions — a clean report on a bind that will never resolve, or an
`unresolved-bind-path` on one that would have.

**Detect:** the flag is visible even though the path is not.

```bash
rive inspect . --json | jq -c '[..|objects|select((.type//"")=="DataBindContext")
                               |select(((((.flags//0)/16)|floor)%2)==1)|.propertyKey]'
```

Anything it returns is a name-based bind. In a project you wrote, that is a
mistake — drop the flag and spell the path out. In one converted with
`rive create --from-rev` it came from the editor, and the manifest should have
come with it as a separate asset file beside your scene; that path is untested
here, so check the binds actually drive something before building on it.

## The keyframe type has to match the property

`KeyFrameDouble` only writes `double` properties. Point one at a colour, a
boolean or a reference and it builds clean, inspects clean, and never writes the
value — the property holds still while the timeline runs.

```xml
<KeyedProperty propertyKey="37">                  <!-- SolidColor.colorValue -->
    <KeyFrameDouble value="123" frame="0"/>       <!-- silently does nothing -->
    <KeyFrameColor value="FFE0573C" frame="0"/>   <!-- correct -->
</KeyedProperty>
```

**Detect:** `rive schema SolidColor` gives the property's type; match it against
the table in [format.md](format.md#the-keyframe-type-must-match-the-property).

## Rotation is radians, durations are frames or milliseconds

Three unit traps:

- `rotation` (propertyKey 15) is **radians**. A full turn is `6.2831855`. Writing
  `360` spins fifty-seven times.
- `LinearAnimation.duration` is **frames**, with `fps` defaulting to 60. Two
  seconds is `duration="120"`.
- `StateTransition.duration`, confusingly, is **milliseconds**.

## A style with no link does nothing

`LayoutComponentStyle` carries every flex property, but only applies if the
`LayoutComponent` names it:

```xml
<LayoutComponent styleId="0:11">          <!-- required -->
    <LayoutComponentStyle id="0:11"/>
</LayoutComponent>
```

Same shape for text: a `TextValueRun` with no `styleId`, or a `TextStylePaint`
with no `Fill` child, renders nothing.

## Script inputs match by name, silently

`ScriptInput*` objects bind to a script's `Input<T>` fields **by name**, checked
by neither side. A rename on either half falls back to the field's default.

```xml
<ScriptInputNumber propertyValue="3" name="speed"/>
```

```luau
type Spin = { speed: Input<number> }   -- must match exactly
```

**Nothing detects this.** `inspect` does not read Luau, so a `ScriptInput*`
whose name matches no field inspects completely clean — the script silently
keeps its default and the scene's value is discarded.

**Detect:** compare the two lists yourself.

```bash
grep -oh 'ScriptInput[A-Za-z]*[^>]*name="[^"]*"' *.rml | sed 's/.*name="//;s/"//' | sort -u > /tmp/scene-inputs
grep -oh '^\s*[a-zA-Z_]*\s*:\s*Input<' *.luau | sed 's/[[:space:]]*//;s/:.*//' | sort -u > /tmp/script-inputs
diff /tmp/scene-inputs /tmp/script-inputs
```

Anything that appears on one side only is a broken input.

## Every listener under the pointer fires

By default nothing blocks anything. A `StateMachineListenerSingle` fires
whenever its target's hit area contains the point, whatever is drawn on top of
it and whatever other listeners also matched.

Blocking exists but is opt-in. The runtime walks hit targets front-to-back
(reverse draw order, with artboard-wide targets first) and passes each one a
`canHit` flag that goes false once something returns an *opaque* hit — which
means a drawable with `isTargetOpaque="true"`, one carrying the opaque drawable
flag, or a scroll listener that has started scrolling. A plain shape on top is
not opaque, so it does not stop anything behind it. Two listeners writing the same
property will fight, and the one that runs last wins.

The expensive version of this is a control that is only dead in one spot. A menu
whose items collapse onto their launch button leaves every item's listener
stacked under it while closed — the button's own toggle runs, then six `Pick`
listeners undo it, and the result is a small dead zone in the middle of a
working button.

**A fully transparent fill is still hit-testable**, and so is a shape at opacity
`0`; neither is a way to switch a target off. `hidden` is not animatable, so
"un-clickable for part of a timeline" has no direct spelling — key the hit
shape's `x` far off-artboard with `hold` keyframes instead.

Detect: only by elimination. Remove listeners a group at a time until the
behaviour changes, or move the suspect targets far off-artboard and see whether
the control starts working.

## Keyboard events need a `FocusData` child

`keyboardEvent` / `textEvent` only run if the `ScriptedLayout` has a **direct**
`<FocusData/>` child and that node is focused. Script-only projects get that
child for free; RML does not. `--verify` and `inspect` stay green, pointer
still works, arrows do nothing.

```xml
<ScriptedLayout scriptAssetId="0:80" name="Game">
    <FocusData/>
</ScriptedLayout>
```

A state-machine keyboard listener uses the same rule: `targetId` must own a
`FocusData` child. The artboard can be the target if it owns one, as in the
`text_input` sample. `KeyboardInput.keyPhase` is a bitmask over the
phases of one keystroke (`1` down, `2` repeat, `4` up): `0` matches nothing,
and `7` fires on both the press and the release of a single keystroke — the
usual cause of a menu that skips two rows per arrow press. See
[format.md](format.md#listeners-two-spellings).

`FocusData` is not only this precondition. It is also how focus *moves*: give
each row one and the arrow keys can drive `FocusActionTraversal` instead of
your own index. See [focus.md](focus.md).

See [luau/protocols.md](luau/protocols.md#keyboard-and-text-input).

## `fill` on the cross axis of a `wrap` container collapses to zero

Cross-axis `fill` becomes `alignSelf: stretch`, but nothing sets
`alignContent: stretch` on the container — so a wrapped flex line is only as
tall as its tallest *item*, never as tall as the container. A row that wraps and
whose children fill the cross axis therefore lays out at zero height, and the
whole region disappears.

Clean `--verify`, empty `problems`, correct object count. A "responsive row of
cards" is the usual way in.

Detect: only a screenshot. Give one child a fixed or `hug` height to establish
the line, or size the container explicitly instead of relying on the children.

## `cubic` with no interpolator eases nothing

```xml
<KeyFrameDouble value="0" frame="0" interpolationType="cubic"/>
```

That builds clean and inspects clean. `cubic` says "use the curve nested inside
me" — with no `CubicEaseInterpolator` child there is no curve, and the segment
does not ease. Same for `elastic` without an `ElasticInterpolator`.

**Detect:** every `cubic` keyframe should have an interpolator child. Ask each
keyframe directly, rather than comparing totals:

```bash
rive inspect . --json | jq '[..|objects
  |select((.type//"")|startswith("KeyFrame"))
  |select(.enums.interpolationType=="cubic")
  |select(([.children[]?|select((.type//"")|test("Interpolator$"))]|length)==0)
  |{frame, type}]'
```

An empty result is what you want: every cubic keyframe has its curve.

Two things make this easy to get wrong. **`interpolationType` reads back as an
integer** — the decoded name is under `.enums`, so `.interpolationType=="cubic"`
matches nothing. And **`interpolatorId` is never emitted at all**: the curve
appears as a `children` entry, so any filter on that id reports every keyframe
as broken.

```json
{"type":"KeyFrameDouble","interpolationType":2,"frame":0,
 "enums":{"interpolationType":"cubic"},
 "children":[{"type":"CubicEaseInterpolator","x1":0,"y1":0,"x2":0.58,"y2":1}]}
```

See [easing.md](easing.md#custom-ease-curves).

## `Feather` in a `Fill` renders nothing without `fillRule="clockwise"`

The renderer only draws a feathered fill under the clockwise fill rule. With
the default `nonZero` the whole fill disappears, with a clean build. A `Stroke`
has no fill rule, so a feathered stroke always works. The editor sets the rule
when you add a feather to a fill; in RML you write it yourself. See
[drawing.md](drawing.md#effects-and-clipping).

## Hidden components affect runtime export

`hidden="true"` is folded into runtime drawable and path flags during export.
Descendants inherit hidden state unless a nearer `visibleOverride="true"`
breaks that inheritance. An object's own hidden bit still takes precedence
for that object. Locked and isolated editor state does not hide runtime art.

The `opaque` component bit does not control hit blocking; use
`isTargetOpaque` on the drawable, which exports the opaque drawable flag.

A hidden clipping source produces an empty mask. Keep mask shapes shown and
use transparent fills (or no paints) when they must not draw themselves.
Write flag bits as boolean attributes rather than a raw `flags` integer.

## A capture with no `--advance` is the pose before anything advanced

The state machine has not run before the first advance, so the capture is
the authored artboard pose rather than the animation's opening frame. It looks like a
perfectly valid frame, which is what makes it costly: use it as the wrap point
of a loop and every cycle flashes the rest pose.

Detect: capture frame 0 and frame 2 and compare. If frame 0 is much further from
frame 2 than frame 2 is from frame 4, you are looking at the rest pose. Start
previews at `--advance=1`.

## Dropping `resize`'s `scale` renders your effect at half resolution

`resize(self, size, scale)` has a third parameter — the surface's device pixels
per point, and it is easy to leave off.

It costs nothing while you draw through the `Renderer`. It costs you half your
resolution the moment you size a `Canvas`, `GPUCanvas` or `GPUTexture` yourself:
size it in points and the runtime upscales your surface 2x on a Retina display,
while the text and shapes beside it rasterise at full device resolution. The
result reads as "my effect looks pixelated but the rest of the screen is fine".

```luau
-- wrong: a 942x566 canvas stretched over an 1880x1130 raster
self.canvas = context:canvas({ width = size.x, height = size.y })

-- right
self.canvas = context:canvas({ width = size.x * scale, height = size.y * scale })
```

Detect: **not with `--screenshot`.** The headless capture always runs at `@1x`
and passes `scale = 1`, so the mistake is invisible to it by construction — this
is the one class of defect the render check cannot see. Open the live window and
read the viewport line (`viewport 1880x1130 @2x`), or `print` the scale you were
handed and compare it with the size of the surface you allocated.

## `--data` is silently overridden by a two-way bind

If a property is also driven by a `DataBind` with `twoWay="true"`, that bind
wins on the first frame and `--data` has no visible effect — while the log still
prints `data: <path> = <value>`, because the write did happen. The documented
"change the data and see the picture change" check then reads as "nothing is
bound" when the truth is the opposite.

Detect: if `--data` logs the assignment but nothing moves, look for a two-way
bind on that property before concluding the binding is broken.

**The fix is `sourceToTargetRunsFirst="true"`** on the `DataBindContext`, which
runs the read before the write and lets an externally-set value survive the
frame. It is one of three bits on `DataBind.flags`, visible only through
`rive schema DataBindContext --all`. The other pattern that works is to point
the pointer at its own `*Base` property and derive the live value from it, so
the host and the user drive different properties and never fight.

## Probe a suspect bind with a number, not a string

When a bind produces nothing, the hard part is telling *which* nothing you have:
the bind never resolved, or it resolved and delivered a value the target could
not use. On a text run those look identical — both leave the authored text on
screen.

Point the same source and converter at a **numeric** property you can see, such
as a shape's `opacity`, and the ambiguity disappears. A number target renders
whatever value actually reached it, so:

- the art changes to something *wrong* → the bind is live and the value arrived
  unconverted, so the converter is the problem
- the art does not change at all → nothing arrived, so the path or the target
  property is the problem

Choose the numbers so the two outcomes cannot be confused. Authoring
`opacity="0.5"` and expecting `0.25` means "unchanged" (0.5), "converted" (0.25)
and "raw value clamped" (1.0) are three distinct pictures rather than two
similar ones.

This is the companion to the literal probe in
[data.md](data.md#checking-your-work): the literal tells you a text bind is
inert, and this tells you why.

## Fields in `inspect` you did not author

Verifying by querying the tree means reading output full of properties you never
set, and two of them look like your work failed when it did not:

```json
{"type": "SolidColor", "colorValue": "FF1D1D1D",
 "colorRed": 0, "colorGreen": 0, "colorBlue": 0, "colorAlpha": 0}
```

`colorRed`/`Green`/`Blue`/`Alpha` are **passthrough views** onto `colorValue`,
provided so data binding can drive one channel. They read `0` unless something
sets them. `colorValue` is the authoritative one — if it is right, your colour
is right.

Likewise every `Fill` and `Stroke` shows `blendModeValue: 127`, which is the
"inherit from the shape" sentinel rather than a blend mode. See
[transforms.md](transforms.md#fills-and-strokes-have-a-separate-one).

Properties marked `D` by `rive schema` are computed rather than authored, and
`computed*` values are `0` until something lays the scene out — so they are not
a way to check the size of what you built.

## A listener's input type and inputs must be nested, not referenced

A `ListenerInputType*` belongs inside its `StateMachineListener`, and a
`KeyboardInput`/`GamepadInput`/`SemanticInput` inside its input type; the
nesting is the link, and there is no attribute to spell it otherwise:

```xml
<StateMachineListener targetId="0:2" name="Bound">
    <ListenerInputTypeViewModel viewModelPathIds="0:14-0:24" listenerTypeValue="11"/>
    <ListenerViewModelChange bindablePropertyId="0:60"/>
</StateMachineListener>
```

The two halves differ in how much slack they get. A root-level
`ListenerInputType*` with a `listenerId` pointing back is a **second valid
spelling**, and it is what older files and editor-exported rml use. A
root-level or misplaced `KeyboardInput`/`GamepadInput`/`SemanticInput` is
**not**: nothing links it, it never reaches the `.riv`, and the input type it
meant to narrow is left with no filters, which matches **every** key.

That case is a build error naming the element and the parent it cannot sit
under.

Same rule for script inputs: a `ScriptInput*` is an input by being a child of
its `Scripted*` object, see
[luau/protocols.md](luau/protocols.md#an-input-is-a-custom-property). If a
construct is not in the tables in [format.md](format.md), assume it needs an
explicit id.

## Names are checked by the editor, not the CLI

View model, property and enum names are validated only when the file is opened
in the editor, so `charge_state`, `battery level` and `type` all build clean
and surface later as Problems for whoever opens the `.rev`. The rules are in
[data.md](data.md#naming).

**Detect:** the names are in the tree, so check them yourself.

```bash
rive inspect . --json | jq -r '[..|objects|select((.type//"")|startswith("ViewModelProperty"))|.name]
  | .[]
  | select((test("^_*[a-z][a-zA-Z0-9]*$")|not)
           or IN("and","break","do","else","elseif","end","false","for","function",
                 "goto","if","in","local","nil","not","or","repeat","return","then",
                 "true","type","typeof","until","while"))'
```

Anything printed is off-convention or a reserved word. Swap the pattern for
`^_*[a-z][a-z0-9]*(_[a-z0-9]+)*$` if your workspace has chosen snake_case.

## A text style with no `familyName` and `styleName` opens unlabelled in the editor

The editor's Font and Weight dropdowns are filled from two strings on
`TextStylePaint`, not from the font asset. A style that names only the asset
and the axis renders correctly everywhere and opens with both dropdowns
showing `-`:

```xml
<TextStylePaint fontSize="24" fontAssetId="0:30" name="Heading" id="0:21">
    <Fill name="Fill"><SolidColor colorValue="FFFFFFFF" name="C"/></Fill>
    <TextStyleAxis tag="2003265652" axisValue="700" name="Weight"/>
</TextStylePaint>
```

`--verify`, `problems` and `--screenshot` are all clean — the CLI never reads
the two attributes — so this surfaces after handoff, on every text element in
the file at once. See [text.md](text.md#name-the-face-not-just-the-file).

**Detect:** in the markup, not the tree. Both attributes are editor-only, so
`rive inspect` drops them and cannot tell a labelled style from a bare one.
Grep the source instead:

```bash
grep -rnE '<TextStyle(Paint)?[[:space:]/>]' --include='*.rml' . |
    grep -vE '(familyName="[^"]+".*styleName="[^"]+"|styleName="[^"]+".*familyName="[^"]+")'
```

Anything printed is a style the editor will show as `-`. This assumes each
`<TextStylePaint` opening tag sits on one line, which is how the editor and
`create --from-rev` write them.

**Fix:** add `familyName="Inter" styleName="Bold"` on the style, matching
the family declared by the font and the named instance selected by its axes.
Use `styleName="Custom"` when the axis coordinates match no named instance.

## Unpositioned states and artboards all land on the same point

States and artboards carry an `x`/`y` that only the editor reads: the node's
place in the state graph, or the artboard's place on the Stage. Both default to
`0`, so a hand-written file opens in the editor as a stack of overlapping nodes.
Runtime behaviour is unaffected.

Give each a distinct position, roughly 100–400 units apart:

```xml
<AnyState x="400" y="0"/>
<ExitState x="480" y="0"/>
<EntryState x="0" y="16"><StateTransition stateToId="0:12"/></EntryState>
<AnimationState animationId="0:20" x="160" y="0" id="0:12"/>
```

**A distinct position is not enough if they share a row.** The editor draws
each transition as a straight line beneath the states, so on a single row a
transition that skips a state, or runs back along the row, disappears behind
the states in between. A straight chain can stay on a row; otherwise move the
states such a transition would pass through, or one of its ends, up or down by
100 or so:

```xml
<EntryState x="0" y="0"><StateTransition stateToId="0:10"/></EntryState>
<AnimationState animationId="0:20" x="160" y="0" id="0:10">    <!-- Hidden -->
    <StateTransition stateToId="0:11"/>
</AnimationState>
<AnimationState animationId="0:21" x="320" y="-100" id="0:11"> <!-- Enter -->
    <StateTransition stateToId="0:12"/>
    <StateTransition stateToId="0:13"/>
</AnimationState>
<AnimationState animationId="0:22" x="520" y="-100" id="0:12"> <!-- Hold -->
    <StateTransition stateToId="0:13"/>
</AnimationState>
<AnimationState animationId="0:23" x="480" y="100" id="0:13">  <!-- Out -->
    <StateTransition stateToId="0:10"/>
</AnimationState>
```

**Detect:** `rive inspect` warns with `states-overlap` and `artboards-overlap`.
`states-overlap` compares exact positions only, so a state covering a
transition is not reported.
