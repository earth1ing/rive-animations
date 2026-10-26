-- Spins a square at a speed provided by the bound view model.
type VmSpin = {
    settings: Input<Data.Settings>?,
    paint: Paint,
    path: Path,
    size: Vector,
    angle: number,
}

local function speedOf(self: VmSpin): number
    local settings = self.settings
    if settings == nil then
        return 0.5
    end
    return settings.speed.value
end

function init(self: VmSpin, context: Context): boolean
    print("vm speed: " .. speedOf(self))
    return true
end

function resize(self: VmSpin, size: Vector)
    self.size = size
end

function update(self: VmSpin)
    print("vm speed changed: " .. speedOf(self))
end

function advance(self: VmSpin, seconds: number): boolean
    self.angle += speedOf(self) * seconds
    return true
end

function draw(self: VmSpin, renderer: Renderer)
    local cx = self.size.x / 2
    local cy = self.size.y / 2
    local r = math.min(self.size.x, self.size.y) * 0.25
    self.path:reset()
    for corner = 0, 3 do
        local a = self.angle + math.pi * 0.5 * corner
        local point = Vector.xy(cx + math.cos(a) * r, cy + math.sin(a) * r)
        if corner == 0 then
            self.path:moveTo(point)
        else
            self.path:lineTo(point)
        end
    end
    self.path:close()
    renderer:drawPath(self.path, self.paint)
end

return function(context: Context): Layout<VmSpin>
    return {
        settings = nil,
        paint = Paint.with({
            color = Color.rgb(87, 165, 224),
        }),
        path = Path.new(),
        size = Vector.xy(0, 0),
        angle = 0,
        init = init,
        resize = resize,
        update = update,
        advance = advance,
        draw = draw,
    }
end
