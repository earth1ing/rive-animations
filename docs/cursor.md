# Native cursor

A scene can ask the window it runs in for an OS cursor: a pointing hand over
a button, a horizontal resize cursor over a divider, an I-beam over editable
text. The scene owns the *intent* — it decides, from its own hover and drag
state, which cursor it wants — and the host owns the pointer: the previewer
shows the request while the pointer is in the window and puts the arrow back
whenever it is not.

A project opts in by naming, in `rive.yaml`, the view model property it will
write cursor names into. Projects without the key keep the OS cursor.

## Opting in

```yaml
name: sidebar
cursor:
  property: cursor
```

`cursor.property` is a path on the artboard's bound view model instance,
spelled the way `--data` spells one: `cursor` for a property on the root,
`ui/cursor` for one on a nested view model. It must be a **string** or
**enum** property; a number, boolean, colour or trigger at that path is
reported once per build and the arrow stays. So is a path that leads nowhere,
or an artboard that binds no view model.

Declare the property like any other. A string is the least ceremony:

```xml
<ViewModel defaultInstanceId="0:41" name="Root" id="0:40">
    <ViewModelPropertyString name="cursor" id="0:45"/>
    <ViewModelInstance exports="true" name="Instance" id="0:41">
        <ViewModelInstanceString propertyValue="arrow" viewModelPropertyId="0:45"/>
    </ViewModelInstance>
</ViewModel>
```

An enum works the same way and keeps the choices in the file: a
`DataEnumCustom` whose keys are the names below, read through
`ViewModelPropertyEnumCustom`. See
[data.md](data.md#enums).

## The names

| Name | Shows |
|---|---|
| `arrow` | the platform's default pointer |
| `pointer` | pointing hand |
| `resizeHorizontal` | left-right resize |
| `resizeVertical` | up-down resize |
| `text` | I-beam |
| `hidden` | no pointer at all |

Matching ignores case and any `-` or `_`, so `resize-horizontal` reads as
`resizeHorizontal`. An empty string is the arrow, so a fresh property nobody
has written yet reads clean. Anything else — `grab`, `ew-resize`, a typo —
shows the arrow and is logged once per value per scene:

```
cursor: cursor = "grab" is not a cursor; the arrow shows. One of: arrow, pointer, resizeHorizontal, resizeVertical, text, hidden
```

The host never writes the property. It reads it after every advance, so
whatever wrote it — a listener, a script, `--data` — sees the same value.

## Writing it

Two listeners are enough for a button; they write a string with
`BindablePropertyString` (`propertyKey="635"`, `direction="true"`), the same
shape as the hover example in
[state-machines.md](state-machines.md#a-button-that-hovers-and-presses):

```xml
<StateMachineListenerSingle targetId="0:20" listenerTypeValue="enter" name="Button In" id="0:50">
    <ListenerViewModelChange>
        <BindablePropertyString propertyValue="pointer">
            <DataBindContext sourcePathIds="0:40-0:45" propertyKey="635" direction="true"/>
        </BindablePropertyString>
    </ListenerViewModelChange>
</StateMachineListenerSingle>

<StateMachineListenerSingle targetId="0:20" listenerTypeValue="exit" name="Button Out" id="0:51">
    <ListenerViewModelChange>
        <BindablePropertyString propertyValue="arrow">
            <DataBindContext sourcePathIds="0:40-0:45" propertyKey="635" direction="true"/>
        </BindablePropertyString>
    </ListenerViewModelChange>
</StateMachineListenerSingle>
```

A drag is a script's job, because the cursor has to *stay* a resize cursor
for the whole gesture, wherever the pointer wanders, and only a script knows
it is mid-drag. It writes the same property through
`context:viewModel():getString('cursor')`:

```luau
function pointerMove(self: Divider, event: PointerEvent)
    if self.dragging then
        want(self, 'resizeHorizontal') -- held: wherever the pointer is
        return
    end
    local over = overDivider(self, event.position.x)
    if over ~= self.over then
        self.over = over
        want(self, if over then 'resizeHorizontal' else 'arrow')
    end
end
```

Write on a **change of intent**, never every frame. Several writers can share
one property — the button's listeners and the divider's script above do — as
long as each writes only when its own state changes; a script that writes
`arrow` on every move would erase the button's `pointer` the moment the
pointer crossed it. Two writers changing intent on the *same* event (a jump
straight from one region onto another, with no move between) both land, and
whichever the state machine runs last wins; keep regions that share a
property apart, or let one writer own them all.

[samples/cursor_demo](../samples/cursor_demo) is the whole of the above as a
runnable project: arrow over the background, hand over the button, a
horizontal resize cursor over the divider that holds through a drag and lets
go on release.

## What the host does

The request shows while the pointer is inside the window's content area. The
arrow comes back when the pointer leaves, the window loses focus, or the scene
is rebuilt; a drag that leaves the window keeps its cursor until release.
Leaving fires the scene's `exit` listeners and `pointerExit` hooks.

The cursor changes on screen on macOS and Linux. On Windows and the web the
request is read and logged, and nothing changes.

## Checking it

`--data-dump` shows what a gesture left in the property:

```sh
rive samples/cursor_demo --pointer=move@261,200 --pointer=down@261,200 --pointer=move@400,200 --data-dump=-
```

`--pointer=exit@x,y` drives the exit path. Whether the OS cursor actually
changed needs the previewer window.
