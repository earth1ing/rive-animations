# View models, data and enums

A view model is a typed data model attached to an artboard. The host
application sets values on it; data binds push those values into component
properties. It is how a file becomes reusable — one battery indicator artboard
driven by a `level` number, rather than one artboard per level.

Everything here is a **root element**, never nested inside an artboard.

> **Binds only apply while a state machine is running.** The CLI previewer and
> captures run only the machine named by `defaultStateMachineId`. Without one,
> no bind is pushed there: every bound text shows its authored literal, every
> bound colour and size stays as drawn, and an `ArtboardComponentList` produces
> **no rows at all**. Some runtimes fall back to the first state machine
> instead; set the id rather than relying on either.
>
> `rive inspect` warns (`no-default-state-machine`) when the artboard has
> animations or a state machine but no default. If a data-bound file renders as
> though the data does not exist, check this first.
>
> In the previewer the same omission also stops pointer input reaching
> anything, while the first animation keeps playing — see
> [gotchas.md](gotchas.md#without-a-state-machine-an-artboard-is-half-alive).
> The examples below leave `defaultStateMachineId` off for brevity. Your artboard
> needs one.

## The three parts

A view model is a *shape*, its properties are *fields*, and an instance holds
*values*:

```xml
<Artboard viewModelId="0:40" width="300" height="120" name="Battery" id="0:2">
    ...
</Artboard>

<ViewModel defaultInstanceId="0:41" name="Battery" id="0:40">
    <ViewModelPropertyNumber name="level" id="0:45"/>
    <ViewModelPropertyBoolean name="isCharging" id="0:46"/>

    <ViewModelInstance exports="true" name="Default" id="0:41">
        <ViewModelInstanceNumber propertyValue="72" viewModelPropertyId="0:45"/>
        <ViewModelInstanceBoolean propertyValue="false" viewModelPropertyId="0:46"/>
    </ViewModelInstance>
</ViewModel>
```

Three links, all required:

- the artboard names the view model with `viewModelId`
- the view model names its default with `defaultInstanceId`
- each instance value names its property with `viewModelPropertyId`

A property with no instance value has no default and reads as empty. An id
among these that names nothing declared fails the build.

Two properties in the example above are editor-only, so
`rive schema ViewModel` does not list them — `defaultInstanceId` and
`exports` need `rive schema ViewModel --all`. Editor-only does not mean
unauthorable: both belong in your RML.

There is a fourth link worth setting: **`Artboard.viewModelInstanceId`**, naming
which instance the artboard shows while being edited. It is editor-only too, so
`--all` again. Without it every bind still resolves at runtime, but the artboard
opens *unpopulated* in the editor — which matters when the point of the `.rev`
is handing the file to a designer.

<!-- rml:skip -->
```xml
<Artboard viewModelId="0:40" viewModelInstanceId="0:41" name="Battery" id="0:2">
```

## Naming

Ids are private to the file, but names are its public surface: the host reads
and writes properties by name, `--data=battery/level=100` addresses them by
name, and scripts reach them with `vmi:getNumber('level')`. Renaming a property
is a breaking change in a way that renumbering an id is not.

Scripts **write** these as well as read them. `context:viewModel()` inside a
`ScriptedLayout` returns the instance bound to the artboard, and setting a
property on it drives every `DataBindContext` reading that property — which is
how a script turns pointer position, physics or elapsed time into motion in the
markup. See
[luau/protocols.md](luau/protocols.md#driving-markup-from-the-pointer).

The convention is **PascalCase for view models and custom enums, camelCase for
their properties**:

```xml
<ViewModel defaultInstanceId="0:41" name="ChargeState" id="0:40">
    <ViewModelPropertyNumber name="batteryLevel" id="0:45"/>
    <ViewModelPropertyBoolean name="isCharging" id="0:46"/>
</ViewModel>
```

Three rules are harder than style, because a name has to survive being used as
a Luau identifier:

- **A leading digit is invalid** — `2xSpeed` reads as a number.
- **A Luau keyword is invalid** — `type`, `end`, `local`, `for`, `not`,
  `repeat` and the rest. `type` is the one that catches people, being otherwise
  perfect camelCase.
- **Spaces, hyphens and punctuation** work, but only through bracket access
  from a script, so `charge level` and `charge-level` are warned about rather
  than rejected.

A leading underscore marks a property as private (`_cachedValue`) and is
allowed under every convention — the casing rule applies to whatever follows
it.

**The CLI checks none of this**; the editor reports it when the file is opened.
A workspace can change the casing rule — snake, kebab or none — but the three
hard rules hold whatever it picks. [gotchas.md](gotchas.md#names-are-checked-by-the-editor-not-the-cli)
has a `jq` check.

## Property types

Each property type has a matching instance type. Declare the property on the
view model, set the value on the instance:

| Property | Instance | Holds |
|---|---|---|
| `ViewModelPropertyNumber` | `ViewModelInstanceNumber` | a number |
| `ViewModelPropertyString` | `ViewModelInstanceString` | text |
| `ViewModelPropertyBoolean` | `ViewModelInstanceBoolean` | true/false |
| `ViewModelPropertyColor` | `ViewModelInstanceColor` | ARGB colour |
| `ViewModelPropertyTrigger` | `ViewModelInstanceTrigger` | a fire-once signal |
| `ViewModelPropertyViewModel` | `ViewModelInstanceViewModel` | a nested view model |
| `ViewModelPropertyList` | `ViewModelInstanceList` | a repeatable list |
| `ViewModelPropertyEnumCustom` | `ViewModelInstanceEnum` | one of your own enum values |
| `ViewModelPropertyEnumSystem` | `ViewModelInstanceEnum` | one of Rive's built-in enums |
| `ViewModelPropertyArtboard` | `ViewModelInstanceArtboard` | an artboard to nest |
| `ViewModelPropertyAssetImage` | `ViewModelInstanceAssetImage` | an image asset |

The property type decides what a bind can drive: a `Number` property cannot
drive a text run without a converter, and cannot drive a colour at all. See
[format.md](format.md#data-binding).

Instance values are written the way the matching component property is:
`propertyValue="FFF5B02E"` for a colour, bare ARGB hex with no `0x` and no `#`,
exactly as `colorValue` takes it. Numbers and booleans are plain literals.

## A worked example: a progress bar

Driving a size from a number is the shape most real files take — a progress bar,
a battery level, a meter. It is worth doing once in full, because it forces the
one decision the format does not make for you.

```xml
<Artboard viewModelId="0:40" width="240" height="40" name="Meter" id="0:2">
    <!-- the groove -->
    <Shape x="20" y="20" name="Track" id="0:20">
        <Rectangle width="200" height="8" originX="0" originY="0.5"
                   cornerRadiusTL="4" name="Path"/>
        <Fill name="Fill"><SolidColor colorValue="FF2A2F3A" name="C"/></Fill>
    </Shape>

    <!-- the fill: its width is bound -->
    <Shape x="20" y="20" name="Filled" id="0:21">
        <Rectangle width="120" height="8" originX="0" originY="0.5"
                   cornerRadiusTL="4" name="Path" id="0:22">
            <DataBindContext sourcePathIds="0:40-0:41" propertyKey="20" converterId="0:50"/>
        </Rectangle>
        <Fill name="Fill"><SolidColor colorValue="FF57A5E0" name="C"/></Fill>
    </Shape>
</Artboard>

<DataConverterRangeMapper minInput="0" maxInput="100" minOutput="0" maxOutput="200"
                          clampLower="true" clampUpper="true" name="ToWidth" id="0:50"/>

<ViewModel defaultInstanceId="0:42" name="Meter" id="0:40">
    <ViewModelPropertyNumber name="progress" id="0:41"/>
    <ViewModelInstance exports="true" name="Default" id="0:42">
        <ViewModelInstanceNumber propertyValue="60" viewModelPropertyId="0:41"/>
    </ViewModelInstance>
</ViewModel>
```

Four things are doing the work:

- **Bind the `Rectangle`, not the `Shape`.** `width` is propertyKey **20** on
  `ParametricPath`; the enclosing `Shape` has no width at all. This is the most
  common way to build one of these and have nothing happen.
- **`originX="0"`** anchors the rectangle at its left edge, so a growing width
  extends rightwards instead of outwards from the centre.
- **A `DataConverterRangeMapper`** turns the source's units into pixels — here
  `0`–`100` into `0`–`200`. `clampLower`/`clampUpper` stop a value of `120`
  running the bar past its groove.
- **The authored `width="120"`** is what shows before data arrives. Set it to
  something plausible rather than `0`.

### Do not bind a layout box's width for this

A `LayoutComponent` also has a `width` (propertyKey **7**), and binding it looks
equivalent. It is not: that value is an input to the layout engine, which is
free to override it based on the box's scale type and its siblings. Bind a
`Rectangle` inside a fixed-size track, as above.

The consequence is that **you have to know the track's width** — it is the
converter's `maxOutput`, hard-coded at `200` here. If the track sits in a `fill`
column whose width the layout engine decides, you must work that number out
yourself and keep the two in step. There is no way to bind against a
layout-resolved size; `computed*` properties are derived and read `0` until the
scene is laid out.

## Swapping an asset from data

`ViewModelPropertyAssetImage` holds an **image asset** rather than a value, so
data can change which picture a scene draws — an avatar, a product photo, a
themed icon — without touching the graphics.

It works like any other bind, with the asset id as the value:

```xml
<Artboard viewModelId="0:50" width="400" height="300" name="Card" id="0:2">
    <Image x="200" y="150" assetId="0:60" name="Photo" id="0:20">
        <DataBindContext sourcePathIds="0:50-0:51" propertyKey="206"/>
    </Image>
</Artboard>

<ImageAsset file="a.png" name="a" id="0:60"/>
<ImageAsset file="b.png" name="b" id="0:61"/>

<ViewModel defaultInstanceId="0:52" name="Card" id="0:50">
    <ViewModelPropertyAssetImage name="photo" id="0:51"/>
    <ViewModelInstance exports="true" name="Default" id="0:52">
        <ViewModelInstanceAssetImage propertyValue="0:60" viewModelPropertyId="0:51"/>
    </ViewModelInstance>
    <ViewModelInstance exports="true" name="Alt" id="0:53">
        <ViewModelInstanceAssetImage propertyValue="0:61" viewModelPropertyId="0:51"/>
    </ViewModelInstance>
</ViewModel>
```

`propertyKey="206"` is `Image.assetId`, and the instance's `propertyValue` is
the id of an `ImageAsset` root element. The two instances above draw different
pictures from one artboard.

**Every asset you might swap to has to be in the file.** The bind selects
between assets that are already there; it cannot introduce one. So all of them
are embedded, and the `.riv` carries every variant — which is the thing to watch
if the images are large.

The `Image` still needs its own `assetId` as the starting value; the bind
replaces it once data arrives.

`ViewModelPropertyAssetFont` and `...AssetBlob` follow the same shape for fonts
and blobs. See [assets.md](assets.md) for how the assets themselves are
declared.

## Nested view models

`ViewModelPropertyViewModel` holds another view model, which is how a list of
cards each get their own data:

```xml
<ViewModel defaultInstanceId="0:51" name="Card" id="0:50">
    <ViewModelPropertyString name="title" id="0:52"/>
    <ViewModelInstance exports="true" name="Default" id="0:51">
        <ViewModelInstanceString propertyValue="Untitled" viewModelPropertyId="0:52"/>
    </ViewModelInstance>
</ViewModel>

<ViewModel defaultInstanceId="0:41" name="Screen" id="0:40">
    <ViewModelPropertyViewModel viewModelReferenceId="0:50" name="card" id="0:45"/>
    <ViewModelInstance exports="true" name="Default" id="0:41">
        <ViewModelInstanceViewModel propertyValue="0:51" viewModelPropertyId="0:45"/>
    </ViewModelInstance>
</ViewModel>
```

`viewModelReferenceId` names the view model being embedded; the instance's
`propertyValue` names *which instance* of it to use.

Bind paths walk through these. `sourcePathIds="0:40-0:45-0:52"` reads as: start
at view model `0:40`, follow property `0:45` (the nested view model), then take
property `0:52` inside it.

## Global view models

A view model can be **global**: one instance, shared by every artboard in the
file, bound to none of them. This is the shape for design tokens — brand
colours, a theme, spacing — read everywhere and owned nowhere. In the editor it
appears as a global view model, and a file published as a library exposes it to
every consumer.

`viewModelType="global"` on the `<ViewModel>` is the whole declaration:

```xml
<Artboard defaultStateMachineId="0:7" width="300" height="120" name="Card" id="0:2">
    <Shape name="Background">
        <Rectangle width="300" height="120" originX="0" originY="0" name="Path"/>
        <Fill name="Fill">
            <SolidColor colorValue="FF141414" name="C">
                <DataBindContext sourcePathIds="0:60-0:62" propertyKey="37"/>
            </SolidColor>
        </Fill>
    </Shape>
    <StateMachine name="State Machine 1" id="0:7">
        <StateMachineLayer name="Layer 1" id="0:8"><AnyState/><ExitState/><EntryState/></StateMachineLayer>
    </StateMachine>
</Artboard>

<ViewModel viewModelType="global" defaultInstanceId="0:61" name="Brand" id="0:60">
    <ViewModelPropertyColor name="surface" id="0:62"/>
    <ViewModelPropertyColor name="accent" id="0:63"/>
    <ViewModelInstance exports="true" name="Default" id="0:61">
        <ViewModelInstanceColor propertyValue="FF141414" viewModelPropertyId="0:62"/>
        <ViewModelInstanceColor propertyValue="FFFFA41C" viewModelPropertyId="0:63"/>
    </ViewModelInstance>
</ViewModel>
```

Three things differ from an ordinary view model:

- **No artboard binds it.** Leave `viewModelId` off. Every artboard reads the
  global through its bind paths, and an artboard with no data of its own needs
  no view model at all — the one above has none.
- **Bind paths are unchanged.** `sourcePathIds="0:60-0:62"` starts at the
  global's own id, exactly as a path into a bound view model starts at that
  view model's id. A path from an artboard's bound view model does not reach
  into a global, and does not need to.
- **`--data` cannot set it.** [The `--data` path](#the---data-path) is relative
  to the artboard's bound instance, and a global is not that: on an artboard
  with no bound view model it reports `no view model is bound to this
  artboard`. To prove a bind reads the global rather than its authored literal,
  change the instance's `propertyValue` in the markup, capture, and change it
  back. [`--data-dump`](#--data-dump-reading-the-values-back) does read it —
  every global is listed under `globals`.

A global still needs a state machine running on the artboard for its binds to
apply, like any other — see the note at the top of this page.

## Stateful components: per-instance data

A component placed several times usually needs different data in each place —
five rows of a list, each with its own name and avatar, drawn from one artboard.

**Stateful components are the format's answer to encapsulation, and they are
the shape to reach for.** A component artboard can be arbitrarily complicated
inside — nested groups, its own state machine, timelines, constraints, dozens of
properties — and expose only the handful of values a caller is meant to touch.
Everything else stays private. Mark a view model property with
`componentProps="1"` and it becomes part of the component's public surface, with
`displayName` naming it for whoever places the component; leave it unmarked and
it is an internal detail. The placement then sets *only* those values, and the
component decides what they mean.

That is worth insisting on, because the alternative — reaching into a
component's internals from outside — couples every caller to how the component
happens to be built today. A stateful component is the difference between "a
row that takes a name and an avatar" and "a row whose third text run you must
know about".

That is a **stateful** nested artboard: it owns its own view model instance
rather than reading the one its parent is bound to.

Three pieces:

1. the component artboard carries `viewModelId`, and its contents bind to that
   view model's properties as usual
2. each `<NestedArtboard>` is marked `isStateful="true"`
3. each one holds a `<ViewModelInstance>` **as a child**, carrying that
   placement's values

```xml
<Artboard defaultStateMachineId="0:80" width="300" height="260" name="Host" id="0:2">
    <NestedArtboard artboardId="0:30" isStateful="true" x="20" y="20" name="RowA" id="0:10">
        <ViewModelInstance viewModelId="0:50" exports="true" name="RowA Instance" id="0:70">
            <ViewModelInstanceString propertyValue="Ada" viewModelPropertyId="0:51" name="Component"/>
        </ViewModelInstance>
    </NestedArtboard>
    <NestedArtboard artboardId="0:30" isStateful="true" x="20" y="140" name="RowB" id="0:11">
        <ViewModelInstance viewModelId="0:50" exports="true" name="RowB Instance" id="0:71">
            <ViewModelInstanceString propertyValue="Grace" viewModelPropertyId="0:51" name="Component"/>
        </ViewModelInstance>
    </NestedArtboard>
    <StateMachine name="State Machine 1" id="0:80">
        <StateMachineLayer name="Layer 1" id="0:82"><AnyState/><ExitState/><EntryState/></StateMachineLayer>
    </StateMachine>
</Artboard>

<Artboard isComponent="true" defaultStateMachineId="0:81" viewModelId="0:50"
          viewModelInstanceId="0:52" width="100" height="40" name="Row" id="0:30">
    <Text x="8" y="8" name="Label" id="0:31">
        <TextStylePaint fontSize="16" fontAssetId="0:90" name="S" id="0:32">
            <Fill name="Fill"><SolidColor colorValue="FF000000" name="C"/></Fill>
        </TextStylePaint>
        <TextValueRun styleId="0:32" text="name" name="Run">
            <DataBindContext sourcePathIds="0:50-0:51" propertyKey="268"/>
        </TextValueRun>
    </Text>
    <StateMachine name="State Machine 1" id="0:81">
        <StateMachineLayer name="Layer 1" id="0:83"><AnyState/><ExitState/><EntryState/></StateMachineLayer>
    </StateMachine>
</Artboard>

<ViewModel defaultInstanceId="0:52" name="Row" id="0:50">
    <ViewModelPropertyString componentProps="1" name="label" id="0:51"/>
    <ViewModelInstance exports="true" name="Instance" id="0:52">
        <ViewModelInstanceString propertyValue="name" viewModelPropertyId="0:51" name="Component"/>
    </ViewModelInstance>
</ViewModel>
```

Two rows, one artboard, different text in each.

### The parts that fail silently

**`exports="true"` is required on the instance.** It defaults to `false`, and an
unexported instance is never written for the runtime, so every placement falls
back to the view model's default. `rive inspect` reports it as
`stateful-instance-not-exported`.

**`viewModelId` on the instance must match the component artboard's.** The
runtime uses the nested artboard's first `ViewModelInstance` child only if the
two ids agree; otherwise it builds a default instance. `rive inspect` reports
it as `stateful-instance-view-model-mismatch`.

**Data binds need a state machine.** The instance is bound through the state
machine, so a component artboard with no `defaultStateMachineId` never runs its
binds — the bound property just keeps whatever value was authored on it.

**The instance must be a child of the `<NestedArtboard>`**, not of the
`<ViewModel>`. An instance under a view model is one of *its* instances,
selected by `defaultInstanceId`; only a child of the nested artboard is that
placement's own.

### `componentProps`

`componentProps="1"` on a view model property marks it as part of the
component's public surface — an input a parent can drive, rather than internal
state. It does not change how binding resolves; it is what an editor shows in a
component's properties panel.

### Driving it from the parent instead

The values above are fixed at author time. To let the *parent* supply them, give
the instance's value a `DataBindContext` pointing at a property on the parent's
view model — `propertyKey` being the value's own `propertyValue` key (`561` for
a string):

```xml
<ViewModelInstance viewModelId="0:50" exports="true" name="RowA Instance" id="0:70">
    <ViewModelInstanceString propertyValue="Ada" viewModelPropertyId="0:51" name="Component">
        <DataBindContext sourcePathIds="0:40-0:41" propertyKey="561"/>
    </ViewModelInstanceString>
</ViewModelInstance>
```

`NestedArtboard.dataBindPathIds` is the *other* mechanism — it hands the nested
artboard an instance resolved from the parent's view model, and applies when the
artboard is **not** stateful. The two are alternatives, not partners.

The same bind works on an instance declared under its `<ViewModel>`, the kind
a `ViewModelInstanceListItem` or a `ViewModelInstanceViewModel` points at. Each
row of an `ArtboardComponentList` gets its own copy of the instance, and the
bind resolves from that row: the path names the host view model, and the
row's value follows the host's property. Add `twoWay="true"` and a change to
the row's value (a listener toggling it, say) writes back to the host. A
`converterId` applies as it does on any other bind.

<!-- rml:skip -->
```xml
<ViewModelInstance exports="true" name="spin" id="0:73">
    <ViewModelInstanceBoolean propertyValue="false" viewModelPropertyId="0:53">
        <DataBindContext sourcePathIds="0:40-0:48" propertyKey="593" twoWay="true"/>
    </ViewModelInstanceBoolean>
</ViewModelInstance>
```

Here `0:40-0:48` is a boolean on the host's view model and `593` is
`ViewModelInstanceBoolean.propertyValue` (`575` for a number). The host wins the
first sync, so the authored `propertyValue` is only what the row shows before it
is bound.

### Checking the placements

`inspect` reports a stateful nested artboard whose instance is unexported or
names a different view model. Beyond that, the ids are worth reading back:

```bash
rive inspect . --json | jq -c '[..|objects|select((.type//"")=="NestedArtboard")
                               |{name,isStateful,children:[(.children//[])[]|.type]}]'
```

A stateful entry with no `ViewModelInstance` child is a placement that will draw
the view model's default.

### Per-placement data from the host's view model

This is a delivery mechanism, not a different architecture. Design the component
exactly as above — internals private, a small set of `componentProps` exposed —
and change only how each placement receives its values.

`dataBindPathIds` on the placement resolves a view model instance out of the
*host's* view model and hands it to that placement. The host keeps one property
per placement, each holding its own instance, and the component artboard binds
to its own view model exactly as before. The component still sees only its own
view model and still knows nothing about its caller.

```xml
<!-- host artboard bound to Sheet (0:360) -->
<NestedArtboardLayout artboardId="0:100" dataBindPathIds="0:360-0:601"
    instanceWidth="132" instanceHeight="46" name="Primary" id="0:501"/>
<NestedArtboardLayout artboardId="0:100" dataBindPathIds="0:360-0:602"
    instanceWidth="132" instanceHeight="46" name="Secondary" id="0:502"/>

<ViewModel defaultInstanceId="0:361" name="Sheet" id="0:360">
    <ViewModelPropertyViewModel viewModelReferenceId="0:340" name="primary" id="0:601"/>
    <ViewModelPropertyViewModel viewModelReferenceId="0:340" name="secondary" id="0:602"/>
    <ViewModelInstance exports="true" name="Instance" id="0:361">
        <ViewModelInstanceViewModel propertyValue="0:371" viewModelPropertyId="0:601"/>
        <ViewModelInstanceViewModel propertyValue="0:372" viewModelPropertyId="0:602"/>
    </ViewModelInstance>
</ViewModel>
```

`dataBindPathIds` is the **same dash-separated absolute path** as
`sourcePathIds`: view model id, then the property id within it. `rive schema`
describes it only as `List<Id> — "Path to the selected property"`, which does
not reveal that spelling.

Two placements pointing at different properties get different data; two pointing
at the same property share it. Change the component artboard and every placement
changes with it.

**Check it properly.** Reading the render is not proof — the failure mode is
every placement showing the component's *authored* values, which look plausible.
Sabotage the authored literals the binds are meant to overwrite (labels to
`PROBE`, colours to magenta), rebuild, and compare hashes: if the render is
byte-identical, every placement really is bound.

```bash
rive <dir> --screenshot=before.png && md5 before.png
# edit the authored literals, then
rive <dir> --screenshot=after.png && md5 after.png
```

## Enums

An enum is a root element listing its values. Rive has two kinds.

**Custom enums** are yours:

```xml
<DataEnumCustom name="Status" id="0:70">
    <DataEnumValue key="idle" value="Idle"/>
    <DataEnumValue key="running" value="Running"/>
    <DataEnumValue key="failed" value="Failed"/>
</DataEnumCustom>

<ViewModel defaultInstanceId="0:41" name="Job" id="0:40">
    <ViewModelPropertyEnumCustom enumId="0:70" name="status" id="0:45"/>
    ...
</ViewModel>
```

`key` is the stable identifier a bind matches on; `value` is the label shown in
the editor. Order defines the underlying integer.

**System enums** expose a built-in Rive enumeration — blend modes, fit types —
so data can drive them. `enumType` selects which:

```xml
<DataEnumSystem enumType="1" id="0:71">
    <DataEnumValue key="screen" value="Screen"/>
    <DataEnumValue key="normal" value="Normal"/>
    <DataEnumValue key="multiply" value="Multiply"/>
</DataEnumSystem>

<ViewModelPropertyEnumSystem enumType="1" enumId="0:71" name="blend" id="0:46"/>
```

The property repeats `enumType` alongside `enumId`; both are needed.

**List a system enum's values in the runtime's own order.** The integer a bind
delivers to an enum-typed target (no converter needed) is the value's index in
your list, and the runtime reads that integer as its built-in enumeration -- so the
list has to match that enumeration's order, not the order that reads best.
`rive schema` prints it: `Text.verticalAlignValue` accepts `top, bottom,
middle`, so the vertical-align enum must go Top, Bottom, Middle. Listed as Top,
Middle, Bottom, "Middle align" delivers 1 and text that should be centred sits
at the bottom of its box. Nothing warns: the build is clean and the render looks
plausible.

Enums only export when a view model property references them, so an unreferenced
`DataEnumCustom` silently vanishes from the built file.

## Custom properties

A **custom property** is a named, typed value that lives on a component instead
of on a view model — what the editor's property-group card on the artboard
holds. They are keyframable and bindable, and they are the *other* thing this
format calls a property, so the first job is telling the two apart.

On the artboard, or on any container component, they come in two levels:

```xml
<Artboard clip="true" width="300" height="300" name="Artboard" id="0:2">
    <CustomPropertyGroup x="-150" y="170" name="Knobs" id="0:70">
        <CustomPropertyNumber propertyValue="0.5" name="progress" id="0:71"/>
        <CustomPropertyColor propertyValue="FF57A5E0" name="accent" id="0:72"/>
        <CustomPropertyTrigger name="ping" id="0:73"/>
    </CustomPropertyGroup>
</Artboard>
```

A group may only hold custom properties, and a `CustomProperty*` goes in a
group — with one exception, a drawable, which takes them directly (next
section). The group itself goes on the artboard, or on any container component,
and is how you attach custom properties to one.

`x`/`y` on the group place its card on the stage. They are editor-only, so they
travel in a `.rev` and are absent from the `.riv` — worth setting anyway if the
file is going to a designer, since every group left at `0,0` lands on the same
spot.

Six types, each holding its value in `propertyValue`:

| Element | `propertyValue` | Key |
|---|---|---|
| `CustomPropertyNumber` | `double` | `243` |
| `CustomPropertyBoolean` | `bool` | `245` |
| `CustomPropertyString` | `String` | `246` |
| `CustomPropertyColor` | `Color` | `836` |
| `CustomPropertyEnum` | the selected value's `Id`, with `enumId` naming the enum | `872` |
| `CustomPropertyTrigger` | `uint`, plus a separate `fire` callback | `870` / `869` |

The trigger is the one with two keys — bind `propertyValue`, keyframe `fire`.
See [luau/protocols.md](luau/protocols.md#the-trigger-has-two-keys).

### What can actually reach one

Less than you would expect, and this is the distinction that matters:

|  | View model property | Custom property |
|---|---|---|
| keyframe it | yes | yes |
| bind to it | yes | yes |
| a transition condition reads it | yes | **no** |
| a listener writes it | yes | **no** |
| the host application reads or sets it | yes | **no** |

There is no listener action that targets a custom property, no transition
comparator that reads one, and no runtime API that exposes one. So a custom
property can be neither the thing a button sets, nor the thing a transition
watches, nor the thing a host application pushes a value into.

And exactly one kind of thing consumes the value: a `Scripted*` object reading
its own `CustomProperty` children. That is what a script input is — see
[luau/protocols.md](luau/protocols.md#an-input-is-a-custom-property).

So if a value has to be reachable by interactivity or by the host, it belongs on
a view model. Reach for a custom property group when the point is the
**editor** — a knob a designer can find on the artboard, key on a timeline, and
bind into the scene.


### Custom properties on a drawable

A shape, image, text, nested artboard, artboard component list or scripted
drawable takes custom properties as direct children, with no group:

```xml
<Shape x="208" y="70" name="Dim" id="0:92">
    <Rectangle width="64" height="64" name="Path" id="0:93"/>
    <Fill name="Fill" id="0:94">
        <SolidColor colorValue="FF4DFF88" name="Color" id="0:95"/>
    </Fill>
    <CustomPropertyNumber propertyValue="0.3" name="emissive" id="0:97"/>
</Shape>
```

These are what a script reads while it draws. In the editor they are added from
the drawable's inspector, under **Custom Properties**, and like a script's
inputs they have no row in the hierarchy and no card on the stage. They key and
bind like any other custom property.

In the `.riv` such a property carries no name: the name is written once in the
file's name table and the property points at it, so tagging two hundred shapes
with `emissive` stores the word once. A script gets the key for a name from
`artboard:propertyKey("emissive")`, once, and reads by it; see `Drawable` and
`Artboard.drawModulated` in the [script API](luau/api/artboards.md).

A layout does not take them this way — its children are its content — and a
script's inputs are untouched: they keep their names and are never read as
tags.

## Lists and repeated artboards

A list turns one artboard into a row per item — a feed, a leaderboard, a set of
cards — without duplicating any graphics. It is four pieces:

1. a **`ViewModelPropertyList`** on the owning view model
2. a **`ViewModelInstanceList`** holding one `ViewModelInstanceListItem` per row
3. an **artboard to repeat**, bound to the row's view model
4. an **`ArtboardComponentList`** in the scene, bound to the list property

```xml
<Artboard viewModelId="0:60" width="400" height="600" styleId="0:5" name="Feed" id="0:2">
    <LayoutComponentStyle name="Artboard Style" id="0:5"/>
    <LayoutComponent width="400" height="600" styleId="0:11" name="List" id="0:10">
        <LayoutComponentStyle flexDirectionValue="column" gapVertical="12"
                              gapVerticalUnitsValue="points" name="S" id="0:11"/>
        <ArtboardComponentList name="Rows" id="0:12">
            <DataBindContext sourcePathIds="0:60-0:62" propertyKey="800"/>
        </ArtboardComponentList>
    </LayoutComponent>
</Artboard>

<!-- The row. Bound to the Card view model -- that binding is what the list
     matches on. -->
<Artboard isComponent="true" viewModelId="0:50" width="360" height="80" name="Card" id="0:30">
    <Text x="16" y="30" name="Title" id="0:31">
        <TextStylePaint fontSize="18" fontAssetId="0:70" name="TS" id="0:32">
            <Fill name="F"><SolidColor colorValue="FFFFFFFF" name="C"/></Fill>
        </TextStylePaint>
        <TextValueRun styleId="0:32" text="Card" name="R">
            <DataBindContext sourcePathIds="0:50-0:51" propertyKey="268"/>
        </TextValueRun>
    </Text>
</Artboard>

<ViewModel defaultInstanceId="0:52" name="Card" id="0:50">
    <ViewModelPropertyString name="title" id="0:51"/>
    <ViewModelInstance exports="true" name="Default" id="0:52">
        <ViewModelInstanceString propertyValue="Untitled" viewModelPropertyId="0:51"/>
    </ViewModelInstance>
    <ViewModelInstance exports="true" name="One" id="0:53">
        <ViewModelInstanceString propertyValue="First card" viewModelPropertyId="0:51"/>
    </ViewModelInstance>
    <ViewModelInstance exports="true" name="Two" id="0:54">
        <ViewModelInstanceString propertyValue="Second card" viewModelPropertyId="0:51"/>
    </ViewModelInstance>
</ViewModel>

<ViewModel defaultInstanceId="0:61" name="Feed" id="0:60">
    <ViewModelPropertyList name="cards" id="0:62"/>
    <ViewModelInstance exports="true" name="Default" id="0:61">
        <ViewModelInstanceList viewModelPropertyId="0:62">
            <ViewModelInstanceListItem viewModelId="0:50" viewModelInstanceId="0:53"/>
            <ViewModelInstanceListItem viewModelId="0:50" viewModelInstanceId="0:54"/>
        </ViewModelInstanceList>
    </ViewModelInstance>
</ViewModel>
```

That renders two cards reading "First card" and "Second card" from one set of
graphics.

### The join that decides which artboard repeats

Nothing names the row artboard directly. Each `ViewModelInstanceListItem`
carries a `viewModelId`, and the runtime **looks for an artboard whose own
`viewModelId` matches it**. That is the entire link.

So the row artboard must set `viewModelId`, and it must be the *same* view model
the list items reference. Get it wrong and the list resolves to nothing, renders
nothing, and reports nothing — `problems` does not check it.

Each item also names `viewModelInstanceId`, which is *which instance* supplies
that row's values. Two items pointing at the same instance render two identical
rows; that is usually a mistake, and it looks like the list "not updating".

### Laying the rows out

`ArtboardComponentList` is a drawable, so put it inside a `LayoutComponent` and
the rows flow with the layout — `flexDirectionValue` picks column or row,
`gapVertical` spaces them. Give the row artboard `isComponent="true"`, which
marks it reusable rather than a top-level screen.

The rows size themselves from the row artboard's own width and height — but
only if the artboard's root layout box is **`fixed` on both axes**. A `fill`
root collapses instead, because the mounted slot hugs: the rows come out as tall
as their tallest child rather than as tall as the artboard, and the content
clips. Set `layoutWidthScaleType="fixed" layoutHeightScaleType="fixed"` on the
row's own root box.

Give the row artboard `isComponent="true"` **and a matching `ComponentAsset`**,
the same pair any reusable artboard needs — see
[format.md](format.md#making-an-artboard-nestable). `inspect` warns when only one half is
present.

### Which row is this? `listIndex`

Every row draws from the same artboard, so nothing in it knows its own position
— which is what you need for "highlight the third card", "stagger each row's
entrance", or "tell me which one was clicked".

A **`ViewModelPropertySymbolListIndex`** on the *item* view model is that
position. The runtime writes each row's index into it, counting from `0`, every
time the list resolves:

```xml
<ViewModel defaultInstanceId="0:52" name="Item" id="0:50">
    <ViewModelPropertySymbolListIndex symbolTypeValue="itemIndex" name="index" id="0:51"/>
    <ViewModelInstance exports="true" name="One" id="0:53">
        <ViewModelInstanceSymbolListIndex viewModelPropertyId="0:51"/>
    </ViewModelInstance>
</ViewModel>
```

**`symbolTypeValue="itemIndex"` is not optional.** It is not decoration on top
of the element name — it is the entire lookup. A view model instance registers
its special properties in a table keyed by that symbol, and the list asks that
table for `itemIndex`. The element type only decides that the value is an
integer; `symbolTypeValue` is what makes anything write to it. The raw number
`15` means the same thing and still parses.

The default is `none`, meaning "not a special property", so a
`ViewModelPropertySymbolListIndex` without it is an ordinary integer nobody ever
writes to: the rows render, the index stays `0` in every one of them, and
`--verify` and `problems` are both clean.

One per view model. The lookup is keyed by symbol, so a second index property on
the same view model replaces the first rather than adding to it.

It is **read-only**: whatever you author into the instance's `propertyValue` is
overwritten the moment the list resolves. Declare the instance value and leave
it alone.

Two things to do with it.

**Bind it into a property.** The index is a raw ordinal, so a
[converter](#converters) is usually doing the real work — the row's own height,
a stagger delay, a colour ramp:

```xml
<Rectangle width="20" height="20" originX="0" name="Bar" id="0:36">
    <DataBindContext sourcePathIds="0:50-0:51" propertyKey="20" converterId="0:80"/>
</Rectangle>
```

**Condition a transition on it**, so a row can enter a different state purely
because of where it sits. The index is an integer, so the pair is
`BindablePropertyInteger` (`propertyKey="686"`) against a
`TransitionValueNumberComparator` — there is no integer comparator:

```xml
<StateTransition stateToId="0:45" duration="0">
    <TransitionViewModelCondition opValue="equal">
        <TransitionPropertyViewModelComparator>
            <BindablePropertyInteger>
                <DataBindContext sourcePathIds="0:50-0:51" propertyKey="686"/>
            </BindablePropertyInteger>
        </TransitionPropertyViewModelComparator>
        <TransitionValueNumberComparator value="1"/>
    </TransitionViewModelCondition>
</StateTransition>
```

To record *which* row was clicked rather than react inside it, point a listener
at a plain number property on the parent view model and write the index into it
— see [Writing a value back from a listener](#writing-a-value-back-from-a-listener).

### Checking the rows

```bash
rive inspect . --json | jq -c '[..|objects|select((.type//"")=="ViewModelInstanceListItem")
                               |{viewModelId,viewModelInstanceId}]'
```

Empty means no rows will draw. Cross-check those `viewModelId`s against the
`viewModelId` on your row artboard — that is the join nothing validates.

```bash
rive inspect . --json | jq -c '[..|objects|select((.type//"")=="ViewModelPropertySymbolListIndex")
                               |{name,symbolTypeValue}]'
```

Anything reporting `"symbolTypeValue": 0` is an index property the runtime will
never write to.

## Converters

A converter transforms a value between source and target. It is a root element,
named from the bind by `converterId`:

```xml
<DataConverterRangeMapper minInput="0" maxInput="100"
                          minOutput="0" maxOutput="4.712389"
                          name="ToAngle" id="0:80"/>

<Shape name="Needle" id="0:14">
    <DataBindContext sourcePathIds="0:40-0:45" propertyKey="15" converterId="0:80"/>
</Shape>
```

A converter changes the effective type of a bind, so a `Number` source can drive
a text run through `DataConverterToString`. Without one, that pairing is a type
mismatch that resolves and does nothing.

### The catalogue

Picking the right one is most of the work. By what they take in and hand back:

| Converter | In → out | Notes |
|---|---|---|
| `DataConverterRangeMapper` | number → number | remap a range (`minInput`/`maxInput` → `minOutput`/`maxOutput`); `clampLower`, `clampUpper`, `modulo`, `reverse` are flag bits, and it can ease with an `interpolatorId` |
| `DataConverterOperationValue` | number → number | one arithmetic op against a literal: `operationType` + `operationValue` |
| `DataConverterOperationViewModel` | number → number | the same, but the right-hand side is read from `sourcePathIds` |
| `DataConverterFormula` | number → number | a full infix expression, see [below](#arithmetic-and-reading-more-than-one-property) |
| `DataConverterRounder` | number → number | round to `decimals` |
| `DataConverterInterpolator` | number → number | eases the value **over `duration` seconds** rather than remapping it, so a bound value animates to its new setting instead of jumping |
| `DataConverterToString` | anything → string | `decimals`, the `round` and `trailingZeros` flag bits, and `colorFormat` for a colour source |
| `DataConverterToNumber` | string or enum → number | an enum source gives the value's index, which is how an enum drives a numeric property |
| `DataConverterStringPad` | string → string | pad with `text` until `length`; `padType` `0` start, `1` end |
| `DataConverterStringTrim` | string → string | `trimType` `0` none, `1` start, `2` end, `3` both |
| `DataConverterStringRemoveZeros` | string → string | drops trailing decimal zeros a `ToString` left behind |
| `DataConverterBooleanNegate` | boolean → boolean | |
| `DataConverterListToLength` | list → number | how many items — a "3 items" label without host code |
| `DataConverterNumberToList` | number → list | builds a list of *n* instances of `viewModelId`, which is how an `ArtboardComponentList` repeats a count rather than real data |
| `DataConverterTrigger` | number → trigger | fires whenever the incoming integer changes |
| `DataConverterGroup` | chains | runs several in order; each member is a `DataConverterGroupItem` child naming one by `converterId` |
| `ScriptedDataConverter` | anything | a Luau `Converter`, see [luau/protocols.md](luau/protocols.md#converter) |

**`decimals` does nothing on its own — it needs `round="true"`.** Without the
flag a number formats at full precision, so `decimals="1"` on `25` gives
`25.000000` rather than `25.0`. And `trailingZeros` reads backwards from what
the name suggests: setting it **strips** trailing zeros. For fixed decimal
places — the usual case for a readout — set `round="true"` and leave
`trailingZeros` off.

```xml
<!-- 25 -> "25.0" -->
<DataConverterToString decimals="1" round="true" name="Fixed" id="0:92"/>
```

`DataConverterSystemDegsToRads` and `DataConverterSystemNormalizer` are the odd
pair. They are `DataConverterOperationValue` subclasses pre-set to a multiply —
`π/180` and `0.01` — and they exist because the editor inserts them for you when
a bind crosses a unit boundary:

```xml
<DataConverterSystemDegsToRads operationType="2" operationValue="0.017453292"
                               name="Degrees to Radians" id="0:80"/>
```

That is the missing half of [rotation being radians](gotchas.md#rotation-is-radians-durations-are-frames-or-milliseconds).
A view model `angle` a designer thinks of in degrees needs this between it and
`rotation`, and the same goes for a `0`–`100` percentage driving anything the
runtime reads as `0`–`1`. Both also respect the bind's direction, converting the
other way on a `direction="true"` write-back — an ordinary
`DataConverterOperationValue` does not, so a two-way bind wants the system pair.

A converted file will already contain them, one per file, named as above.

`rive schema --search DataConverter` lists every type; `rive schema <Type>` has
the properties.

**A range mapper is also how you add a constant.** There is no "offset"
converter, but a mapper whose input and output ranges are the same width has
slope 1, so it shifts without scaling. Both ranges one apart gives `input + 1`:

```xml
<DataConverterRangeMapper minInput="0" maxInput="1" minOutput="1" maxOutput="2"
                          name="Plus one" id="0:70"/>
```

Widen both ends by the same amount and the offset holds for any input — the
range is not a domain limit unless you set the `clampLower`/`clampUpper` flag
bits. This is worth knowing because the alternative, `DataConverterOperationValue`
with `operationType="0"`, costs you the same element but a
[raw enum integer](#arithmetic-and-reading-more-than-one-property).

### Chaining them

Most converters do one small thing, so the useful ones are usually chains. A
`DataConverterGroup` is the chain, and each link is a `DataConverterGroupItem`
naming a converter **by id** rather than nesting it:

```xml
<DataConverterGroup name="Count label" id="0:81">
    <DataConverterGroupItem converterId="0:91"/>
    <DataConverterGroupItem converterId="0:92"/>
</DataConverterGroup>

<DataConverterListToLength name="Count" id="0:91"/>
<DataConverterToString decimals="0" name="As text" id="0:92"/>
```

Point a text run's `converterId` at the **group** and a view model list drives
it: the list becomes its length, the length becomes text. The members stay
ordinary root elements, so the same `DataConverterToString` can be a link in
several groups.

Order is the child order, and each link receives what the previous one returned
— so a chain that ends in the wrong type fails the same silent way an unconverted
mismatch does.

A **script** can be a converter too, for arithmetic the built-ins do not cover.
`ScriptedDataConverter` is a `DataConverter`, so it is a root element named by
`converterId` exactly like the ones above. Note the protocol requires
`reverseConvert` as well as `convert`. See
[luau/protocols.md](luau/protocols.md#converter).

### Arithmetic, and reading more than one property

`DataConverterFormula` holds a sequence of **token children** read left to right
as an infix expression. `FormulaTokenInput` is the incoming value:

```xml
<DataConverterFormula name="half, negated" id="0:80">
    <FormulaTokenParenthesisOpen/>
    <FormulaTokenInput/>
    <FormulaTokenOperation operationType="3"/>
    <FormulaTokenValue operationValue="2"/>
    <FormulaTokenParenthesisClose/>
    <FormulaTokenOperation operationType="2"/>
    <FormulaTokenValue operationValue="-1"/>
</DataConverterFormula>
```

That is `(input / 2) * -1`. The pieces are `FormulaTokenValue` (a literal in
`operationValue`), `FormulaTokenOperation`, `FormulaTokenFunction`,
`FormulaTokenParenthesisOpen`/`Close` and `FormulaTokenArgumentSeparator` for
multi-argument functions.

A function token opens its own bracket. Write the function, its arguments
separated by `FormulaTokenArgumentSeparator`, then a `FormulaTokenParenthesisClose`
and nothing else: a `FormulaTokenParenthesisOpen` after the function starts a
second group that swallows the close, and the formula quietly evaluates to
nothing. `min(100, max(0, input + 10))` is:

```xml
<DataConverterFormula name="clamp step" id="0:82">
    <FormulaTokenFunction functionType="0"/>
    <FormulaTokenValue operationValue="100"/>
    <FormulaTokenArgumentSeparator/>
    <FormulaTokenFunction functionType="1"/>
    <FormulaTokenValue operationValue="0"/>
    <FormulaTokenArgumentSeparator/>
    <FormulaTokenInput/>
    <FormulaTokenOperation operationType="0"/>
    <FormulaTokenValue operationValue="10"/>
    <FormulaTokenParenthesisClose/>
    <FormulaTokenParenthesisClose/>
</DataConverterFormula>
```

`operationType` and `functionType` have **no symbolic names** — they are raw
integers, the only enums in the format you cannot write by name. `rive schema`
will not list their values either, so they are reproduced here in full.

`operationType`, on `FormulaTokenOperation` and on `DataConverterOperation`
(which `DataConverterOperationValue` and `DataConverterOperationViewModel`
both extend):

| | | | | | | |
|---|---|---|---|---|---|---|
| 0 `+` | 1 `-` | 2 `*` | 3 `/` | 4 `%` | 5 `sqrt` | 6 `pow` |
| 7 `exp` | 8 `log` | 9 `cos` | 10 `sin` | 11 `tan` | 12 `acos` | 13 `asin` |
| 14 `atan` | 15 `atan2` | 16 `round` | 17 `floor` | 18 `ceil` | | |

`functionType`, on `FormulaTokenFunction`:

| | | | | | | |
|---|---|---|---|---|---|---|
| 0 `min` | 1 `max` | 2 `round` | 3 `ceil` | 4 `floor` | 5 `sqrt` | 6 `pow` |
| 7 `exp` | 8 `log` | 9 `cos` | 10 `sin` | 11 `tan` | 12 `acos` | 13 `asin` |
| 14 `atan` | 15 `atan2` | 16 `random` | | | | |

The two lists overlap but **are not the same numbering** — `round` is 16 as an
operation and 2 as a function. Read the column you are actually in.

**A token can read a property of its own.** Put a `DataBindContext` inside a
`FormulaTokenValue` and it pulls that value instead of a literal, which is how
one converter combines several view model properties:

```xml
<DataConverterFormula name="total" id="0:81">
    <FormulaTokenValue>
        <DataBindContext sourcePathIds="0:40-0:45" propertyKey="777"/>
    </FormulaTokenValue>
    <FormulaTokenOperation/>
    <FormulaTokenValue>
        <DataBindContext sourcePathIds="0:40-0:46" propertyKey="777"/>
    </FormulaTokenValue>
</DataConverterFormula>
```

## Writing a value back from a listener

Everything above pushes data *into* the scene. A listener can push the other
way — setting a view model property when something is clicked, which is how a
file changes its own data without host code.

`ListenerViewModelChange` holds a **bindable property** carrying the value to
write, and the bind inside it is marked `direction="true"` to mean
target-to-source:

```xml
<StateMachineListenerSingle targetId="0:30" listenerTypeValue="click" name="Select" id="0:60">
    <ListenerViewModelChange>
        <BindablePropertyBoolean propertyValue="true">
            <DataBindContext sourcePathIds="0:40-0:46" propertyKey="634" direction="true"/>
        </BindablePropertyBoolean>
    </ListenerViewModelChange>
</StateMachineListenerSingle>
```

`direction="true"` is the whole trick, and nothing else in the format needs it.
Without it the bind reads instead of writes, the click does nothing, and — as
everywhere else in data binding — nothing reports it.

The `BindableProperty*` types mirror the property types, so
`BindablePropertyNumber`, `...String`, `...Color` and the rest write their own
kinds. There are eleven, and the `propertyKey` on the nested `DataBindContext`
is the bindable's own — several of them share a key, so the element name is what
picks the type. The full table is in
[state-machines.md](state-machines.md#bindable-properties-and-matching-the-pair).

**To write a value derived from the current one** — flipping a boolean, stepping
a counter — set `fromViewModelProperty="true"` and give the bindable property
*two* contexts: a read carrying an `id`, named by `fromDataBindId`, with the
converter on it, and a write marked `direction="true"`. See
[state-machines.md](state-machines.md#a-control-that-stays-put) for a toggle
built this way. With only the write context the converter transforms a constant,
not the stored value.

## Checking your work

Data binding has more silent failures than any other part of the format —
dangling paths, binds on the wrong object, type mismatches — and none of them
are build errors:

```bash
rive inspect . --json | jq '.problems'
```

That reports unresolved paths, binds whose target lacks the property, and
incompatible source/target types by name.

It has a blind spot worth knowing: the path is resolved inside the view model
it names, and nothing checks that the artboard is bound to that view model. A
bind copied from one artboard to another can name a valid path in a view model
this artboard never binds, resolve to nothing at runtime, and report clean.

The direct check is to change the data and see the picture change:

```bash
rive <dir> --screenshot=a.png
rive <dir> --screenshot=b.png --data=battery/level=100
```

If those match, nothing is bound — whatever `problems` says.

### The `--data` path

The path is relative to **the view model instance bound to the artboard**, and
every segment is a *property name*. Neither the view model's name nor the
instance's name appears in it.

A [global view model](#global-view-models) is not on this path: it is bound to
no artboard, so `--data` cannot reach it. `--data-dump` can.

So for a flat view model — an artboard bound to `Score`, which has a `score`
property — the path is the bare property name:

```bash
rive <dir> --screenshot --data=score=87.6      # correct
rive <dir> --screenshot --data=Score/score=87.6   # "no property at ..."
```

A slash descends through a `ViewModelPropertyViewModel`. `battery/level` above
means: the bound instance has a `battery` property holding a nested view model,
and that one has `level`. The nesting is not optional — you cannot skip a level
and write `level` on its own.

Getting this wrong is cheap to spot: an unresolved path prints
`data: no property at "..."` rather than failing silently, and a resolved one
prints `data: <path> = <value>`. If you see neither, the flag never parsed.

The value is read according to the property's own type, and a value the type
cannot take is an **error**, not a silent zero:

| type | accepts | rejected |
|---|---|---|
| number | a whole number or decimal | anything with trailing junk |
| boolean | `true`, `false`, `1`, `0` | `yes`, `on`, anything else |
| color | 8 hex digits of ARGB, or 6 of RGB taken as opaque | prefixed, non-hex, any other length |
| enum | one of the enum's own value keys | a name the enum does not declare |
| string | anything | — |
| trigger | fires regardless of the value | — |

A rejected value prints to **stderr** — past `--quiet`, so it survives a
`--data-dump=-` pipe — naming the path and, for an enum, the values it does
accept. A headless run exits non-zero rather than capturing a scene the value
never reached; a watch session reports it and keeps going.

> Authored `colorValue` is looser: it accepts anything and gives whatever it
> cannot parse an alpha of zero, so `colorValue="notacolor"` draws nothing and
> reports nothing. `--data` refuses instead, since an invisible fill reads as
> a broken bind.

```
--data mode: "melting" is not one of: idle, heating, cooling
```

It reports whether a value was **applied**, but not whether anything
downstream consumed it. To read the other end, see
[`--data-dump`](#--data-dump-reading-the-values-back) below.

## `--data-dump`: reading the values back

`--data` sets values; `--data-dump` reads them, at whatever moment the
interactions leave the scene in:

```bash
rive . --data-dump --data=speed=88 --advance=500ms
```

That writes `build/<name>.data.json`, a headless one-shot like `--screenshot`
and `--semantics`, and it combines with all three plus `--viewport`,
`--pointer` and `--advance`. While watching, `d` (or `data`) dumps on demand
without restarting.

`--data-dump=` chooses the destination — a path, or `-` (equivalently
`stdout`) for standard output, the same way `--semantics=` does. The build log goes to stderr, so on stdout the
JSON is the only thing on the pipe:

```bash
rive . --data-dump=- --advance=500ms | jq '.viewModel'
```

What it holds:

| key | what it is |
|---|---|
| `viewModel` | the artboard's bound instance, walked in full |
| `globals` | one entry per global view model |
| `inputs` | legacy state machine inputs — **absent unless the file has some** |
| `nested` | each nested artboard's own instance |

`inputs` is the exception to "the dump holds everything": `StateMachineBool`,
`StateMachineNumber` and `StateMachineTrigger` are
[deprecated](state-machines.md), so the key is omitted entirely when a file has
none. A file that uses them still gets them — a diagnostic that hid live state
would be lying — but a file that does not is never shown the concept.

Every property carries its `path` — the same path `--data` takes, so a value
you read can be fed straight back in. Two exceptions, both dump-only: list
rows read as `cards[0]/title`, and entries under `nested` are relative to that
nested artboard's own instance, which `--data` cannot address at all.

### Nested artboards

`nested` walks every artboard this one hosts, and everything they host in
turn. Nested artboards and component list rows are the same thing to the
runtime, so both appear — a list row per index:

```json
"nested": [
  {"path": "Plain", "artboard": "Row", "inherits": true},
  {"path": "Stateful", "artboard": "Row", "viewModels": [{...}]},
  {"path": "Zones[0]", "artboard": "Zone", "viewModels": [{...}]},
  {"path": "Zones[0]/Badge", "artboard": "Badge", "inherits": true}
]
```

**`"inherits": true`** means the placement has no data context of its own — it
draws from its parent's, which is already in the dump once, higher up. That is
the ordinary case for a plain `<NestedArtboard>`; a stateful placement, or one
whose bind path resolves to an instance, gets its own `viewModels` instead.

An instance is reported **once**, wherever it is first reached. Without that, a
placement sharing its parent's context would repeat the root's instance and
every global under its own name, which reads as though the component held
them.

Entries carry no `changed`: these instances are never primed, so there is
nothing to compare against. Their property paths are relative to their own
instance, so they collide with the root's namespace by design.

### Dumping only some of it

`--data-dump-filter=` takes those paths, comma-separated, and keeps only
what they match. `*` spans any run of characters including `/`, and `?` matches one:

```bash
rive . --data-dump-filter=battery/*,score --advance=500ms
rive . --data-dump=stdout --data-dump-filter='cards[*]/title'
```

A **container survives when anything under it matched**, so `battery/*` keeps
the `battery` property itself and drops its siblings. A list reports its true
`size` whatever the filter kept, so a narrowed row set never reads as a
shorter list. A global view model or a nested artboard that matched nothing is
dropped entirely; the root instance stays, with an empty `properties`.


Types read back as themselves. Numbers, strings and booleans are bare; colours
are bare ARGB hex, the form `colorValue` and `--data` both take. An enum
carries its `value`, its `index`, and `values` — every legal option, so a wrong
value reads differently from one that is merely unexpected. Images, fonts and
blobs report their type only; the runtime has no getter for them.

A **trigger** reports no value at all. `changed` is the signal instead: a fire
dirties the property, and the flag is sticky, so `"changed": true` on a trigger
means it fired at some point since the scene bound.

### Over time, not just at the end

`--data-dump-every=<N|Ns|Nms>` samples the run instead of capturing the end of
it, writing **JSON Lines** — one object per line — to
`build/<name>.data.jsonl`:

```bash
rive . --data-dump-every=1 --pointer=click@60,30 --advance=2s   # every frame
rive . --data-dump-every=100ms --advance=10s                    # every 6th
rive . --data-dump-every=1s --advance=30s                       # every 60th
```

The interval takes the same forms `--advance` does, and has to come out as a
whole number of frames at 60fps — sampling happens per advance, so `10ms`
(0.6 of a frame) is refused rather than rounded.

Line 1 is a header. Line 2 is frame 0: every value on the bound instance and
the globals, flat. After that each line carries only what moved:

```json
{"frame": 0, "time": 0, "full": true, "values": [{"path": "speed", "value": 31}, ...]}
{"frame": 18, "time": 0.3, "values": [{"path": "speed", "value": 44}]}
{"frame": 19, "time": 0.316, "values": [{"path": "go", "fired": true}]}
```

Records are **flat** — `path` and `value`, not the nested tree a snapshot
emits — because over a run the tree is almost all redundancy, and a flat
delta answers the question a sequence is for: *when did this change?*

```bash
jq -s '[.[] | select(.values) | .values[] | select(.path == "speed") | .value]' build/app.data.jsonl
```

Frames where nothing moved produce no line at all, which is what keeps a long
run small. A trigger appears only on the frame it fired, as
`{"path": "go", "fired": true}` — it has no value to report. The last line is
always a full state, whatever the interval, so a run ends on where it got to.

A sequence covers the bound view model instance and the globals, which sit
under `globals/<name>/`. It does **not** cover state machine inputs or nested
artboards: nested instances are never primed, so there is no change to detect
in them. `--data-dump` without `--data-dump-every` still reports both.

Sampling counts **every** advance, including the frames a gesture steps
internally — `--pointer=drag@...` advances one per interpolated move — so a
drag is sampled through, not skipped over.

> `changed` does not appear in a sequence. Finding what moved consumes the
> same per-frame dirt the snapshot's sticky `changed` flag reads, so the two
> cannot both be live: `--data-dump-every` produces a stream *instead of* a
> snapshot, not alongside one.

When anything moves rows out from under their paths, the whole frame is
re-emitted with `"full": true` — a list that changed length, a list whose rows
were swapped or reordered, or a nested view model that was replaced. A path
like `cards[1]/title` names a different row after any of those, so a delta
keyed on it would quietly attribute one row's value to another.

### What `changed` does and does not mean

Value properties on the bound instance and the globals carry `changed`. Not
everything does: nested view models and images, fonts and blobs have no value
to have changed, and entries under `nested` are not tracked at all. An absent
flag means "not tracked", never "has not changed".

Two things about the flag are easy to get wrong, and both have caught people.

**It is cumulative, not per-frame.** `changed` is true if anything has written
to that property at *any* point since the scene bound, and it stays true for
the rest of the run. It does not mean "changed on the frame this was
captured". The runtime does have a per-frame flag, but every advance clears
it, and a capture always happens after an advance — so it would read `false`
on a property that had just been written a hundred times. For per-frame
answers use [`--data-dump-every`](#over-time-not-just-at-the-end), where a
value appearing in a frame's record *is* the statement that it moved on that
frame.

**It is about writes to the property, not about the binds reading it.** In the
ordinary direction — a host sets data, binds
push it into the graphics, nothing writes back — `changed` is `false` for every
property that is working perfectly. Filtering for `changed == false` to find
inert binds flags the whole file.

Where it does earn its keep is the other direction: a listener, a script or a
`--data` override writing *into* a property.

```bash
rive . --data-dump=- --pointer=click@60,30 --advance=500ms \
  | jq '.. | objects | select(.changed == true) | .path'
```

An empty result after a click that should have written something means the
listener never fired — the property is the far end of an interaction that did
not happen.

|  | `--data-dump` | `--data-dump-every` |
|---|---|---|
| answers | has anything written this since bind? | what moved on this frame? |
| reads as | `"changed": true` on the property | the property appearing in that frame's record |

### What it still cannot tell you

The dump says a bind wrote a value; it does not say the value is on screen. A
target that is clipped, transparent or behind something else reads identically
to one that is visible. For that, the check that works is still a literal
probe: temporarily set a bound text run's authored `text` to `LITERAL-HERE` and
render it. Seeing the literal means the bind is inert.
