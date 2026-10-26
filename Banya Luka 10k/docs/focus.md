# Focus

Focus is how the runtime decides which node a keystroke belongs to. Exactly
one node holds it at a time, and key events are offered to that node first and
then to its ancestors. Without it, keyboard listeners never fire: see
[gotchas.md](gotchas.md#keyboard-events-need-a-focusdata-child).

It is also a navigation system in its own right. Moving a selection between
menu rows, list items or form fields is something the runtime does, and
rebuilding it out of view model state and transitions is a common and
avoidable detour.

## Making a node focusable

A node is focusable when it has a `FocusData` child. That is the whole
declaration:

```xml
<Shape x="150" y="40" name="Play">
    <FocusData/>
    <Rectangle width="200" height="40" name="Path"/>
    <Fill name="Fill">
        <SolidColor colorValue="FF3D7EFF" name="Color"/>
    </Fill>
</Shape>
```

`FocusData` carries three switches, each a bit of the `focusFlags` mask and
each writable as its own attribute:

| Attribute | Meaning |
|---|---|
| `canFocus` | the master switch; `false` makes the node unfocusable by any route |
| `canTouch` | can take focus from a pointer or touch |
| `canTraverse` | included in traversal, **all** of it |

All three default on. `canFocus="false"` is how
[text_input](../samples/text_input) marks a node that hosts listeners but
should never itself be the focused thing.

Both switches only ever speak for the node that carries them. A node with
`canFocus="false"` is skipped, and traversal carries straight on into its
children; the same for `canTraverse="false"`. A container cannot take its
contents out of the keyboard with it.

The other half of that: **containing other focusable nodes does not take a
node out of the order.** A `FocusData` on a group makes the group a stop in
its own right, visited before its children, and Tab goes group → first child →
second child. If the group is meant to be nothing but a container, say so with
`canTraverse="false"` — its children are unaffected either way.

`canTraverse` is the one to read carefully. It does not mean "Tab order only".
Directional traversal builds its candidate list through the same filter, so a
node with `canTraverse="false"` is skipped by the arrow keys as well, and
focus jumps straight past it to the next one that qualifies. If you want a
node reachable by arrows but not by Tab, this flag will not give you that.

## Nothing is focused until something focuses it

Declaring a `FocusData` registers a node as focusable. It does not give it
focus. Until something sets focus, there is no focused node, and **every
keyboard listener in the file is inert** — the runtime offers key events to
the focused node and its ancestors, and with nothing focused there is nobody
to offer them to.

Two things can set it: the host application, through the runtime's focus API,
or the file itself. If the file is going to be embedded somewhere that will
not do it, do it in the file:

```xml
<AnimationState x="200" animationId="0:91" id="0:90">
    <FocusActionTarget targetId="0:20"/>
</AnimationState>
```

Nested in the state the entry transition runs into, that focuses the node as
the machine starts.

**`targetId` names the node, not its `FocusData`.** Pointing it at the
`FocusData` child compiles, reports nothing, and focuses nothing.

One warning about testing this. `rive` focuses the first `FocusData` it finds
when it opens a scene, so a file with no initial focus still responds to the
keyboard in the player and goes dead once it is embedded. That convenience is
the player's, not the runtime's, and it will hide exactly this mistake.

`--key` replays a keystroke headless through the real dispatch path, and
reports when nothing is focused rather than letting it look like a filter that
did not match. See [workflow.md](workflow.md#keyboard).

## Moving focus

`FocusActionTraversal` is a listener action that moves focus. Its
`traversalKind` takes six values:

| Kind | Moves |
|---|---|
| `next`, `previous` | tab order, the Tab and Shift+Tab pair |
| `up`, `down`, `left`, `right` | directional, by where the nodes actually are on screen |

The directional kinds use each focusable node's world bounds, so a column of
rows responds to `up` and `down` without you telling it what order they are
in. Wire them to the arrow keys like any other key listener:

```xml
<StateMachineListener targetId="0:6" name="Move Down">
    <ListenerInputTypeKeyboard listenerTypeValue="keyboard">
        <KeyboardInput keyType="down" keyPhase="1"/>
    </ListenerInputTypeKeyboard>
    <FocusActionTraversal traversalKind="down"/>
</StateMachineListener>
```

The listener's `targetId` must name a node that owns a `FocusData`, the same
rule every keyboard listener follows. A full-bleed backdrop shape with
`canFocus="false"` is the usual host: it covers the artboard, it is never
itself the selection, and the keys reach it wherever focus sits below. That
backdrop does not hide anything under it — `canFocus="false"` takes the
backdrop out of the order and nothing else.

Traversal stops at the ends rather than running off. `FocusData` also carries
`edgeBehaviorValue` (`parentScope`, `closedLoop`, `stop`), which governs what
happens when traversal would **leave that node's subtree** — so it only means
anything on a node that has children. `closedLoop` wraps within the subtree,
and the node itself is part of that loop when it is focusable: group → row 1 →
row 2 → group. `stop` holds focus on whatever the boundary element is, which
is likewise the group itself when the group is focusable. Check
`rive schema FocusData` for the values and verify the behaviour with `--key`.

## Reacting to focus

Two listener input types fire as focus arrives and leaves:

```xml
<StateMachineListener targetId="0:20" name="Play Focused">
    <ListenerInputType listenerTypeValue="focus"/>
    <ListenerViewModelChange>
        <BindablePropertyNumber propertyValue="0">
            <DataBindContext sourcePathIds="0:70-0:71" propertyKey="636" direction="true"/>
        </BindablePropertyNumber>
    </ListenerViewModelChange>
</StateMachineListener>
```

One of these per item, each writing its own index, gives you a view model
number that always says which item is focused. Everything visual hangs off
that one value: a highlight bar's position, a colour, a scale. The runtime
owns *which* item is selected, and your state machine owns only what that
looks like.

`listenerTypeValue="blur"` is the same thing as focus leaves.

## The shape of a keyboard menu

Putting it together, a menu is three focusable rows, two key listeners, and
one number:

- each row is a shape with a `FocusData` child, so the runtime knows the set
  and their positions
- one backdrop with `canFocus="false"` hosts the listeners, and its being
  unfocusable says nothing about the rows
- the entry state carries a `FocusActionTarget` naming the first row, so
  something is focused before the first keystroke arrives
- `down` and `up` arrows fire `FocusActionTraversal` in those directions
- a `focus` listener on each row writes its index to a view model
- the highlight animates to the row that number names

Nothing counts rows, nothing clamps at the ends, and nothing tracks a
selection. Doing it the other way, with triggers moving an index through a
state graph, is several times the markup and reimplements what the runtime
already does.

## See also

- [gotchas.md](gotchas.md#keyboard-events-need-a-focusdata-child) — the
  `FocusData` requirement that catches everyone once
- [format.md](format.md#listeners-two-spellings) — key filters, phases and
  modifiers
- [semantics.md](semantics.md) — `isFocusable` and `isFocused` as
  accessibility traits, and pairing keys with screen-reader actions
- `rive schema FocusData` / `FocusActionTraversal` / `FocusActionTarget` /
  `FocusActionClear` / `TransitionFocusCondition`
