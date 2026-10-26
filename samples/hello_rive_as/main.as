import { Layout, Context } from "rive/host";
import { Renderer } from "rive/renderer";
import { Paint } from "rive/paint";
import { Path } from "rive/path";
import { Vector } from "rive/vector";
import { Color } from "rive/color";

// The AnimaScript twin of hello_rive: a square orbiting the artboard.
export class Hello extends Layout {
    paint: Paint = new Paint();
    path: Path = new Path();
    width: f64 = 0;
    height: f64 = 0;
    elapsed: f64 = 0;

    override init(context: Context): bool {
        this.paint.color = Color.rgb(255, 100, 50);
        context.log("hello from rive");
        return true;
    }

    override resize(width: f64, height: f64, scale: f64): void {
        this.width = width;
        this.height = height;
    }

    override advance(seconds: f64): bool {
        this.elapsed += seconds;
        return true;
    }

    override draw(renderer: Renderer): void {
        const w = this.width;
        const h = this.height;
        const cx = w / 2 + Math.cos(this.elapsed) * w * 0.25;
        const cy = h / 2 + Math.sin(this.elapsed * 1.3) * h * 0.25;
        const r = Math.min(w, h) * 0.1;
        const path = this.path;
        path.reset();
        path.moveTo(Vector.xy(<f32>(cx - r), <f32>(cy - r)));
        path.lineTo(Vector.xy(<f32>(cx + r), <f32>(cy - r)));
        path.lineTo(Vector.xy(<f32>(cx + r), <f32>(cy + r)));
        path.lineTo(Vector.xy(<f32>(cx - r), <f32>(cy + r)));
        path.close();
        renderer.drawPath(path, this.paint);
    }
}
