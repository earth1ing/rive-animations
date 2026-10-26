# Shapes and paint

Everything visible is a `Shape`: a container holding **geometry** and **paint**.
The shape carries position and transform, its geometry children carry size, and
its paint children carry colour.

```xml
<Shape x="200" y="150" name="Box" id="0:14">
    <Rectangle width="120" height="80" name="Path"/>
    <Fill name="Fill">
        <SolidColor colorValue="FF57A5E0" name="Color"/>
    </Fill>
</Shape>
```

That split matters constantly: `width` lives on the `Rectangle`, `x` on the
`Shape`. Bind or key the one that owns the property.

Draw order runs front-to-back: the **first** shape declared paints on top.
See [transforms.md](transforms.md#draw-order) — it is the reverse of HTML.

## Geometry

Parametric shapes take `width`/`height` and an origin:

| Element | Notes |
|---|---|
| `Rectangle` | `cornerRadiusTL/TR/BL/BR`; `linkCornerRadius` (default true) makes TL drive all four |
| `Ellipse` | a circle is equal width and height |
| `Triangle` | |
| `Polygon` | `points`, `cornerRadius` |
| `Star` | extends `Polygon`, adding `innerRadius` — so it has `points` and `cornerRadius` too |

`originX`/`originY` are normalized: `0.5` centres the geometry on the shape's
position, which is what you want for anything that rotates or scales.

A `Shape` can hold several geometry children — they combine into one filled
path, which is how holes and compound shapes are made.

### Polygons and stars

`Polygon` is a regular n-gon inscribed in `width` × `height`. `Star` extends it,
adding a second radius for the inner points:

```xml
<Shape x="150" y="150" name="Badge" id="0:20">
    <Star width="120" height="120" points="6" innerRadius="0.45"
          cornerRadius="2" name="Path"/>
    <Fill name="Fill"><SolidColor colorValue="FFE0B057" name="C"/></Fill>
</Shape>

<Shape x="320" y="150" name="Hex" id="0:22">
    <Polygon width="100" height="100" points="6" name="Path"/>
    <Fill name="Fill"><SolidColor colorValue="FF57A5E0" name="C"/></Fill>
</Shape>
```

`points` counts the corners — `3` is a triangle, `6` a hexagon, and the default
is `5`. On a `Star` it counts the outer spikes, so a five-pointed star is
`points="5"`.

`innerRadius` is a fraction of the outer radius, not a length. `0.5` is the
default and reads as a conventional star; below about `0.3` the spikes turn into
needles, and at `1` a star is indistinguishable from its polygon.

`cornerRadius` rounds every corner, inner and outer alike, and is what turns a
star into a soft badge or burst.

**These differ in what they support.** `innerRadius` is marked animatable *and*
bindable; `points` and `cornerRadius` are marked bindable only:

| Property | Animatable | Bindable |
|---|---|---|
| `width`, `height`, `originX`, `originY` | yes | yes |
| `innerRadius` *(Star)* | yes | yes |
| `points` | no | yes |
| `cornerRadius` | no | yes |

So a pulsing star keys `innerRadius`, while a shape whose corner count follows
data uses a bind. `points` is an integer, so if you do key it the keyframe is
`KeyFrameUint`, not `KeyFrameDouble` — see
[format.md](format.md#the-keyframe-type-must-match-the-property).

`rive schema Star` marks each property, and is the check to run before building
an animation around one.

### Custom paths

For anything not parametric, use `PointsPath` with vertex children:

```xml
<Shape x="100" y="100" name="Arrow" id="0:20">
    <PointsPath isClockwise="true" name="Path">
        <StraightVertex x="0" y="-40"/>
        <StraightVertex x="30" y="20"/>
        <CubicMirroredVertex x="0" y="0" rotation="0" distance="12"/>
        <StraightVertex x="-30" y="20"/>
    </PointsPath>
    <Fill name="Fill">
        <SolidColor colorValue="FFE0E0E0" name="Color"/>
    </Fill>
</Shape>
```

Vertices are in the shape's local space, in order. The four kinds differ only in
how they curve:

- `StraightVertex` — a corner. Takes `radius` to round it, **clamped** to what
  the corner can take: never more than half the shorter adjacent segment, and
  reduced further on tight angles. Oversized values round as much as fits
  rather than distorting the path, so a large `radius` is a safe way to say
  "as round as this corner allows".
- `CubicMirroredVertex` — smooth, symmetric handles. `rotation` and `distance`.
- `CubicDetachedVertex` — handles set independently:
  `inRotation`/`inDistance` and `outRotation`/`outDistance`.
- `CubicAsymmetricVertex` — shared direction, independent lengths.

**The two cubic types name their handles differently.** `CubicMirroredVertex`
has one pair, `rotation`/`distance`, because both handles mirror. The detached
and asymmetric ones have two pairs and prefix them — `inRotation`, not
`rotation`. Reaching for `rotation` on a detached vertex is a build error, which
at least tells you immediately.

**Close the path with `isClosed="true"`.** An open `PointsPath` with a `Fill`
renders the fill across an implied straight line between the last vertex and the
first, which is rarely what you want for an icon. `isClockwise` is a separate
thing and does not close anything.

**`isClockwise` has to match the direction your vertices actually run.** It is
not computed for you, and nothing checks it. It defaults to `true`, so a path
whose vertices run counter-clockwise needs `isClockwise="false"` written on it.

With the `clockwise` fill rule, which the editor enables for features such as
feathering, the direction decides whether a contour fills or cuts a hole. Get
`isClockwise` wrong there and the shape does the opposite of what you meant,
usually meaning it vanishes.

To tell which way a path runs, walk its vertices in order. In Rive's
coordinates y grows downward, so a path going right along the top, down, then
back left along the bottom is clockwise. Reversing the order of the vertices
reverses the winding.

**Do not write `pathFlags`.** `rive schema` lists it on every path type, but it
is computed at build time from `isClockwise` and the hidden state, and an
authored value is ignored. It is not an error to write one, it simply has no
effect.

## Fills and strokes

Both are paint children of a `Shape`, and both need a colour child of their own
— a `Fill` with no `SolidColor` or gradient inside draws nothing.

```xml
<Shape x="200" y="200" name="Ring" id="0:30">
    <Ellipse width="120" height="120" name="Path"/>
    <Stroke thickness="8" cap="round" join="round" name="Stroke">
        <SolidColor colorValue="FFFFFFFF" name="Color"/>
    </Stroke>
</Shape>
```

`Stroke` takes `thickness`, `cap` (`butt`, `round`, `square`) and `join`
(`miter`, `round`, `bevel`). `Fill` takes `fillRule` (`nonZero`, `evenOdd`).

A shape with no `Fill` is outline-only; one with both paints the fill first.

**Paint order inside a shape is the opposite of shape order between shapes.**
Sibling shapes paint first-declared-on-top (see [transforms.md](transforms.md));
paint children *within* one shape paint last-declared-on-top, so a second `Fill`
covers the first. Both rules matter the moment you layer — put the glow paint
first and the crisp one last.

### Dashes and trims

Stroke effects nest **inside the `Stroke`**:

```xml
<Stroke thickness="4" name="Stroke">
    <SolidColor colorValue="FFFFFFFF" name="Color"/>
    <DashPath name="Dashes">
        <Dash length="20" name="On"/>
        <Dash length="10" name="Off"/>
    </DashPath>
</Stroke>
```

`Dash` children alternate drawn and gap, starting with drawn. `DashPath.offset`
shifts the pattern along the path, and `DashPath.offsetIsPercentage` switches
*that* to a fraction of path length. The matching `lengthIsPercentage` is on
each **`Dash`**, not on `DashPath`.

`TrimPath` draws only part of the outline — `start`, `end` and `offset` as
fractions of path length (`end="1"` is the whole path), which is how progress
rings and drawing-on effects are made.

`modeValue` picks how a trim spanning several contours is measured:
`sequential` (the default) walks them end to end, `synchronized` applies the
same fraction to each. There is no `0`; writing one is an error naming the
accepted values.

### Sharing one effect across many paints

Authoring the same trim on eight strokes means eight objects to keep in step,
and keyframing the reveal means eight keyed objects. A **`GroupEffect`** is that
stack of effects written once. It holds the effects as children, and each paint
that wants them nests a **`TargetEffect`** pointing at it:

```xml
<GroupEffect name="Reveal" id="0:80">
    <TrimPath start="0" end="0.4" name="Trim"/>
</GroupEffect>

<Shape x="80" y="100" name="A" id="0:20">
    <Ellipse width="60" height="60" name="P"/>
    <Stroke thickness="4" name="S">
        <SolidColor colorValue="FF57A5E0" name="C"/>
        <TargetEffect targetId="0:80" name="Use Reveal"/>
    </Stroke>
</Shape>
```

The group sits in the artboard alongside the shapes rather than inside any of
them, and its effects apply in child order — so a group holding a trim then a
dash trims first and dashes the result. Point a second shape's `TargetEffect` at
the same id and both strokes reveal together off one keyed `TrimPath`.

`TargetEffect` is only valid inside a `Fill` or a `Stroke`; anywhere else the
runtime rejects the whole file. A `targetId` naming something that is not a
`GroupEffect` is the softer failure — that paint just draws unaffected.

## Gradients

A gradient replaces `SolidColor` inside a `Fill` or `Stroke`, with two or more
`GradientStop` children:

```xml
<Fill name="Fill">
    <LinearGradient startX="0" startY="-60" endX="0" endY="60" name="Gradient">
        <GradientStop colorValue="FFFFE066" position="0"/>
        <GradientStop colorValue="FFCC3311" position="1"/>
    </LinearGradient>
</Fill>
```

`position` is `0`–`1` along the gradient. `startX/Y` and `endX/Y` are in the
shape's local space, so a vertical gradient differs in Y and not X.

`RadialGradient` takes the same stops; `start` is the centre and `end` sets the
radius.

Stops with no `position` all sit at `0` and the gradient renders flat — a common
silent mistake, since nothing errors.

## Effects and clipping

**`Feather`** softens a stroke, nested inside it:

```xml
<Stroke thickness="5" name="Glow">
    <SolidColor colorValue="FF3FE0C8" name="Color"/>
    <Feather strength="7" name="Feather"/>
</Stroke>
```

`inner="true"` feathers inward from the edge; the default feathers outward.

The feathered paint **is** the blurred shape — it replaces the crisp one rather
than adding a halo behind it. A glowing outline is therefore two paints: the
feathered one first, the crisp one after. Within a shape the later paint draws
on top, so the crisp copy sits over its own glow.

```xml
<Shape x="250" y="100" name="Node" id="0:30">
    <Ellipse width="70" height="70" originX="0.5" originY="0.5" name="Path"/>
    <Stroke thickness="5" name="Glow">
        <SolidColor colorValue="FF3FE0C8" name="C"/>
        <Feather strength="7" name="F"/>
    </Stroke>
    <Stroke thickness="2.5" name="Crisp">
        <SolidColor colorValue="FF3FE0C8" name="C"/>
    </Stroke>
</Shape>
```

> **A feathered `Fill` needs `fillRule="clockwise"`.** The renderer skips a
> feathered fill under any other rule, so the paint disappears entirely — at
> every strength, and with `inner="true"` — while the build stays clean and
> `problems` stays empty. The editor switches the rule for you when you feather
> a fill; here you write it:
>
> ```xml
> <Fill fillRule="clockwise" name="Shadow">
>     <SolidColor colorValue="66000000" name="Color"/>
>     <Feather strength="24" offsetY="16" name="Feather"/>
> </Fill>
> ```
>
> `offsetX`/`offsetY` move the blurred copy, which with a crisp `Fill` declared
> after it is a drop shadow. A `Feather` placed directly under a `Shape` rather
> than inside a paint parses and does nothing.

**`ClippingShape`** masks a shape to another shape's geometry. It nests inside
the shape being clipped and names the clipper by id:

```xml
<Shape x="100" y="100" name="Photo" id="0:40">
    <Rectangle width="200" height="200" name="Path"/>
    <Fill name="Fill">...</Fill>
    <ClippingShape sourceId="0:50" name="Clip"/>
</Shape>

<Shape x="100" y="100" name="Mask" id="0:50">
    <Ellipse width="180" height="180" name="Path"/>
</Shape>
```

The clipper is a normal shape elsewhere in the artboard. Give it no `Fill` and
no `Stroke` and it masks without drawing — a shape with no paints still
contributes its geometry.

Keep the clipping source shown: `hidden="true"` hides its descendant paths
in runtime export, leaving an empty mask that hides the clipped artwork.
To make a mask invisible while retaining its geometry, use no paints or a
transparent fill instead of hiding the shape.

Clips follow the fill's post-effect path.

### 9-slice: stretching a bitmap without stretching its corners

An `Image` that has to change size distorts everything in it — rounded corners
smear, borders thicken on one axis. **`NSlicer`** cuts the image into patches
with cut lines and stretches only the middle bands, the same idea as CSS
`border-image` or a 9-patch.

It nests inside the `Image` and holds the cuts as children: `AxisX` for vertical
cut lines, `AxisY` for horizontal ones. Two of each gives the classic nine
patches.

```xml
<Image assetId="0:720" name="Surface" id="0:198">
    <LayoutParticipant layoutWidthScaleType="fill" layoutHeightScaleType="hug" name="LP"/>
    <NSlicer name="Slicer" id="0:199">
        <AxisX offset="0.34" normalized="true" name="x0"/>
        <AxisX offset="0.66" normalized="true" name="x1"/>
        <AxisY offset="0.34" normalized="true" name="y0"/>
        <AxisY offset="0.66" normalized="true" name="y1"/>
    </NSlicer>
</Image>
```

`offset` is where the cut falls. With `normalized="true"` it is a fraction of
the image, which is usually what you want — the same slicer then works whatever
the source resolution is. Leave `normalized` off and the offset is in image
pixels.

`NSlicer` has no properties of its own, so `rive schema NSlicer` looks empty;
everything is in the `Axis` children. One texture plus a slicer is what lets a
single component artboard be placed at several widths with its corners intact.

### When the effect you want is not here

`Feather`, `blendModeValue`, `ClippingShape` and the stroke's `Trim`/`Dash` are
the effects the format has. For anything else, attach a script to the one
shape or region that needs it — see
[luau/protocols.md](luau/protocols.md#scripts-as-effects), and
[luau/api/gpu.md](luau/api/gpu.md) for effects that need WGSL.

## Images

An image is a `Shape`-level drawable referencing an `ImageAsset` root element:

```xml
<Image x="100" y="100" assetId="0:60" name="Logo"/>

<ImageAsset file="logo.png" name="logo" id="0:60"/>
```

An `Image` has **no `width`/`height`** — it takes its size from the asset, and
`x`/`y` plus `originX`/`originY` place it. `fit` and `alignmentX`/`alignmentY`
only matter when a layout sizes it.

The asset is a root element referencing a project file; the bytes are embedded
at build time. Embedded bytes, when you need them, go in a nested
`FileAssetContents`, never in a `bytes` attribute on the asset itself.

To make an image bend rather than just move — an arm, a flag, a face — nest a
`Mesh` in it and skin that. See
[rigging.md](rigging.md#images-deform-the-same-way-once-they-have-a-mesh).

## Finding the rest

Every property of any of these, with types, defaults and accepted enum values:

```bash
rive schema Stroke
rive schema --search gradient
```

`rive schema <Type>` is authoritative; this page covers how the pieces nest,
which is the part schema cannot tell you.
