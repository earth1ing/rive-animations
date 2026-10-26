# Groups, transforms and draw order

Everything visible in an artboard sits in a tree, and its position on screen is
the product of its own transform and every transform above it. This is the part
of the format you use in every file without thinking about it — until something
lands in the wrong place.

## Node is the group

A `Node` draws nothing. It exists to hold a transform that its children inherit:

```xml
<Node x="150" y="100" rotation="0.5235988" name="Dial" id="0:20">
    <Shape name="Hand" id="0:21">
        <Rectangle width="4" height="60" name="Path"/>
        <Fill name="Fill"><SolidColor colorValue="FFE0573C" name="C"/></Fill>
    </Shape>
    <Shape x="0" y="-60" name="Tip" id="0:22">
        <Ellipse width="10" height="10" name="Path"/>
        <Fill name="Fill"><SolidColor colorValue="FFFFFFFF" name="C"/></Fill>
    </Shape>
</Node>
```

Rotating the `Node` swings both children around the node's origin. This is what
the editor calls a **group**, and it is the standard way to build anything that
pivots: put the children in a group positioned at the pivot point, then animate
the group rather than the parts.

It is also the cheapest fix for an object that rotates about the wrong point.
Rather than offsetting the shape, wrap it in a `Node` placed where the pivot
belongs and key that.

## The shared transform properties

Every positioned object — `Node`, `Shape`, `Text`, `Bone`, `Solo`,
`LayoutComponent` — carries the same set, inherited from `TransformComponent`:

| Property | Default | Note |
|---|---|---|
| `x`, `y` | `0` | position in the parent's space |
| `rotation` | `0` | **radians**; a full turn is `6.2831855` |
| `scaleX`, `scaleY` | `1` | negative values mirror |
| `opacity` | `1` | `0`–`1` |

All six are animatable *and* bindable, which is most of what a Rive file
animates. `x` is propertyKey 13, `y` 14, `rotation` 15, `scaleX` 16, `scaleY`
17, `opacity` 18 — the keys you will key and bind most often.

Children are positioned in their parent's space, so a child at `x="0"` sits at
the parent's origin, not the artboard's.

## Opacity multiplies

A group's opacity is not just its own — it is multiplied into every descendant.
A `Node` at `opacity="0.5"` containing a shape at `opacity="0.5"` renders that
shape at `0.25`.

That makes a wrapping `Node` the way to fade a whole assembly with one keyed
property, instead of keying opacity on each part. It also means an assembly that
will not become fully visible usually has a partly-transparent ancestor.

## Hiding without deleting

`Component.flags` carries bits written as individual attributes:

```xml
<Shape hidden="true" name="Debug Overlay" id="0:30"/>
```

`hidden` removes it from rendering, `locked` and `guide` are editor affordances,
and `guide` marks it as a non-exporting reference object.

