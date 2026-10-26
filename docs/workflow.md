# Building a screen in passes

Do not emit a finished screen in one go. Build it outside-in in visible passes,
rebuilding after each one.

Builds are cheap — a full screen compiles in about a second — so the cost of
this is close to zero, and it buys three things:

- **Structural mistakes surface while they are cheap.** Sizing errors are the
  expensive kind, and they are visible in the first pass, before any detail has
  been written on top of them.
- **Anyone watching can see the direction.** A wireframe after ten seconds says
  more about where you are heading than ten minutes of silence.
- **They can redirect you mid-build**, instead of discovering at the end that
  the whole shape was wrong.

## Pass 1: the wireframe

Lay out every region as an empty filled box, roughly the size it will end up.
No text, no art, no detail — the same thing apps show as a loading skeleton.

```xml
<LayoutComponent width="390" height="844" styleId="0:2" name="Screen" id="0:1">
    <LayoutComponentStyle layoutWidthScaleType="fill" layoutHeightScaleType="fill"
                          flexDirectionValue="column"
                          gapVertical="12" gapVerticalUnitsValue="points"
                          paddingLeft="16" paddingLeftUnitsValue="points"
                          paddingRight="16" paddingRightUnitsValue="points"
                          paddingTop="16" paddingTopUnitsValue="points"
                          name="Screen Style" id="0:2"/>

    <LayoutComponent height="180" styleId="0:4" name="Header" id="0:3">
        <LayoutComponentStyle layoutWidthScaleType="fill" layoutHeightScaleType="fixed"
                              name="Header Style" id="0:4"/>
        <Fill name="Fill"><SolidColor colorValue="FF1E2430" name="C"/></Fill>
    </LayoutComponent>

    <LayoutComponent height="122" styleId="0:6" name="Hourly" id="0:5">
        <LayoutComponentStyle layoutWidthScaleType="fill" layoutHeightScaleType="fixed"
                              name="Hourly Style" id="0:6"/>
        <Fill name="Fill"><SolidColor colorValue="FF1E2430" name="C"/></Fill>
    </LayoutComponent>

    <LayoutComponent height="280" styleId="0:8" name="Forecast" id="0:7">
        <LayoutComponentStyle layoutWidthScaleType="fill" layoutHeightScaleType="fixed"
                              name="Forecast Style" id="0:8"/>
        <Fill name="Fill"><SolidColor colorValue="FF1E2430" name="C"/></Fill>
    </LayoutComponent>
</LayoutComponent>
```

That renders as three grey blocks in the right places — which is exactly what
it should look like.

**Give every wireframe box a `Fill`.** An empty box with no fill draws nothing,
so a wireframe without fills renders a blank screen and the pass is wasted.

**Do not leave a box `hug` in this pass.** A `hug` box with no children has zero
size and vanishes. Either size it `fixed`/`fill` now, or give it a placeholder
child.

## Keep it from thrashing

Every later pass adds content *inside* boxes that already exist. If a box's
size comes from its own style, adding content to it changes nothing on screen —
the wireframe stays put and detail appears within it.

**So decide the sizing model in pass 1 and do not change it.** Switching a box
from `fixed` to `hug` in a later pass re-lays out everything around it, and the
screen jumps.

Where the content genuinely has to determine the size, use `hug` from the
start and accept that box growing once, when its content lands. That is one
honest movement, not a cascade.

## Later passes

Work down the tree, one region at a time:

1. wireframe — every region, sized and filled
2. structure within each region — rows, cells, nested boxes
3. text and real content
4. art and detail

Finish a region before starting the next. Half of every region is worse to look
at, and worse to redirect, than all of one and none of the next.

## Patch, do not regenerate

Edit the file in place. Rewriting the whole document each pass costs as much as
writing it several times over, and re-emitting a large tree is how closing tags
get lost.

Expect the file to change under you on the first build: `rive` writes an `id=`
onto every element that had none, and adds any `AnyState` or `ExitState` a
layer left out, so the ids survive the next rebuild and the next push. That first diff touches nearly every line and is worth its own
commit; after it, a build only adds ids for markup you just wrote.

## Check every pass

