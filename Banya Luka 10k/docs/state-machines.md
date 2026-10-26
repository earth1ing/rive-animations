# State machines

A `LinearAnimation` is a fixed timeline: it plays from frame 0 to the end. A
**state machine** decides *which* timeline plays and *when* it changes, driven
by data, pointer gestures or time. It is what makes a Rive file interactive
rather than a video.

Anything that reacts — a button that responds to hover, a toggle, a character
that idles until told to walk — is a state machine.

> **Drive it with view model data, not state machine inputs.**
> `StateMachineBool`, `StateMachineNumber` and `StateMachineTrigger` are the
> older mechanism and are **deprecated**. They still load and still work, so you
> will meet them in existing files and they are documented below — but do not
> reach for them in something new.
>
> Everything they do, a view model property does: a listener writes a property
> with `ListenerViewModelChange`, and a transition reads it with
> `TransitionViewModelCondition`. The same property is then also bindable into
> colours, sizes and text, which an input never was. See
> [data.md](data.md).
>
> **Watch components.** A plain nested artboard inherits its parent's data
> context rather than binding its own `viewModelInstanceId`, so a
> view-model-driven machine works while the component artboard is the root and
> never reads true once it is placed. Make the placement own its data with
> `isStateful="true"` — see
> [data.md](data.md#stateful-components-per-instance-data).

## The shape of one

```xml
<Artboard defaultStateMachineId="0:7" width="200" height="80" name="Button" id="0:2">
    <StateMachine name="State Machine 1" id="0:7">
        <StateMachineLayer name="Layer 1" id="0:8">
            <AnyState x="200" y="-120"/>
            <ExitState x="400" y="-120"/>
            <EntryState>
                <StateTransition stateToId="0:12"/>
            </EntryState>

            <AnimationState x="200" animationId="0:20" id="0:12"/>
        </StateMachineLayer>
    </StateMachine>

    <LinearAnimation duration="30" name="Idle" id="0:20"/>
</Artboard>
```

Four levels, each mandatory:

- **`StateMachine`** — named by the artboard's `defaultStateMachineId` so it
  plays on load. Without that link the CLI previewer never runs the machine —
  and the artboard receives no data and no pointer input there either, however
  complete the rest of the file is
  ([why](gotchas.md#without-a-state-machine-an-artboard-is-half-alive)).
- **`StateMachineLayer`** — holds the states. A machine can have several.
- **`EntryState`** — every layer needs one; a layer without it does not
  import.
- **`AnyState`, `ExitState`** — added for you when a layer omits them, and
  written into your `.rml`, since older runtimes and the editor refuse a layer
  without both.
- **`AnimationState`** — a state that plays a timeline, named by `animationId`.

**Declare the `StateMachine` before any `LinearAnimation`.** The editor's
Animations list follows source order, and Animate mode opens whatever is on
top, so a timeline declared first opens instead of the machine.

The `EntryState` decides where the machine starts, via a transition to the first
real state. A layer whose entry has no transition starts nowhere and does
nothing.

Every state, `AnyState` and `ExitState` included, carries an `x` and `y`:
its position on the editor's state machine graph. The CLI never draws the
graph, so a layer without them builds and runs, and opens in the editor with
every state stacked on the entry. Editor exports put animation states on a
row from `x="160"` and the any and exit states further along it; `inspect`
reports a layer whose states share a position as `states-overlap`. A row only
suits a straight chain: a transition that skips a state, or runs back along
the row, is drawn behind the states in between
([gotchas.md](gotchas.md#unpositioned-states-and-artboards-all-land-on-the-same-point)).

## States

| State | Does |
|---|---|
| `EntryState` | starting point; its transition picks the first state |
| `AnimationState` | plays one `LinearAnimation` |
| `BlendState1DInput` / `BlendState1DViewModel` / `BlendStateDirect` | mixes several animations at once |
| `AnyState` | source for transitions that can fire from *any* state |
| `ExitState` | terminates the layer, for nested machines |

`AnimationState` takes `speed` (`1` is normal, `-1` plays backwards) and two
flag bits written as their own attributes:

```xml
<AnimationState animationId="0:20" speed="0.5" reset="true" id="0:12"/>
```

`reset="true"` restarts the animation each time the state is entered rather than
resuming it. `random="true"` is for random selection among outgoing transitions.

States carry **no `name`** — unlike most of the format they are identified only
by id, and `name` on a state is a build error.

Blend states are covered in [easing.md](easing.md#blend-states).

**Give every state an `x`/`y`.** Left unset they default to `(0, 0)`, so every
state in a layer stacks on the same point in the editor's graph — the one
place states have nothing else to be told apart by. See
[gotchas.md](gotchas.md#unpositioned-states-and-artboards-all-land-on-the-same-point).

## Transitions

A transition is a **child of the state it leaves**, and `stateToId` names where
it goes:

```xml
<AnimationState animationId="0:20" id="0:12">
    <StateTransition stateToId="0:13" duration="150"/>
</AnimationState>

<AnimationState animationId="0:21" id="0:13"/>
```

> `rive schema StateTransition` describes `stateToId` as the state the
> transition "originates from". That description is wrong — it is the
> destination. The origin is whichever state the transition is nested in.

`duration` is the blend time in **milliseconds** — not frames, unlike
everything else in the format. `interpolationType` and a nested interpolator
shape that blend the same way they do on a keyframe, see [easing.md](easing.md).

A transition with no conditions fires as soon as it is allowed to. That is the
common case: most transitions in real files carry no conditions and are gated by
exit time instead.

### Exit time

By default a transition can interrupt its animation part-way. `enableExitTime`
makes it wait:

```xml
<StateTransition stateToId="0:13"
                 enableExitTime="true" exitTimeIsPercetange="true" exitTime="100"/>
```

That reads: do not leave this state until the animation has played 100% of the
way through. It is how you chain timelines into a sequence.

**`exitTimeIsPercetange` is misspelled in the format itself.** The correct
spelling is not accepted — write the typo. With the flag off, `exitTime` is in
milliseconds instead.

### The other flags

Each is its own boolean attribute on `StateTransition`:

| Flag | Effect |
|---|---|
| `disabled` | transition is ignored |
| `enableExitTime` | honour `exitTime` |
| `exitTimeIsPercetange` | `exitTime` is 0–100% rather than ms |
| `durationIsPercentage` | `duration` is 0–100% rather than ms |
| `pauseOnExit` | hold the outgoing animation where it stopped |
| `enableEarlyExit` | allow leaving before the blend finishes |

`randomWeight` biases selection when several transitions are eligible and the
source state is `random="true"`.

## Conditions

A condition is a child of the transition. All conditions on a transition must
pass for it to fire.

### From view model data

`TransitionViewModelCondition` compares two **comparators**, nested as children
in order — left first, then right:

```xml
<StateTransition stateToId="0:13" duration="150">
    <TransitionViewModelCondition opValue="equal">
        <TransitionPropertyViewModelComparator>
            <BindablePropertyBoolean>
                <DataBindContext sourcePathIds="0:40-0:45" propertyKey="634"/>
            </BindablePropertyBoolean>
        </TransitionPropertyViewModelComparator>
        <TransitionValueBooleanComparator value="true"/>
    </TransitionViewModelCondition>
</StateTransition>
```

Read outwards: the left side reads a view model property through a bind, the
right side is the literal to compare it with, and `opValue` is the operator.

`opValue` takes the same operator names as an input condition — `equal`,
`notEqual`, `lessThan`, `lessThanOrEqual`, `greaterThan`, `greaterThanOrEqual`.
`equal` is the default, so an equality test can leave it off entirely, which is
what editor-exported files do.

The two families:

- **`TransitionProperty*Comparator`** reads a live value.
  `TransitionPropertyViewModelComparator` wraps a `BindableProperty*` holding a
  `DataBindContext`. `TransitionPropertyArtboardComparator` reads artboard
  state, paired with a `TransitionArtboardCondition`.
- **`TransitionValue*Comparator`** is a literal: `...Boolean`, `...Number`,
  `...String`, `...Color`, `...Enum`, `...Trigger`, `...Asset`, `...Artboard`.

`leftComparatorId` and `rightComparatorId` are set by nesting — do not write
them. Neither `bindablePropertyId` nor an `id` on the `BindableProperty` appears
in real files.

This is the most involved construct in the format, and it is worth the verbosity:
the property it reads is the same one you bind into colours, sizes and text, so a
button's pressed state and its pressed appearance come from one source.

#### Bindable properties, and matching the pair

A `BindableProperty*` is the adapter between a view model and something in a
state machine: it holds the bind, and whatever consumes it reads a typed value
out. Three things take one, always by nesting —
`TransitionPropertyViewModelComparator` here, `ListenerViewModelChange` for a
[listener write](data.md#writing-a-value-back-from-a-listener), and the blend
states in [easing.md](easing.md#blend-states).

**Pick the type from the view model property**, and write the matching
`propertyKey` on the nested `DataBindContext` — it targets the bindable's own
`propertyValue`:

| Bindable | `propertyKey` | Literal it compares against |
|---|---|---|
| `BindablePropertyNumber` | `636` | `TransitionValueNumberComparator` |
| `BindablePropertyInteger` | `686` | `TransitionValueNumberComparator` |
| `BindablePropertyBoolean` | `634` | `TransitionValueBooleanComparator` |
| `BindablePropertyString` | `635` | `TransitionValueStringComparator` |
| `BindablePropertyColor` | `638` | `TransitionValueColorComparator` |
| `BindablePropertyEnum` | `637` | `TransitionValueEnumComparator` |
| `BindablePropertyTrigger` | `686` | `TransitionValueTriggerComparator` |
| `BindablePropertyAsset` | `823` | `TransitionValueAssetComparator` |
| `BindablePropertyArtboard` | `823` | `TransitionValueArtboardComparator` |
| `BindablePropertyViewModel` | `823` | — not comparable |
| `BindablePropertyList` | `835` | — not comparable |

**The keys are not unique**, which is the trap in that table. `Integer` and
`Trigger` share `686`; `Asset`, `Artboard` and `ViewModel` all share `823`. The
element name is the only thing that distinguishes them, so a `propertyKey`
copied from the wrong row is not a build error — it is a bind pointed at a
property the enclosing element does not have.

The pairing rule is **exact match, with one exception**: the two numeric kinds
interoperate, so a `BindablePropertyInteger` against a
`TransitionValueNumberComparator` is legal and compares as a float. Two integers
compare exactly. Everything else must line up.

`TransitionValueIdComparator` is a **base class**, not something to author. The
runtime matches its three subclasses — `...Enum`, `...Asset`, `...Artboard` —
and never a bare `Id`, so one written directly produces a condition that never
resolves.

**`problems` does not check any of this.** `incomparable-condition` reads the
left type by looking for a `sourcePathIds` on a *direct* child of the
comparator, and in this structure that attribute is a level deeper, inside the
`BindableProperty*`. So it gives up and reports nothing — a clean build says
nothing about whether the two sides can ever be compared. Match them by hand
against the table above.

### From inputs (deprecated)

The older mechanism, kept because existing files use it. For anything new,
use the view model form above — it does the same job with a property you can
also bind to a colour, a size or a text run.

Inputs are declared on the `StateMachine` and referenced by id:

```xml
<StateMachine name="State Machine 1" id="0:7">
    <StateMachineBool name="hovered" id="0:40"/>
    <StateMachineNumber name="progress" id="0:41"/>
    <StateMachineTrigger name="pressed" id="0:42"/>

    <StateMachineLayer name="Layer 1" id="0:8">
        <AnyState/>
        <ExitState/>
        <EntryState><StateTransition stateToId="0:12"/></EntryState>

        <AnimationState animationId="0:20" id="0:12">
            <StateTransition stateToId="0:13" duration="150">
                <TransitionBoolCondition inputId="0:40" opValue="equal"/>
            </StateTransition>
            <StateTransition stateToId="0:14">
                <TransitionNumberCondition inputId="0:41"
                                           opValue="greaterThan" value="80"/>
            </StateTransition>
        </AnimationState>

        <AnimationState animationId="0:21" id="0:13"/>
        <AnimationState animationId="0:22" id="0:14"/>
    </StateMachineLayer>
</StateMachine>
```

| Condition | Input type | Compares |
|---|---|---|
| `TransitionBoolCondition` | `StateMachineBool` | against `true`, no `value` |
| `TransitionNumberCondition` | `StateMachineNumber` | against its `value` |
| `TransitionTriggerCondition` | `StateMachineTrigger` | fired since last check |

`opValue` accepts `equal`, `notEqual`, `lessThan`, `lessThanOrEqual`,
`greaterThan`, `greaterThanOrEqual`. A boolean condition has no `value`:
`equal` fires when the input is true, `notEqual` when it is false.

Listeners set inputs with `ListenerTriggerChange` (no value),
`ListenerBoolChange` (`value="1"` or `"0"`) and `ListenerNumberChange`.

For a condition no comparator can express, a **script** can be one:
`ScriptedTransitionCondition` nests in the `StateTransition` beside these, and
its `evaluate` returns whether the transition may take. See
[luau/protocols.md](luau/protocols.md#transition-condition).

## Layers

Layers in one machine run **simultaneously**, each holding its own current
state. That is how independent behaviours compose — a layer for hover, a layer
for selection, a layer for a loading spinner — without one state having to
encode every combination.

```xml
<StateMachine name="State Machine 1" id="0:7">
    <!-- every layer reads the same bound view model; declare no inputs here -->
    <StateMachineLayer name="Hover" id="0:8">...</StateMachineLayer>
    <StateMachineLayer name="Select" id="0:9">...</StateMachineLayer>
</StateMachine>
```

A view model property is visible to every layer at once — the bound instance is
shared across the whole machine — so any layer's transitions can gate on the
same value. (The deprecated inputs were machine-global in the same way.) If two
layers animate the same property, the later layer wins.

**Give each independent widget its own layer.** Three buttons on one layer would
need a state per combination; three buttons on three layers need three states
each and never interact. The rule of thumb: one layer per thing that can be in a
state on its own.

### Something that animates at rest

A layer whose looping animation state has **no outgoing transitions** runs its animation
forever. That is the whole recipe for a pulsing status dot, a drifting
background or a spinner — an entry transition into one state playing a looping
timeline, and nothing to move it anywhere else:

```xml
<StateMachineLayer name="Live Pulse" id="0:90">
    <AnyState/>
    <ExitState/>
    <EntryState><StateTransition stateToId="0:92"/></EntryState>
    <AnimationState animationId="0:95" id="0:92"/>
</StateMachineLayer>
```

Layers run simultaneously, so this sits alongside the interactive ones and needs
nothing from them. The animation it names must carry `loopValue="loop"` — see
[easing.md](easing.md#looping), where the default of running once is the usual
reason an "idle" plays exactly one time and stops.

## Reacting to pointers

Listeners turn clicks, hovers and drags into data changes. They live on the
`StateMachine`, not in a layer, and are covered in
[format.md](format.md#listeners).

The usual pattern: a listener writes a view model property, and a condition
reads it. A listener can also run a script
([`ListenerAction`](luau/protocols.md#listener-action)) or, in older files, set
an input. Listeners do not change states directly.

**Every listener needs a `targetId`.** It is the object whose hit area the
listener watches, and a listener without one never fires; `rive inspect` warns
with `missing-reference`. Pointer
input is not offered on the artboard itself, so for artboard-wide input give the
artboard a background shape covering it and target that.

## Reacting to a gamepad

A gamepad listener is the **general** `StateMachineListener` form, like a
keyboard one: the element carries only `targetId`, and the trigger is a nested
`ListenerInputTypeGamepad` holding `listenerTypeValue` and the input filters.
The action is whatever any other listener would do.

```xml
<StateMachineListener targetId="0:10" name="Punch" id="0:70">
    <ListenerInputTypeGamepad listenerTypeValue="gamepad">
        <GamepadInput kind="button" mapping="standard" inputIndex="2" buttonPhase="1"/>
    </ListenerInputTypeGamepad>
    <ListenerViewModelChange>
        <BindablePropertyBoolean propertyValue="true">
            <DataBindContext sourcePathIds="0:40-0:41" propertyKey="634" direction="true"/>
        </BindablePropertyBoolean>
    </ListenerViewModelChange>
</StateMachineListener>
```

**Not `StateMachineListenerSingle`.** That is the folded spelling, with
`listenerTypeValue` on the listener itself, and it is for pointer listeners.
Gamepad and keyboard filters have to nest under an input type, so they need the
general form — see [format.md](format.md#listeners-two-spellings).

**The `GamepadInput` goes inside the `ListenerInputTypeGamepad`, not directly
under the listener.** Put it directly under and the file builds clean, inspects
clean, and the listener never fires: `ListenerInputTypeGamepad` is the object
that collects the filters, and an input type with no inputs matches everything
rather than nothing.

`listenerTypeValue="gamepad"` on the input type is load-bearing too: drop it and
the listener goes quiet the same silent way.

`GamepadInput` has four properties:

| Property | Meaning |
|---|---|
| `kind` | `button`, `axis`, `connected` or `disconnected` |
| `mapping` | `standard` reads `inputIndex` as a W3C standard slot, `index` as a raw index |
| `inputIndex` | which button or axis, **W3C 0-based** |
| `buttonPhase` | bit flag for the phases to match: `1` down, `2` up, `3` both; `button` kind only |

**`inputIndex` is 0-based, and a Luau `gamepadEvent` is not.** The same physical
button is `inputIndex="2"` here and `changeIndex == 3` in a script. The wire
format and this attribute agree; the Luau binding adds one.

`GamepadInput` takes no `name` — it is a filter, not a component, and giving it
one is a build error rather than a silently ignored attribute.

The whole shape has three silent failure modes and one loud one, so it is worth
checking with `--gamepad` rather than by eye.

A gamepad listener still needs a `targetId` like any other, and the same
"targeting nothing means never firing" rule applies.

**Test it with `--gamepad`**, which delivers events through the runtime's own
dispatch so listeners and scripts both see them — see
[workflow.md](workflow.md#gamepad). It needs a capture mode: pair it with
`--screenshot`. There is no other way to reach this listener without a physical
controller.

## A button that hovers and presses

The thing most files need first. Two **view model booleans**, four listeners,
three states — no state machine inputs anywhere.

Declare the properties on a view model the artboard is bound to:

```xml
<ViewModel defaultInstanceId="0:41" name="Button" id="0:40">
    <ViewModelPropertyBoolean name="hover" id="0:45"/>
    <ViewModelPropertyBoolean name="down" id="0:46"/>
    <ViewModelInstance exports="true" name="Default" id="0:41">
        <ViewModelInstanceBoolean propertyValue="false" viewModelPropertyId="0:45"/>
        <ViewModelInstanceBoolean propertyValue="false" viewModelPropertyId="0:46"/>
    </ViewModelInstance>
</ViewModel>
```

The listeners write them. `direction="true"` is what makes a bind *write* rather
than read, and a `LayoutComponent` is a `Drawable`, so it is a perfectly good
target with no `Shape` behind it:

```xml
<StateMachineListenerSingle targetId="0:10" listenerTypeValue="enter" name="In" id="0:50">
    <ListenerViewModelChange>
        <BindablePropertyBoolean propertyValue="true">
            <DataBindContext sourcePathIds="0:40-0:45" propertyKey="634" direction="true"/>
        </BindablePropertyBoolean>
    </ListenerViewModelChange>
</StateMachineListenerSingle>

<StateMachineListenerSingle targetId="0:10" listenerTypeValue="exit" name="Out" id="0:51">
    <ListenerViewModelChange>
        <BindablePropertyBoolean propertyValue="false">
            <DataBindContext sourcePathIds="0:40-0:45" propertyKey="634" direction="true"/>
        </BindablePropertyBoolean>
    </ListenerViewModelChange>
    <ListenerViewModelChange>
        <BindablePropertyBoolean propertyValue="false">
            <DataBindContext sourcePathIds="0:40-0:46" propertyKey="634" direction="true"/>
        </BindablePropertyBoolean>
    </ListenerViewModelChange>
</StateMachineListenerSingle>
```

`down` and `up` follow the same shape, writing `true` and `false` to `0:46`.
Note `exit` clears **both** — a pointer that leaves while held would otherwise
strand the button in its pressed state.

A listener can also run a **script**: `ScriptedListenerAction` nests in the
listener beside `ListenerViewModelChange`, for an effect that is computed
rather than a value written. See
[luau/protocols.md](luau/protocols.md#listener-action).

The transitions read those properties:

```xml
<StateTransition stateToId="0:62" duration="120">
    <TransitionViewModelCondition>
        <TransitionPropertyViewModelComparator>
            <BindablePropertyBoolean>
                <DataBindContext sourcePathIds="0:40-0:45" propertyKey="634"/>
            </BindablePropertyBoolean>
        </TransitionPropertyViewModelComparator>
        <TransitionValueBooleanComparator value="true"/>
    </TransitionViewModelCondition>
</StateTransition>
```

Each state plays a one-keyframe animation holding that appearance — rest, hover
and press differ only in the button's `colorValue`. **A one-key animation per
state is the normal way to build this**, not a shortcut: during a transition the
runtime mixes the two states' values from 0 to 1 over `duration`, so two hold
keys plus `duration="120"` *is* a 120ms cross-fade. Set `duration="0"` and it
snaps. You do not author the in-between.

The payoff over the deprecated input form is that `hover` and `down` are
ordinary view model properties. The same `down` can drive the button's colour
through a normal bind, be read by another artboard, or be set by the host — none
of which a `StateMachineBool` could do.

## A control that stays put

A toggle wants a value that persists, which a boolean property already does —
so the state itself does not have to remember anything.

Point the two transitions at the same property with opposite comparators:
Off→On fires when it reads `true`, On→Off when it reads `false`. Then the click
listener writes the value, and the states follow.

```xml
<StateTransition stateToId="0:64" duration="180">
    <TransitionViewModelCondition>
        <TransitionPropertyViewModelComparator>
            <BindablePropertyBoolean>
                <DataBindContext sourcePathIds="0:40-0:47" propertyKey="634"/>
            </BindablePropertyBoolean>
        </TransitionPropertyViewModelComparator>
        <TransitionValueBooleanComparator value="true"/>
    </TransitionViewModelCondition>
</StateTransition>
```

**Author both directions.** The return transition is the easiest thing in the
format to leave out, and nothing reports it: a state with no way out builds
clean, inspects clean, and produces a control that works exactly once.

To flip the value, the listener reads the property, negates it, and writes it
back. That takes a `DataConverterBooleanNegate` and a bindable property holding
**two** contexts — one to read, one to write:

```xml
<DataConverterBooleanNegate name="Not" id="0:98"/>

<StateMachineListenerSingle targetId="0:10" listenerTypeValue="click" name="Tap" id="0:60">
    <ListenerViewModelChange fromViewModelProperty="true" fromDataBindId="0:99">
        <BindablePropertyBoolean>
            <DataBindContext sourcePathIds="0:40-0:47" propertyKey="634" id="0:99"
                             converterId="0:98"/>
            <DataBindContext sourcePathIds="0:40-0:47" propertyKey="634" direction="true"/>
        </BindablePropertyBoolean>
    </ListenerViewModelChange>
</StateMachineListenerSingle>
```

Three parts, and all three are load-bearing:

- **the first context reads**, with the negate converter on it. It carries
  the `id` that `fromDataBindId` names, which is what tells the listener where
  the incoming value comes from.
- **the second context writes**, marked `direction="true"`.
- **`fromViewModelProperty="true"`** says the value is taken from a property
  rather than being a literal.

The converter goes on the read context. The runtime applies it in either
place, but the editor's listener inspector reads and edits the converter on
the read context only, so one on the write context works at runtime and
shows as no converter at all in the editor.

Leave the read context out and the listener negates a constant instead of the
stored value, so every click writes `true` and the control latches on. It builds
clean either way.

`ViewModelPropertyTrigger` exists for fire-once signals and behaves like the
deprecated `StateMachineTrigger`: spent at the end of the frame it fires in, and
consumable once per layer.

## Dragging something

Everything above routes a pointer through a property. One listener action skips
that and moves an object directly: **`ListenerAlignTarget`** writes the
pointer's position into a `Node`'s `x`/`y`, which is how a knob, a slider handle
or a draggable card is built.

```xml
<StateMachineListenerSingle targetId="0:30" listenerTypeValue="drag" name="Drag Knob" id="0:50">
    <ListenerAlignTarget targetId="0:30" preserveOffset="true"/>
</StateMachineListenerSingle>
```

Two `targetId`s, and they do different jobs: the listener's is what you have to
grab, the action's is what moves. Pointing both at the same shape drags that
shape; pointing the action at a parent `Node` drags a whole assembly by one
handle.

**`preserveOffset="true"` is what you almost always want.** It moves the target
by the pointer's *delta*, so the object keeps the offset it was grabbed at.
Leave it `false` and the target's origin snaps to the pointer on the first
event, so a knob grabbed near its edge jumps.

The position is resolved in the **target's parent space**, so what a drag
actually does depends on where the target sits — a knob inside a rotated or
scaled group moves along that group's axes, not the screen's.

Constrain the result rather than the input: there is nothing on the action to
limit an axis or clamp a range, so pair it with a constraint on the target, the
same way the editor's own sliders are built. A `TranslationConstraint` gives you
a rectangular limit — see [rigging.md](rigging.md#per-axis-control) — while a
`DistanceConstraint` in its default mode gives a **circular** one, which is what
a joystick knob wants
([rigging.md](rigging.md#distanceconstraint-modes)).

A knob dragged this way is usually read by a `Joystick`, which turns its
position into a 2-D value that poses the artboard: see
[easing.md](easing.md#joysticks).

Give it a pointer listener type — `drag`, or `down`/`move`/`up`. On a
non-pointer listener (`event`, `viewModel`) there is no position to read and the
action drives the target to its parent's origin instead, which looks like the
object teleporting the first time the listener fires.

## Firing events

An event is a **one-way notification out of the file**. A plain `Event` does
nothing on its own — firing it reports the event to whoever is running the
scene, and that is the entire behaviour. Two subclasses do act: `AudioEvent`
plays an `AudioAsset`, and `OpenUrlEvent` opens its `url`.

That makes events the wrong tool for telling the rest of *this* file something
happened. To drive a transition, a bind or a script from a click, write a view
model trigger with `ListenerViewModelChange` — the machine reads it, binds read
it, and the host can set it too. Reach for an event when the message is genuinely
leaving: the host application needs to know, a sound should play, a link should
open.

A state can emit an event the host application receives:

```xml
<Event name="ding" id="0:60"/>

<AnimationState animationId="0:20" id="0:12">
    <StateMachineFireEvent eventId="0:60" occursValue="0"/>
</AnimationState>
```

`occursValue` chooses when it fires: **`0` at start, `1` at end**. It is a bare
uint with no registered names, and the enumeration is spelled out only in the
doc string of a different type, so write the number.

A listener can fire an event directly, which is how a button tells the host
application something happened without routing it through a property first:

```xml
<StateMachineListenerSingle targetId="0:14" listenerTypeValue="click" name="Next">
    <ListenerFireEvent eventId="0:61"/>
</StateMachineListenerSingle>
```

One listener can carry several actions — a `ListenerTriggerChange` to drive the
machine and a `ListenerFireEvent` to notify the host, side by side.

**An event can carry a payload.** `Event` is itself a `CustomPropertyGroup`, so
custom properties nested inside it ride along and the host reads them off the
reported event:

```xml
<Event name="itemPicked" id="0:60">
    <CustomPropertyString propertyValue="" name="sku"/>
    <CustomPropertyNumber propertyValue="0" name="price"/>
</Event>
```

Those are ordinary custom properties — bindable and keyframable like any other,
and subject to the same rules ([data.md](data.md#custom-properties)). Binding
`sku` to a view model string is how the payload gets a value before the event
fires.

`AudioEvent` and `OpenUrlEvent` are the two that do something themselves:

```xml
<AudioEvent assetId="0:70" name="ding" id="0:61"/>
<OpenUrlEvent url="https://rive.app" targetValue="0" name="visit" id="0:62"/>
```

Both are fired exactly like a plain `Event`, by a state or a listener, and the
player reports each one so you can tell it happened:

```
sound ding: triggered           nothing the player can see stopped it
sound ding: muted               volume resolved to 0
sound ding: did not decode      the asset is there, decoding kept nothing
open https://rive.app           the url was handed to the OS
url https://rive.app            no opener is set, as in a screenshot run
```

`triggered` means none of those checks failed, not that a sound was heard;
confirm that in the previewer.

## Checking your work

A state machine that builds is not a state machine that runs. The common
failures are all silent:

```bash
rive inspect . --json | jq '.problems'
```

A transition, animation or input id that names nothing fails the build. What
builds clean is a machine that is wired to the wrong thing, or not wired at all.
List where the transitions go and compare against what you meant:

```bash
# every transition, and where it goes
rive inspect . --json | jq '[..|objects|select((.type//"")=="StateTransition")
                             |{to:.stateToId,duration}]'
```

An empty result means no transition survived, and the machine will sit in its
entry state forever.

For pointer interactions authored with state-machine listeners, an omitted listener
is another silent failure: the file still builds and inspects clean, but that
interaction never fires. Count them (the `inputs` line is a legacy signal — a
modern file drives itself through view model properties and reacts fine with
zero inputs):

```bash
rive inspect . --json | jq '{
  machines:    [..|objects|select((.type//"")=="StateMachine")]|length,
  layers:      [..|objects|select((.type//"")=="StateMachineLayer")]|length,
  inputs:      [..|objects|select((.type//"")|test("^StateMachine(Bool|Number|Trigger)$"))]|length,
  listeners:   [..|objects|select((.type//"")|startswith("StateMachineListener"))]|length,
  transitions: [..|objects|select((.type//"")=="StateTransition")]|length
}'
```

A zero in `listeners` on a file with buttons means nothing you built is
interactive, however complete the rest looks.

None of that proves it *behaves*, though. For that, click it:

```bash
rive <dir> --screenshot=a.png --pointer=click@120,60 --advance=20
rive <dir> --screenshot=b.png --pointer=click@120,60 --pointer=click@120,60 --advance=20
```

One click and two clicks should not look the same, and two clicks should return
a toggle to where it started. See
[workflow.md](workflow.md#prove-the-interaction-works).
