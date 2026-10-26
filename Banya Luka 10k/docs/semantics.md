# Semantics

Accessibility. A `SemanticData` describes one node to a screen reader: what
it is, what it says, what state it is in. The runtime builds a tree from
them, and a platform (Flutter, iOS, Android, web) hands that tree to its
accessibility layer. Semantic actions come back the other way: a screen
reader's "activate" reaches a `StateMachineListener` the same way a click
does.

## Describing a node

`SemanticData` is a direct child of the node it describes. A `Shape`, a
`Text`, a `LayoutComponent` and a plain `Node` are all nodes; an empty `Node`
with a `SemanticData` is a group.

```xml
<Shape x="60" y="30" name="Play" id="0:11">
    <SemanticData role="button" label="Play" hint="Starts playback" name="Semantics"/>
    <Rectangle width="120" height="60" name="Path"/>
    <Fill name="Fill"><SolidColor colorValue="FF57A5E0" name="C"/></Fill>
</Shape>
```

| Attribute | What it is |
|---|---|
| `role` | `none`, `button`, `link`, `checkbox`, `switchControl`, `slider`, `textField`, `text`, `image`, `group`, `list`, `listItem`, `tab`, `tabList`, `dialog`, `alertDialog`, `radioGroup`, `radioButton` (or the number; `rive schema SemanticData` lists them) |
| `label` | what is read out; bindable |
| `value` | the current value, such as a slider's percentage or a field's contents; bindable |
| `hint` | how to use it; bindable |
| `headingLevel` | 1 to 6 for a heading, 0 otherwise |

`label`, `value` and `hint` are animatable and bindable, so a label can follow
a view model string the same way a `TextValueRun` does.

An interactive role (`button`, `link`, `checkbox`, `switchControl`, `slider`,
`tab`, `listItem`, `radioButton`) with an empty `label` derives one from the
text under it, or from a single image's label, and absorbs those descendants
into itself. A labelled button keeps its label and its children.

## Traits and states

A trait says what a node can do. A state says what it is doing now, and
only means something when its trait is set, so `isChecked` needs
`isCheckable`. Write each as its own attribute:

```xml
<Node x="20" y="120" name="Notifications" id="0:12">
    <SemanticData role="switchControl" label="Notifications"
                  isToggleable="true" isToggled="true" name="Semantics"/>
</Node>
```

| Traits | States they gate |
|---|---|
| `isExpandable` | `isExpanded` |
| `isSelectable` | `isSelected` |
| `isCheckable` | `isChecked`: `unchecked`, `checked` or `mixed` |
| `isToggleable` | `isToggled` |
| `isRequirable` | `isRequired` |
| `isEnablable` | `isDisabled` |
| `isFocusable` | `isFocused` (runtime-driven) |

Ungated states: `isHidden`, `isLiveRegion`, `isReadOnly`, `isModal`,
`isObscured`, `isMultiline`.

A role brings the traits it cannot do without, as the editor sets them
when a role is picked: `button`, `link`, `slider`, `textField` and
`radioGroup` are enablable; `checkbox` and `radioButton` are checkable and
enablable; `switchControl` is toggleable and enablable; `tab` is selectable
and enablable. The build adds those bits whatever you wrote, so `inspect`
and `--semantics` show them. Focusable is not a role trait: the runtime sets
it when the node has a `FocusData` child. That child is also what lets
keyboard focus reach the node and what scrolls it into view when a screen
reader lands on it, so the build adds one to any node whose role a user
focuses (`button`, `link`, `checkbox`, `switchControl`, `slider`,
`textField`, `listItem`, `tab`, `radioButton`) if the author wrote none.
Any other node that should scroll into view, such as a heading in a scroll
view, needs a `FocusData` written by hand, and then takes keyboard focus
too.

These are bits of two packed properties, `traitFlags` and `stateFlags`. The
attributes fold into them at build time and `inspect` shows both forms, so
`isHidden="true"` and `stateFlags="256"` build the same file. Animate or bind
the bit you mean, such as `isToggled`, not the mask.

## What ends up in the tree

- A node whose `isHidden` is set is left out **with its whole subtree**. So
  is anything under a collapsed parent (a `Solo` sibling that is not active,
  a hidden drawable). Opacity 0 does not hide anything. An invisible control
  can still be interactive.
