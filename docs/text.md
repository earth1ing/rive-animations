# Text

Text is three objects, not one: a `Text` container that positions it, one or
more `TextStylePaint` styles that define appearance, and `TextValueRun`s that
hold the actual characters and point at a style.

```xml
<Text x="40" y="60" name="Label" id="0:20">
    <TextStylePaint fontSize="24" fontAssetId="0:30" name="Body" id="0:21">
        <Fill name="Fill">
            <SolidColor colorValue="FFE0E0E0" name="Color"/>
        </Fill>
    </TextStylePaint>
    <TextValueRun styleId="0:21" text="Hello Rive" name="Run"/>
</Text>

<FontAsset file="Inter.ttf" name="Inter" id="0:30"/>
```

Three links to get right:

- the **style needs a `Fill`** with a colour inside it, or the text is invisible
- the **run needs `styleId`** naming a style, or it does not render
- the **style needs `fontAssetId`** naming a `FontAsset` root element

They fail in two different ways. A link that names something wrong — a
`styleId` or `fontAssetId` naming an id that does not exist, or a `FontAsset`
whose `file` is not on disk — **fails the build**, and the error names it. A
link that is simply *missing* — a run with no `styleId`, a style with no `Fill`
— builds clean and renders nothing. Text that is invisible after a clean build
is almost always a missing link.

## Rich text

Multiple runs inside one `Text` flow together as a single paragraph. Give them
different styles to mix appearance mid-sentence:

```xml
<Text x="40" y="60" name="Readout" id="0:20">
    <TextStylePaint fontSize="32" fontAssetId="0:30" name="Big" id="0:21">
        <Fill name="Fill"><SolidColor colorValue="FFFFFFFF" name="C"/></Fill>
    </TextStylePaint>
    <TextStylePaint fontSize="16" fontAssetId="0:30" name="Small" id="0:22">
        <Fill name="Fill"><SolidColor colorValue="FF9099A8" name="C"/></Fill>
    </TextStylePaint>

    <TextValueRun styleId="0:21" text="72" name="Value"/>
    <TextValueRun styleId="0:22" text="°F" name="Unit"/>
</Text>
```

Runs render in document order.

## Sizing and wrapping

`Text` itself carries the layout properties:

| Property | Values |
|---|---|
| `sizingValue` | `autoWidth`, `autoHeight`, `fixed` |
| `overflowValue` | `visible`, `hidden`, `clipped`, `ellipsis`, `fit`, `fitFontSize` |
| `alignValue` | `left`, `right`, `center` |
| `verticalAlignValue` | `top`, `middle`, `bottom` |
| `wrapValue` | `wrap`, `noWrap` |
| `originValue` | `top`, `baseline` |
| `originX`, `originY` | the box's own anchor, `0`–`1`; `0,0` (the default) is top-left |

`verticalAlignValue` only has room to act when the box is taller than its text,
so it does nothing under `autoHeight` — pair it with `fixed` and a `height`.

**`alignValue` works the same way, and this catches people out.** It aligns the
text *within the box*, so under `autoWidth` — where the box shrink-wraps the
line — there is no slack for it to distribute and it does nothing at all. The
`x`/`y` you set is then simply the top-left corner of the text, which reads as
"my centred headline came out right of where I put it".

To centre an auto-sized run on a point, move the box's anchor instead of
aligning inside it:

```xml
<Text x="250" y="150" sizingValue="autoWidth" originX="0.5" originY="0.5"
      name="Headline" id="0:20">
    ...
</Text>
```

