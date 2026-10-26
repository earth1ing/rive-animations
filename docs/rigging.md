# Bones, skinning and constraints

Two ways to make one thing follow another: **constraints**, which tie a
component's transform to a target, and **skinning**, which deforms geometry —
a vector path, or an image once it carries a `Mesh` — by a bone hierarchy.

Both are heavily used in real files — this is how characters, mechanical
linkages and reactive UI get built.

Looking for a **joystick** — one 2-D control that poses a rig? It is a
scrubbing control rather than a constraint, so it lives in
[easing.md](easing.md#joysticks), alongside the blend states it is related to.

## Constraints

A constraint is a child of the component it constrains, usually naming a target
by id:

```xml
<Shape x="200" y="100" name="Follower" id="0:20">
    <Rectangle width="40" height="40" name="Path"/>
    <Fill name="Fill"><SolidColor colorValue="FF57A5E0" name="C"/></Fill>
    <TranslationConstraint targetId="0:30" strength="0.5" name="Follow"/>
</Shape>

<Node x="400" y="100" name="Target" id="0:30"/>
```

`strength` is `0`–`1`, so a constraint can partially apply — which is how
easing-by-follow effects are made.

| Constraint | Ties |
|---|---|
| `TranslationConstraint` | position |
| `RotationConstraint` | rotation |
| `ScaleConstraint` | scale |
| `TransformConstraint` | all three at once |
| `DistanceConstraint` | stays within a `distance` of the target |
| `IKConstraint` | bends a bone chain to reach the target |
| `FollowPathConstraint` | rides along a path |

### IK, and the two things it is actually used for

`parentBoneCount` says how many bones *above* the constrained one join the
solve, and it is what selects between the two behaviours:

- **`parentBoneCount="1"`** — a two-bone solve. The classic elbow or knee: the
  chain bends so the tip reaches the target. `invertDirection="true"` picks the
  other elbow.
- **`parentBoneCount="0"`** — a one-bone solve, which is Rive's **look-at**.
  The bone simply aims at the target. This is how you point a turret, a head, or
  a hydraulic ram at something, and nothing else in the format does it.

An `IKConstraint` must sit on a `Bone`. On any other target the whole file fails
to import, and the error names no object — so if a build dies with
`the built riv could not be re-imported` shortly after you added IK, check what
you parented it to first.

**A `RootBone` may be nested inside another `Bone`.** That is how you anchor an
aim constraint to something that is itself moving — a ram whose barrel is bolted
to a swinging boom. It reads like a contradiction, and it is legal and load
bearing.

### `DistanceConstraint` modes

`modeValue` picks what `distance` means, and `rive schema` does not list the
values:

| | |
|---|---|
| `0` closer | acts only when the object is *further* than `distance`, pulling it back — a maximum radius |
| `1` further | acts only when it is *closer*, pushing it out — a minimum radius |
| `2` exact | always acts, pinning the object onto the ring |

Mode `0` is the **circular gate**: the object moves freely inside the radius and
cannot leave it. That is what a joystick knob wants — constrain the handle to a
`Node` at the centre of the joystick's box and the knob travels in a disc rather
than the rectangle a `TranslationConstraint`'s min/max would give it. See
[easing.md](easing.md#joysticks).

Mode `0` is also the default, so a `DistanceConstraint` with no `modeValue`
already behaves as a gate.

### Targets are not always required

`TranslationConstraint`, `RotationConstraint` and `ScaleConstraint` work with
**no target** — they then constrain against the parent. Every other constraint
needs `targetId`, and omitting it means the constraint silently does nothing.
`rive inspect` reports the ones that genuinely need a target.

### Per-axis control

The translation, scale and transform constraints expose each axis separately:
`copyFactorX`/`copyFactorY` scale how much of the target's value is taken
(negative values mirror), `doesCopyX`/`doesCopyY` switch an axis off, and
`minValueX`/`maxValueX` clamp the result when `maxX`/`minX` are enabled.

`sourceSpaceValue` and `destSpaceValue` choose whether values are read and
applied in world or local space — the usual cause of a constraint that works
until its parent moves.

### Follow path

`FollowPathConstraint` puts a component at `distance` along the target path
(`0`–`1` of its length), with `orient` turning it to face along the path. Keying
`distance` is how something animates along a curve.

## Bones

Bones are transforms in a chain. A `RootBone` starts one and takes `x`/`y`;
`Bone` children inherit position from their parent's tip:

```xml
<RootBone x="0" y="0" length="76" rotation="-1.5707964" name="Body" id="0:40">
    <Bone length="18" rotation="0" name="Neck" id="0:41">
        <Bone length="24" rotation="0" name="Head" id="0:42"/>
    </Bone>
</RootBone>
```

`length` positions the next bone in the chain; `rotation` is radians, relative
to the parent bone. A bone is a `TransformComponent`, so anything that can be
constrained can be constrained to one.

Bones alone move whatever is parented to them. To deform geometry, skin it.

## Skinning

A `Skin` binds a vertex list to bones. It nests **inside the thing it deforms**
— a `PointsPath` here, a `Mesh` under [Images](#images-deform-the-same-way-once-they-have-a-mesh)
below, and nothing else — holds a `Tendon` per bone, and each vertex carries a
`Weight`:

```xml
<Shape name="Arm" id="0:50">
    <PointsPath name="Path" id="0:51">
        <StraightVertex x="0" y="-10">
            <Weight values="255" indices="1"/>   <!-- all of tendon 0 -->
        </StraightVertex>
        <StraightVertex x="80" y="-10">
            <Weight values="255" indices="2"/>   <!-- all of tendon 1 -->
        </StraightVertex>

        <Skin tx="0" ty="0" name="Skin">
            <Tendon boneId="0:40" tx="0" ty="0" name="Upper"/>
            <Tendon boneId="0:41" tx="76" ty="0" name="Fore"/>
        </Skin>
    </PointsPath>
    <Fill name="Fill"><SolidColor colorValue="FFE0E0E0" name="C"/></Fill>
</Shape>
```

**`Tendon`** names a bone and records the bind pose — `tx`/`ty` and the `xx`
… `yy` matrix values are the bone's transform at the moment of binding, which is
what deformation is measured against.

The four matrix components are read as `Mat2D(xx, xy, yx, yy, tx, ty)`, so the
**x unit vector is `(xx, xy)`** and the **y unit vector is `(yx, yy)`**. Every
example here binds with an identity rotation, where the two orderings are
indistinguishable; they are not once a bone is rotated. A bind at +90° is:

```xml
<Tendon boneId="0:40" xx="0" xy="1" yx="-1" yy="0" tx="0" ty="0" name="Upper"/>
```

Get the pair the wrong way round and the rest pose renders mirrored or
collapsed, with no error and an empty `problems`.

**`Weight`** on a vertex says which bones move it and by how much. `indices`
selects up to four tendons, `values` the matching influences out of 255. Both
are packed integers, one byte per slot, slot *i* of one pairing with slot *i* of
the other — slot 0 is the low byte.

**`indices` is 1-based: each byte is `tendonIndex + 1`, and a `0` slot is
the identity transform**, a real influence that holds the vertex where it was
bound. A vertex whose only slot is `0` therefore keeps its bind position while
everything around it deforms, which looks exactly like bones not working at
all; `inspect` reports it as `weight-without-bone`. This is also why the
property's default is `1` — "the first tendon", not "the second".

**The values must total 255.** The runtime divides each byte by 255 and does
not renormalize, so 128 + 128 scales the vertex by 256/255. Split an even
blend 128/127. Tendons 0 and 1 at half influence each is therefore:

```
indices = 1 | (2 << 8) = 513
values  = 128 | (127 << 8) = 32640
```

```xml
<Weight values="32640" indices="513"/>
```

`inspect` prints every Weight decoded beside the packed form:

```json
"rig": {"influences": [{"tendon": 1, "weight": 0.502}, {"tendon": 2, "weight": 0.498}]}
```

`CubicWeight` does the same for cubic vertices, adding `inIndices`/`inValues`
and `outIndices`/`outValues` so the bezier handles deform with the point.

Only four bones per vertex, and that is the runtime's limit rather than a
convention — `indices` has four slots and there is nowhere to put a fifth.

### Images deform the same way, once they have a mesh

Everything above works on a `PointsPath` — a vector shape. An **image** deforms
too, but it has no vertices of its own to move, so it needs geometry first: a
`Mesh`, a triangulated set of vertices carrying texture coordinates, nested
inside the `Image`.

```xml
<Image x="150" y="150" assetId="0:60" name="Arm" id="0:20">
    <Mesh triangleIndexBytes="AAECAAID" name="Mesh" id="0:21">
        <ContourMeshVertex x="-100" y="-100" u="0" v="0" name="V0">
            <Weight values="255" indices="1"/>
        </ContourMeshVertex>
        <ContourMeshVertex x="100" y="-100" u="1" v="0" name="V1">
            <Weight values="255" indices="2"/>
        </ContourMeshVertex>
        <ContourMeshVertex x="100" y="100" u="1" v="1" name="V2">
            <Weight values="255" indices="2"/>
        </ContourMeshVertex>
        <ContourMeshVertex x="-100" y="100" u="0" v="1" name="V3">
            <Weight values="255" indices="1"/>
        </ContourMeshVertex>

        <Skin tx="0" ty="0" name="Skin">
            <Tendon boneId="0:40" tx="-100" ty="0" name="Upper"/>
            <Tendon boneId="0:41" tx="0" ty="0" name="Fore"/>
        </Skin>
    </Mesh>
</Image>
```

From `Skin` down it is **identical to the path case** — the same `Skin`, the
same `Tendon` per bone, the same packed `Weight` on each vertex. A mesh and a
points path are the only two things that can be skinned, and they are skinned
the same way. So the only extra work an image costs you is the mesh itself.

**`x`/`y`** are the vertex position in the image's local space; **`u`/`v`** are
where that vertex samples the texture, normalized `0`–`1`. Moving a vertex drags
its bit of the image with it, which is the whole trick.

**`triangleIndexBytes`** is the triangle list: three vertex indices per
triangle, varuint-encoded and then base64'd into the attribute. The four
vertices above with `AAECAAID` are `0,1,2` and `0,2,3` — the two triangles of a
quad. It is validated as base64, so a malformed value is a build error, but what
it *decodes to* is not checked until load.

Contour vertices come first. `ContourMeshVertex` marks a vertex on the outline;
the editor reads the leading run of them as the silhouette, and interior
`MeshVertex` points follow. At runtime the two behave identically, so this only
matters for a file that has to survive a round trip through the editor.

**Two ways a mesh builds and then misbehaves**, and they fail very
differently at runtime:

- **The `Mesh` is not a child of an `Image`.** Nothing else can host one, and a
  mesh that lands anywhere else is simply ignored — the image draws normally,
  undeformed, and moving the bones does nothing to it. `inspect` reports it as
  `mesh-not-under-image`; `--verify` passes, because the file loads.
- **`triangleIndexBytes` is missing, or an index is `>=` the vertex count.**
  This one takes the **whole file** down: the runtime rejects the `.riv` as
  malformed, so every artboard in it fails to load, not just this image.
  `--verify` fails and names the mesh and the index
  (`mesh-triangle-index-out-of-range`, `mesh-without-triangles`).

`inspect` decodes the buffer beside the object, so what you wrote is readable:

```json
"rig": {"vertices": 4, "triangles": [[0, 1, 2], [0, 2, 3]]}
```

A `Skin` gets its tendons listed with their bind matrices in the order a
`Weight` slot counts them, and every `Weight` its influences by tendon number.
What none of this catches is appearance: a transposed bind is a valid matrix
that happens to be the wrong one. Take a `--screenshot` for that.

### Take it from a `.rev`

Skinning is the one part of the format that is genuinely painful to author by
hand — the weights are packed, the bind pose has to match the bones' actual
transforms, and a mesh adds an encoded index buffer. `--verify` and `inspect`
name the structural mistakes, but not a bind that is merely wrong. If the
geometry comes from a designer, take the skinned path or mesh from a
decompiled `.rev` rather than writing it.

## Solo

A `Solo` shows exactly one of its children at a time:

```xml
<Solo activeComponentId="0:62" name="Icon States" id="0:60">
    <Shape name="Idle" id="0:61">...</Shape>
    <Shape name="Active" id="0:62">...</Shape>
    <Shape name="Error" id="0:63">...</Shape>
</Solo>
```

`activeComponentId` names the visible child; the rest are not drawn. It is
animatable and bindable, so keying it switches states in a timeline, and binding
it lets data pick the variant — which is how icon sets and multi-state badges
are built without a state machine.

Keying it takes `KeyFrameId` on propertyKey 296, not `KeyFrameDouble` — a
reference is not a number, and the wrong keyframe type does nothing at all:

```xml
<KeyedObject objectId="0:60">
    <KeyedProperty propertyKey="296">
        <KeyFrameId value="0:61" frame="0"/>
        <KeyFrameId value="0:62" frame="30"/>
        <KeyFrameId value="0:63" frame="60"/>
    </KeyedProperty>
</KeyedObject>
```

`hold` is the right interpolation here, and it is the default, so these need no
`interpolationType`. See
[format.md](format.md#the-keyframe-type-must-match-the-property).

A `Solo` is a `Node`, so it positions and transforms its children normally.
Inside a layout box it is transparent: only the **active** child takes part in
the layout, so switching variants reflows the box around the one showing. See
[layout.md](layout.md#groups-and-solos-inside-a-layout).

## Tags

`Tag` is editor organisation — labels for filtering the hierarchy. Any component
can carry tag ids:

```xml
<Tag name="Interactive" id="0:70"/>
<Tag name="Generated" id="0:71"/>

<Shape tagIds="0:70-0:71" name="Button" id="0:14">
    ...
</Shape>
```

`tagIds` is a dash-separated list, the same form as bind paths. Tags carry a
`hidden`/`locked`/`filtered` flag set of their own.

Nothing at runtime reads tags, so they cost nothing in the `.riv`. They are
worth setting from a generator anyway: a file produced by a script is far easier
for a designer to navigate afterwards if the generated parts are labelled.