- **Bounds are in artboard space.** A drawable reports its own bounds. A node
  with no bounds of its own (an empty `Node` grouping some buttons, a shape
  whose path has collapsed to nothing) reports the union of every node under
  it. A node with nothing to measure at all reports its position as a point.
- Children are ordered by visual position, not declaration order.

`rive <dir> --semantics` writes that tree (see below).

## Semantic listeners

A screen reader's activate, increment or decrement arrives as a semantic
action. A listener receives one through a `ListenerInputTypeSemantic`
trigger. Its `SemanticInput` rows say which actions (`tap`, `increase`,
`decrease`), and no rows means any of them. The usual shape pairs it with a
pointer trigger so the control works both ways:

```xml
<StateMachineListener targetId="0:11" name="Play">
    <ListenerInputType listenerTypeValue="click"/>
    <ListenerInputTypeSemantic listenerTypeValue="semanticAction">
        <SemanticInput actionType="tap"/>
    </ListenerInputTypeSemantic>
    <ListenerViewModelChange>
        <BindablePropertyString propertyValue="play">
            <DataBindContext sourcePathIds="0:40-0:45" propertyKey="635" direction="true"/>
        </BindablePropertyString>
    </ListenerViewModelChange>
</StateMachineListener>
```

**The target rule.** `targetId` must name the node whose *direct* child is
the `SemanticData`. The runtime does not look up or down from the target: a
listener aimed at a wrapper `Node` whose semantics sit on the `Shape` inside
it builds clean and never fires. `inspect` reports that as
`semantic-listener-target-without-data`.

**Only the typed trigger fires.** A plain
`<ListenerInputType listenerTypeValue="semanticAction"/>`, or a
`StateMachineListenerSingle` with that value, gets a listener but never
matches an action. `inspect` reports either as
`semantic-listener-without-input-type`.

An action queues and runs on the next frame, and whatever the listener
changes (a trigger a host reacts to) lands on the frame after that, so a
`--semantic-action` is followed by two advances before anything is captured.

## Checking it headless

```bash
rive <dir> --semantics                     # build/<name>.semantics.json
rive <dir> --semantics=out.json --advance=45
rive <dir> --semantics=out.json --semantic-action="tap@Play"
rive <dir> --screenshot --semantics --pointer=click@120,60
rive <dir> --semantics=out.json --advance=1s --semantic-action="tap@Start"
rive <dir> --semantics=- --advance=45 | jq '.roots'
```

`--semantics=-` writes to standard output instead of a file; `stdout` is
accepted as the same thing, for anyone who has not met the `-` convention.
The build log goes to stderr, so on stdout the JSON is the only thing on the
pipe. `--data-dump=` takes the same two spellings. A file genuinely named
`-` or `stdout` is reachable as `./-` or `./stdout`.

`--semantics` runs the scene offscreen like `--screenshot` and writes the
tree the runtime would hand a platform, after the same `--data`, `--pointer`,
`--semantic-action`, `--advance` and `--viewport` handling.
`--screenshot` and `--semantics` together are one run with both outputs. A
`--viewport` is applied before any interaction, so a gesture lands on the
layout at that size.
`--semantic-action=<type>@<label>` dispatches through the same path a screen
reader uses, aimed at the one node whose `label` matches exactly. An
ambiguous or unknown label fails the run. Interactions apply in command-line
order.

`--advance=<N>` is an interaction too. It steps `N` frames at 60fps where
it sits in the sequence, so a control an intro reveals can be tapped once
the intro has run, and a second action can follow the first one's
transition. `--advance=1s` or `--advance=250ms` steps that much animation
time instead, in 1/60 s frames with one shorter frame at the end when the
time is not a whole number of them. One after the last interaction is the
settle before the capture, which is where the animation's frame is picked.

Each node in the JSON carries `id`, `role` (the name) and `roleValue`,
`label`, `value`, `hint`, `headingLevel`, `stateFlags`, `traitFlags`,
`bounds` (`x`, `y`, `width`, `height` in artboard space) and `children`.
Roots are under `roots`. A fixture assertion is a `jq` line:

```bash
jq '[.. | objects | select(.role == "button") | .label]' build/app.semantics.json
```

Or without the file at all:

```bash
rive <dir> --semantics=- --advance=45 \
  | jq '[.. | objects | select(.role == "button") | .label]'
```

## Draw order

A drawable nested inside a `Shape` paints behind its parent. Reordering with
`DrawRules` is in [transforms.md](transforms.md).