That stays centred at any text length, which `fixed` plus `alignValue="center"`
also achieves — but `fixed` pins the box, so if anything downstream depends on
the box tracking its content (a [background](#backgrounds-behind-text), a
parent that hugs it) the origin is the one you want.

Two more live on `TextStylePaint` rather than `Text`, and neither is obvious
from the sizing table:

| Property | |
|---|---|
| `lineHeight` | line spacing; `-1` (the default) means automatic, from the font's own metrics |
| `letterSpacing` | tracking, `0` by default |

`lineHeight` is the one to reach for when a box has to be a predictable height —
two lines at an explicit `lineHeight` is arithmetic you can do, whereas
automatic depends on metrics you cannot see.

`autoWidth` grows the box to fit one line, so wrapping needs `fixed` (or
`autoHeight`) plus a `width`:

```xml
<Text x="40" y="60" width="220" sizingValue="autoHeight" wrapValue="wrap"
      alignValue="center" name="Paragraph" id="0:20">
    ...
</Text>
```

### Positioning several text boxes is a layout job

Everything above sizes text *inside* one box. Placing boxes relative to each
other — a legend, a row of labels, a caption under a heading — is
[layout.md](layout.md)'s job, not something to solve with `x`.

There is no way to ask how wide a rendered run is: `computed*` values are `0`
until something lays the scene out, so hand-positioning a horizontal run of
labels means guessing an advance width and correcting it against a screenshot.
That works for one label and does not scale to four. A `LayoutComponent` row
with a `gap` does, with each `Text` in it carrying a `hug`
`LayoutParticipant` — not wrapped in a layout box of its own. The participant
makes the text the row item directly and sizes it to its glyphs; see
[layout.md](layout.md#shapes-and-text-inside-a-layout-box).

```xml
<Text name="Label" id="0:30">
    <LayoutParticipant layoutWidthScaleType="hug" layoutHeightScaleType="hug"
                       name="Label Layout"/>
    ...
</Text>
```

Inside a layout the participant's scale types decide how the box is sized.
`hug` on both axes leaves the text's own `sizingValue` in charge. A `fixed` or
`fill` width with a `hug` height acts as `autoHeight`: the layout sets the
width and the text wraps within it, so pair it with `wrapValue="wrap"`. `fixed`
or `fill` on both axes acts as `fixed`.

## Binding text to data

A run's `text` is `propertyKey` **268**. Nest the bind under the run:

```xml
<TextValueRun styleId="0:21" text="placeholder" name="Run">
    <DataBindContext sourcePathIds="0:40-0:45" propertyKey="268"/>
</TextValueRun>
```

The source must be a string property. To show a number, put a converter between
them — `DataConverterToString`, optionally with `DataConverterRounder` or
`DataConverterStringPad` — and name it with `converterId` on the bind. Binding a
number property straight to `text` is a type mismatch: it resolves, and does
nothing. `rive inspect` reports that as `incompatible-bind-types`.

The literal `text` stays in the file and shows until the binding takes effect,
so it is worth setting to something sensible rather than empty.

## Fonts

**You must supply a font file. Rive ships none, and there is no system
fallback.** If your project has no font, it cannot render text at all — that is
a hard stop, not a styling problem. Get a `.ttf` into the project first, or use
shapes.

A `FontAsset` is a root element, referenced by `fontAssetId`:

```
myproject/
  rive.yaml
  scene.rml
  Inter.ttf
```

```xml
<FontAsset file="Inter.ttf" name="Inter" id="0:30"/>
```

`file` is a path resolved **relative to the project directory**, and the bytes
are embedded into the built file, so the `.riv` carries the font and does not
need it at runtime.

Because the font is embedded, building a file **redistributes** it. Do not copy
one out of the system font directory to get unblocked: most bundled faces are
licensed for use on that machine, not for embedding in a file you ship, and it
would also make the project build only on your own machine. Use a font that is
licensed for embedding — the open ones from Google Fonts are the usual choice —
or ask whoever owns the project which face to use.

A `file` that is not on disk is the worst silent failure in the format: it
builds clean, `problems` is empty, and the text renders as nothing. See
[gotchas.md](gotchas.md#a-missing-asset-file-reports-nothing-at-all).

### Name the face, not just the file

`fontAssetId` loads the font. Two more attributes on the style, `familyName`
and `styleName`, say which face that is — and **the editor reads those, not the
asset**. Its Font and Weight dropdowns are filled from these two strings, so a
style that omits them opens with both showing `-`, on every text element that
uses it, while the glyphs underneath render correctly.

Nothing here reports it. The CLI resolves text through the asset reference and
the axes alone, so `--verify`, `problems` and `--screenshot` are all clean, and
the gap surfaces after handoff — a designer opens the `.rev` and finds every
text style unlabelled, with no way to tell which weight was meant without
reading the axis value. Set both on every `TextStylePaint`:

```xml
<TextStylePaint fontSize="24" fontAssetId="0:30" familyName="Inter" styleName="Bold"
                name="Heading" id="0:21">
    <Fill name="Fill"><SolidColor colorValue="FFFFFFFF" name="C"/></Fill>
    <TextStyleAxis tag="2003265652" axisValue="700" name="Weight"/>
</TextStylePaint>
```

`familyName` is the family as the font file declares it — name id 1 in the
TTF's `name` table: `Inter`, `Orbitron`, `PragmataPro VF` — not the filename.
`styleName` is the face within that family: `Regular`, `Bold`, `Black`, or for
a variable font the named instance that matches the axis values you set.

They are labels, nothing more. A `styleName` of `Bold` with no `wght` axis still
renders the font's default instance, and an axis at `700` with no `styleName`
still renders bold. The axis decides what renders; the names decide what the
editor shows. Set both, and keep them in step.

### Shipping without embedding

Sometimes you do not want the bytes in the file — a licence that forbids
redistribution, a face the host app already has, or several `.riv`s that would
otherwise each carry the same 300kB font. **Omit `file`** and the asset ships as
a name and nothing else:

```xml
<FontAsset name="Inter" id="0:30"/>
```

Everything else is unchanged: `fontAssetId` still points at it, the runs still
reference their style. What changes is who supplies the bytes — the host
application hands them over at load time through its runtime's asset-handler
API, matching on the asset's `name`.

The catch is local. Nothing in this toolchain can satisfy that handler, so the
font is simply absent here: `--verify` passes, `problems` is empty, and a
`--screenshot` or the watch preview renders the text as nothing at all. If text
is invisible and the font asset has no `file`, that is why.

The same applies to any asset type. See [assets.md](assets.md#three-ways-an-asset-gets-its-bytes).

### Check whether the font is variable

A variable font renders at its **default instance** unless you say otherwise,
and that default is often not what you want. Montserrat's is Thin (100) — drop
it in, set no axes, and every label on the screen comes out hairline, with no
error and nothing in `inspect` to explain it.

If text renders but looks wrong — too light, too narrow — the axes are the first
thing to check, using `TextStyleAxis` below.

For a **variable font**, `TextStyleAxis` children of the style set the axis
values. `tag` is the four-character OpenType axis tag as a packed integer —
`wght` is `2003265652`, `wdth` is `2003072104`:

```xml
<TextStylePaint fontSize="24" fontAssetId="0:30" name="Bold" id="0:21">
    <Fill name="Fill"><SolidColor colorValue="FFFFFFFF" name="C"/></Fill>
    <TextStyleAxis tag="2003265652" axisValue="700" name="Weight"/>
</TextStylePaint>
```

Text with no `fontAssetId` renders nothing, which is the most common reason a
text element appears blank — after the font file simply not being there.

Pair every axis you set with a `styleName` naming the same instance, so the
editor labels the weight you chose — see
[Name the face, not just the file](#name-the-face-not-just-the-file).

### OpenType features

`TextStyleAxis` moves a variable axis. **`TextStyleFeature`** switches an
OpenType *feature* on or off — small caps, ligatures, tabular figures — for
every run using that style:

```xml
<TextStylePaint fontSize="24" fontAssetId="0:30" name="Caps" id="0:21">
    <Fill name="Fill"><SolidColor colorValue="FFFFFFFF" name="C"/></Fill>
    <TextStyleFeature tag="1936548720" featureValue="1" name="smcp"/>
    <TextStyleFeature tag="1818847073" featureValue="0" name="liga"/>
</TextStylePaint>
```

`tag` is packed exactly like an axis tag: the four ASCII characters read
**big-endian**, so `smcp` is `(0x73 << 24) | (0x6D << 16) | (0x63 << 8) | 0x70`
= `1936548720`. In Python that is
`struct.unpack('>I', b'smcp')[0]`. The common ones:

| | | | |
|---|---|---|---|
| `liga` 1818847073 | `dlig` 1684826471 | `calt` 1667329140 | `kern` 1801810542 |
| `smcp` 1936548720 | `c2sc` 1664250723 | `case` 1667330917 | `titl` 1953068140 |
| `lnum` 1819178349 | `onum` 1869509997 | `pnum` 1886287213 | `tnum` 1953396077 |
| `frac` 1718772067 | `ordn` 1869767790 | `sups` 1937076339 | `subs` 1937072755 |
| `zero` 2053468783 | `swsh` 1937208168 | `ss01` 1936928817 | |

`featureValue` is usually `1` on or `0` off; features with several alternates
take the alternate's index. It defaults to `1`, so a feature declared and left
alone is *enabled*.

**The font has to have the feature.** Ask for `smcp` from a face without small
caps and nothing happens — no error, no fallback, no synthesised caps.

A wrong `tag` integer behaves identically, and that combination makes this the
most silent thing in the file: the build is clean, `problems` is empty, and
`rive inspect` echoes whatever integer you wrote back at you, so the tree looks
like confirmation. Nothing in the toolchain distinguishes "feature applied",
"feature absent from the font" and "tag miscomputed".

The only reliable check is a visible A/B. Pick a feature whose effect you can
see on the sample text, render it, flip `featureValue` between `0` and `1`, and
render again — if the two images are identical, the feature is not reaching the
shaper. Choose the pair carefully: proving `lnum` on a face whose figures are
already lining proves nothing, so test it against `onum` instead, and test on a
string that actually contains digits.

`featureValue` is animatable, which is a cheap way to flip a whole style between
lining and old-style figures on a timeline.

### Backgrounds behind text

A **`TextStyleBackground`** paints behind the runs that use a style, sized to
the text rather than to the `Text` box — the highlighter-pen effect, and the
only way to get a box that tracks the glyphs as they reflow.

It is a paint container like a shape, so it takes `Fill` and `Stroke` children
of its own, and `cornerRadius` rounds the result:

```xml
<TextStylePaint fontSize="24" fontAssetId="0:30" name="Highlight" id="0:21">
    <Fill name="Fill"><SolidColor colorValue="FFFFFFFF" name="C"/></Fill>
    <TextStyleBackground cornerRadius="4" name="BG">
        <Fill name="BGF"><SolidColor colorValue="FF2A2F3A" name="C"/></Fill>
    </TextStyleBackground>
</TextStylePaint>
```

The style's own `Fill` paints the glyphs; the one nested inside the background
paints the box. Getting those the wrong way round is the easy mistake — a
background with no paint of its own draws nothing.

The geometry is built per **glyph** — each glyph's advance box, full line
height — and those boxes are then unioned into contours. So the background hugs
the text rather than filling the `Text` box, the corner radius rounds the merged
outline rather than every letter, and a run that wraps comes out as one band per
line instead of a single enclosing block.

Backgrounds draw before any glyph, in style child order, so they never cover the
text they sit behind.

### Scripts cannot draw text

This is all RML. A Luau script has **no text API**: `Renderer` draws paths and
images, and `Font` is an opaque handle with no drawing method. Lettering in a
script has to be built glyph by glyph out of paths.

So text is a reason to build UI in markup rather than in a script — see
[luau/protocols.md](luau/protocols.md#what-to-put-in-a-script).

## Modifiers

A modifier transforms **parts of the text independently** — per character, word
or line. This is how text types on, letters cascade in, or a highlight sweeps
through a sentence. Without modifiers a `Text` can only be animated as one
block.

It takes two nested pieces: a `TextModifierGroup` holding *what* to change, and
a `TextModifierRange` inside it selecting *which* glyphs to change.

```xml
<Text x="40" y="60" name="Title" id="0:20">
    <TextStylePaint fontSize="32" fontAssetId="0:30" name="Body" id="0:21">
        <Fill name="Fill"><SolidColor colorValue="FFFFFFFF" name="C"/></Fill>
    </TextStylePaint>
    <TextValueRun styleId="0:21" text="Hello Rive" name="Run"/>

    <TextModifierGroup modifyOpacity="true" modifyTranslation="true"
                       invertOpacity="true"
                       opacity="0" y="20" name="Fade In" id="0:40">
        <TextModifierRange modifyFrom="0" modifyTo="0.3" name="Sweep" id="0:41"/>
    </TextModifierGroup>
</Text>
```

The group's `opacity="0"` and `y="20"` describe the state of a **fully
modified** glyph. The range decides how much of that each glyph receives, so
this reads as: characters inside the range are invisible and pushed down 20
units, and characters outside are untouched.

**`invertOpacity="true"` is doing load-bearing work there, and opacity is the
one property that does not behave like the others.** Translation, rotation and
scale interpolate from the glyph's current value toward the group's; opacity by
default *multiplies*:

```
default              current * opacity() * t
invertOpacity="true" current * (1 - t) + opacity() * t
```

So with `opacity="0"` and no `invertOpacity`, every glyph in the text goes
invisible — coverage `t` never rescues it, because the whole product is zero.
Dropping the flag gives you a `Text` that renders nothing, with a clean build
and an empty `problems`, which is indistinguishable from a missing font. Set
`invertOpacity` whenever `opacity` is the thing you are animating.

### Three things about groups that are not obvious

**A `TextModifierGroup` needs a `TextModifierRange`, even when the modifier
looks range-independent.** `TextFollowPathModifier` is gated on range coverage
like everything else, so a group holding only a follow-path modifier is a
complete no-op — the text renders exactly as if the group were absent, with
nothing reported.

**Child order matters.** Groups pre-multiply the glyph transform, so a group
that scales, declared *after* a follow-path group, scales the path displacement
too and the glyphs drift off the curve. Declare the follow-path group last.

**The range positions may go outside 0-1, and often must.** For a cascade where
the first character starts fully hidden, `modifyFrom` has to begin negative —
starting at `0` leaves the leading glyphs part-revealed on the first frame.

### The flags are the trap

`TextModifierGroup` carries `x`, `y`, `rotation`, `scaleX`, `scaleY`, `opacity`
and `originX`/`originY` — but **none of them apply unless the matching flag is
set**:

| Flag | Enables |
|---|---|
| `modifyTranslation` | `x`, `y` |
| `modifyRotation` | `rotation` |
| `modifyScale` | `scaleX`, `scaleY` |
| `modifyOpacity` | `opacity` |
| `modifyOrigin` | `originX`, `originY` |
| `invertOpacity` | makes `opacity` interpolate rather than multiply — see above |

Each is its own boolean attribute. Setting `rotation="0.5"` without
`modifyRotation="true"` is a silent and complete no-op — the value is stored and
never read. This is the single most likely reason a modifier appears to do
nothing.

**Detect:** the flags come back from `inspect` packed into one integer, so you
can confirm they landed. `modifyTranslation` is 4, `modifyRotation` 8,
`modifyScale` 16, `modifyOpacity` 32, `modifyOrigin` 1:

```bash
rive inspect . --json | jq '[..|objects|select((.type//"")=="TextModifierGroup")|.modifierFlags]'
```

`36` means translation (4) plus opacity (32). `0` means every value on the group
is inert.

### Selecting glyphs

`TextModifierRange` selects a span. `modifyFrom` and `modifyTo` are `0`–`1`
across the text by default:

| Property | Default | Meaning |
|---|---|---|
| `modifyFrom` / `modifyTo` | `0` / `1` | the selected span |
| `falloffFrom` / `falloffTo` | `0` / `1` | where the ramps end — see below |
| `strength` | `1` | scales the whole contribution |
| `offset` | `0` | shifts all four positions along the text |
| `clamp` | `false` | clamps rather than wrapping at the ends |
| `runId` | — | limit to one `TextValueRun` instead of the whole text |

### Coverage is per glyph, and hard-edged by default

Each unit gets **one** coverage value, sampled at its centre. All four position
properties live in the same space, and together they describe a trapezoid:

```
          falloffFrom     falloffTo
             |               |
   0 ────────/───────────────\──────── 0
 modifyFrom  ^      1.0      ^   modifyTo
             ramp up      ramp down
```

Outside `modifyFrom`–`modifyTo` a glyph gets `0`. Between `falloffFrom` and
`falloffTo` it gets the full effect. In the two edge zones it gets a partial
value proportional to how far in it sits.

**`falloffFrom`/`falloffTo` are positions, not widths, and not fractions of the
span.** They are measured the same way `modifyFrom`/`modifyTo` are, so with
`typeValue="0"` all four are fractions of the whole text.

The defaults are the trap. `falloffFrom="0"` and `falloffTo="1"` coincide with
the default span, leaving both ramps zero-width — so **every glyph is either
fully modified or untouched, with nothing in between.** A range with no falloff
makes characters pop on, not fade on. If you want each character to ease in, you
must author a ramp.

#### Easing the ramp

A ramp is linear by default: a glyph halfway into the edge zone gets half the
effect. To curve it, nest a **`CubicInterpolatorComponent`** in the range:

```xml
<TextModifierRange modifyFrom="0" modifyTo="1" falloffFrom="0.2" falloffTo="0.8" name="Range">
    <CubicInterpolatorComponent x1="0.42" y1="0" x2="0.58" y2="1" name="Ease"/>
</TextModifierRange>
```

`x1`/`y1`/`x2`/`y2` are the usual cubic-bezier control points, and the range
picks the component up simply by it being a child — there is no id to set.

Despite the name it is **not** a `KeyFrameInterpolator`, so it cannot be a
keyframe's `interpolatorId` and none of the interpolator types from
[easing.md](easing.md#custom-ease-curves) can be used here instead. This one
type, nested exactly here, is the only way to shape a falloff.

Its four control points are animatable, so the shape of the falloff can itself
be keyed — a reveal that starts abrupt and softens as it crosses the text.

`offset` shifts all four together, which is the cheap way to slide a
fixed-shape effect through the text without keying four properties.

Three enums select the units, and they are **numeric** — no symbolic names:

`unitsValue` — what a unit is:

| | |
|---|---|
| `0` | characters *(default)* |
| `1` | characters excluding spaces |
| `2` | words |
| `3` | lines |

`typeValue` — how `modifyFrom`/`modifyTo` are read: `0` percentage *(default)*,
`1` unit index. Use `1` with `unitsValue="2"` to say "words 2 through 4"
literally rather than as fractions.

`modeValue` — how this range combines with others in the same group: `0` add
*(default)*, `1` subtract, `2` multiply, `3` min, `4` max, `5` difference. A
group can hold several ranges, which is how a highlight is masked to one word.

### Animating one

The group's transform values are static; **the range is what you key.** Sliding
the span through the text is what produces the effect.

A reveal keys `modifyFrom` from `0` to `1` against a fixed `modifyTo="1"`, so
the modified — here invisible — span shrinks away from the start. Keying
`falloffFrom` alongside it keeps a soft edge ahead of the reveal, so characters
ease in rather than popping:

```xml
<TextModifierGroup modifyOpacity="true" modifyTranslation="true"
                   opacity="0" y="20" name="Type On" id="0:40">
    <TextModifierRange modifyFrom="0" modifyTo="1"
                       falloffFrom="0.15" falloffTo="1" name="Sweep" id="0:41"/>
</TextModifierGroup>

<LinearAnimation duration="60" name="Reveal" id="0:50">
    <KeyedObject objectId="0:41">
        <KeyedProperty propertyKey="327">
            <KeyFrameDouble value="0" frame="0" interpolationType="linear"/>
            <KeyFrameDouble value="1" frame="60" interpolationType="linear"/>
        </KeyedProperty>
        <KeyedProperty propertyKey="317">
            <KeyFrameDouble value="0.15" frame="0" interpolationType="linear"/>
            <KeyFrameDouble value="1" frame="60" interpolationType="linear"/>
        </KeyedProperty>
    </KeyedObject>
</LinearAnimation>
```

The keys you need: `modifyFrom` is 327, `modifyTo` 336, `falloffFrom` 317,
`falloffTo` 318, `offset` 319.

`falloffFrom` is keyed here because it is an absolute position: as
`modifyFrom` advances, a fixed `falloffFrom` would fall behind it and the ramp
would invert. Keeping the two a constant distance apart holds the soft edge at
the same width all the way across.

Keying both `modifyFrom` and `modifyTo` with a small gap between them sweeps a
travelling effect instead of a reveal.

**+y is downward.** A group with `y="20"` starts its glyphs 20 units *below*
the baseline and they rise into place as coverage falls off. For the opposite,
use a negative value.

### Variable fonts and paths

Two modifiers do something other than transform glyphs, and both go inside a
`TextModifierGroup` alongside its ranges:

`TextVariationModifier` drives one variable-font axis per glyph. `axisTag` is
the same packed OpenType tag as `TextStyleAxis`, so weight cascading through a
word is a keyed `axisValue`:

```xml
<TextModifierGroup name="Weight Wave" id="0:42">
    <TextModifierRange modifyFrom="0" modifyTo="0.4" name="Range"/>
    <TextVariationModifier axisTag="2003265652" axisValue="900" name="Weight"/>
</TextModifierGroup>
```

`TextFollowPathModifier` runs the text along a path named by `targetId`, with
`start`/`end` bounding the portion used, `offset` sliding along it, `orient`
turning glyphs to face the path, and `radial` for a circular arrangement.

These are rarely used; check the shape with `rive schema` and a screenshot
before relying on it.
