# Sample projects

Runnable projects, each a complete `rive.yaml` plus its sources. Copy one out
and build it:

```bash
cp -R "$(rive samples --path)/hello_rive" myproject
rive myproject --verify
```

`rive samples` picks one and copies it for you; `--path` prints the
directory. Where no picker can draw -- Windows, stdin or stderr not a
terminal as in CI, `TERM=dumb`, or `RIVE_NO_TUI=1` -- it lists them with
their descriptions instead. Redirecting stdout alone keeps the picker: it draws on
stderr, so `rive samples > log` still asks.

## What each one shows

| Shows | Sample |
|---|---|
| The smallest layout script: draw a moving shape each frame | [hello_rive](hello_rive) |
| The same layout in AnimaScript, run on the wasm VM (`RIVE_RASC_STD` names rasc's std tree) | [hello_rive_as](hello_rive_as) |
| Keyboard, text and gamepad events in a script | [input_demo](input_demo) |
| Fetching a page from a script with `fetch()`; run with `--allow-net` | [fetch_demo](fetch_demo) |
| Downloading a .riv and binding its artboard to a view model property; run with `--allow-net` | [remote_artboard](remote_artboard) |
| The smallest RML document: one artboard, one shape | [rml_triangle](rml_triangle) |
| RML driven by view model data, with a script input | [rml_vm_input](rml_vm_input) |
| The same scene split across files: view models in `data/`, referenced by id from the scene | [rml_split](rml_split) |
| Making a scene follow the mouse: pointer to view model to data bind | [pointer_reactive](pointer_reactive) |
| Every view model property type driven by a script in Luau or AnimaScript, toggled in `rive.yaml`, plus a click listener writing one natively, for the debugger's View Models panel and data breakpoints | [vm_debug](vm_debug) |
| Asking the window for an OS cursor: hand over a button, resize across a drag | [cursor_demo](cursor_demo) |
| Editable text fields via the TextInput component: placeholder, obscured entry, Tab traversal | [text_input](text_input) |
| A keyboard-driven menu with no script: named key filters on a focus node, view model triggers driving a state machine, events on activate | [keyboard_menu](keyboard_menu) |
| Wheel and trackpad scrolling, with a horizontal strip nested inside a vertical list | [scroll_demo](scroll_demo) |
| Luau unit tests, run with `--test` | [tests_demo](tests_demo) |
| Fonts and shaped text from a script: a wrapped bilingual paragraph, a caret with its selection, and the same glyphs animated one by one | [scripted_text](scripted_text) |
| A three column blob poured around a circle that follows the pointer: the script is the line breaker over runtime shaped words | [text_island](text_island) |
| The same island in AnimaScript, for `--bench` comparisons between the script engines | [text_island_as](text_island_as) |
| A paragraph threaded on a string: shaped glyphs as beads on a Verlet rope, drag the last letters and it unravels | [text_string](text_string) |
| The same rope in AnimaScript, for `--bench` comparisons between the script engines | [text_string_as](text_string_as) |
| Text rain sheltered by an artist's umbrella: a Rive artboard opens and closes it, and the script reads the canopy back to size the shelter | [text_rain](text_rain) |
| The same rain in AnimaScript, for `--bench` comparisons between the script engines | [text_rain_as](text_rain_as) |
| A skinned mesh from a `.glb` blob, animated and drawn as a wireframe, with the skinning baked wide under the default `wasmSimd: on` | [mesh_skin_as](mesh_skin_as) |
| A path effect that resamples each contour and displaces it along its normal with a travelling sine wave, baked wide under the default `wasmSimd: on` | [wavy_effect_as](wavy_effect_as) |
| Twenty thousand particles integrated four per op under the default `wasmSimd: on`, the cleanest wide against scalar comparison with `wasmSimd: off` | [particles_as](particles_as) |
| An app shell under the macOS traffic lights: integrated title bar, draggable header, resizable sidebar | [integrated_titlebar](integrated_titlebar) |

Each has its own `rive.yaml`, so the directory you copy is a project in its own
right — nothing outside it is needed.