After each pass, in order:

```bash
rive <dir> --verify                       # did it still parse and compile?
rive <dir> --screenshot=build/pass2.png   # what does it look like now?
rive inspect <dir> --json | jq '[..|objects]|length'
```

`--screenshot` is local and needs no session, like `--verify`, `--once` and
`--test`. Of those four, none requires `rive login`; `--publish` does, because
it signs through the API, and so does `--rev`.

### What each one actually proves

The three checks answer different questions, and the gap between them is where
silent failures live:

| | Answers | Blind to |
|---|---|---|
| `--verify` | does it compile, and would the `.riv` load? | anything that only shows when the scene runs or renders |
| `--test` | do the scripts behave? | everything with no `Tests` script |
| `--screenshot` | does it look right? | nothing visual — this is the backstop |

`--verify` builds the `.riv` in memory and reads it back through the importer
before reporting success, so a file that would fail to load is a build failure
rather than something the next tool discovers. It still writes nothing and
still needs no session. If it reports

```
the built riv could not be re-imported; it would fail to load at runtime
```

the document compiled but does not survive the round trip, and no `.riv` is
written. Read the errors above that line first: a property carrying a value the
runtime has no case for is the usual cause, and those are reported by name. If
nothing above it names an object, it is worth reporting as a tool bug.

**`inspect` shows the RML you authored, not the `.riv` that was written.**
The tree it prints is the parsed document, so anything the exporter drops on the
way out is still there in full — correct ids, correct nesting, `problems` empty.
Three separate export gaps have been found this way, each one authorable,
clean through every static check, and inert at runtime. When something is wired
correctly and still does nothing, "it is in `inspect`" is not evidence that it
shipped; render it, or look in the bytes:

```bash
rive <dir> --once
strings -n 3 build/<name>.riv | grep -c "MyEventName"
```

**The screenshot is still the one that finds real defects.** `--verify` and
`inspect` are structural hygiene — they will both pass a screen with an
invisible shape, a collapsed icon or text in the wrong place. Neither has ever
caught an appearance bug, because neither looks at one. Do not treat a clean
pair as evidence the pass worked.

Nor does `--verify` run anything. A Luau script that type-checks can still throw
on its first call, and a `require` that resolves at check time can still fail to
resolve at run time — both compile clean and do nothing. Scripts need `--test`
or a render before you believe them.

`--screenshot` resolves its path against the **current directory**, not the
project directory, and a missing directory fails with only
`screenshot failed: <path>`. Create the directory first, or write somewhere
that exists.

The object count must go **up** every pass. If it drops, an edit truncated the
tree.

**Some passes are invisible, and that is fine.** A pass that adds a state
machine can add a hundred objects and change the screenshot not at all — states,
listeners and transitions do nothing until something is clicked, and an idle
animation is at its resting value on frame 0. For those passes the object count
and a `jq` readback are the evidence; use `--advance=<N>` to see an animation and
the viewer to see interaction.

That check matters more than it looks. A dropped closing tag can leave a
document that parses to nothing — and while both commands now report the parse
error, an empty file is otherwise indistinguishable from a clean one. The
object count is what tells you the difference between "nothing is wrong" and
"nothing is there".

Also worth asserting as you go:

```bash
# every layout box still has its style linked
rive inspect <dir> --json | jq '[..|objects|select((.type//"")=="LayoutComponent" and .styleId==null)]|length'
```

Anything other than `0` means a box was added without its
`LayoutComponentStyle`, and it will not lay out the way you wrote it.

## Prove the interaction works

Structure is not behaviour. A state machine that builds, inspects clean and
reads back correctly with `jq` can still be wired so that nothing happens, or
so that it happens exactly once. Two flags let you check without a human:

```bash
rive <dir> --screenshot=rest.png
rive <dir> --screenshot=on.png    --pointer=click@120,60 --advance=20
rive <dir> --screenshot=off.png   --pointer=click@120,60 --pointer=move@400,400 \
                                  --pointer=click@120,60 --advance=20
```

