-- Turns pointer position into view model numbers. The markup is data bound to
-- those numbers, so the script never touches the scene graph itself.
--
-- The whole chain: pointerMove -> context:viewModel() -> DataBindContext.

type Track = {
    size: Vector,
    -- Nil until the second init; see below.
    cardX: Property<number>?,
    cardY: Property<number>?,
    cardRot: Property<number>?,
    dotX: Property<number>?,
    dotY: Property<number>?,
    -- Smoothed pointer, so the card eases rather than snapping.
    x: number,
    y: number,
    targetX: number,
    targetY: number,
}

function init(self: Track, context: Context): boolean
    -- init runs twice and the view model is absent the first time. Without
    -- this guard the handles stay nil and the scene never moves.
    local vm = context:viewModel()
    if vm == nil then
        return true
    end
    self.cardX = vm:getNumber('cardX')
    self.cardY = vm:getNumber('cardY')
    self.cardRot = vm:getNumber('cardRot')
    self.dotX = vm:getNumber('dotX')
    self.dotY = vm:getNumber('dotY')
    return true
end

function resize(self: Track, size: Vector)
    self.size = size
end

-- A fill-sized ScriptedLayout at the artboard root receives the whole
-- artboard, and event.position is in artboard coordinates.
function pointerMove(self: Track, event: PointerEvent)
    self.targetX = event.position.x
    self.targetY = event.position.y
end

function advance(self: Track, seconds: number): boolean
    -- Frame-rate independent follow.
    local k = 1 - math.exp(-10 * seconds)
    self.x += (self.targetX - self.x) * k
    self.y += (self.targetY - self.y) * k

    local w = if self.size.x > 0 then self.size.x else 500
    local h = if self.size.y > 0 then self.size.y else 500
    -- -1..1 from the centre.
    local nx = (self.x / w) * 2 - 1
    local ny = (self.y / h) * 2 - 1

    -- Parallax: the card leans a little way toward the cursor.
    if self.cardX ~= nil then
        self.cardX.value = w / 2 + nx * 26
    end
    if self.cardY ~= nil then
        self.cardY.value = h / 2 + ny * 26
    end
    -- rotation is radians, not degrees.
    if self.cardRot ~= nil then
        self.cardRot.value = nx * 0.10
    end
    if self.dotX ~= nil then
        self.dotX.value = self.x
    end
    if self.dotY ~= nil then
        self.dotY.value = self.y
    end
    return true
end

return function(context: Context): Layout<Track>
    return {
        size = Vector.xy(0, 0),
        cardX = nil,
        cardY = nil,
        cardRot = nil,
        dotX = nil,
        dotY = nil,
        x = 250,
        y = 250,
        targetX = 250,
        targetY = 250,
        init = init,
        resize = resize,
        advance = advance,
        pointerMove = pointerMove,
    }
end
