# AnimaScript protocols

AnimaScript is Rive's TypeScript syntax language over WebAssembly types. It
began as AssemblyScript, and our compiler, `rasc`, which the CLI carries, turns
`.as` files into a wasm module. It does the same jobs as Luau; see
[../luau/protocols.md](../luau/protocols.md) for that lane.

A `.as` file becomes part of a Rive file by **exporting a class that extends a
protocol base**. The base you extend determines what the script is and when it
runs.

| Extend | Import from | What it is | Attached with |
|---|---|---|---|
| `Layout` | `rive/host` | a drawable that fills a layout box | `ScriptedLayout` |
| `Node` | `rive/host` | a drawable in the artboard tree | `ScriptedDrawable` |
| `PathEffect` | `rive/host` | rewrites a shape's geometry | `ScriptedPathEffect` |
| `Converter` | `rive/host` | transforms a value in a data bind | `ScriptedDataConverter` |
| `ListenerAction` | `rive/host` | runs when a listener fires | `ScriptedListenerAction` |
| `TransitionCondition` | `rive/host` | decides whether a transition may take | `ScriptedTransitionCondition` |
| `Interpolator` | `rive/host` | a custom easing curve | `ScriptedInterpolator` |
| `Transition` | `rive/host` | composites the switch between two nested artboards | `ScriptedTransition` |
| `Tests` | `rive/test` | unit tests, run headless | — |

The hooks each base declares, with their exact signatures, are in
[api/host.md](api/host.md). The rest of the API — `Renderer`, `Path`, `Paint`,
`Vector`, `Color` — is in [api/](api/README.md), one page per `rive/*` module.
Use it rather than guessing names.

## Turning it on

AnimaScript compiles to wasm, so the project has to say so in `rive.yaml`:

```yaml
name: myproject
scripting: wasm
```

Without it any `.as` file fails the build with *"AnimaScript sources need
scripting: wasm"*. Keep a wasm project to `.as` files: a `.luau` file in it
needs a separate VM blob (`scriptVm`) and fails without one.

Every `.as` file in the project directory is picked up. Its module id is its
path without the extension, so `fx/wave.as` is `fx/wave`.

## Declaring a protocol

```as
import { Layout, Context } from "rive/host";
import { Renderer } from "rive/renderer";

export class Main extends Layout {
    override init(context: Context): bool {
        context.log("hello");
        return true;
    }

    override draw(renderer: Renderer): void {}
}
```

The rules:

- **The class must be exported**, or nothing registers it, and extend one of
  the bases above, directly or through a class of your own. Extending
  `Protocol` itself is an error.
- **Every hook is marked `override`.** A hook without it fails with *"overrides
  a Layout hook; mark it override"*. `override` on a name the base does not
  declare fails with *"override on 'x' but no base declares it"*. So unlike
  Luau, **a misspelled hook marked `override` is a build error**, not a
  silently dropped key.
- **Abstract hooks are required** (`Converter.convert`, `PathEffect.update`,
  `TransitionCondition.evaluate`, `Interpolator.transform`, `Transition.draw`).
  The rest are optional, and the host calls only the ones you override.
- **Hooks cannot be `static`.**

Per-instance setup goes in field initializers or the constructor. `init` is the
first call that has a `Context`; return `false` from it to decline. `advance`
returning `true` keeps the advances coming; `false` is a static frame.

One file can hold several protocol classes. A file with exactly one is
registered under its module id; with several, each is registered as
`<module>#<Class>`. A file with none is a library, imported by other files and
never a script asset of its own.

Write to the build log with `context.log(message)`, which needs the `Context`
from `init` — keep it in a field.

## Checking a script

```bash
rive <dir> --verify
```

Compiles every `.as` file along with the RML and shaders, and exits non-zero
on an error, without writing a `.riv`. As with Luau, it compiles; it does not
run. A runtime trap — an out-of-bounds read, a null dereference — shows up
only when the scene runs, in the console of `--screenshot` or the live window.
`rive inspect` does not read scripts at all.

## Values and types

AnimaScript is statically typed and compiled, closer to C than to TypeScript.
What trips people up first:

- **Numbers have sizes.** `f64`, `f32`, `i32`, `u32` and the rest; `bool`, not
  `boolean`. Most of the API takes `f32` (`Vector`, path points) and the hooks
  take `f64` (`advance`, `resize`), so convert with a cast: `<f32>this.width`.
- **`Vector`, `Mat2D` and `Color` are values.** `Vector` and `Mat2D` are
  structs, copied on assignment; `Color` is a `u32`, `0xAARRGGBB`. Build them
  with `Vector.xy(x, y)` and `Color.rgb(r, g, b)`.
