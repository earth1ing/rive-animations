# Easing and blending

## Interpolation

Every keyframe decides how the value leaves it and travels to the **next**
keyframe. `interpolationType` picks the kind:

| Value | Behaviour |
|---|---|
| `hold` | no interpolation — snap at this keyframe |
| `linear` | constant rate |
| `cubic` | a bezier ease curve, defined by a nested interpolator |
| `cubicValue` | a bezier applied to the value rather than time |
| `elastic` | overshoot and settle, defined by a nested interpolator |

`hold` is the default, so a keyframe with no `interpolationType` snaps rather
than animating — the most common reason an animation looks like a slideshow.

**The direction matters.** Each segment is governed by the keyframe at its
*start*. So the ease on frame 0 shapes the motion from frame 0 to frame 60, and
the `interpolationType` on the **last** keyframe is never read — there is no
segment after it. Putting your ease on the final keyframe and leaving the first
at the default is the usual way to get an animation that snaps instead of
easing.

Everything below uses `KeyFrameDouble`, because eases only mean something for
numbers. Colours, booleans and references have their own keyframe elements and
mostly want `hold`; see
[format.md](format.md#the-keyframe-type-must-match-the-property).

### Custom ease curves

`cubic` needs a curve, and the curve is a **child of the keyframe**:

```xml
<KeyedProperty propertyKey="15">
    <KeyFrameDouble value="0" frame="0" interpolationType="cubic">
        <CubicEaseInterpolator x1="0.42" y1="0" x2="0.58" y2="1"/>
    </KeyFrameDouble>
    <KeyFrameDouble value="6.2831855" frame="120" interpolationType="linear"/>
</KeyedProperty>
```

This is one of the inverted references: the keyframe's `interpolatorId` is set
from the nested child, not written by hand. See
[format.md](format.md#the-parent-references-its-child).

**Do not try to verify that id** — `inspect` never emits it. The curve shows up
as a `children` entry on the keyframe instead, so a check for a null
`interpolatorId` flags every keyframe, attached or not. See
[gotchas.md](gotchas.md#cubic-with-no-interpolator-eases-nothing) for the query
that works.

`x1`/`y1` and `x2`/`y2` are the two bezier control points, the same numbers CSS
`cubic-bezier()` takes. The defaults `(0.42, 0)` and `(0.58, 1)` are ease-in-out.
Familiar equivalents:

| Curve | `x1 y1 x2 y2` |
|---|---|
| ease | `0.25 0.1 0.25 1` |
| ease-in | `0.42 0 1 1` |
| ease-out | `0 0 0.58 1` |
| ease-in-out | `0.42 0 0.58 1` |

Each keyframe carries its own curve, so easing is per-segment rather than
per-animation.

### `cubicValue`: a curve through values, not time

`interpolationType` accepts `cubicValue` as well as `cubic`, and the two are not
variants of one thing. They take the same four numbers and read them completely
differently.

**`cubic`** with a `CubicEaseInterpolator` shapes **time**. The curve is
normalized: it maps progress `0`–`1` through the bezier, and the value is then a
plain blend between the two keyframes. `y1`/`y2` are heights in that `0`–`1`
space, so the result stays between the keyframed values.

**`cubicValue`** with a `CubicValueInterpolator` shapes the **value**. It builds
a bezier whose four control points are `[from, y1, y2, to]` — so `y1` and `y2`
are in **the property's own units**, not fractions:

```xml
<KeyedProperty propertyKey="13">
    <KeyFrameDouble value="0" frame="0" interpolationType="cubicValue">
        <CubicValueInterpolator x1="0.42" y1="250" x2="0.58" y2="-50"/>
    </KeyFrameDouble>
    <KeyFrameDouble value="100" frame="60" interpolationType="linear"/>
</KeyedProperty>
```

That moves `x` from `0` to `100` while swinging out to `250` and dipping to
`-50` on the way. `x1`/`x2` still shape the timing; `y1`/`y2` are now positions.

It is the graph-editor curve — free handles on the value axis — where `cubic` is
the CSS easing curve. Reach for it when the motion has to leave the range
between its keyframes, and for anything else prefer `cubic`, whose numbers are
portable between properties.

**The nested type is what decides**, not the enum. At runtime
`interpolationType` is only tested for `hold` — any other value means "use the
interpolator you were given", and the object nested in the keyframe supplies the
behaviour. So a `CubicValueInterpolator` under `interpolationType="cubic"` still
interpolates through values.

Set them consistently anyway. The enum is what the editor reads to decide which
curve UI to show, so a mismatched pair round-trips into a file whose editing
controls disagree with what it renders — and nothing on either side reports it.

### Elastic

`elastic` overshoots and settles:

```xml
<KeyFrameDouble value="1.0" frame="30" interpolationType="elastic">
    <ElasticInterpolator easingValue="1" amplitude="1" period="0.4"/>
</KeyFrameDouble>
```

`amplitude` is the overshoot as a fraction of the change; `period` is the
oscillation length as a fraction of the segment duration. Smaller periods
wobble faster.

### Elsewhere

The same interpolators attach to anything that eases, always as a nested child:

- `StateTransition` — smooths the blend between states
- `LayoutComponentStyle` — eases layout changes
- `DataConverterInterpolator` — shapes a value inside a data bind

## Looping

`loopValue` on a `LinearAnimation` decides what happens when it reaches the end:

| Value | Behaviour |
|---|---|
| `oneShot` | plays once and stops — **the default** |
| `loop` | jumps back to the start and repeats |
| `pingPong` | plays forwards, then backwards, forever |

The default catches people out. An animation with no `loopValue` runs once and
holds its final frame, so a "continuous" spin or pulse needs `loopValue="loop"`
written explicitly:

```xml
<LinearAnimation loopValue="loop" fps="60" duration="120" name="Spin" id="0:6"/>
```

**Mind the seam on `loop`.** The jump from the last frame back to the first is
instant, so unless those two frames hold the same value the animation visibly
pops once per cycle. A rotation from `0` to `6.2831855` is seamless because the
two are the same angle; an opacity from `1` to `0.3` is not, and will snap back
to full brightness at the boundary.

Two ways out: give the timeline a symmetric third keyframe returning to the
starting value, or use `pingPong`, which reverses instead of jumping and is
therefore seamless by construction. For a there-and-back pulse, `pingPong` with
two keyframes is the shortest correct answer.

### Looking at a loop

A well-built loop is at its resting value on its first frame — that is what
makes the seam invisible. So a correct animation and a completely broken one
produce the same first frame, and one screenshot tells you nothing.

`--advance=<N>` steps the file at 60fps before capturing. Take three, starting
at `1` (with no `--advance` the machine has not run at all; see
[gotchas.md](gotchas.md#a-capture-with-no---advance-is-the-pose-before-anything-advanced)):

```bash
rive <dir> --screenshot=f1.png  --advance=1     # start of the loop
rive <dir> --screenshot=f20.png --advance=20    # mid-cycle
rive <dir> --screenshot=f45.png --advance=45    # further round
```

If those three are identical, nothing is animating, whatever the keyframes say.

## Blend states

An `AnimationState` plays one animation. A **blend state** mixes several at
once, weighted by a number — a walk/run cycle driven by speed, or a face that
follows a cursor.

`BlendState1DViewModel` blends along a single axis read from a view model
number, wired by a nested `BindableProperty*`:

```xml
<BlendState1DViewModel id="0:70">
    <BindablePropertyNumber>
        <DataBindContext sourcePathIds="0:40-0:45" propertyKey="636"/>
    </BindablePropertyNumber>
    <BlendAnimation1D animationId="0:71" value="0"/>
    <BlendAnimation1D animationId="0:72" value="50"/>
    <BlendAnimation1D animationId="0:73" value="100"/>
    <BlendStateTransition stateToId="0:80"/>
</BlendState1DViewModel>
```

Each `BlendAnimation1D` pins an animation to a point on the axis with `value`.
At `0` the first plays alone; at `75` the runtime mixes the second and third.
Older files use `BlendState1DInput` with an `inputId` naming a deprecated
`StateMachineNumber`; the children are the same.

Three things about blend states are easy to get wrong and are not reported:

- **Weights run 0-100, not 0-1.** Authoring an axis over 0-1 collapses every
  pose onto the first one.
- **`BlendAnimation1D` children must be in ascending `value` order.** The
  runtime binary-searches them and does not check, so an out-of-order child
  silently blends the wrong pair.
- **Key every blended property in every pose.** A property keyed in one pose and
  absent from another has nothing to mix toward, and the result is a pose that
  jumps rather than blends.

For a blend to look smooth you usually want the axis eased rather than the
poses. A **`DataConverterRangeMapper` can carry an interpolator**, so the
easing can live on the value feeding the blend, and it chains with other
converters through a `DataConverterGroup`.

States carry no `name` — unlike most of the format, they are identified only by
id, so `name` on any state or blend state is a build error. `reset` is a flag
bit on the state (`reset="true"`), restarting its animations on entry.

A blend state sits in a `StateMachineLayer` exactly where an `AnimationState`
would, and takes transitions the same way.

`BlendStateDirect` is the other kind: each animation gets its own input
controlling its weight independently, rather than positions on one axis.

### Blending per animation

In a `BlendStateDirect`, `BlendAnimationDirect`
picks where its weight comes from with `blendSource`: **`0`** the `inputId`,
**`1`** its own `mixValue`, **`2`** a nested `BindableProperty*`. It is a bare
uint with no symbolic names, and it defaults to `0` — so nesting a bindable
without setting `blendSource="2"` leaves the animation reading an input that is
probably not there, and the weight stays put.

`BindableProperty*` is the shared adapter between view model data and a state
machine, and choosing the right one matters everywhere it appears. The types,
their `propertyKey`s and the pairing rules are in
[state-machines.md](state-machines.md#bindable-properties-and-matching-the-pair).

## Joysticks

A blend state mixes animations by weight. A **`Joystick`** does something
different with a similar goal: it *scrubs* two timelines from an `x`/`y` pair,
so one 2-D value poses the artboard. It is how a character looks at the cursor,
or a face is rigged to a single control.

```xml
<Joystick posX="120" posY="200" width="120" height="120"
          xId="0:30" yId="0:31" handleSourceId="0:25" name="Look" id="0:26"/>
```

`xId` and `yId` name two `LinearAnimation`s in the same artboard. **`x` and `y`
run −1 to 1**, and each maps across its animation's whole duration: `-1` is the
first frame, `0` the middle, `1` the last. So the two timelines are authored as
*ranges* — leftmost pose to rightmost pose — not as motion.

Nothing plays them. The joystick applies the animations directly at the frame
its value selects, so this works with no state machine driving it and holds
whatever pose the value implies. `x` and `y` are animatable and bindable, so a
view model number can pose the rig.

**A `handleSource` inverts the control.** Point `handleSourceId` at any
transform component and the joystick stops being driven and starts *reading*:
each frame it measures where that component sits inside its own
`width`/`height` box (placed by `posX`/`posY`, pivoted by `originX`/`originY`)
and writes the resulting −1..1 factors into `x`/`y`. Pair it with a drag
listener on the same shape and you have a knob a user can move:

```xml
<StateMachineListenerSingle targetId="0:25" listenerTypeValue="drag" name="Drag" id="0:50">
    <ListenerAlignTarget targetId="0:25" preserveOffset="true"/>
</StateMachineListenerSingle>
```

The listener moves the handle, the joystick reads it, the two timelines pose the
art — see [state-machines.md](state-machines.md#dragging-something).

Inside that box, **`-1` is the left edge and the *top* edge** — the factors are
measured in artboard space, where `y` grows downward. Since `-1` is also the
first frame, a `yId` timeline should be authored top-pose first: frame 0 is the
handle pushed *up*. Authoring it the other way round is what `invertY` is for.

Once `handleSourceId` is set, **`x` and `y` become outputs**. The joystick
recomputes and writes both every time the handle's transform is dirty, so a
bind or a keyframe on them is overwritten before it can be seen. Drive the
handle's position instead — that is the input now. Bind `x`/`y` directly only
on a joystick with no handle.

`invertX` and `invertY` are flag bits (`invertX="true"`) negating the value
before it maps, for when a timeline was authored the other way round.

A joystick also drives any `NestedRemapAnimation` keyed inside the animations it
applies, so one control can scrub a nested artboard's timeline too — see
[format.md](format.md#driving-the-childs-timelines).
