-- Text rain under an artist's umbrella. Sixteen phrases are shaped once by
-- the runtime, then poured down the screen in tight monospace columns; the
-- characters the umbrella shelters are skipped. The umbrella is a Rive
-- artboard: its state machine opens and closes the canopy from the `open`
-- view model property, and the script reads the canopy's animated scale back
-- so the sheltered zone follows the artwork frame by frame. Move the pointer
-- to carry it, click to open or close it. The AnimaScript twin in
-- text_rain_as is the same scene for `rive <dir> --bench=300`.

-- A stretch of a column the canopy has eaten, in world y. It falls with the
-- letters around it; while the canopy is still cutting, its top is held at
-- the cut.
type Gap = {
    top: number,
    bottom: number,
}

type Column = {
    x: number,
    -- One glyph id per character of the repeated phrase, 0 for a space.
    glyphs: { number },
    y: number,
    speed: number,
    -- Which of the opacity paths this column draws into.
    bucket: number,
    gaps: { Gap },
}

type Splash = {
    x: number,
    y: number,
    vx: number,
    vy: number,
    life: number,
    size: number,
}

-- A character knocked out of its column by the umbrella, flying free.
type Loose = {
    id: number,
    x: number,
    y: number,
    vx: number,
    vy: number,
    angle: number,
    spin: number,
    life: number,
}

type Rain = {
    umbrella: Input<Artboard<Data.Umbrella>>,
    instance: Artboard<Data.Umbrella>?,
    canopy: NodeData?,
    handle: NodeData?,
    glyphSets: { { number } },
    outlines: { [number]: Path },
    advanceWidth: number,
    baseline: number,
    columns: { Column },
    rain: { Path },
    inks: { Paint },
    splashes: { Splash },
    splashInk: Paint,
    loose: { Loose },
    -- One path and paint per fade step, so a fading letter costs nothing
    -- beyond its outline.
    loosePaths: { Path },
    looseInks: { Paint },
    dot: Path,
    ground: Path,
    groundInk: Paint,
    label: Text?,
    size: Vector,
    builtFor: number,
    position: Vector,
    target: Vector,
    velocity: number,
    -- The umbrella as the columns last saw it, the start of this frame's
    -- motion.
    prevX: number,
    prevY: number,
    prevTilt: number,
    prevSpread: number,
    prevRise: number,
    open: boolean,
    pointerSeen: boolean,
    elapsed: number,
    seed: number,
}

local COL_SPACING = 11
local CHAR_HEIGHT = 12
local FONT_SIZE = 11
-- The open canopy in artboard units, matching the Umbrella artboard.
local CANOPY = 65
-- The underside band, stem and hook in the umbrella's own space, relative
-- to the carried point; they block rain as well.
local UNDERSIDE = 11.38
local STEM_HALF = 3.5
local STEM_TOP = -53
local STEM_BOTTOM = 80
local HOOK_LEFT = -24
local HOOK_TOP = 78
local HOOK_BOTTOM = 94
-- How far above and below the carried point a column is walked, in steps
-- of this many pixels, before the hit is bisected.
local REACH_ABOVE = -60
local REACH_BELOW = 100
local STRIDE = 2
-- Columns the umbrella may have touched replay its motion this frame in
-- this many sub steps, so a fast swipe cuts every row along its path.
local SUBSTEPS = 3
local MAX_GAPS = 6
-- How far the canopy may rise into a stream in one frame and still be
-- cutting the same gap; the rows it passed bounce off it.
local SWEEP = 40
local NONE = 0
local DOME = 1
local STEM = 2
local HOOK = 3
-- Where the carried point sits inside the Umbrella artboard.
local ORIGIN = Vector.xy(100, 60)
local BUCKETS = 5
local MAX_SPLASHES = 150
local MAX_LOOSE = 400
local FADE_STEPS = 6
local LOOSE_LIFE = 1.1
local GRAVITY = 520
local BOUNCE = 0.85
-- The fall speed a bounce reflects, fixed so the rain's own speed only
-- changes how often letters hit, not how far they fly.
local IMPACT = 125
-- Extra speed away from the surface, so a letter jumps clear like a drop.
local KICK = 80
-- The canopy's height above the carried point, for the surface normal.
local DOME_HEIGHT = 41
-- How far below the carried point a loose letter is kept out from under
-- the canopy.
local SHELTER_DEPTH = 140

