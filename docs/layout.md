# Layout

Shapes positioned with `x`/`y` sit where you put them. A `LayoutComponent`
instead arranges its children with a flexbox model, so content responds to the
space it is given — necessary for anything that resizes.

A layout tree is built from two kinds of thing, with separate jobs:

| | Job |
|---|---|
| `LayoutComponent` | **blocks out an area** — a region with a visual size and position that arranges what is inside it: a screen, a row, a card, a slot |
| `LayoutParticipant` | **sizes and positions a leaf** — nested in a `Shape`, `Text` or `Image`, it decides how that one object is sized and placed within the area around it |

Use a `LayoutComponent` where you need an area; put a `LayoutParticipant` on
the content that goes in it. A box whose only job is to hold one shape, label or
image is the wrong tool — that is the participant's job
([below](#shapes-and-text-inside-a-layout-box)).

Layout boxes are **two objects**: the `LayoutComponent` holding the tree position and
size, and a `LayoutComponentStyle` carrying every flex property, linked by
`styleId`.

```xml
<LayoutComponent width="600" height="120" styleId="0:11" name="Row" id="0:10">
    <LayoutComponentStyle
        flexDirectionValue="row"
        layoutAlignmentType="spaceBetweenCenter"
        paddingLeft="16" paddingRight="16"
        paddingLeftUnitsValue="points" paddingRightUnitsValue="points"
        layoutWidthScaleType="fill" layoutHeightScaleType="hug"
        name="Row Style" id="0:11"/>

    <LayoutComponent width="120" height="80" styleId="0:13" name="Card" id="0:12">
        <LayoutComponentStyle name="Card Style" id="0:13"/>
        <Fill name="Fill"><SolidColor colorValue="FF2A2F3A" name="C"/></Fill>
    </LayoutComponent>
</LayoutComponent>
```

The style is a **child of the component it styles** *and* named by its
`styleId`. Nesting it without the link is the single most common layout
mistake — every value is right and nothing applies. Nothing errors.

Three more rules cause most of the rest, each silently:

- **Every artboard needs its own style** — [below](#every-artboard-needs-one).
- **A padding, gap or inset with no `*UnitsValue` is ignored.** Units default
  to `undefined`, not `points` — see [Units, and the trap](#units-and-the-trap).
- **A shape or text with no `LayoutParticipant` inside a `fixed` or `fill`
  box is stretched to fill it** — see
  [But it may still be resized by that box](#but-it-may-still-be-resized-by-that-box).
  Give drawables in a layout a participant rather than a wrapper box; see
  [Shapes and text inside a layout box](#shapes-and-text-inside-a-layout-box).

## Every artboard needs one

An `Artboard` **is** a `LayoutComponent`, so it carries a style like any other
layout box. Give every artboard one — the editor does: creating an artboard
there always adds a `LayoutComponentStyle`, whether or not anything in it
lays out. It matters most the moment the artboard holds a layout child (a
`LayoutComponent`, a `ScriptedLayout`, an `ArtboardComponentList`), because
that child has nothing to lay it out against:

```xml
<Artboard defaultStateMachineId="0:7" width="500" height="500" styleId="0:5" name="Artboard" id="0:2">
    <LayoutComponentStyle name="Artboard Style" id="0:5"/>
    <LayoutComponent width="500" height="500" styleId="0:11" name="Root" id="0:10">
        <LayoutComponentStyle layoutWidthScaleType="fill" layoutHeightScaleType="fill"
                              name="Root Style" id="0:11"/>
    </LayoutComponent>
</Artboard>
```

The default style needs no attributes — `<LayoutComponentStyle name="Artboard
Style" id="0:5"/>` is enough. What matters is that it exists and that the
artboard's `styleId` points at it.

**This one does not fail locally.** The CLI lays the scene out and renders it
correctly without an artboard style, so `--once`, `--screenshot` and the live
window all look right. The same file opened in the editor cannot lay anything
out, and the editor offers no way to add the style afterwards.

`rive inspect` reports it as the warning `artboard-without-style`. A warning
rather than an error because markup that never reaches the editor is fine
without a style — but it is not worth the bet, since nothing can add one once
the file is there.

## Sizing

`layoutWidthScaleType` and `layoutHeightScaleType` decide where a dimension
comes from:

| Value | Meaning |
|---|---|
| `fixed` | use the `width`/`height` on the component |
| `fill` | take the space the parent offers |
| `hug` | shrink to fit the children |

A sidebar-and-content shell is one `fixed` child beside one `fill` child. A row
that grows with its contents is `hug` on height.

**For a panel behind *text*, reach for `TextStyleBackground` first.** Hugging a
`Text` child is the obvious instinct and it is not the shortest path: a
`TextStyleBackground` is sized from the runs themselves, tracks them as they
reflow, and takes its own `Fill` and `cornerRadius`. See
[text.md](text.md#backgrounds-behind-text).

`minWidth`, `maxWidth`, `minHeight` and `maxHeight` clamp the result whichever
scale type is in play — a `hug` box that must not collapse below 44, a `fill`
column that should stop growing at 600. They live on the shared sizing base, so
they work on a `LayoutComponentStyle` and a `LayoutParticipant` alike, and take
the same `*UnitsValue` treatment as everything else dimensional.

### Filled boxes: use the layout, not a shape behind it

A `LayoutComponent` is a `Drawable`. It takes a `Fill`, a `Stroke` and
`cornerRadius*` directly, so a card, a button, an avatar circle or a coloured
panel is **one box** — no `Shape` + `Rectangle` inside it.

```xml
<LayoutComponent width="160" height="200" styleId="0:11" name="Card" id="0:10">
    <LayoutComponentStyle cornerRadiusTL="16" name="Card Style" id="0:11"/>
    <Fill name="Fill"><SolidColor colorValue="FF2A2F3A" name="C"/></Fill>
</LayoutComponent>
```

This matters more than it looks. A `Rectangle` inside a `Shape` has its own
fixed `width`/`height` that the layout engine does not touch, so the moment the
box resizes, the painted rectangle stops matching it. Fill the layout box
itself and the paint tracks the computed size.

**With one exception: gradients.** A `SolidColor` covers whatever the box
resolves to, but `LinearGradient` and `RadialGradient` position themselves with
`startX`/`startY`/`endX`/`endY` in **local points**, and there is no percentage
form. Author them against the size you expect; at a different size the ramp
ends early or runs past the edge. It degrades quietly — a gradient authored for
a 342pt button still looks plausible at 320pt — so if a gradient must hold up
across sizes, check it at both with `--viewport`.

Reach for `Shape` when you need geometry a box cannot express — an icon, a
path, a non-rectangular silhouette — and give it a `LayoutParticipant` so it
takes part in the layout directly. Reach for a filled `LayoutComponent` for
anything rectangular that has to respond to layout.

## Shapes and text inside a layout box

**Give every `Shape`, `Text` and `Image` in a layout tree a `LayoutParticipant`.**
It is the default way to put a drawable into a layout: nest a participant inside
it and the drawable becomes a layout item itself — spaced, aligned and sized by
its parent like any box — with **no wrapper `LayoutComponent`**. The participant
*is* the item's layout, so there is nothing left to wrap.

Keep the division of labour straight: `LayoutComponent`s block out the areas
(their visual size and position, and how they arrange their contents), and a
participant decides how the leaf object inside an area is sized and positioned.

```xml
<LayoutComponent width="400" height="80" styleId="0:11" name="Row" id="0:10">
    <LayoutComponentStyle flexDirectionValue="row" layoutAlignmentType="centerLeft"
                          gapHorizontal="12" gapHorizontalUnitsValue="points"
                          name="Row Style" id="0:11"/>

    <Shape name="Dot" id="0:20">
        <LayoutParticipant layoutWidthScaleType="fixed" layoutHeightScaleType="fixed"
                           width="40" height="40" name="Dot Layout"/>
        <Ellipse width="40" height="40" name="Path"/>
        <Fill name="Fill"><SolidColor colorValue="FF57A5E0" name="C"/></Fill>
    </Shape>

    <Text name="Label" id="0:30">
        <LayoutParticipant layoutWidthScaleType="hug" layoutHeightScaleType="hug"
                           name="Label Layout"/>
        <TextStylePaint fontSize="18" fontAssetId="0:40" name="Style" id="0:32">
            <Fill name="Fill"><SolidColor colorValue="FFFFFFFF" name="C"/></Fill>
        </TextStylePaint>
        <TextValueRun styleId="0:32" text="Hello" name="Run"/>
    </Text>
</LayoutComponent>
```

Three reasons to reach for it first:

- **A flatter tree.** Without participants every item needs a layout box of its
  own just to get into the flow — one per label, per icon, per image — which
  roughly doubles the tree and puts two objects where one belongs. With them
  the hierarchy stays the shape of the content.
- **It is the only way to hug a custom shape.** A `hug` box sizes itself by
  asking its children to measure, and only parametric paths (`Rectangle`,
  `Ellipse`, `Triangle`, `Polygon`, `Star`) can answer; a hand-drawn
  `PointsPath` measures as zero. So a `hug` box around a custom icon collapses to
  0×0, with a clean build. A participant measures the shape's combined bounds
  across **all** its paths, parametric or not, so `hug` on the participant gives
  the icon exactly its drawn size.
- **The shape is sized as one piece.** `hug` keeps the drawn size; `fixed` and
  `fill` scale every path in the shape together into the slot, so a multi-path
  icon keeps its internal arrangement. The scale is per axis, so a slot of a
  different aspect ratio stretches it — prefer `hug`, or match the aspect.

The wrapper this replaces:

```xml
<!-- avoid: a box whose only job is to put one label into the row -->
<LayoutComponent styleId="0:51" name="Label Box" id="0:50">
    <LayoutComponentStyle layoutWidthScaleType="hug" layoutHeightScaleType="hug"
                          name="Label Box Style" id="0:51"/>
    <Text name="Label" id="0:52">...</Text>
</LayoutComponent>

<!-- prefer: the text is the item -->
<Text name="Caption" id="0:53">
    <LayoutParticipant layoutWidthScaleType="hug" layoutHeightScaleType="hug"
                       name="Caption Layout"/>
    ...
</Text>
```

Keep a real `LayoutComponent` for what a participant cannot do. A participant
carries **sizing and nothing else**, so a box is still the answer when the item
needs to paint a background, stroke or corner radius, pad or clip its content,
pin to an edge (`positionTypeValue="absolute"`), or arrange several children of
its own.

**Nesting is the whole link.** Unlike `LayoutComponentStyle`, a
`LayoutParticipant` has no `styleId` and nothing points at it — being a child of
the component it governs is the only thing that connects the two. A participant
declared as a root element, or as a sibling of the shape rather than inside it,
attaches to nothing: the shape stays out of the flow. The build still succeeds;
`inspect` reports it as `wrong-parent`. Only a `Shape`, `Text` or `Image` can
host one.

Where it sits among the other children does not matter — before or after the
geometry and paint both work. First is the readable convention, since it
describes the component as a whole.

It carries the sizing half of a layout style:

| Property | |
|---|---|
| `layoutWidthScaleType` / `layoutHeightScaleType` | `fixed`, `fill`, `hug` |
| `width` / `height` | used when the scale type is `fixed` |
| `fractionalWidth` / `fractionalHeight` | fill **weights**, see [below](#fill-is-a-weight-not-a-percentage) |
| `minWidth` / `maxWidth` / `minHeight` / `maxHeight` | clamps |
| `displayValue` | `none` takes the item out of the layout entirely |

Alignment, direction, padding and gaps stay on the parent's
`LayoutComponentStyle` — a participant describes how one item wants to be
sized, not how it arranges children. Grid placement is not on the participant
either: a `GridItemPlacement` goes beside it, as another child of the same
`Shape`, `Text` or `Image`.

### Which size wins

The scale type decides who measures the item, and this holds for **every**
participant, not just text:

| Scale type | Size comes from |
|---|---|
| `hug` | the content — the text's own measured extent, the shape's combined bounds, the image's size |
| `fixed` | the `width`/`height` on the participant |
| `fill` | the space the parent gives it |

So a `Text` with a `hug` participant sizes itself to its glyphs, and the same
`Text` with `fixed` or `fill` is sized by the layout instead — its own
`sizingValue` and `width` stop deciding. Set the two consistently rather than
hoping one wins; `hug` on the participant is what you want when the content
should drive the box.

### Without a participant

A `Shape`, `Text` or `Image` with no participant does **not** join the flow — it
is not placed in the row or column alongside its siblings. It keeps its own
`x`/`y`, **measured from the layout box's top-left**, so hand-placed content
travels with its parent. That is occasionally what you want (a decoration at a
fixed offset); for anything that should take part in the layout, add the
participant.

### But it may still be resized by that box

Not joining the flow is not the same as being left alone — in the common case
it is the opposite. A drawable with no `LayoutParticipant` is **stretched to
fill the box**, so an 18pt icon centred in a 24pt frame is drawn at 24pt, and a
non-square one has its aspect ratio pulled with it. A `LayoutParticipant` set
`fixed` or `hug` is what gives the drawable a size of its own.

Whether a non-participating child keeps its size depends on the **parent's**
scale type:

| Parent | Non-participating child |
|---|---|
| `LayoutComponent` set `fixed` or `fill` | keeps its `x`/`y`, **but is resized to the box** |
| `LayoutComponent` set `hug` | keeps its `x`/`y` **and its size** |
| `Artboard` | keeps its `x`/`y` **and its size** |

The direction of causation is what to remember. Under `fixed` or `fill` the box
has a size of its own and pushes it down, so an `Ellipse` in a `fill` box grows
with the box whether you wanted that or not. Under `hug` the box takes its size
*from* the content, so there is nothing to push — the shape stays as drawn and
the box wraps it.

An artboard never does this to a non-participating child, whatever its own
sizing. So the same `Shape` behaves differently depending on where it sits, with
no error and nothing in `inspect` to show it: art dropped onto an artboard stays
the size you drew it, and silently stretches the moment you group it inside a
`fill` box.

A custom `PointsPath` is the odd one out in the other direction: without a
participant a box can neither measure it nor resize it. It keeps its drawn size
under `fixed` and `fill`, and contributes **nothing** to a `hug` box, which
collapses around it. Give the shape a participant and both problems go away.

### Pinning to an edge: only a `LayoutComponent` can

`positionTypeValue="absolute"` lives on `LayoutComponentStyle`, and
`LayoutParticipant` has no equivalent — it carries sizing and nothing else. So
a box can be pinned to one or more edges of its parent:

```xml
<LayoutComponentStyle positionTypeValue="absolute"
    positionTop="16" positionTopUnitsValue="points"
    positionRight="16" positionRightUnitsValue="points"
    name="Badge Style" id="0:11"/>
```

Insets default to `undefined`, not `0`, so a `position*` without its matching
`*UnitsValue` does nothing at all. Pin the edges you want and leave the rest
alone; setting `positionLeft` **and** `positionRight` stretches the box between
them instead of pinning it.

To pin a `Shape`, `Text` or `Image`, give it a box of its own — one pinned
`LayoutComponent`, sized to the art, with the drawable inside filling it.
Withholding a `LayoutParticipant` is **not** the way to do it: that is what
makes the drawable fill, which is the opposite of leaving it alone.

A **nested artboard** is the exception, and a useful one. A
`NestedArtboardLeaf` in a `fixed` or `fill` box *is* resized — but resizing it
scales the whole artboard through its `fit` and `alignment`, the way an image
fits a frame. It never lays out or resizes the art inside. Drop the same symbol
into a 132pt slot and a 30pt slot and both render correctly from one definition.

`NestedArtboardLayout` is the other one: unlike a leaf it *does* join the flow,
as one of the four layout node providers listed under
[Layouts and artboards](#layouts-and-artboards). It joins by grafting the
**referenced artboard's** layout node into the host's tree, which means that
artboard must be a layout root — it needs a `LayoutComponentStyle` of its own.
Point one at an artboard without a style and the instance does not draw at all:
not misplaced, not the wrong size, simply absent, with nothing in `--verify` or
`inspect` to say why.

### Keeping art the size you drew it

Three ways, and which one you want depends on the art:

| | Use when |
|---|---|
| a `hug` `LayoutParticipant` on the shape | the art is one `Shape`, however many paths it has — the default |
| wrap it in a `Node` | the art is several shapes that must keep their arrangement, placed by hand |
| put it in its own artboard, reference it with `NestedArtboardLeaf` | the same art repeats, especially at several sizes |

**A `hug` participant** takes the shape into the flow at exactly its drawn
size, custom paths included, with no box around it. This is the first thing to
try for an icon; it only stops fitting when the art spans several `Shape`s,
since each participant is laid out as its own item and their relative
arrangement is lost.

**Wrap it in a `Node`.** A plain `Node` stops the box's sizing: everything
inside that does not participate keeps its size *and* its `x`/`y`, exactly as
drawn. Reach for it with composite artwork made of several shapes, because it
preserves their arrangement relative to each other. The art does not take part
in the flow, so it needs a slot box around it to be placed.
It has to be a `Node` — a `Solo` does **not** stop sizing (see
[Groups and Solos inside a layout](#groups-and-solos-inside-a-layout)).

```xml
<LayoutComponent width="18" height="18" styleId="0:11" name="Icon Slot" id="0:10">
    <LayoutComponentStyle layoutWidthScaleType="fixed" layoutHeightScaleType="fixed"
                          name="Icon Slot Style" id="0:11"/>
    <Fill name="Fill"><SolidColor colorValue="FF2A2F3A" name="C"/></Fill>

    <Node name="Icon Art">
        <Shape x="9" y="9" name="Bars">
            <Rectangle x="-4.6" y="3" width="3.4" height="6" name="Bar 1"/>
            <Rectangle x="0" y="0.5" width="3.4" height="11" name="Bar 2"/>
            <Rectangle x="4.6" y="2" width="3.4" height="8" name="Bar 3"/>
            <Fill name="Fill"><SolidColor colorValue="FF6A7486" name="C"/></Fill>
        </Shape>
    </Node>
</LayoutComponent>
```

Without that `Node` (or a participant), the `fixed` slot resizes the bars'
geometry to 18×18 — a three-bar chart icon becomes a grey square, with a clean
build and nothing in `problems`. It is the single most likely way an icon set
comes out wrong.

These three bars happen to be one `Shape`, so a `hug` participant on it does
the same job with no slot box at all. The `Node` earns its place when the art
is several `Shape`s, or when the slot itself has to paint.

Note the box's own `Fill` stays **outside** the group. It paints the slot, not
the art.

**Put it in its own artboard.** Give the symbol a small artboard of its own,
mark it `isComponent="true"`, and drop it into each slot with a
`NestedArtboardLeaf`:

```xml
<LayoutComponent width="30" height="30" styleId="0:31" name="Icon Slot" id="0:30">
    <LayoutComponentStyle layoutWidthScaleType="fixed" layoutHeightScaleType="fixed"
                          name="Icon Slot Style" id="0:31"/>
    <NestedArtboardLeaf artboardId="0:40" fit="contain" name="Icon"/>
</LayoutComponent>
```

The slot sizes the leaf and `fit` scales the artboard into it, so the art keeps
its proportions and internal arrangement at any size. This is the better answer
when a symbol repeats — one definition, edited once, rendered at 132pt in a
header and 30pt in a row.

### Groups and Solos inside a layout

A `Node` or `Solo` between a layout box and its content does not hide that
content from the layout. Both are **transparent**: they have no layout node of
their own, and the box reaches through them, to any depth, for whatever takes
part — a `LayoutComponent`, a `NestedArtboardLayout`, or a `Shape`, `Text` or
`Image` carrying a `LayoutParticipant`. Those are laid out as if they were
direct children, in hierarchy order.

| Between the box and its content | The layout sees | Non-participating content |
|---|---|---|
| `Node` | every participating descendant | keeps its size |
| `Solo` | only the **active** child, and what takes part inside it | sized by the box, like a direct child |

So a group can organise a row's items without breaking the row, and a `Solo`
of variants reflows the box around whichever one is showing. The group's own
transform still applies to what it holds, on top of the laid-out positions.

The difference in the last column is the trap. A `Node` is what keeps art
[the size you drew it](#keeping-art-the-size-you-drew-it); a `Solo` is not,
so icon variants in a `Solo` inside a `fixed` slot are stretched to the slot.
Wrap each variant in its own `Node`.

**An `ArtboardComponentList` is the exception.** Inside a group it stays out of
the layout by default — that is how a file asks for free-form items placed by
`x`/`y` or a follow-path constraint. Set `participatesInLayout="true"` on the
list to lay it out through the group instead. A list that is a direct child of
a layout box is always laid out, and the flag does nothing there.

```xml
<LayoutComponent styleId="0:11" name="Feed" id="0:10">
    <LayoutComponentStyle name="Feed Style" id="0:11"/>
    <Node name="Rows">
        <ArtboardComponentList participatesInLayout="true" name="Items" id="0:12"/>
    </Node>
</LayoutComponent>
```

### A layout box can be a listener target

`LayoutComponent` is a `Drawable`, so it hit-tests and can be a listener's
`targetId` directly. A button does not need a `Shape` behind it to catch
clicks — give the box a `Fill` and point the listener at the box.

### `fill` is a weight, not a percentage

`fill` means "grow to share the leftover space", and `fractionalWidth` is this
item's share. Two `fill` siblings at the default `1` split the space evenly; set
one to `2` and it takes twice as much. It does **not** mean 100% of the parent,
which is the reading that produces a layout overflowing its box.

A five-cell tab bar is five participants at `fill` with equal weights.

### Pushing things apart

There is no spacer element and no flex-grow property. `flexGrow` exists in the
schema and **the layout engines never read it**. Setting it does nothing.

Two ways to distribute leftover space, both already here:

**Let a real region absorb it.** Give the box that should take up the slack
`fill` on the long axis and leave its siblings `fixed` or `hug`. A sign-in
screen whose brand block is `fill` height and whose form rows are `fixed` puts
the brand in the middle and pins the form below it, with no spacer.

**Or space the children apart.** `layoutAlignmentType` carries three
distributing values alongside the nine positions — `spaceBetweenStart`,
`spaceBetweenCenter` and `spaceBetweenEnd` — which spread the children along the
main axis and use the suffix for the cross axis.

An empty `LayoutComponent` set `fill` works as a spacer too, and costs an
object. Prefer letting a region you already have absorb the space.

**The weights are not on the style.** Every other layout knob lives on
`LayoutComponentStyle`, but `fractionalWidth`/`fractionalHeight` sit on the
`LayoutComponent` itself — and on a `LayoutParticipant`, which carries its own.
`rive schema LayoutComponentStyle` does not list them, because they are not
there.

```xml
<!-- weights on the component, scale type on the style -->
<LayoutComponent fractionalWidth="2" width="0" height="0" styleId="0:11" name="Main" id="0:10">
    <LayoutComponentStyle layoutWidthScaleType="fill" layoutHeightScaleType="fill"
                          name="Main Style" id="0:11"/>
</LayoutComponent>

<!-- a participant carries both itself -->
<LayoutParticipant layoutWidthScaleType="fill" fractionalWidth="1" name="Cell"/>
```

This split is the most common reason a `fill` layout ignores the ratio you
thought you set: the weight went onto the style, where nothing reads it.

## Units, and the trap

Every dimensional property has a matching `*UnitsValue`, accepting `points`,
`percent`, `auto` or `undefined`.

**Their defaults differ, and that matters.** `widthUnitsValue` and
`heightUnitsValue` default to `points`, so sizes work with no extra attribute.
But `paddingLeftUnitsValue`, `marginTopUnitsValue`, `gapHorizontalUnitsValue`,
`gapVerticalUnitsValue` and the rest default to `undefined` — which is why
editor-exported files set them explicitly on every padding, margin and gap they
use.

**An `undefined` unit means the value is ignored, not defaulted.** A
`gapVertical="12"` with no `gapVerticalUnitsValue` lays out with **no gap at
all** — it builds clean, inspects clean, and the spacing you asked for simply
is not there.

So padding takes two attributes, not one:

```xml
paddingLeft="16" paddingLeftUnitsValue="points"
```

Set the value alone and the units stay `undefined`. Check with `rive inspect`
whether the units landed as you intended.

## Direction and alignment

| Property | Values |
|---|---|
| `flexDirectionValue` | `column`, `columnReverse`, `row`, `rowReverse` |
| `layoutAlignmentType` | see below |
| `flexWrapValue` | `noWrap`, `wrap`, `wrapReverse` |
| `positionTypeValue` | `static`, `relative`, `absolute` |
| `displayValue` | `flex`, `none` |
| `overflowValue` | `visible`, `hidden`, `scroll` |

### Alignment is one property

`layoutAlignmentType` sets both axes at once. If you know CSS flexbox, this is
the one place Rive diverges — there is no separate main-axis and cross-axis
property to set.

| `layoutAlignmentType` | |
|---|---|
| `topLeft` `topCenter` `topRight` | top row |
| `centerLeft` `center` `centerRight` | middle row |
| `bottomLeft` `bottomCenter` `bottomRight` | bottom row |
| `spaceBetweenStart` `spaceBetweenCenter` `spaceBetweenEnd` | push children apart, aligned on the cross axis |

The nine positional values are **absolute screen positions**, exactly like the
editor's 3×3 alignment picker: the first half is vertical (`top`/`center`/
`bottom`), the second horizontal (`Left`/`Center`/`Right`). `centerLeft` means
vertically centred and packed left, in a `row` or a `column` alike.

Direction does not change what they mean — only how the engine achieves it.
`topLeft` in a row becomes "align items to the cross-axis start"; in a column
the same value becomes "justify content to the main-axis start". Both put the
children at the top.

The three `spaceBetween*` values push children apart along the main axis, with
the suffix choosing the other axis: `spaceBetweenCenter` spreads them and
centres them across.

### Set `clip` explicitly

`LayoutComponent.clip` decides whether a box cuts off what its children draw
outside its bounds — a knob on the edge of a progress track, a badge
overhanging a card corner, a shadow.

**Do not rely on the default.** `rive schema` reports `= true`, the runtime's
own default is `false`, and which one a given file ends up with depends on how
it was produced. Write it on any box where the answer matters:

```xml
<LayoutComponent clip="false" width="340" height="120" styleId="0:11" name="Card" id="0:10">
    <LayoutComponentStyle name="Card Style" id="0:11"/>
</LayoutComponent>
```

Prefer the symbolic names. Enums are the one place a typo is a build error
rather than a silent wrong value, and `rive schema LayoutComponentStyle` lists
every accepted name per property.

## Gaps, borders, corners

`gapHorizontal` and `gapVertical` space children without margins on each one.
`borderLeft`/`Right`/`Top`/`Bottom` inset content. `cornerRadiusTL` and siblings
round the layout box itself, so a `LayoutComponent` with a `Fill` can be a
rounded card without a `Shape` inside it.

All take the same `*UnitsValue` treatment as padding.

## Grid

`layoutTypeValue` on the style picks the algorithm the box uses for its
children: `flex` (the default), `grid`, or `stack`. A grid is what you want when
things have to line up in **both** directions — a stack of flex rows cannot keep
a column aligned across rows, because each row sizes independently.

The tracks are **`GridTrack` children of the `LayoutComponent`, not of the
style**. That split catches people out: the algorithm is chosen on the style,
the tracks live on the component beside it. A track nested in the style, or
anywhere else, is ignored; `inspect` reports it as `wrong-parent`.

```xml
<LayoutComponent styleId="0:11" name="Sources" id="0:10">
    <LayoutComponentStyle layoutTypeValue="grid"
        layoutWidthScaleType="fill" layoutHeightScaleType="fill"
        gapHorizontal="12" gapHorizontalUnitsValue="points"
        gapVertical="14" gapVerticalUnitsValue="points"
        name="Sources Style" id="0:11"/>

    <!-- three columns: hug the label, give the bar the slack, hug the value -->
    <GridTrack collection="template-columns" trackType="auto" name="Label"/>
    <GridTrack collection="template-columns" trackType="fr" trackValue="1" name="Bar"/>
    <GridTrack collection="template-columns" trackType="auto" name="Value"/>

    <GridTrack collection="template-rows" trackType="fr" trackValue="1" name="Row"/>
    <GridTrack collection="template-rows" trackType="fr" trackValue="1" name="Row"/>

    <!-- children fill the cells in order -->
    ...
</LayoutComponent>
```

Each `GridTrack` is one track. `collection` says which list it joins —
`template-columns`, `template-rows`, `auto-columns`, `auto-rows` — and
`trackType` is the sizing function: `auto`, `points`, `percent` or `fr`, with
`trackValue` carrying the number. Set `trackMaxType` as well and the track
becomes `minmax(track, max)`; its `none` is the "no maximum" case, so its
numbering is offset by one from `trackType`.

Children flow into the cells in declaration order, row by row; tracks past the
template come from `auto-columns`/`auto-rows`, or are sized `auto` if there are
none. To place one explicitly, give it a **`GridItemPlacement`** child:
`gridColumn` and `gridRow` are 1-based with `0` meaning auto and `-1` the last
cell, and `gridColumnSpan`/`gridRowSpan` stretch it.

```xml
<LayoutComponent styleId="0:31" name="Hero" id="0:30">
    <GridItemPlacement gridColumn="1" gridRow="1" gridColumnSpan="2" name="Place"/>
    ...
</LayoutComponent>

<!-- on a participant, the placement sits beside the LayoutParticipant -->
<Text name="Caption" id="0:40">
    <LayoutParticipant layoutWidthScaleType="fill" name="Caption Layout"/>
    <GridItemPlacement gridColumn="2" gridRow="-1" name="Place"/>
    ...
</Text>
```

A placement goes on a `LayoutComponent` or on the `Shape`, `Text` or `Image`
that hosts a `LayoutParticipant`. Anywhere else — inside the participant, on a
nested artboard, a leaf or a list — it is ignored and the item is auto-placed;
`inspect` reports the misplaced ones as `wrong-parent`. A placement on a
drawable with no `LayoutParticipant` is ignored too, since that drawable is not
a grid item at all.

### Alignment inside a cell

An item placed straight into a cell sits at the cell's top-left, and a `fill`
axis stretches it across the cell. That is all a grid decides.

**To align something within a cell, give the cell a layout box** and let that
box align what goes in it. The box fills the cell (`fill` on both axes) and uses
the ordinary `layoutAlignmentType` — the same nine-way picker as any flex box,
`bottom*` included:

```xml
<!-- a value right-aligned and vertically centred in its cell -->
<LayoutComponent styleId="0:61" name="Value Cell" id="0:60">
    <LayoutComponentStyle layoutWidthScaleType="fill" layoutHeightScaleType="fill"
        layoutAlignmentType="centerRight" name="Value Cell Style" id="0:61"/>
    <Text name="Value" id="0:62">
        <LayoutParticipant layoutWidthScaleType="hug" layoutHeightScaleType="hug"
                           name="Value Layout"/>
        ...
    </Text>
</LayoutComponent>
```

This is the area/leaf split again: the cell box is the area, the participant
inside it is the leaf. Add one only where a cell needs something other than
top-left — a centred label, a right-aligned value, a thin progress bar sitting
level with the text beside it. A `GridItemPlacement`, if the cell needs one,
goes on the cell box. A cell box is still measured by what it holds, so it is
safe in an `auto` track.

Do not reach for the grid's own alignment properties (`justifyItemsValue`,
`justifySelfValue`, or a `layoutAlignmentType` on the grid's style). The editor
shows none of them for a grid, so whatever they do cannot be seen or changed
there.

Remember that a `fixed` item keeps its size even across a span; use `fill` to
cover the area.

An `auto` track sizes to its content, so a child that is `fill` on that axis
gives it nothing to measure and the track collapses to zero — the neighbouring
`fr` track then takes the whole width and the cell vanishes. Put `hug` content
in an `auto` track, or size the track with `points`/`percent`/`fr` instead.

There is no `repeat()`, `auto-fill` or `auto-flow` — write the tracks out, or
generate the markup.

An `ArtboardComponentList` in a grid contributes **one cell per item**, auto
placed in order, so a list inside a grid fills rows and grows implicit rows as
data arrives. Give the grid an `auto-rows` track to size those rows.

### Stack

`layoutTypeValue="stack"` puts every child into one shared cell, overlapping,
like a `ZStack`. It needs no tracks. `layoutAlignmentType` picks where they sit
using the nine positional values, which here mean exactly what the picker shows
whatever the direction; the `spaceBetween*` values keep their horizontal suffix
and sit at the top. `fill` on an axis stretches a child across the box. A
`GridItemPlacement` does nothing in a stack.

## Scrolling

A scroll view is **two nested layout boxes** with a `ScrollConstraint` on the
inner one. The constraint reads its own parent as the content and its
grandparent as the viewport, so the nesting is the wiring:

```xml
<ElasticScrollPhysics name="Physics" id="0:90"/>

<LayoutComponent width="240" height="300" clip="true" styleId="0:3" name="Viewport" id="0:2">
    <LayoutComponentStyle layoutWidthScaleType="fixed" layoutHeightScaleType="fixed"
                          flexDirectionValue="column" name="VS" id="0:3"/>

    <LayoutComponent width="240" styleId="0:5" name="Content" id="0:4">
        <LayoutComponentStyle layoutWidthScaleType="fixed" layoutHeightScaleType="hug"
                              flexDirectionValue="column"
                              gapVertical="6" gapVerticalUnitsValue="points"
                              name="CS" id="0:5"/>
        <ScrollConstraint directionValue="vertical" physicsId="0:90" name="Scroll"/>
    </LayoutComponent>
</LayoutComponent>
```

Four things have to be true:

- the **viewport is `fixed`** on the scroll axis and `clip="true"`, or there is
  nothing to scroll within and the overflow just draws
- the **content `hug`s** that axis, so it can grow past the viewport
- the **constraint is a child of the content**, not the viewport
- there is a **state machine on the artboard**, or no pointer reaches it at all
  ([why](gotchas.md#without-a-state-machine-an-artboard-is-half-alive))

**Always point `physicsId` at an `ElasticScrollPhysics`.** With no physics
object the constraint still scrolls, but without momentum — behaviour identical
to `ClampedScrollPhysics`, and nothing reports it. `physicsTypeValue` defaults
to elastic, which makes the omission look harmless; the effective behaviour is
not. `inspect` warns with `scroll-without-physics`.

**Interactive content inside a scroll view must claim its pointer.** A script
that handles a drag and does not call `event:hit()` on every event of it loses
the gesture to the scroll, and its clicks with it — see
[luau/protocols.md](luau/protocols.md#claim-the-pointer-or-something-above-you-takes-it).

`snap`, `infinite`, `dragMultiplier` and `threshold` tune the feel.
`virtualize` with `virtualizeBuffer` keeps only the visible rows realized, for
long lists.

### Tuning the fling

Momentum lives on the physics object, not the constraint:

| Property | Default | Effect |
|---|---|---|
| `friction` | `8.0` | how fast a fling decelerates — **lower carries further** |
| `speedMultiplier` | `1.0` | how fast a fling launches |
| `elasticFactor` | `0.66` | how far it rubber-bands past the ends |

**The default is heavy.** At `friction="8"` a flick travels a short distance and
stops, which reads as "momentum isn't working" next to a phone. For a
touch-like throw start around:

```xml
<ElasticScrollPhysics friction="2.5" speedMultiplier="1.2"
                      elasticFactor="0.7" name="Physics" id="0:90"/>
```

and adjust from there — lower `friction` for a longer glide, higher
`speedMultiplier` if the throw feels reluctant to start.

Captures are reproducible for this — a headless run is deterministic, so the
same gesture throws the same distance every time and you can compare step counts
to confirm momentum is carrying. Whether it *feels* right is still a human call
in the live window, which runs on real time. See
[workflow.md](workflow.md#dragging); a `--pointer=trackpad` swipe flings the
same way, and `--pointer=wheel` checks the view takes a wheel at all
([workflow.md](workflow.md#wheel-and-trackpad)). `wheelInteractive="false"` on
the constraint keeps drags and refuses both.

The decay is exponential — `speed -= speed * min(1, dt * friction)` — so glide
distance is roughly `velocity / friction`. Halving `friction` doubles the
throw, which makes these large steps rather than fine adjustments. For
reference, an iPhone's `decelerationRate.normal` works out at about `2.0`, so
the `8.0` default decelerates roughly four times as hard as a phone.

`elasticFactor` is an **exponent**, not a fraction: overscroll is
`pow(distance, elasticFactor)`, so `0.7` turns 100pt of pull into about 25pt of
visible give. The `0.66` default invites the wrong reading.

### A scroll bar

`ScrollBarConstraint` gives the scroll view a visible bar, and it is wired by
nesting in the same way the scroll constraint is — one layout box inside
another, with the constraint on the inner one:

```xml
<LayoutComponent width="8" height="300" styleId="0:21" name="Track" id="0:20">
    <LayoutComponentStyle layoutWidthScaleType="fixed" layoutHeightScaleType="fixed" name="TrS" id="0:21"/>
    <Fill name="F"><SolidColor colorValue="FF2A2F3A" name="C"/></Fill>

    <LayoutComponent width="8" height="60" styleId="0:23" name="Thumb" id="0:22">
        <LayoutComponentStyle layoutWidthScaleType="fixed" layoutHeightScaleType="fixed"
                              cornerRadiusTL="4" name="ThS" id="0:23"/>
        <Fill name="F"><SolidColor colorValue="FF57A5E0" name="C"/></Fill>
        <ScrollBarConstraint scrollConstraintId="0:14" directionValue="vertical" name="Bar"/>
    </LayoutComponent>
</LayoutComponent>
```

The constraint's **parent is the thumb** and its **grandparent is the track** —
so the two boxes are the bar, and both are ordinary layout boxes you style with
a `Fill` and `cornerRadius*`. `scrollConstraintId` is the one id, naming the
`ScrollConstraint` the bar reflects; the bar and the scroll view do not have to
be siblings, or anywhere near each other in the tree.

It is two-way: the thumb tracks the scroll offset, and dragging the thumb — or
clicking the track — scrolls the content. That is why it needs no listener.

`autoSize` defaults to **true**, which sizes the thumb from the fraction of the
content actually visible, the way a native scroll bar does; the `height` you
author is then only a starting value. Set it `false` to keep a fixed-size thumb.
`directionValue` must match the axis the `ScrollConstraint` scrolls.

## Layouts and artboards

**An artboard lays out its children**, but only the ones that take part. As a
direct child of an artboard:

| Child | Treated as |
|---|---|
| `LayoutComponent` | positioned and sized by the artboard |
| a component carrying a `LayoutParticipant` | positioned and sized by the artboard |
| `NestedArtboardLayout` | positioned and sized by the artboard |
| `ArtboardComponentList` | positioned and sized by the artboard |
| `Node`, `Solo` | transparent: whatever takes part inside is laid out by the artboard, [as in a box](#groups-and-solos-inside-a-layout) |
| anything else — a `Shape` or `Text` with no participant | ordinary artboard transform space, left where you put it |

That is what lets a responsive shell and a hand-placed watermark live at the top
level together.

**An artboard is stricter than a layout box about the rest.** A `fixed` or
`fill` layout box resizes its non-participating children; an artboard never
does. See [above](#but-it-may-still-be-resized-by-that-box) — it is the one
place where moving a shape between two apparently similar parents changes its
size.

For a scene that is responsive throughout, the usual shape is one root
`LayoutComponent` sized to fill the artboard, with everything inside it — one
place to reason about instead of a mix.

That root is also what a `ScriptedLayout` needs to receive the artboard's size —
see [luau/protocols.md](luau/protocols.md).

To repeat one artboard per item in a data list — a feed, a leaderboard — put an
`ArtboardComponentList` inside a layout box and the rows flow with it. See
[data.md](data.md#lists-and-repeated-artboards).

## Transforming a layout box

A `LayoutComponent` is a `TransformComponent`, so it carries the ordinary
`x`, `y`, `rotation`, `scaleX`, `scaleY` and `opacity` — all animatable and
bindable — **on top of** whatever the layout engine computes for it.

The engine decides where the box goes; the transform then offsets it from
there. That separation is what makes state changes cheap: a card can be
positioned entirely by layout and still scale up on hover, without any of its
layout properties changing.

```xml
<LayoutComponent scaleX="1.04" scaleY="1.04" width="160" height="200"
                 styleId="0:11" name="Card" id="0:10">
    <LayoutComponentStyle name="Card Style" id="0:11"/>
    <ComponentOrigin originX="0.5" originY="0.5" name="Origin"/>
    <Fill name="Fill"><SolidColor colorValue="FF2A2F3A" name="C"/></Fill>
</LayoutComponent>
```

**`ComponentOrigin` sets the pivot**, as a nested child, in normalized
coordinates — `0.5, 0.5` is the centre. Without it a layout box scales and
rotates about its top-left corner, so a hover grow slides down and right
instead of expanding in place. It is the layout equivalent of `originX`/
`originY` on a parametric shape.

This is the natural way to build interaction states. Give the base state a
timeline with `scaleX`/`scaleY` at `1`, the hover state one at `1.04`, and
transition between them — the layout never recomputes, so nothing reflows and
neighbouring items do not shift. The same applies to a transition-in: key
`opacity` and `y` on the box while the engine holds its position.

Keying `x`/`y` here offsets the box **from** its computed position rather than
replacing it, which is what you want for a nudge, a shake or a slide-in.

## Animating layout

`interpolationTime` and `interpolationType` on the style animate layout changes
rather than snapping them, which is how a resizing panel eases into place.
`animationStyleType` chooses between `none`, `inherit` and `custom`.
