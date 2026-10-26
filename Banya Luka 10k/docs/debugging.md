# Debugging scripts

The preview can host a debugger for the Luau and AnimaScript scripts in
a project. VS Code speaks to it through the Rive extension; any Debug
Adapter Protocol client can connect the same way.

## From VS Code

Install the Rive extension, open the project folder and press F5. The
extension runs `rive <project> --debug` in a terminal, waits for the preview
to come up and attaches. Breakpoints in `.luau` and `.as` files, stepping,
the call stack and the Debug Console work as they do for any other language;
Luau frames also show locals and upvalues and answer a hover. Script errors
pause where they were raised, with the message; turn that off under
Breakpoints, "Script errors".

To attach to a preview you started yourself, run it with `--debug`:

```bash
rive . --debug          # listens on 9641
rive . --debug=9700     # any port
```

then pick "Rive: attach to preview" from the Run and Debug dropdown, or add
the configuration to `launch.json`:

```json
{ "type": "rive", "request": "attach", "name": "Rive: attach", "port": 9641 }
```

The listener is loopback only.

## View models

The debugger shows the data the preview is bound to, whichever language
your scripts are in, and whether or not one has stopped.

- **View Models panel.** Under Run and Debug, the View Models panel lists
  the artboard's own view model instance and every global one. It refreshes
  while the preview runs, so you can watch values move. Expand a nested view
  model or a list to see what is inside it. Hover over a number, string,
  boolean, color or enum and press the pencil to change it, or press the
  bolt on a trigger to fire it.
- **At a stop.** The Variables panel adds a View Models scope beside Locals
  and Upvalues. Set Value works there too. A value you set while paused takes
  effect when you continue, and a value it cannot take is reported in the
  Debug Console then.

Values are read and written the way `--data` takes them: numbers in plain
form, colors as hex ARGB or RGB like `FF3311BB` or `3311BB`, enums by the
name of an option, and booleans as `true`, `false`, `1` or `0`. A value the
property cannot take is refused with the reason.

### Breaking when a value changes

Right click a view model value in Variables and pick **Break on Value
Change**, or press the breakpoint button beside it in the View Models panel.
The next time anything writes that value, the preview stops where it was
written.

- **A script wrote it.** The stop lands on the line that assigned it, in
  Luau or AnimaScript, with the full call stack.
- **The scene wrote it.** A listener action, or a data bind writing back to its
  view model, has no line to show. The call stack lists what did it instead,
  innermost first, for example `Bind from a listener's value`,
  `Listener 'Tap'`, `State Machine 'State Machine 1' on Artboard 'Main'`. An
  action on a state or transition names its layer too. A write from outside
  any script or state machine says so.
- **The message says what changed**, like `Main/stats/bursts: 0 → 1`, and a
  trigger says it fired.

A stop in the scene has no lines to step through, so stepping from it just
continues. Your own edits from the debugger never stop, but whatever they set
off does:
firing a trigger from the panel stops in the script listener that reacts to
it. A breakpoint follows its path, so it survives a rebuild and a script
replacing a nested view model or a list row.

## What to expect

- **Rebuilds keep the session.** Save a script and the preview rebuilds as
  usual; the breakpoints are planted again in the new build. A build that
  lands while you are paused waits until you continue.
- **Breakpoints move to the next executable line.** A breakpoint on a blank
  line, a comment or `end` binds to the next line that runs, and the editor
  shows where it landed. One that binds nowhere stays hollow.
- **The window freezes while paused.** Scripts run on the preview's own
  thread, so a stop holds the whole window, including its menus, until you
  continue. Its terminal keeps logging.
- **Stepping out of a callback lands in the next one.** Protocol methods
  like `advance` and `draw` are called from the runtime, so stepping out of
  the outermost frame stops at the first line the runtime runs next, usually
  the next callback of the frame.
- **`async` functions.** A breakpoint inside an `async` body stops on that
  coroutine, with its own stack. Stepping over a yield lands where the
  resumer continues. In AnimaScript an async body is one frame per
  resume: it leaves the stack when it suspends at an `await`, and a resume
  shows it above whatever settled its promise (usually a callback like
  `advance`). Stepping over an `await` that suspends lands in the next code
  the runtime runs.
- **`--optimize` bakes are for shipping, not debugging.** The optimised
  Luau bake keeps line numbers but not the locals panel; the optimised
  AnimaScript bake carries no line probes at all, so its breakpoints stay
  hollow and nothing stops. A project with `dangerouslyFast: true` in its
  `rive.yaml` takes that release bake for AnimaScript too.
- **AnimaScript shows frames, not variables.** Breakpoints, stepping,
  the call stack and stops on traps work; locals and hover stay empty
  until a later bake can spill locals. The View Models scope still shows. A generator body is a frame
  under its own name for each `next()`.
- **Hover and Watch evaluate names, not expressions.** Dotted paths walk
  tables, vectors and Rive objects, so `self.size.x` works; `self.size.x * 2`
  does not.