local phrases = {
    'the rain drips on saw erent das',
    'in givialp retaw fo seldeen',
    'htrae ent noqu egnipm niar eht',
    'drust eni fo eno htuorht',
    'a senep nekorb eht fo eno',
    'semas yniar eht ni gruos',
    'transecri eni f ent',
    'givialp retaw fo seldeen',
    'niar ent draeh i senep nekorb',
    'eht ni gruos on saw erent das',
    'htrae ent noqu egnipm niar',
    'drust eni fo eno htuorht senep',
    'a semas yniar eht ni givialp',
    'retaw fo seldeen transecri',
    'niar eht drus on saw erent',
    'das gnimes yniar eht ni gruos',
}

-- A fixed sequence keeps every run, and the AnimaScript twin, on the same
-- field.
local function rand(self: Rain): number
    self.seed = (self.seed * 1664525 + 1013904223) % 4294967296
    return self.seed / 4294967296
end

function init(self: Rain, context: Context): boolean
    local font = context:font('JetBrainsMono')
    if font == nil then
        print('font asset missing')
        return false
    end
    self.baseline = -font.ascent * FONT_SIZE

    -- One line per phrase; a column is that line's glyphs repeated.
    local text = Text.new()
    text:append(table.concat(phrases, '\n'), { font = font, size = FONT_SIZE })
    text.wrap = 'noWrap'
    local source = table.concat(phrases, '\n')
    for i, line in text:lines() do
        local ids = {}
        for _, glyph in line do
            local id = glyph.id
            if string.byte(source, glyph.textIndex) == 32 then
                id = 0
            elseif self.outlines[id] == nil then
                self.outlines[id] = font:glyphPath(id)
                self.advanceWidth = glyph.advance
            end
            ids[#ids + 1] = id
        end
        self.glyphSets[i] = ids
    end

    for b = 1, BUCKETS do
        local opacity = 0.4 + 0.6 * (b - 0.5) / BUCKETS
        self.rain[b] = Path.new()
        self.inks[b] = Paint.with({ color = Color.rgba(74, 142, 212, math.floor(0.85 * opacity * 255)) })
    end
    for k = 1, FADE_STEPS do
        self.loosePaths[k] = Path.new()
        self.looseInks[k] = Paint.with({ color = Color.rgba(120, 178, 240, math.floor(0.9 * 255 * (k - 0.5) / FADE_STEPS)) })
    end

    local k = 0.5522847498
    self.dot:moveTo(Vector.xy(1, 0))
    self.dot:cubicTo(Vector.xy(1, k), Vector.xy(k, 1), Vector.xy(0, 1))
    self.dot:cubicTo(Vector.xy(-k, 1), Vector.xy(-1, k), Vector.xy(-1, 0))
    self.dot:cubicTo(Vector.xy(-1, -k), Vector.xy(-k, -1), Vector.xy(0, -1))
    self.dot:cubicTo(Vector.xy(k, -1), Vector.xy(1, -k), Vector.xy(1, 0))
    self.dot:close()

    local label = Text.new()
    label:append('move to carry the umbrella, click to open or close it', {
        font = font,
        size = 12,
        paint = Paint.with({ color = Color.rgba(120, 140, 170, 255) }),
    })
    self.label = label

    local instance = self.umbrella:instance()
    instance.data.open.value = self.open
    self.canopy = instance:node('Canopy')
    self.handle = instance:node('Rig')
    instance:advance(0)
    self.instance = instance
    return true
end

function resize(self: Rain, size: Vector)
    self.size = size
end

local function buildColumns(self: Rain)
    self.columns = {}
    local count = math.floor(self.size.x / COL_SPACING)
    local needed = math.ceil(2 * self.size.y / CHAR_HEIGHT) + 10
    for c = 1, count do
        local set = self.glyphSets[(c - 1) % #self.glyphSets + 1]
        local ids = {}
        while #ids < needed do
            for _, id in set do
                ids[#ids + 1] = id
            end
            ids[#ids + 1] = 0
        end
        self.columns[c] = {
            x = (c - 1) * COL_SPACING + COL_SPACING / 2,
            glyphs = ids,
            y = rand(self) * self.size.y,
            speed = 140 + 100 * rand(self),
            bucket = 1 + math.floor(rand(self) * BUCKETS),
            gaps = {},
        }
    end
    self.builtFor = self.size.x * 4096 + self.size.y
end

local function splash(self: Rain, x: number)
    if #self.splashes >= MAX_SPLASHES then
        return
    end
    local count = 2 + math.floor(2 * rand(self))
    for _ = 1, count do
        self.splashes[#self.splashes + 1] = {
            x = x + (rand(self) - 0.5) * 6,
            y = self.size.y - 4 - 4 * rand(self),
            vx = (rand(self) - 0.5) * 30,
            vy = -(20 + 40 * rand(self)),
            life = 1,
            size = 1 + 1.5 * rand(self),
        }
    end
end

-- The world space unit normal of the piece a point in the umbrella's space
-- is on, with the canopy at the given scale and the rig at the given tilt.
local function normalAt(kind: number, lx: number, ly: number, halfWidth: number, rise: number, cosT: number, sinT: number): (number, number)
    local nx, ny = 0, -1
    if kind == DOME and ly > 0 then
        -- Below the arch is the underside band; a letter in there leaves
        -- through the nearer rim, never down into the shelter.
        nx = if lx < 0 then -1 else 1
        ny = 0
    elseif kind == DOME then
        nx = lx / (halfWidth * halfWidth)
        ny = ly / (DOME_HEIGHT * rise * DOME_HEIGHT * rise)
        local len = math.sqrt(nx * nx + ny * ny)
        if len > 0 then
            nx /= len
            ny /= len
        else
            nx, ny = 0, -1
        end
    elseif kind == STEM then
        nx = if lx < 0 then -1 else 1
        ny = 0
    end
    return cosT * nx - sinT * ny, sinT * nx + cosT * ny
end

local function inGap(gaps: { Gap }, y: number): boolean
    for _, gap in gaps do
        if y >= gap.top and y < gap.bottom then
            return true
        end
    end
    return false
end

-- Records that the rows from top to bottom are gone, widening a gap they
-- touch or opening a new one, dropping the lowest gap when the list is full.
local function eat(gaps: { Gap }, top: number, bottom: number)
    for _, gap in gaps do
        if top <= gap.bottom + 0.5 and bottom >= gap.top - 0.5 then
            gap.top = math.min(gap.top, top)
            gap.bottom = math.max(gap.bottom, bottom)
            return
        end
    end
    if #gaps >= MAX_GAPS then
        local lowest = 1
        for k, gap in gaps do
            if gap.top > gaps[lowest].top then
                lowest = k
            end
        end
        gaps[lowest] = gaps[#gaps]
        gaps[#gaps] = nil
    end
    gaps[#gaps + 1] = { top = top, bottom = bottom }
end

-- A character falling at this speed meets the surface with unit normal
-- (nx, ny) and reflects off it, keeping its speed and jumping clear.
local function bounce(self: Rain, id: number, x: number, y: number, nx: number, ny: number, speed: number)
    if #self.loose >= MAX_LOOSE then
        return
    end
    local along = speed * ny
    local kick = KICK * (0.7 + 0.6 * rand(self))
    local vx = -2 * along * nx * BOUNCE + nx * kick + (rand(self) - 0.5) * 60
    self.loose[#self.loose + 1] = {
        id = id,
        x = x,
        y = y,
        vx = vx,
        vy = (speed - 2 * along * ny) * BOUNCE + ny * kick,
        angle = 0,
        -- Tumbles the way it flies.
        spin = (if vx < 0 then -1 else 1) * (3 + 7 * rand(self)),
        life = 1,
    }
end

-- The dome's top edge in the canopy's unscaled space, one entry per unit of
-- x across the canopy, sampled from the two arch curves the artwork draws.
local function buildProfile(): { number }
    local profile = table.create(CANOPY * 2 + 1, math.huge)
    local function arch(x0: number, y0: number, x1: number, y1: number, x2: number, y2: number, x3: number, y3: number)
        for i = 0, 260 do
            local t = i / 260
            local u = 1 - t
            local x = u * u * u * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3
            local y = u * u * u * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3
            local k = math.clamp(math.round(x), -CANOPY, CANOPY) + CANOPY + 1
            if y < profile[k] then
                profile[k] = y
            end
        end
    end
    arch(CANOPY, UNDERSIDE, CANOPY + 6.5, -27.3, 19.5, -48.75, 0, -39)
    arch(0, -39, -19.5, -48.75, -CANOPY - 6.5, -27.3, -CANOPY, UNDERSIDE)
    return profile
end

local domeProfile = buildProfile()

-- What the point (x, y) in the umbrella's space is inside of, with the
-- canopy at the given scale.
local function inside(x: number, y: number, spread: number, rise: number): number
    local xc = x / spread
    local yc = y / rise
    if xc >= -CANOPY and xc <= CANOPY and yc <= UNDERSIDE and yc >= domeProfile[math.round(xc) + CANOPY + 1] then
        return DOME
    end
    if x >= -STEM_HALF and x <= STEM_HALF and y >= STEM_TOP and y <= STEM_BOTTOM then
        return STEM
    end
    if x >= HOOK_LEFT and x <= 0 and y >= HOOK_TOP and y <= HOOK_BOTTOM then
        return HOOK
    end
    return NONE
end

-- Narrows a hit found between two steps of the walk to a quarter pixel.
local function refine(px: number, py: number, dx: number, dy: number, spread: number, rise: number, lo: number, hi: number, kind: number): number
    for _ = 1, 4 do
        local mid = (lo + hi) / 2
        local at = inside(px + mid * dx, py + mid * dy, spread, rise)
        if (kind == DOME and at == DOME) or (kind ~= DOME and at ~= NONE and at ~= DOME) then
            hi = mid
        else
            lo = mid
        end
    end
    return hi
end

-- Walks the line p + t*d down through the umbrella's space. Returns where
-- it enters and leaves the canopy, which shelters everything below, then
-- where it enters and leaves the stem or hook, which swallow the rows they
-- cover, any of them nil, then what the stick hit was. A tilt is just a
-- leaning line.
local function walk(px: number, py: number, dx: number, dy: number, spread: number, rise: number): (number?, number?, number?, number?, number)
    local canopyAt: number? = nil
    local canopyEnd: number? = nil
    local stickAt: number? = nil
    local stickEnd: number? = nil
    local stickKind = NONE
    local prev = REACH_ABOVE
    local t = REACH_ABOVE
    while t <= REACH_BELOW and (canopyEnd == nil or stickEnd == nil) do
        local kind = inside(px + t * dx, py + t * dy, spread, rise)
        if kind == DOME and canopyAt == nil then
            canopyAt = refine(px, py, dx, dy, spread, rise, prev, t, DOME)
        elseif kind ~= DOME and canopyAt ~= nil and canopyEnd == nil then
            canopyEnd = t
        end
        if kind ~= NONE and kind ~= DOME and stickAt == nil then
            stickAt = refine(px, py, dx, dy, spread, rise, prev, t, kind)
            stickKind = kind
        elseif (kind == NONE or kind == DOME) and stickAt ~= nil and stickEnd == nil then
            stickEnd = t
        end
        prev = t
        t += STRIDE
    end
    if canopyAt ~= nil and canopyEnd == nil then
        canopyEnd = REACH_BELOW
    end
    if stickAt ~= nil and stickEnd == nil then
        stickEnd = REACH_BELOW
    end
    return canopyAt, canopyEnd, stickAt, stickEnd, stickKind
end

function advance(self: Rain, seconds: number): boolean
    local dt = math.min(seconds, 0.05)
    self.elapsed += seconds
    if self.builtFor ~= self.size.x * 4096 + self.size.y then
        buildColumns(self)
    end

    -- The umbrella follows the pointer, or sways on its own until one arrives.
    if not self.pointerSeen then
        local t = self.elapsed * 0.3
        self.target = Vector.xy(
            self.size.x * (0.5 + 0.2 * math.sin(t)),
            self.size.y * (0.35 + 0.08 * math.sin(1.7 * t))
        )
    end
    local before = self.position
    self.position = before + (self.target - before) * math.min(1, dt * 3)
    local vx = (self.position.x - before.x) / math.max(dt, 0.001)
    self.velocity += (vx - self.velocity) * math.min(1, dt * 6)
    local handle = self.handle
    if handle then
        handle.rotation = math.clamp(self.velocity * 0.0008, -0.3, 0.3)
    end
    local instance = self.instance
    if instance then
        instance:advance(dt)
    end

    -- The shelter is whatever the artwork says it is right now: a column
    -- stops at the first thing it hits, dome, stem or hook, and stays dry
    -- all the way down. The umbrella moved from where the columns last saw
    -- it to here; the columns it may have touched replay that motion in sub
    -- steps, each against the umbrella interpolated to that moment.
    local canopy = self.canopy
    local spread = if canopy then canopy.scaleX else 1
    local rise = if canopy then canopy.scaleY else 1
    local tilt = if handle then handle.rotation else 0
    local endX = self.position.x
    local endY = self.position.y
    local reach = CANOPY + REACH_BELOW
    -- Rows the umbrella slides into are shoved the way it is moving.
    local plowSign = if self.velocity < 0 then -1 else 1

    for _, path in self.rain do
        path:reset()
    end
    local h = self.size.y
    local half = self.advanceWidth / 2
    local splashLine = h - CHAR_HEIGHT * 2
    for _, column in self.columns do
        local step = column.speed * dt
        local block = CHAR_HEIGHT * #column.glyphs
        local gaps = column.gaps
        local near = math.abs(column.x - endX) < reach or math.abs(column.x - self.prevX) < reach
        local subs = if near then SUBSTEPS else 1
        local sub = step / subs
        for k = 1, subs do
            column.y += sub
            if column.y >= block then
                column.y -= block
            end
            -- The gaps fall with the stream.
            local g = 1
            while g <= #gaps do
                local gap = gaps[g]
                gap.top += sub
                gap.bottom += sub
                if gap.top >= h or gap.bottom <= gap.top then
                    gaps[g] = gaps[#gaps]
                    gaps[#gaps] = nil
                else
                    g += 1
                end
            end
            if near then
                local f = k / subs
                local ux = self.prevX + (endX - self.prevX) * f
                local uy = self.prevY + (endY - self.prevY) * f
                local t = self.prevTilt + (tilt - self.prevTilt) * f
                local sp = self.prevSpread + (spread - self.prevSpread) * f
                local ri = self.prevRise + (rise - self.prevRise) * f
                local cosT = math.cos(t)
                local sinT = math.sin(t)
                local halfWidth = CANOPY * sp
                local plowNx = plowSign * cosT
                local plowNy = plowSign * sinT
                local off = column.x - ux
                local stop = h + CHAR_HEIGHT
                local canopyBottom = h + CHAR_HEIGHT
                local stick = h + CHAR_HEIGHT
                local stickBottom = h + CHAR_HEIGHT
                local canopyNx, canopyNy = 0, -1
                local stickNx, stickNy = 0, -1
                if math.abs(off) < reach then
                    local px = cosT * off
                    local py = -sinT * off
                    local canopyAt, canopyEnd, stickAt, stickEnd, stickKind = walk(px, py, sinT, cosT, sp, ri)
                    if canopyAt ~= nil and canopyEnd ~= nil then
                        stop = uy + canopyAt
                        canopyBottom = uy + canopyEnd
                        canopyNx, canopyNy = normalAt(DOME, px + canopyAt * sinT, py + canopyAt * cosT, halfWidth, ri, cosT, sinT)
                    end
                    -- The stick only counts when the column reaches it before
                    -- the canopy catches the row.
                    if stickAt ~= nil and stickEnd ~= nil and uy + stickAt < stop then
                        stick = uy + stickAt
                        stickBottom = uy + stickEnd
                        stickNx, stickNy = normalAt(stickKind, px + stickAt * sinT, py + stickAt * cosT, halfWidth, ri, cosT, sinT)
                    end
                end
                -- The gap the canopy is cutting keeps its top at the cut, even
                -- when the canopy rose a few rows into the stream, and covers
                -- the canopy body, so rows the umbrella slid into are plowed.
                local sweptTo = stop
                local plowFrom = canopyBottom
                local plowTo = canopyBottom
                if stop < h then
                    local cut: Gap? = nil
                    for _, gap in gaps do
                        if gap.bottom >= stop and (cut == nil or gap.top < cut.top) then
                            cut = gap
                        end
                    end
                    if cut ~= nil and cut.top <= stop + SWEEP then
                        if cut.top > stop then
                            sweptTo = cut.top
                        end
                        cut.top = stop
                        if cut.bottom < canopyBottom then
                            plowFrom = cut.bottom
                            cut.bottom = canopyBottom
                        end
                    else
                        plowFrom = stop + sub
                        eat(gaps, stop, canopyBottom)
                    end
                end
                local x = column.x - half
                for i, id in column.glyphs do
                    if id ~= 0 then
                        local y = (i - 1) * CHAR_HEIGHT + column.y
                        if y >= block then
                            y -= block
                        end
                        if y >= -CHAR_HEIGHT and y <= h then
                            if y >= stick and y < stickBottom then
                                -- A row on the stem or hook bounces off it, at
                                -- the entry when it fell in, sideways when the
                                -- stick slid into it.
                                if not inGap(gaps, y) then
                                    if y - sub < stick then
                                        bounce(self, id, x, stick - CHAR_HEIGHT, stickNx, stickNy, IMPACT)
                                    else
                                        bounce(self, id, x, y, plowNx, plowNy, IMPACT)
                                    end
                                    eat(gaps, y, y + CHAR_HEIGHT)
                                end
                            elseif y >= stop and (y - sub < stop or y < sweptTo) then
                                bounce(self, id, x, stop - CHAR_HEIGHT, canopyNx, canopyNy, IMPACT)
                            elseif y >= plowFrom and y < plowTo then
                                bounce(self, id, x, y, plowNx, plowNy, IMPACT)
                            end
                        end
                    end
                end
            end
        end
        local path = self.rain[column.bucket]
        local x = column.x - half
        for i, id in column.glyphs do
            if id ~= 0 then
                local y = (i - 1) * CHAR_HEIGHT + column.y
                if y >= block then
                    y -= block
                end
                if y >= -CHAR_HEIGHT and y <= h and not inGap(gaps, y) then
                    if y > splashLine and rand(self) < 0.02 then
                        splash(self, column.x)
                    end
                    path:add(self.outlines[id], Mat2D.values(FONT_SIZE, 0, 0, FONT_SIZE, x, y + self.baseline))
                end
            end
        end
    end
    self.prevX = endX
    self.prevY = endY
    self.prevTilt = tilt
    self.prevSpread = spread
    self.prevRise = rise

    for _, path in self.loosePaths do
        path:reset()
    end
    local ux = endX
    local uy = endY
    local cosT = math.cos(tilt)
    local sinT = math.sin(tilt)
    local halfWidth = CANOPY * spread
    local loose = self.loose
    local n = 1
    while n <= #loose do
        local l = loose[n]
        l.x += l.vx * dt
        l.y += l.vy * dt
        l.vy += GRAVITY * dt
        l.angle += l.spin * dt
        l.life -= dt / LOOSE_LIFE
        -- A letter inside the umbrella, plowed out of a column or landing
        -- back on it, bounces again and is walked out until it is clear.
        for _ = 1, 24 do
            local dx = l.x + half - ux
            local dy = l.y + CHAR_HEIGHT / 2 - uy
            local lx = cosT * dx + sinT * dy
            local ly = cosT * dy - sinT * dx
            local kind = inside(lx, ly, spread, rise)
            -- The shelter under the canopy stays dry too: a letter drifting
            -- in there is walked out through the nearer rim.
            if kind == NONE and ly > 0 and ly < SHELTER_DEPTH and lx > -halfWidth and lx < halfWidth then
                kind = DOME
            end
            if kind == NONE then
                break
            end
            local nx, ny = normalAt(kind, lx, ly, halfWidth, rise, cosT, sinT)
            local into = l.vx * nx + l.vy * ny
            if into < 0 then
                l.vx = (l.vx - 2 * into * nx) * 0.7
                l.vy = (l.vy - 2 * into * ny) * 0.7
            end
            l.x += nx * 4
            l.y += ny * 4
        end
        if l.life <= 0 or l.y > h then
            loose[n] = loose[#loose]
            loose[#loose] = nil
        else
            local k = math.min(FADE_STEPS, math.floor(l.life * FADE_STEPS) + 1)
            -- The glyph placed as in its column, then turned about its centre.
            local c = math.cos(l.angle)
            local sn = math.sin(l.angle)
            local ox = -half
            local oy = self.baseline - CHAR_HEIGHT / 2
            self.loosePaths[k]:add(self.outlines[l.id], Mat2D.values(
                FONT_SIZE * c,
                FONT_SIZE * sn,
                -FONT_SIZE * sn,
                FONT_SIZE * c,
                l.x + half + c * ox - sn * oy,
                l.y + CHAR_HEIGHT / 2 + sn * ox + c * oy
            ))
            n += 1
        end
    end

    local splashes = self.splashes
    local i = 1
    while i <= #splashes do
        local s = splashes[i]
        s.x += s.vx * dt
        s.y += s.vy * dt
        s.vy += 120 * dt
        s.life -= 2.5 * dt
        if s.life <= 0 then
            splashes[i] = splashes[#splashes]
            splashes[#splashes] = nil
        else
            i += 1
        end
    end

    self.ground:reset()
    local w = self.size.x
    for gx = 0, w, 2 do
        local point = Vector.xy(gx, h - 8 + 3 * math.sin(0.05 * gx + 2 * self.elapsed))
        if gx == 0 then
            self.ground:moveTo(point)
        else
            self.ground:lineTo(point)
        end
    end
    return true
end

function draw(self: Rain, renderer: Renderer)
    for b, path in self.rain do
        renderer:drawPath(path, self.inks[b])
    end
    renderer:drawPath(self.ground, self.groundInk)
    local instance = self.instance
    if instance then
        renderer:save()
        renderer:transform(Mat2D.withTranslation(self.position - ORIGIN))
        instance:draw(renderer)
        renderer:restore()
    end
    for k, path in self.loosePaths do
        renderer:drawPath(path, self.looseInks[k])
    end
    for _, s in self.splashes do
        self.splashInk.color = Color.rgba(74, 142, 212, math.floor(0.7 * s.life * 255))
        renderer:save()
        renderer:transform(Mat2D.values(s.size, 0, 0, s.size, s.x, s.y))
        renderer:drawPath(self.dot, self.splashInk)
        renderer:restore()
    end
    local label = self.label
    if label then
        renderer:save()
        renderer:transform(Mat2D.withTranslation(16, self.size.y - 34))
        label:draw(renderer)
        renderer:restore()
    end
end

function pointerMove(self: Rain, event: PointerEvent)
    self.pointerSeen = true
    self.target = event.position
end

function pointerExit(self: Rain, event: PointerEvent)
    self.pointerSeen = false
end

function pointerDown(self: Rain, event: PointerEvent)
    self.open = not self.open
    local instance = self.instance
    if instance then
        instance.data.open.value = self.open
    end
end

return function(context: Context): Layout<Rain>
    return {
        umbrella = late(),
        instance = nil,
        canopy = nil,
        handle = nil,
        glyphSets = {},
        outlines = {},
        advanceWidth = 0,
        baseline = 0,
        columns = {},
        rain = {},
        inks = {},
        splashes = {},
        splashInk = Paint.new(),
        loose = {},
        loosePaths = {},
        looseInks = {},
        dot = Path.new(),
        ground = Path.new(),
        groundInk = Paint.with({ style = 'stroke', thickness = 1.5, color = Color.rgba(26, 58, 92, 102) }),
        label = nil,
        size = Vector.xy(1000, 700),
        builtFor = -1,
        position = Vector.xy(600, 245),
        target = Vector.xy(600, 245),
        velocity = 0,
        prevX = 600,
        prevY = 245,
        prevTilt = 0,
        prevSpread = 1,
        prevRise = 1,
        open = true,
        pointerSeen = false,
        elapsed = 0,
        seed = 12345,
        init = init,
        resize = resize,
        advance = advance,
        draw = draw,
        pointerMove = pointerMove,
        pointerExit = pointerExit,
        pointerDown = pointerDown,
    }
end
