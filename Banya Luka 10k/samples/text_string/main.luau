-- A paragraph threaded on a string. The runtime shapes and wraps the text;
-- the script then treats every glyph as a bead on one rope that snakes
-- through the lines so the last line reads left to right. The last few
-- letters hang free: drag one and the rope unlocks letter by letter behind
-- it, under Verlet integration with distance constraints, letter collision
-- and a bounce off the window. F toggles gravity, and turning it back on
-- unravels the whole paragraph. The AnimaScript twin in text_string_as is
-- the same rope, for `rive <dir> --bench=300`.

type Letter = {
    id: number,
    w: number,
    x: number,
    y: number,
    -- Where the layout put it and what a relayout moves it to.
    ox: number,
    oy: number,
    -- The previous position, for the Verlet step.
    px: number,
    py: number,
    reading: number,
    locked: boolean,
}

-- One glyph as the layout placed it, in reading order.
type Slot = {
    id: number,
    x: number,
    y: number,
    w: number,
}

type Rope = {
    font: Font?,
    letters: { Letter },
    rests: { number },
    outlines: { [number]: Path },
    baseline: number,
    locked: Path,
    lockedDirty: boolean,
    loose: Path,
    ink: Paint,
    looseInk: Paint,
    hint: Text?,
    hintShown: boolean,
    button: Path,
    buttonInk: Paint,
    buttonLabel: Text?,
    buttonHover: boolean,
    size: Vector,
    left: number,
    laidOutFor: number,
    gravityOn: boolean,
    unraveling: boolean,
    unravelIdx: number,
    dragIdx: number,
    dragOffset: Vector,
    accumulator: number,
    -- Grid broadphase for letter collision, rebuilt every step.
    heads: { number },
    next: { number },
    gridWidth: number,
    gridHeight: number,
}

local TEXT = 'Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, \u{201C}and what is the use of a book,\u{201D} thought Alice \u{201C}without pictures or conversations?\u{201D} So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her. There was nothing so very remarkable in that; nor did Alice think it so very much out of the way to hear the Rabbit say to itself, \u{201C}Oh dear! Oh dear! I shall be late!\u{201D}'

local FONT_SIZE = 20
local LINE_HEIGHT = 28
local CONTAINER = 600
local MARGIN = 20
local CONSTRAINT_DIST = 1.2
local UNLOCK_THRESHOLD = 1
local ITERATIONS = 12
local DAMPING = 0.97
local GRAVITY = 0.15
local RADIUS = 7
local BOUNCE = 0.4
local FREE_TAIL = 6
local FIXED_DT = 1 / 120
local MAX_STEPS = 4
local KEY_F = 70
local CELL = RADIUS * 2
local BUTTON_WIDTH = 84
local BUTTON_HEIGHT = 32
local BUTTON_INSET = 16

local function containerWidth(self: Rope): number
    return math.min(CONTAINER, self.size.x)
end