- **Only class instances can be null.** An optional object is `T?`;
  narrow it through a local before use, as every example here does. An optional
  number or struct needs a wrapper, `Box<f64>?`; see
  [api/box.md](api/box.md).
- **`this.` is optional** inside a method when no local, parameter or global
  shares the name.

```as
import { Node, Context } from "rive/host";
import { Color } from "rive/color";
import { Paint } from "rive/paint";
import { Path } from "rive/path";
import { Renderer } from "rive/renderer";
import { Vector } from "rive/vector";

export class Dot extends Node {
    radius: f64 = 20;
    path: Path = new Path();
    paint: Paint = new Paint();
    context: Context? = null;

    override init(context: Context): bool {
        this.context = context;
        this.paint.color = Color.rgb(255, 100, 50);
        let r = <f32>this.radius;
        this.path.moveTo(Vector.xy(-r, 0));
        this.path.lineTo(Vector.xy(0, -r));
        this.path.lineTo(Vector.xy(r, 0));
        this.path.lineTo(Vector.xy(0, r));
        this.path.close();
        return true;
    }

    override draw(renderer: Renderer): void {
        renderer.drawPath(this.path, this.paint);
    }
}
```

## Layout

The workhorse. Receives a size and draws.

```as
import { Layout, Context } from "rive/host";
import { Color } from "rive/color";
import { Paint } from "rive/paint";
import { Path } from "rive/path";
import { Renderer } from "rive/renderer";
import { Vector } from "rive/vector";

export class Spin extends Layout {
    @input speed: f64 = 1;
    angle: f64 = 0;
    width: f64 = 0;
    height: f64 = 0;
    path: Path = new Path();
    paint: Paint = new Paint();

    override init(context: Context): bool {
        this.paint.color = Color.rgb(255, 100, 50);
        return true;
    }

    override resize(width: f64, height: f64, scale: f64): void {
        this.width = width;
        this.height = height;
    }

    override advance(seconds: f64): bool {
        this.angle += seconds * this.speed;
        return true;
    }

    override draw(renderer: Renderer): void {
        let cx = this.width / 2;
        let cy = this.height / 2;
        let r = Math.min(cx, cy) * 0.8;
        this.path.reset();
        this.path.moveTo(Vector.xy(<f32>cx, <f32>cy));
        this.path.lineTo(Vector.xy(<f32>(cx + Math.cos(this.angle) * r),
                                   <f32>(cy + Math.sin(this.angle) * r)));
        this.path.lineTo(Vector.xy(<f32>(cx - Math.sin(this.angle) * r),
                                   <f32>(cy + Math.cos(this.angle) * r)));
        this.path.close();
        renderer.drawPath(this.path, this.paint);
    }
}
```