For switching between variants at runtime, use a `Solo` rather than keying
`hidden` — see [rigging.md](rigging.md#solo).

## Origin

`originX` and `originY` on the artboard are **normalized**, not pixels: `0` is
the left/top edge, `0.5` the centre, `1` the right/bottom.

```xml
<Artboard originX="0.5" originY="0.5" width="500" height="500" name="A" id="0:2"/>
```

The origin is where the artboard is anchored when a runtime positions it, so a
centred origin is what you want for anything that scales or rotates as a whole.

**It also shifts the artboard's own coordinate space, so it is not free.** With
`originX="0.5" originY="0.5"` on a 500×500 artboard, content authored at
`(250,250)` no longer sits in the middle — every child moves by half the
artboard and most of the scene leaves the frame. The build stays clean and
`problems` stays empty, so it reads as a layout bug. Leave the origin at `0`
unless a host is positioning the artboard and you know it wants a centred
anchor, and re-place content when you change it.

Procedural shapes have their own `originX`/`originY` with the same normalized
meaning — that is how a `Rectangle` grows from its centre rather than its
corner, covered in [drawing.md](drawing.md).

## Draw order

**The first sibling draws on top.** Declaration order is front-to-back, the way
a layers panel in a design tool reads — the thing you write first is the thing
in front.

This catches people out, because it is the opposite of HTML and SVG. If a shape
you added is invisible, this is the first thing to suspect: it is almost
certainly behind a sibling you declared earlier, and nothing in `--verify` or
`inspect` will say so.

```xml
<Node name="Badge">
    <Shape name="Dot"><Ellipse width="12" height="12" name="P"/>
        <Fill name="F"><SolidColor colorValue="FFFFFFFF" name="C"/></Fill></Shape>
    <Shape name="Plate"><Ellipse width="64" height="64" name="P"/>
        <Fill name="F"><SolidColor colorValue="FF6C5CE7" name="C"/></Fill></Shape>
</Node>
```

The dot is on top of the plate. Swap them and the dot disappears behind it.

So to put something in front, move it **earlier** in its parent's children.
Nesting does not change the rule, and it is the same whether the parent is a
`Node`, a `LayoutComponent` or the artboard itself.

### Overriding it

`DrawRules` and `DrawTarget` override hierarchy order, which is how you animate
one part moving in front of another without restructuring the tree:

```xml
<Shape name="Card" id="0:20">
    <Rectangle width="80" height="120" name="Path"/>
    <Fill name="Fill"><SolidColor colorValue="FF2A2F3A" name="C"/></Fill>
</Shape>

<Shape name="Chip" id="0:21">
    <Rectangle width="40" height="40" name="Path"/>
    <Fill name="Fill"><SolidColor colorValue="FFE0B057" name="C"/></Fill>

    <DrawRules drawTargetId="0:31" name="Rules" id="0:30">
        <DrawTarget drawableId="0:20" placementValue="before" name="Above card" id="0:31"/>
    </DrawRules>
</Shape>
```

`DrawRules` attaches to the object being reordered and names the active
`DrawTarget`, which must be nested inside it. The runtime collects targets
from each rule's children, so a target declared anywhere else is never
registered and the rule silently does nothing. `inspect` reports that as
`draw-target-not-child-of-rules`. The target names some other drawable and
whether to sit `before` or `after` it in the painted order. `before` draws
the ruled object on top of the target and `after` draws it behind. The chip
above is declared later than the card, so tree order would put it behind,
and the rule brings it to the front.

`drawTargetId` is animatable, so keying it between targets is how a card is
dealt to the top of a stack.

Reordering the tree is almost always simpler. Reach for it only when the order has to change
over time.

## Blend modes

Every drawable has `blendModeValue`, controlling how it composites with what is
beneath:

```xml
<Shape blendModeValue="screen" name="Glow" id="0:20">
    <Ellipse width="120" height="120" name="Path"/>
    <Fill name="Fill"><SolidColor colorValue="FF57A5E0" name="C"/></Fill>
</Shape>
```

Accepted names: `srcOver` (the default, ordinary alpha compositing), `screen`,
`overlay`, `darken`, `lighten`, `colorDodge`, `colorBurn`, `hardLight`,
`softLight`, `difference`, `exclusion`, `multiply`, `hue`, `saturation`,
`color`, `luminosity`.

The underlying integers are not contiguous — `srcOver` is `3` and the rest run
from `14` — so use the names. Files exported from the editor contain the raw
numbers, which is why a decompiled `.rev` shows `blendModeValue="15"` where you
would write `overlay`.

Blend mode is neither animatable nor bindable. To change compositing over time,
key opacity, or swap between two shapes with a `Solo`.

### Fills and strokes have a separate one

Confusingly, `Fill` and `Stroke` carry their **own** `blendModeValue` — a
different property from the drawable's, letting one paint composite differently
from the shape as a whole.

It does **not** accept the names. It is numeric only, and its default is `127`,
meaning *inherit from the shape*:

```xml
<Shape blendModeValue="screen" name="Glow" id="0:20">   <!-- names work here -->
    <Fill blendModeValue="14" name="Fill">              <!-- numbers only here -->
        <SolidColor colorValue="FF57A5E0" name="C"/>
    </Fill>
</Shape>
```

Writing `blendModeValue="screen"` on a `Fill` is a build error, not a silent
one, so you will find out immediately. Set the mode on the shape unless you
specifically need the paint to differ, and expect to see `127` on every `Fill`
in `rive inspect` output — that is the inherit sentinel, not a real mode.

## Clipping

Clipping is a `ClippingShape` child naming the shape to clip against — see
[drawing.md](drawing.md#effects-and-clipping).

## Checking your work

Transform bugs are position bugs, and `inspect` resolves the tree so you can see
where something actually ended up:

```bash
rive inspect . --json | jq '[..|objects|select((.type//"")=="Node")|{name,x,y,rotation}]'
```

If a group's `rotation` reads `0` when you keyed it, the keys went onto the
shape rather than the group — a common outcome when the `KeyedObject.objectId`
names the wrong id.
