-- Circles the Dashboard view model's orbs around a centre shape and writes
-- live stats back every frame, so the debugger always has values moving.
type Slot = { path: Path, paint: Paint }

type Orbit = {
    vm: ViewModel?,
    speed: Property<number>?,
    paused: Property<boolean>?,
    tint: Property<Color>?,
    shape: PropertyEnum?,
    orbs: PropertyList?,
    frames: Property<number>?,
    spin: Property<number>?,
    bursts: Property<number>?,
    angle: number,
    pulse: number,
    size: Vector,
    -- One per shape drawn, since the renderer may hold a path past drawPath.
    slots: { Slot },
}

local RING = 130

local function sidesOf(shape: string): (number, number)
    if shape == 'square' then
        return 4, math.pi / 4
    elseif shape == 'diamond' then
        return 4, 0
    end
    return 24, 0
end

local function polygon(
    path: Path,
    center: Vector,
    radius: number,
    sides: number,
    turn: number
)
    path:reset()
    for i = 0, sides - 1 do
        local a = turn + math.pi * 2 * i / sides
        local point = Vector.xy(
            center.x + math.cos(a) * radius,
            center.y + math.sin(a) * radius
        )
        if i == 0 then
            path:moveTo(point)
        else
            path:lineTo(point)
        end
    end
    path:close()
end

local function slotAt(self: Orbit, index: number): Slot
    local slot = self.slots[index]
    if slot == nil then
        slot = { path = Path.new(), paint = Paint.new() }
        self.slots[index] = slot
    end
    return slot
end

local function onBurst(self: Orbit)
    self.pulse = 1
    local bursts = self.bursts
    if bursts then
        bursts.value += 1
    end
    print('burst')
end

function init(self: Orbit, context: Context): boolean
    -- init runs twice, and the view model is absent the first time.
    local vm = context:viewModel()
    if vm == nil then
        return true
    end
    self.vm = vm
    self.speed = vm:getNumber('speed')
    self.paused = vm:getBoolean('paused')
    self.tint = vm:getColor('tint')
    self.shape = vm:getEnum('shape')
    self.orbs = vm:getList('orbs')
    local stats = vm:getViewModel('stats')
    if stats then
        self.frames = stats.value:getNumber('frames')
        self.spin = stats.value:getNumber('angle')
        self.bursts = stats.value:getNumber('bursts')
    end
    local burst = vm:getTrigger('burst')
    if burst then
        burst:addListener(self, onBurst)
    end
    local title = vm:getString('title')
    if title then
        title:addListener(function()
            print('title is now ' .. title.value)
        end)
    end
    return true
end

function resize(self: Orbit, size: Vector)
    self.size = size
end

function advance(self: Orbit, seconds: number): boolean
    local paused = self.paused
    if not (paused and paused.value) then
        local speed = self.speed
        self.angle += (if speed then speed.value else 1) * seconds
    end
    self.pulse = math.max(0, self.pulse - seconds * 2)
    local frames = self.frames
    if frames then
        frames.value += 1
    end
    local spin = self.spin
    if spin then
        spin.value = math.floor(math.deg(self.angle) % 360)
    end
    return true
end

function draw(self: Orbit, renderer: Renderer)
    local center = Vector.xy(self.size.x / 2, self.size.y / 2)
    local shape = self.shape
    local sides, turn = sidesOf(if shape then shape.value else 'circle')
    local tint = self.tint

    local core = slotAt(self, 1)
    polygon(core.path, center, 36 + self.pulse * 40, sides, turn + self.angle)
    core.paint.color = if tint then tint.value else Color.rgb(255, 255, 255)
    renderer:drawPath(core.path, core.paint)

    local orbs = self.orbs
    if orbs == nil then
        return
    end
    local count = orbs.length
    for i = 1, count do
        local orb = orbs[i]
        local size = orb:getNumber('size')
        local color = orb:getColor('color')
        local a = self.angle + math.pi * 2 * (i - 1) / count
        local at = Vector.xy(
            center.x + math.cos(a) * RING,
            center.y + math.sin(a) * RING
        )
        local slot = slotAt(self, i + 1)
        polygon(
            slot.path,
            at,
            if size then size.value else 10,
            sides,
            turn - self.angle * 2
        )
        slot.paint.color = if color
            then color.value
            else Color.rgb(255, 255, 255)
        renderer:drawPath(slot.path, slot.paint)
    end
end

return function(context: Context): Layout<Orbit>
    return {
        vm = nil,
        speed = nil,
        paused = nil,
        tint = nil,
        shape = nil,
        orbs = nil,
        frames = nil,
        spin = nil,
        bursts = nil,
        angle = 0,
        pulse = 0,
        size = Vector.xy(0, 0),
        slots = {},
        init = init,
        resize = resize,
        advance = advance,
        draw = draw,
    }
end