**`resize` takes three numbers, `width`, `height` and `scale`**, not Luau's
`size` vector. `scale` is the presenting surface's device pixels per point.
Ignore it while you draw through the `Renderer`; size any canvas you allocate
yourself in points times `scale`, or it renders soft on a Retina display — see
[../luau/protocols.md](../luau/protocols.md#layout), which applies unchanged.

`measure()` returns the size the layout wants when its parent hugs its
content.

In a project with no `.rml`, every `Layout` gets its own artboard
automatically. In an RML project, attach it with a `ScriptAsset` whose `file`
is the `.as` path:

```xml
<Artboard defaultStateMachineId="0:7" width="500" height="500" styleId="0:5" name="Artboard" id="0:2">
    <LayoutComponentStyle name="Artboard Style" id="0:5"/>
    <LayoutComponent width="500" height="500" styleId="0:11" name="Root" id="0:10">
        <LayoutComponentStyle layoutWidthScaleType="fill" layoutHeightScaleType="fill"
            widthUnitsValue="auto" heightUnitsValue="auto" name="Style" id="0:11"/>
        <ScriptedLayout scriptAssetId="0:80" name="Spin" id="0:12"/>
    </LayoutComponent>
</Artboard>

<ScriptAsset file="spin.as" name="spin" id="0:80"/>
```

The fill-sized parent and the artboard's own `LayoutComponentStyle` matter
exactly as for Luau; see [../layout.md](../layout.md).

For a file with several protocol classes, `file` names one of them as
`<module>#<Class>.as`, so the `Spin` class of `fx.as` is
`file="fx#Spin.as"`.

## Node

A component in the tree rather than a layout box; it has no `resize` or
`measure`. The `Dot` above is one. Attach it with a `ScriptedDrawable`:

```xml
<ScriptedDrawable x="120" y="20" scriptAssetId="0:83" name="Orbit" id="0:12"/>
```

## Path effect

Rewrites one shape's geometry. `update` receives the path the markup produced
and returns the one to draw. For an effect that moves on its own, call
`markNeedsUpdate` from `advance`, or `update` runs only when an input changes.

```as
import { PathEffect, Context } from "rive/host";
import { Mat2D } from "rive/mat2d";
import { Path } from "rive/path";
import { PathEffectNode } from "rive/path_effect";

export class Pulse extends PathEffect {
    elapsed: f64 = 0;
    outPath: Path = new Path();
    context: Context? = null;

    override init(context: Context): bool {
        this.context = context;
        return true;
    }

    override advance(seconds: f64): bool {
        this.elapsed += seconds;
        let context = this.context;
        if (context != null) {
            context.markNeedsUpdate();
        }
        return true;
    }

    override update(path: Path, node: PathEffectNode): Path {
        let s = <f32>(1 + Math.sin(this.elapsed * 4) * 0.1);
        this.outPath.reset();
        this.outPath.add(path, Mat2D.withScale(s, s));
        return this.outPath;
    }
}
```

```xml
<Shape x="10" y="10" name="Panel" id="0:10">
    <Rectangle width="180" height="100" originX="0" originY="0" name="Path"/>
    <ScriptedPathEffect scriptAssetId="0:80" name="Pulse" id="0:11"/>
    <Fill name="Fill"><SolidColor colorValue="FF7DB8A9" name="C"/></Fill>
</Shape>
```

## Converter

Both directions take and return a `DataValue`, or `null` for no result.
`reverseConvert` is optional here, unlike Luau.

```as
import { Converter } from "rive/host";
import { DataValue, DataValueNumber } from "rive/data_value";

export class Half extends Converter {
    override convert(input: DataValue): DataValue? {
        if (input.isNumber()) {
            return new DataValueNumber((<DataValueNumber>input).value * 0.5);
        }
        return null;
    }

    override reverseConvert(input: DataValue): DataValue? {
        if (input.isNumber()) {
            return new DataValueNumber((<DataValueNumber>input).value * 2);
        }
        return null;
    }
}
```

`ScriptedDataConverter` is a root element named from the bind by
`converterId`, as in [../luau/protocols.md](../luau/protocols.md#converter).

## Listener action

```as
import { ListenerAction } from "rive/host";
import { ListenerContext } from "rive/events";

export class Tap extends ListenerAction {
    clicks: i32 = 0;

    override performAction(context: ListenerContext): void {
        if (context.isPointerEvent()) {
            this.clicks++;
        }
    }
}
```

```xml
<StateMachineListenerSingle targetId="0:10" listenerTypeValue="click" name="Tap" id="0:50">
    <ScriptedListenerAction scriptAssetId="0:85" id="0:51"/>
</StateMachineListenerSingle>
```

## Transition condition

```as
import { TransitionCondition } from "rive/host";

export class WhenReady extends TransitionCondition {
    @input ready: bool = false;

    override evaluate(): bool {
        return this.ready;
    }
}
```

```xml
<StateTransition stateToId="0:14" duration="100">
    <ScriptedTransitionCondition scriptAssetId="0:84" id="0:15"/>
</StateTransition>
```

`ScriptedListenerAction` and `ScriptedTransitionCondition` take no `name`; see
[../luau/protocols.md](../luau/protocols.md#two-of-these-take-no-name).

## Interpolator

`transform` maps linear progress, 0 to 1, to eased progress.

```as
import { Interpolator } from "rive/host";

export class EaseIn extends Interpolator {
    override transform(value: f64): f64 {
        return value * value;
    }
}
```

It nests under a keyframe like the built-in curves in
[../easing.md](../easing.md), with `interpolationType="scripted"`:

```xml
<KeyFrameDouble value="0" frame="0" interpolationType="scripted">
    <ScriptedInterpolator scriptAssetId="0:86"/>
</KeyFrameDouble>
```

## Transition

Composites the switch between the children of a `ScriptedTransition`, each a
`NestedArtboard`. `activeComponentId` picks the active one; when it changes,
`changed` runs, then `advance` and `draw` until `advance` returns `false`.

```as
import { Transition, TransitionChild } from "rive/host";
import { Renderer } from "rive/renderer";

export class Crossfade extends Transition {
    progress: f64 = 0;

    override changed(from: TransitionChild?, to: TransitionChild?,
                     direction: f64): void {
        this.progress = 0;
    }

    override advance(seconds: f64): bool {
        this.progress = Math.min(1, this.progress + seconds * 2);
        return this.progress < 1;
    }

    override draw(renderer: Renderer, from: TransitionChild?,
                  to: TransitionChild?): void {
        if (from != null) {
            renderer.save();
            renderer.modulateOpacity(1 - this.progress);
            from.draw(renderer);
            renderer.restore();
        }
        if (to != null) {
            renderer.save();
            renderer.modulateOpacity(this.progress);
            to.draw(renderer);
            renderer.restore();
        }
    }
}
```

```xml
<ScriptedTransition scriptAssetId="0:81" activeComponentId="0:30" name="Switch" id="0:20">
    <NestedArtboard artboardId="0:90" name="A" id="0:30"/>
    <NestedArtboard artboardId="0:95" name="B" id="0:31"/>
</ScriptedTransition>
```

## Inputs

A member marked `@input` is set by the scene. Three shapes:

```as
import { Layout } from "rive/host";
import { Color } from "rive/color";

export class Ball extends Layout {
    @input radius: f32 = 50;
    @input label: string = "";
    @input tint: Color = 0xFFFFFFFF;
    @input("speed") speedValue: f64 = 1;
    dirty: bool = false;

    @input set visible(value: bool) {
        this.dirty = true;
    }

    @input onReset(): void {
        this.radius = 50;
    }
}
```

- **A field** takes the value.
- **A setter** runs code on each change. Put `@input` on the setter, not a
  getter.
- **A method with no parameters returning `void`** is a trigger: firing the
  input calls it.

The input's name is the member's, or the one given as `@input("name")`. Field
types are any number type, `bool`, `string`, `Color`, `Artboard` and a class
extending `ViewModel`.

RML supplies each with a `ScriptInput*` child of the `Scripted*` object,
**matched by name**, the same elements as for Luau:

```xml
<ScriptedLayout scriptAssetId="0:80" name="Ball" id="0:12">
    <ScriptInputNumber propertyValue="30" name="radius"/>
    <ScriptInputString propertyValue="Go" name="label"/>
    <ScriptInputNumber propertyValue="2" name="speed"/>
    <ScriptInputBoolean propertyValue="true" name="visible"/>
    <ScriptInputTrigger name="onReset"/>
</ScriptedLayout>
```

| Member type | RML element |
|---|---|
| any number type | `ScriptInputNumber` |
| `bool` | `ScriptInputBoolean` |
| `string` | `ScriptInputString` |
| `Color` | `ScriptInputColor` |
| a trigger method | `ScriptInputTrigger` |
| `Artboard?` | `ScriptInputArtboard`, with `artboardId` |
| a nullable `ViewModel` subclass, `T?` | `ScriptInputViewModelProperty` |

A name that matches nothing leaves the member at its initializer and reports
nothing. Binding, keying and the trigger's two keys work as described in
[../luau/protocols.md](../luau/protocols.md#an-input-is-a-custom-property).

### View model inputs

A view model input is declared with a class named after the view model,
extending `ViewModel` from `rive/data`. It needs a constructor that takes the
handle, since constructors are not inherited. `Artboard<Character>` names the
view model an artboard input binds.

```as
import { Node, Context } from "rive/host";
import { Artboard } from "rive/artboard";
import { ViewModel } from "rive/data";

export class Character extends ViewModel {
    constructor(handle: u32) {
        super(handle);
    }
}

export class Scene extends Node {
    @input settings: Character? = null;
    @input character: Artboard<Character>? = null;
    health: f64 = 0;

    override update(): void {
        let settings = this.settings;
        if (settings == null) {
            return;
        }
        let health = settings.getNumber("health");
        if (health != null) {
            this.health = health.value;
        }
    }
}
```

The input may not be bound yet when `init` runs; read it where it is used,
and guard for `null`. `context.viewModel()` is the view model the scripted
object is bound to, and a script can write it through the same property
handles; see
[../luau/protocols.md](../luau/protocols.md#driving-markup-from-the-pointer).

## Pointer, keyboard and gamepad input

`Node` and `Layout` receive input by overriding `pointerDown`, `pointerMove`,
`pointerUp`, `pointerExit`, `pointerScroll`, `keyboardEvent`, `textEvent`,
`gamepadConnected`, `gamepadEvent` and `gamepadDisconnected`; the event types
are in [api/events.md](api/events.md). The runtime rules are the Luau ones:

- `event.position` is in the script's local coordinates, and the script sees
  every pointer event in the artboard, not only those inside its bounds.
- **`event.hit()` claims the event.** Call it on every event of a gesture you
  own, or an enclosing scroll view takes the drag. `event.hit(true)` lets it
  continue to whatever is behind.
- `pointerScroll` gets a `ScrollEvent` for a mouse wheel or trackpad scroll,
  and only while the pointer is over the script: a `Layout` inside its box, a
  `Node` anywhere in its artboard. `event.delta` follows the content, as a
  `ScrollConstraint` does. Without `event.hit()` the scroll passes to
  whatever lies behind. Implementing it makes that area a scroll target for
  the host, so a host such as a Flutter page hands the wheel to the scene
  there even when the script declines it.
- Keyboard and text events need a direct `FocusData` child of the scripted
  object.
- **Gamepad indices are 0-based here**, unlike Luau's 1-based `changeIndex`.
  `changeIndex`, `standardButton`, `standardAxis` and the `buttons` and `axes`
  arrays all use W3C slots, so the bottom face button (`south`) is `0`, the
  same as `GamepadInput.inputIndex` in the scene format.

See [../luau/protocols.md](../luau/protocols.md#pointer-and-gamepad-input) for
the detail.

```as
import { Layout } from "rive/host";
import { PointerEvent } from "rive/events";

export class Slider extends Layout {
    value: f64 = 0;
    width: f64 = 1;
    down: bool = false;

    override resize(width: f64, height: f64, scale: f64): void {
        this.width = width;
    }

    override pointerDown(event: PointerEvent): void {
        this.down = true;
        this.write(event);
    }

    override pointerMove(event: PointerEvent): void {
        if (this.down) {
            this.write(event);
        }
    }

    override pointerUp(event: PointerEvent): void {
        if (this.down) {
            this.down = false;
            this.write(event);
        }
    }

    private write(event: PointerEvent): void {
        this.value = Math.min(Math.max(<f64>event.position.x / this.width, 0), 1);
        event.hit();
    }
}
```

Zooming on the wheel, around the pointer:

```as
import { Layout } from "rive/host";
import { ScrollEvent } from "rive/events";
import { Vector } from "rive/vector";

export class ZoomView extends Layout {
    zoom: f32 = 1;
    offset: Vector = Vector();

    override pointerScroll(event: ScrollEvent): void {
        let factor = <f32>Math.exp(-event.delta.y * 0.01);
        this.offset = event.position - (event.position - this.offset) * factor;
        this.zoom *= factor;
        event.hit();
    }
}
```

## Tests

A suite is an exported class extending `Tests` from `rive/test`. `run` declares
groups and cases; each case receives its own `expect`.

```as
import { Expect, Tests } from "rive/test";

function clamp(value: f64, low: f64, high: f64): f64 {
    return Math.min(Math.max(value, low), high);
}

@editTime
function expectClamped(expect: Expect, value: f64, want: f64): void {
    expect.that(clamp(value, 0, 5)).is(want);
}

export class MathTests extends Tests {
    override run(): void {
        group("clamp", () => {
            test("clamps high", (expect) => {
                expectClamped(expect, 10, 5);
            });
            test("passes through", (expect) => {
                expect.that(clamp(3, 0, 5)).is(3);
            });
        });
    }
}
```

```bash
rive <dir> --test        # headless, non-zero exit on failure
```

Matchers: `is`, `lessThan`, `lessThanOrEqual`, `greaterThan`,
`greaterThanOrEqual`, each negatable as `expect.that(x).never.is(y)`.

Test code never ships. `Tests` and its subclasses are edit-time only, and a
runtime build refuses runtime code that names `Expect` or `Expectation`, so a
helper that takes `expect` is marked `@editTime`, as above.

## Modules

A `.as` file with no protocol class is a library. Import from it with a
relative path, and from the Rive API with `rive/*`:

<!-- as:file mathutil.as -->
```as
export function clamp(value: f64, low: f64, high: f64): f64 {
    return Math.min(Math.max(value, low), high);
}
```

```as
import { Converter } from "rive/host";
import { DataValue, DataValueNumber } from "rive/data_value";
import { clamp } from "./mathutil";

export class Clamp extends Converter {
    override convert(input: DataValue): DataValue? {
        if (input.isNumber()) {
            return new DataValueNumber(clamp((<DataValueNumber>input).value, 0, 1));
        }
        return null;
    }
}
```

All of a project's `.as` files compile into one wasm module, so there is no
per-file or per-import `ScriptAsset` to declare and no declaration order to
get right, unlike Luau's `require`. A `ScriptAsset` is needed only for a
protocol script the scene attaches.

A module published by a Rive library, which is a different thing from a `.as`
file with no protocol class, is imported by the library's name after `lib:`,
the same spelling a Luau `require` uses:

<!-- as:skip -->
```as
import { wavePhase } from "lib:bar/bar_math";
```

The name is the key under `libraries:` in rive.yaml. See
[project/rive-yaml.md](../project/rive-yaml.md#libraries).