-- Shapes and wraps the paragraph for the current width. Returns every glyph
-- in reading order and the reading indices of each line.
local function layoutText(self: Rope): ({ Slot }, { { number } })
    local slots: { Slot } = {}
    local lines: { { number } } = {}
    local font = self.font
    if font == nil then
        return slots, lines
    end
    local text = Text.new()
    text:append(TEXT, { font = font, size = FONT_SIZE, lineHeight = LINE_HEIGHT })
    text.sizing = 'fixed'
    text.maxWidth = containerWidth(self) - MARGIN * 2
    text.maxHeight = 100000
    local offsetY = math.max(0, (self.size.y - text.lineCount * LINE_HEIGHT) * 0.3)
    for _, line in text:lines() do
        self.baseline = line.baseline - line.top
        local indices = {}
        for _, glyph in line do
            slots[#slots + 1] = { id = glyph.id, x = MARGIN + glyph.x, y = line.top + offsetY, w = glyph.advance }
            indices[#indices + 1] = #slots
            if self.outlines[glyph.id] == nil then
                self.outlines[glyph.id] = font:glyphPath(glyph.id)
            end
        end
        lines[#lines + 1] = indices
    end
    return slots, lines
end

local function buildRope(self: Rope)
    local slots, lines = layoutText(self)
    -- Snake through the lines so the last one reads left to right.
    local flip = (#lines - 1) % 2 == 1
    local order = {}
    for li, indices in lines do
        local reversed = if flip then (li - 1) % 2 == 0 else (li - 1) % 2 == 1
        if reversed then
            for k = #indices, 1, -1 do
                order[#order + 1] = indices[k]
            end
        else
            for _, r in indices do
                order[#order + 1] = r
            end
        end
    end
    self.letters = {}
    for _, r in order do
        local s = slots[r]
        self.letters[#self.letters + 1] = {
            id = s.id,
            w = s.w,
            x = s.x,
            y = s.y,
            ox = s.x,
            oy = s.y,
            px = s.x,
            py = s.y,
            reading = r,
            locked = true,
        }
    end
    local letters = self.letters
    local n = #letters
    self.rests = {}
    for i = 1, n - 1 do
        local a = letters[i]
        local b = letters[i + 1]
        local dx = (b.ox + b.w / 2) - (a.ox + a.w / 2)
        local dy = b.oy - a.oy
        self.rests[i] = math.sqrt(dx * dx + dy * dy) * CONSTRAINT_DIST
    end
    for i = n, math.max(1, n - FREE_TAIL + 1), -1 do
        letters[i].locked = false
    end
    self.next = table.create(n, 0)
    self.lockedDirty = true
end

-- A resize moves the locked letters to their new slots; the rope keeps its
-- rest lengths, so it never changes length.
local function relayout(self: Rope)
    local slots = layoutText(self)
    for _, l in self.letters do
        local s = slots[l.reading]
        if s ~= nil then
            l.ox = s.x
            l.oy = s.y
            if l.locked then
                l.x = s.x
                l.y = s.y
                l.px = s.x
                l.py = s.y
            end
        end
    end
    self.lockedDirty = true
end

local function startUnravel(self: Rope)
    self.unraveling = true
    self.hintShown = false
    local idx = #self.letters
    while idx >= 1 and not self.letters[idx].locked do
        idx -= 1
    end
    self.unravelIdx = idx
end

local function collide(self: Rope)
    local letters = self.letters
    local gw = self.gridWidth
    local gh = self.gridHeight
    local heads = self.heads
    local nxt = self.next
    local left = self.left
    for c = 1, gw * gh do
        heads[c] = 0
    end
    for i, l in letters do
        if not l.locked then
            local cx = math.clamp(math.floor((l.x + l.w / 2 + left) / CELL), 0, gw - 1)
            local cy = math.clamp(math.floor((l.y + LINE_HEIGHT / 2) / CELL), 0, gh - 1)
            local c = cy * gw + cx + 1
            nxt[i] = heads[c]
            heads[c] = i
        end
    end
    local minDist = RADIUS * 2
    local drag = self.dragIdx
    for i, a in letters do
        if not a.locked then
            local acx = a.x + a.w / 2
            local acy = a.y + LINE_HEIGHT / 2
            local cx = math.clamp(math.floor((acx + left) / CELL), 0, gw - 1)
            local cy = math.clamp(math.floor(acy / CELL), 0, gh - 1)
            for yy = math.max(cy - 1, 0), math.min(cy + 1, gh - 1) do
                for xx = math.max(cx - 1, 0), math.min(cx + 1, gw - 1) do
                    local j = heads[yy * gw + xx + 1]
                    while j ~= 0 do
                        -- Each pair once, and never the rope neighbour.
                        if j > i + 1 then
                            local b = letters[j]
                            local dx = (b.x + b.w / 2) - acx
                            local dy = (b.y + LINE_HEIGHT / 2) - acy
                            local dist = math.sqrt(dx * dx + dy * dy)
                            if dist == 0 then
                                dist = 0.001
                            end
                            if dist < minDist then
                                local overlap = (minDist - dist) / dist * 0.5
                                if i == drag then
                                    b.x += dx * overlap
                                    b.y += dy * overlap
                                elseif j == drag then
                                    a.x -= dx * overlap
                                    a.y -= dy * overlap
                                else
                                    a.x -= dx * overlap
                                    a.y -= dy * overlap
                                    b.x += dx * overlap
                                    b.y += dy * overlap
                                end
                            end
                        end
                        j = nxt[j]
                    end
                end
            end
        end
    end
end

local function simulate(self: Rope)
    local letters = self.letters
    local n = #letters
    if self.unraveling then
        if not self.gravityOn or self.unravelIdx < 1 then
            self.unraveling = false
        elseif letters[self.unravelIdx].locked then
            local l = letters[self.unravelIdx]
            l.locked = false
            l.px = l.x
            l.py = l.y - 0.5
            self.unravelIdx -= 1
            self.lockedDirty = true
        else
            self.unravelIdx -= 1
        end
    end
    -- A free letter pulled past its rest length unlocks the one before it.
    for i = n - 1, 1, -1 do
        local a = letters[i]
        local b = letters[i + 1]
        if a.locked and not b.locked then
            local dx = (b.x + b.w / 2) - (a.ox + a.w / 2)
            local dy = b.y - a.oy
            if math.sqrt(dx * dx + dy * dy) > self.rests[i] + UNLOCK_THRESHOLD then
                a.locked = false
                a.px = a.x
                a.py = a.y
                self.lockedDirty = true
                self.hintShown = false
            end
        end
    end
    local gravity = if self.gravityOn then GRAVITY else 0
    local drag = self.dragIdx
    for i, l in letters do
        if not l.locked and i ~= drag then
            local vx = (l.x - l.px) * DAMPING
            local vy = (l.y - l.py) * DAMPING
            l.px = l.x
            l.py = l.y
            l.x += vx
            l.y += vy + gravity
        end
    end
    for _ = 1, ITERATIONS do
        for i = 1, n - 1 do
            local a = letters[i]
            local b = letters[i + 1]
            if not (a.locked and b.locked) then
                local dx = (b.x + b.w / 2) - (a.x + a.w / 2)
                local dy = b.y - a.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist == 0 then
                    dist = 0.001
                end
                local diff = (dist - self.rests[i]) / dist
                local aFixed = a.locked or i == drag
                local bFixed = b.locked or i + 1 == drag
                if aFixed and not bFixed then
                    b.x -= dx * diff
                    b.y -= dy * diff
                elseif bFixed and not aFixed then
                    a.x += dx * diff
                    a.y += dy * diff
                elseif not aFixed then
                    a.x += dx * diff * 0.5
                    a.y += dy * diff * 0.5
                    b.x -= dx * diff * 0.5
                    b.y -= dy * diff * 0.5
                end
            end
        end
    end
    collide(self)
    local minX = -self.left
    local maxX = self.size.x - self.left
    local maxY = self.size.y
    for i, l in letters do
        if not l.locked and i ~= drag then
            if l.x < minX then
                l.x = minX
                l.px = l.x + (l.x - l.px) * BOUNCE
            end
            if l.x + l.w > maxX then
                l.x = maxX - l.w
                l.px = l.x + (l.x - l.px) * BOUNCE
            end
            if l.y < 0 then
                l.y = 0
                l.py = l.y + (l.y - l.py) * BOUNCE
            end
            if l.y + LINE_HEIGHT > maxY then
                l.y = maxY - LINE_HEIGHT
                l.py = l.y + (l.y - l.py) * BOUNCE
            end
        end
    end
end

-- Every letter back on its slot, locked, and the rope at rest.
local function reset(self: Rope)
    for _, l in self.letters do
        l.locked = true
        l.x = l.ox
        l.y = l.oy
        l.px = l.ox
        l.py = l.oy
    end
    local n = #self.letters
    for i = n, math.max(1, n - FREE_TAIL + 1), -1 do
        self.letters[i].locked = false
    end
    self.dragIdx = 0
    self.unraveling = false
    self.gravityOn = true
    self.hintShown = true
    self.accumulator = 0
    self.lockedDirty = true
end

local function buttonOrigin(self: Rope): Vector
    return Vector.xy(self.size.x - BUTTON_WIDTH - BUTTON_INSET, BUTTON_INSET)
end

local function overButton(self: Rope, p: Vector): boolean
    local o = buttonOrigin(self)
    return p.x >= o.x and p.x <= o.x + BUTTON_WIDTH and p.y >= o.y and p.y <= o.y + BUTTON_HEIGHT
end

local function place(self: Rope, path: Path, l: Letter)
    path:add(self.outlines[l.id], Mat2D.values(FONT_SIZE, 0, 0, FONT_SIZE, l.x, l.y + self.baseline))
end

function init(self: Rope, context: Context): boolean
    local font = context:font('Lora')
    if font == nil then
        print('font asset missing')
        return false
    end
    self.font = font
    local hint = Text.new()
    hint:append('drag the last letters, F toggles gravity', {
        font = font,
        size = 12,
        paint = Paint.with({ color = Color.rgba(150, 140, 130, 255) }),
    })
    self.hint = hint

    local r = BUTTON_HEIGHT / 2
    local k = 0.5522847498 * r
    local w = BUTTON_WIDTH
    self.button:moveTo(Vector.xy(r, 0))
    self.button:lineTo(Vector.xy(w - r, 0))
    self.button:cubicTo(Vector.xy(w - r + k, 0), Vector.xy(w, r - k), Vector.xy(w, r))
    self.button:cubicTo(Vector.xy(w, r + k), Vector.xy(w - r + k, r * 2), Vector.xy(w - r, r * 2))
    self.button:lineTo(Vector.xy(r, r * 2))
    self.button:cubicTo(Vector.xy(r - k, r * 2), Vector.xy(0, r + k), Vector.xy(0, r))
    self.button:cubicTo(Vector.xy(0, r - k), Vector.xy(r - k, 0), Vector.xy(r, 0))
    self.button:close()
    local label = Text.new()
    label:append('reset', {
        font = font,
        size = 14,
        paint = Paint.with({ color = Color.rgba(245, 240, 232, 255) }),
    })
    self.buttonLabel = label
    return true
end

function resize(self: Rope, size: Vector)
    self.size = size
end

function advance(self: Rope, seconds: number): boolean
    local key = self.size.x * 4096 + self.size.y
    if self.laidOutFor ~= key then
        self.left = (self.size.x - containerWidth(self)) / 2
        self.gridWidth = math.ceil(self.size.x / CELL) + 1
        self.gridHeight = math.ceil(self.size.y / CELL) + 1
        self.heads = table.create(self.gridWidth * self.gridHeight, 0)
        if #self.letters == 0 then
            buildRope(self)
        else
            relayout(self)
        end
        self.laidOutFor = key
    end
    self.accumulator += math.min(seconds, MAX_STEPS * FIXED_DT)
    while self.accumulator >= FIXED_DT do
        simulate(self)
        self.accumulator -= FIXED_DT
    end
    if self.lockedDirty then
        self.locked:reset()
        for _, l in self.letters do
            if l.locked then
                place(self, self.locked, l)
            end
        end
        self.lockedDirty = false
    end
    self.loose:reset()
    for _, l in self.letters do
        if not l.locked then
            place(self, self.loose, l)
        end
    end
    return true
end

function draw(self: Rope, renderer: Renderer)
    renderer:save()
    renderer:transform(Mat2D.withTranslation(self.left, 0))
    renderer:drawPath(self.locked, self.ink)
    renderer:drawPath(self.loose, self.looseInk)
    local hint = self.hint
    if hint and self.hintShown and #self.letters > 0 then
        local last = self.letters[#self.letters]
        renderer:save()
        renderer:transform(Mat2D.withTranslation(last.ox - 40, last.oy + LINE_HEIGHT + 4))
        hint:draw(renderer)
        renderer:restore()
    end
    renderer:restore()

    local origin = buttonOrigin(self)
    self.buttonInk.color = if self.buttonHover then Color.rgba(178, 76, 48, 255) else Color.rgba(74, 74, 74, 255)
    renderer:save()
    renderer:transform(Mat2D.withTranslation(origin))
    renderer:drawPath(self.button, self.buttonInk)
    local label = self.buttonLabel
    if label then
        local min, max = label:bounds()
        renderer:transform(Mat2D.withTranslation((BUTTON_WIDTH - (max.x - min.x)) / 2 - min.x, (BUTTON_HEIGHT - (max.y - min.y)) / 2 - min.y))
        label:draw(renderer)
    end
    renderer:restore()
end

function pointerDown(self: Rope, event: PointerEvent)
    if overButton(self, event.position) then
        reset(self)
        return
    end
    local p = event.position - Vector.xy(self.left, 0)
    for i = #self.letters, 1, -1 do
        local l = self.letters[i]
        if not l.locked and p.x >= l.x - 4 and p.x <= l.x + l.w + 4 and p.y >= l.y - 4 and p.y <= l.y + LINE_HEIGHT + 4 then
            self.dragIdx = i
            self.dragOffset = p - Vector.xy(l.x, l.y)
            return
        end
    end
end

function pointerMove(self: Rope, event: PointerEvent)
    self.buttonHover = overButton(self, event.position)
    if self.dragIdx == 0 then
        return
    end
    local p = event.position - Vector.xy(self.left, 0)
    local l = self.letters[self.dragIdx]
    l.x = p.x - self.dragOffset.x
    l.y = p.y - self.dragOffset.y
    l.px = l.x
    l.py = l.y
    l.locked = false
end

function pointerUp(self: Rope, event: PointerEvent)
    self.dragIdx = 0
end

function keyboardEvent(self: Rope, event: KeyboardEvent): boolean
    if event.phase ~= 'down' or event.key ~= KEY_F then
        return false
    end
    self.gravityOn = not self.gravityOn
    if self.gravityOn and not self.unraveling then
        startUnravel(self)
    end
    return true
end

return function(context: Context): Layout<Rope>
    return {
        font = nil,
        letters = {},
        rests = {},
        outlines = {},
        baseline = 0,
        locked = Path.new(),
        lockedDirty = true,
        loose = Path.new(),
        ink = Paint.with({ color = Color.rgba(74, 74, 74, 255) }),
        looseInk = Paint.with({ color = Color.rgba(178, 76, 48, 255) }),
        hint = nil,
        hintShown = true,
        button = Path.new(),
        buttonInk = Paint.new(),
        buttonLabel = nil,
        buttonHover = false,
        size = Vector.xy(900, 640),
        left = 0,
        laidOutFor = -1,
        gravityOn = true,
        unraveling = false,
        unravelIdx = 0,
        dragIdx = 0,
        dragOffset = Vector.xy(0, 0),
        accumulator = 0,
        heads = {},
        next = {},
        gridWidth = 1,
        gridHeight = 1,
        init = init,
        resize = resize,
        advance = advance,
        draw = draw,
        pointerDown = pointerDown,
        pointerMove = pointerMove,
        pointerUp = pointerUp,
        keyboardEvent = keyboardEvent,
    }
end