Coordinates are in **artboard space**, not window pixels. `click` is a move, a
press and a release with a frame between each, because a state machine only
sees a gesture when it next runs. The trailing `--advance` then steps whatever
settling the resulting transition needs before the capture — and it counts
from *after* the gestures, not from scene time zero.

**An advance steps where you put it.** `--advance` is an interaction like the
gestures, so one before a click runs an intro first, and one between two
clicks lets the first one's transition land before the second. It takes
frames, or a time in seconds or milliseconds:

```bash
rive <dir> --screenshot=ready.png --advance=1s --pointer=click@120,60 --advance=20
```

**Put something between two clicks on the same target.** A value a listener
writes is not visible to the next listener that reads it until a frame has
passed, so back-to-back clicks can both act on the pre-write value and a toggle
latches on. Any filler gesture works; a `move` well away from the control is
the cheapest.

Every listener whose target contains the point fires — drawing one thing over
another does not block it unless the thing on top is explicitly opaque
(`isTargetOpaque`), and a fully transparent fill is still hit-testable. Two
listeners writing the same property will fight, which is the usual reason a
control appears dead in one spot and works everywhere else.

Compare the three. `rest` and `on` must differ, or the control does nothing.
`off` must match `rest`, or it only works one way — the single most common
state machine bug, and invisible to every static check.

### Dragging

`drag` presses at the first point, moves to the second in `steps` moves, and
releases:

```bash
rive <dir> --screenshot=scrolled.png '--pointer=drag@200,300>200,80:12'
```

**Quote the argument.** The `>` between the two points is a shell redirection
otherwise: the flag is truncated at `drag@200,300`, the CLI reports
`--pointer=drag wants x1,y1>x2,y2[:steps]`, and that message lands in a file
named `200,80:12` in whatever directory you ran from.

**The step count controls how far each move jumps**, so the same distance in
one step is a coarse drag and in twenty is a fine one. That changes how much
scroll offset a *drag* produces, and it is what you want for testing direct
manipulation.

**That makes the step count the velocity, and a fling reproducible.** A capture
runs in a deterministic mode, so scroll physics derives velocity from
the replay's own 1/60s clock rather than the wall clock. The same gesture throws
the same distance on any machine and in any run, and the same distance in two
steps travels further than in sixty.

