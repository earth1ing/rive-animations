type Hello = {
    paint: Paint,
    path: Path,
    size: Vector,
    elapsed: number,
}

function init(self: Hello, context: Context): boolean
    print("hello from rive")
    return true
end

function resize(self: Hello, size: Vector)
    self.size = size
end

function advance(self: Hello, seconds: number): boolean
    self.elapsed += seconds
    return true
end

function draw(self: Hello, renderer: Renderer)
    local w = self.size.x
    local h = self.size.y
    local cx = w / 2 + math.cos(self.elapsed) * w * 0.25
    local cy = h / 2 + math.sin(self.elapsed * 1.3) * h * 0.25
    local r = math.min(w, h) * 0.1
    self.path:reset()
    self.path:moveTo(Vector.xy(cx - r, cy - r))
    self.path:lineTo(Vector.xy(cx + r, cy - r))
    self.path:lineTo(Vector.xy(cx + r, cy + r))
    self.path:lineTo(Vector.xy(cx - r, cy + r))
    self.path:close()
    renderer:drawPath(self.path, self.paint)
end

return function(context: Context): Layout<Hello>
    return {
        paint = Paint.with({
            color = Color.rgb(255, 100, 50),
        }),
        path = Path.new(),
        size = Vector.xy(0, 0),
        elapsed = 0,
        init = init,
        resize = resize,
        advance = advance,
        draw = draw,
    }
end
