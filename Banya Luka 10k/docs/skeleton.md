# A complete file, annotated

The smallest RML document that produces a moving, self-playing scene. Every line
is load-bearing; this section explains which and why.

## The project

Two files:

```
myproject/
  rive.yaml
  scene.rml
```

```yaml
name: myproject
```

`name` is the only required key. See
[project/rive-yaml.md](project/rive-yaml.md) for the rest.

## The scene

```xml
<Rive version="1" kind="fragment">
    <Artboard defaultStateMachineId="0:7" styleId="0:5" width="500" height="500" name="Artboard" id="0:2">
        <LayoutComponentStyle name="Artboard Style" id="0:5"/>

        <Fill name="Background">
            <SolidColor colorValue="FF1D1D1D" name="Color"/>
        </Fill>

        <Shape x="250" y="250" name="Triangle" id="0:14">
            <Triangle originX="0.5" originY="0.5" width="220" height="200" name="Path"/>
            <Fill name="Fill">
                <SolidColor colorValue="FF57A5E0" name="Color"/>
            </Fill>
        </Shape>

        <StateMachine name="State Machine 1" id="0:7">
            <StateMachineLayer name="Layer 1" id="0:8">
                <AnyState x="200" y="-120"/>
                <ExitState x="400" y="-120"/>
                <EntryState>
                    <StateTransition stateToId="0:12"/>
                </EntryState>
                <AnimationState x="200" animationId="0:6" id="0:12"/>
            </StateMachineLayer>
        </StateMachine>

        <LinearAnimation loopValue="loop" duration="120" name="Spin" id="0:6">
            <KeyedObject objectId="0:14">
                <KeyedProperty propertyKey="15">
                    <KeyFrameDouble value="0" interpolationType="linear"/>
                    <KeyFrameDouble value="6.2831855" interpolationType="linear" frame="120"/>
                </KeyedProperty>
            </KeyedObject>
        </LinearAnimation>
    </Artboard>
</Rive>
```

## Line by line

**`<Rive version="1" kind="fragment">`** — the root every file has. `version`
is the format version; `kind` is `fragment` for a project file.

**`<Artboard ... id="0:2">`** — the scene container. `defaultStateMachineId`
points at the state machine to auto-play. Without it the CLI previewer plays
the first animation and runs no data binds or listeners; other runtimes may
fall back to the first state machine instead.

**`<Fill>` directly under the artboard** — the background. An artboard can carry
paint like any shape.

**`<Shape>` wraps `<Triangle>`** — geometry never stands alone. `Shape` holds
position and transform; the path child holds size. This split matters when
binding: `width` lives on `Triangle`, not on `Shape`.

`originX`/`originY` of `0.5` centre the geometry on the shape's origin, so
rotation spins about the middle rather than a corner.

**`<SolidColor>` inside `<Fill>`** — a fill with no paint child draws nothing.

**`id="0:14"` on the Shape** — needed only because the animation refers to it.
Elements nothing points at can omit `id` entirely; `Fill`, `SolidColor` and the
`Triangle` here have none.

**`<AnyState/>`, `<ExitState/>`, `<EntryState>`** — the `EntryState` is required;
a layer without one does not import. `AnyState` and `ExitState` are added for
you when omitted, so writing them here is optional.

**`<StateTransition stateToId="0:12"/>` inside `<EntryState>`** — what makes the
machine actually enter the animation state on load.

**`<AnimationState animationId="0:6">`** — plays the named animation.

**`<KeyedObject objectId="0:14">`** — one of the few references you write by
hand. Animations live beside the objects they animate, so the link is explicit.

**`propertyKey="15"`** — rotation. These are numbers, never names. Look them up
with `rive schema Shape --animatable`.

**`value="6.2831855"`** — radians, not degrees. One full turn is 2π.

**`duration="120"`** — frames. `fps` defaults to 60, so this is two seconds.

**No `Backboard`.** The default artboard and the publish settings are
project configuration in `rive.yaml`, not scene content; with one artboard and
no `main` key it is the default. See [format.md](format.md).

## Check it

```bash
rive . --once
rive inspect . --json | jq '.problems, [..|objects|select(.type=="KeyedProperty")|.propertyKey]'
```

Expect `[]` and `[15]`. An empty problems list plus the property key you meant
to animate is the minimum bar for "this worked".

## Growing it

- More shapes: add `<Shape>` siblings. The first one declared paints on top.
- Text: needs a `<FontAsset>` root element, a `<TextStylePaint>` and a
  `<TextValueRun>`.
- Layout: wrap children in `<LayoutComponent>` with a `<LayoutComponentStyle>`,
  and give the artboard a `styleId` and a `<LayoutComponentStyle>` of its own —
  an artboard is a layout box too, and the editor gives every one a style.
  Layout boxes block out areas; the `Shape`, `Text` or `Image` inside one gets a
  nested `<LayoutParticipant>` to size and position it, not a wrapper box of its
  own. See
  [layout.md](layout.md).
- Data: add a `<ViewModel>` root element and bind with `<DataBindContext>`.

Each is covered in [format.md](format.md).