Two consequences worth knowing. Fling *distance* is now measurable — capture at
several step counts and check they differ, and a fling that lands identically at
every speed is not carrying momentum. Fling *feel* is still a human judgement:
matching a real thumb means matching real event timing, which a synthesised
gesture does not attempt. Tune the numbers by reasoning about them (see
[layout.md](layout.md#tuning-the-fling)) and confirm the result in the live
window, which runs on real time.

The default is 8. A gesture is otherwise fully composable from the primitives,
so `down`, several `move`s and an `up` express anything `drag` does, with the
spacing under your control.

### Wheel and trackpad

`wheel` and `trackpad` scroll the way a mouse does: the pointer sits over a
scroll view and the view moves, with no press and no drag.

```bash
rive <dir> --screenshot=wheel.png --pointer=wheel@200,200:0,-150 --advance=20
rive <dir> --screenshot=swipe.png --pointer=trackpad@200,200:0,-150:4 --advance=60
```

The second pair is how far the **content** travels, in artboard units and in a
drag's sense: `0,-150` moves it up and reveals what is below, as
`drag@200,300>200,150` would. The mouse moves to the point first, as a real one
has to be there to scroll there.

- **`wheel`** is a detented mouse wheel. It is one notch unless counted —
  `:5` splits the travel over five notches a frame apart — and it stops
  exactly where its travel ends.
- **`trackpad`** is a two-finger swipe. It begins, moves in `steps` (default
  8) and lifts, and the runtime then flings from its speed, so it lands past
  its travel. The step count is the velocity, as it is for `drag`, and the
  throw is reproducible.

**A scroll only reaches a view that can move the way it points.** The
innermost scroll view under the point that can move along that axis takes
it, so a vertical list ignores a sideways wheel and a horizontal strip inside
it takes one. When nothing takes it the run says so — `wheel: nothing at
200,250 scrolled` — rather than leaving a capture of a list that never moved.
The usual causes are a point over a gap or along the wrong axis, a view
already at that end (a wheel cannot push past an edge, where a trackpad
stretches an elastic view instead), or `wheelInteractive="false"` on the
`ScrollConstraint`, which keeps drags and refuses wheel and trackpad.

### Multitouch

`--touch` is a finger where `--pointer` is the mouse:

```bash
# two fingers held on two buttons at once, lifted in the other order
rive <dir> --screenshot=chord.png \
    --touch=down@80,80 --touch=down:1@300,80 \
    --touch=up@80,80 --touch=up:1@300,80 --advance=20
```

`down`, `move`, `up` and `tap` take a pointer id after a colon; without one
the finger is 0. Each id is its own pointer, so two fingers hold two
listeners, drag two things, and reach a script as two values of `event.id`.
Two differences from the mouse matter:

- **A finger has no hover.** It arrives and presses in the same frame, where
  `click` moves first and waits a frame.
- **A lifted finger is gone.** `up` is also that finger's exit, so enter and
  exit listeners unwind as they do on a phone. The mouse keeps hovering after
  a `click` until `--pointer=exit`.

For fingers that move together — a pinch, a two-finger pan — give `drag` more
than one finger, `+` between them. They land, move and lift in the same
frames, and finger `i` is pointer `id + i`:

```bash
# pinch out: two fingers moving apart over 12 moves
rive <dir> --screenshot=zoomed.png \
    '--touch=drag@150,200>100,200+250,200>300,200:12' --advance=30
```

Quote it, as for any drag. Ids run 0–255, since a script reads `event.id`
from a byte, and a drag takes up to ten fingers. The mouse and finger 0 are
both pointer 0, as they are on a device, so mixing `--pointer` with an
unnumbered `--touch` drives one pointer from both.

### Gamepad

`--gamepad` synthesises pad input the same way. It is repeatable, and it shares
one queue with `--pointer`, `--touch` and `--semantic-action`, so they replay
in the order they were written — a stick held while a drag runs is a different
scene from the same two events the other way round.

```bash
rive <dir> --screenshot=punch.png \
    --gamepad=axis@leftX:-0.9 \
    --gamepad=button@west:down --gamepad=button@west:up --advance=20
```

**A capture mode is required**, as it is for the other two: synthesised input
needs a scene to go into, so `--gamepad` without `--screenshot` or
`--semantics` is a usage error rather than a flag that quietly does nothing.

Buttons and axes take **names** from the W3C standard layout — `south`, `east`,
`west`, `north`, `leftShoulder`, `rightShoulder`, `leftTrigger`, `rightTrigger`,
`back`, `forward`, `leftStick`, `rightStick`, `dpadUp`, `dpadDown`, `dpadLeft`,
`dpadRight`, `start`, and axes `leftX`, `leftY`, `rightX`, `rightY`,
`leftTrigger`, `rightTrigger`.

Prefer the names. A bare index is accepted and is **W3C 0-based**, matching the
wire format and `GamepadInput.inputIndex` — but a Luau `gamepadEvent` reads the
same slot as `changeIndex` **+ 1**. `west` means the same button everywhere;
`2` does not.

`button@<x>:down` and `:up` are the press and the release. A value in `0..1`
sets analog pressure instead, which is what a trigger reports. Values past the
rails clamp, because real sticks report slightly past them; a value that is not
a finite number is rejected.

**A pad is connected implicitly** by the first event, so a run can go straight
to `button@west:down`. `--gamepad=connect` does it explicitly when a
`gamepadConnected` handler is what you are testing, and `--gamepad=disconnect`
fires the other end. There is no mapping variant: a synthetic pad connects
through the same `gamepadConnected` a real one does, and nothing in the
event reports anything but the standard mapping.

The event goes through the very handlers a plugged-in controller's events go
through, so it dispatches exactly like a real pad's — reaching **state machine
listeners and scripts both**. That matters: a `listenerTypeValue="gamepad"`
listener has no other way to be exercised headlessly.

`--data` does the same for bound values, setting a view model property before
the scene runs:

```bash
rive <dir> --screenshot=full.png --data=battery/level=100
```

Repeat either flag for several values or gestures. An unknown property path is
reported rather than ignored.

`battery/level` is a **nested** view model: a `battery` property holding another
view model, which has `level`. The path is relative to the instance bound to the
artboard and every segment is a property name — the view model's own name is
never part of it, so a flat view model takes the bare property
(`--data=level=100`). See [data.md](data.md#the---data-path).

### Keyboard

`--key` replays a keystroke through the same dispatch a real keyboard takes,
so filters, phases and modifiers all apply:

```bash
rive . --screenshot=out.png --key=down --key=down --key=enter
rive . --data-dump=- --key=right:down          # the press alone
rive . --data-dump=- --key=tab:down+shift      # a different event to shift-less tab
```

The key is any name `rive schema KeyboardInput` accepts, or the same number
the markup takes. The phase is `down`, `repeat` or `up`; leaving it off sends
a whole keystroke, a down and an up, which is what a person pressing the key
produces. That default matters for the thing worth testing here: **one
keystroke should move a menu exactly one row.** A listener masked for every
phase moves it two, and only a full press shows that.

```bash
rive . --data-dump=- --key=down --advance=10
```

One `--key=down`, then read the selection out of the dump. If it moved by two,
the phase mask is the bug.

Keys reach only whatever holds focus, and a headless run starts with nothing
focused unless the file establishes it, so `--key` says so rather than
leaving you to read it as a filter that did not match. See
[focus.md](focus.md#nothing-is-focused-until-something-focuses-it).

## Prove it is actually responsive

A layout tree and a hand-positioned screen look identical in a single
screenshot. `--viewport` is what tells them apart — shoot the same file at a
second size and see whether anything moved:

```bash
rive <dir> --screenshot=wide.png  --viewport=900x600
rive <dir> --screenshot=narrow.png --viewport=320x700
```

`--viewport` sets the size the scene is laid out at -- the capture here, and
the window when watching, so the same number shows you the same layout either
way. It is not a fit. An artboard that lays itself out reflows into it, which
is the point of the check. A **fixed-size** artboard does not: it renders at
its authored size anchored top-left, so a smaller viewport crops it and a
larger one leaves background around it. That is the flag working, not a layout
bug.

Do this once the wireframe is up, before any detail exists. That is the cheapest
moment to discover the whole structure is pinned, and the most expensive one to
miss — every later pass is built on top of it.

Things to look for: fixed regions holding their size, flexible ones absorbing
the difference, nothing overflowing the artboard, and gradients still reaching
the edges of the boxes they fill.

## The viewer window

With no flags at all:

- **The window opens at the artboard's size**, and keeps following it. Change
  the artboard's size in the source and the window moves with it on the next
  build. That stops the moment you drag the window — from then on the size is
  yours and nothing resizes it. `z` (or **View → Size to Artboard**) puts it
  back and resumes following. Switching artboards always resizes.
- **The fit is `layout`.** The artboard is resized to the window and its layout
  reflows, so dragging the window is a real resize of the scene rather than a
  zoom. That is what makes the window a responsive check, and it is what a
  capture does too.

Two flags override those defaults.

`--viewport=<WxH>` pins the size. The window opens at it and stays there; the
artboard gets no vote and no rebuild moves it:

```bash
rive <dir> --viewport=300x200
```

`--fit=<mode>` changes the mapping. Every mode other than `layout` leaves the
artboard at its authored size and scales the drawing into the window instead:

```bash
rive <dir> --viewport=900x600 --fit=contain
```

`fill`, `contain`, `cover`, `fit-width`, `fit-height`, `none` and `scale-down`
mean what they do in every Rive runtime. `none` draws one artboard unit per
point, so the artboard appears at its authored size whatever the display.

Both flags apply to `--screenshot` and `--semantics` too, where `--viewport` is
the capture size. Live, the fits are also under the **View** menu, and `f` in
the terminal switches between them (`f contain`, or bare `f` to list them).

Input is the real thing. The mouse wheel and a trackpad's two-finger scroll,
the platform's own momentum included, reach scroll views as they would in an
app, and on a phone each finger is its own pointer that exits when it lifts —
what `--pointer=wheel`, `--pointer=trackpad` and `--touch` reproduce headless.
