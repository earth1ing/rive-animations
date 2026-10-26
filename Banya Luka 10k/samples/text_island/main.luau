-- A large multi column blob poured around a circle that follows the pointer.
-- The runtime shapes the whole blob once; the script reads the shaped words
-- back and is its own line breaker, so every line gets the segments the
-- circle leaves free. Left to right text only: words are walked in reading
-- order. The AnimaScript twin in text_island_as does the same for a speed
-- comparison with `rive <dir> --bench=300`.
type Word = {
    -- Glyph outlines at the word's origin with the baseline at y 0; a negative
    -- width marks a paragraph break.
    path: Path,
    width: number,
}

type Island = {
    words: { Word },
    spaceWidth: number,
    lineHeight: number,
    ascent: number,
    descent: number,
    columns: { Path },
    circle: Vector,
    target: Vector,
    laidOut: Vector,
    ink: Paint,
    ring: Paint,
    ringPath: Path,
    size: Vector,
    elapsed: number,
    -- Until the pointer arrives the circle drifts on its own, so a headless
    -- bench relayouts every frame the way a moving pointer would.
    pointerSeen: boolean,
}

local RADIUS = 90
local MARGIN = 16
local COLUMNS = 3
local EDGE = 40
local GUTTER = 28

local sentences = {
    'Text in Rive is shaped by the runtime, so a script never has to know how a font joins its letters.',
    'The words below were laid out once, then poured into columns by this script.',
    'Move the pointer and the circle pushes the words aside, line by line.',
    'Every line asks the circle which spans it leaves free and fills them in reading order.',
    'A paragraph break ends the line early and leaves a little extra room.',
    'The glyph outlines are cached per word, so a relayout only moves paths around.',
    'Three columns of text, one circle, and a script that acts as the line breaker.',
    'Nothing here is drawn by a text component; the renderer only ever sees paths.',
}

local function blob(): string
    local parts = {}
    for paragraph = 1, 9 do
        local words = {}
        for i = 1, 9 do
            words[#words + 1] = sentences[(paragraph + i) % #sentences + 1]
        end
        parts[#parts + 1] = table.concat(words, ' ')
    end
    return table.concat(parts, '\n')
end

local source = blob()

function init(self: Island, context: Context): boolean
    local font = context:font('Inter')
    if font == nil then
        print('font asset missing')
        return false
    end
    local size = 14
    local text = Text.new()
    text:append(source, { font = font, size = size })
    text.wrap = 'noWrap'
    self.lineHeight = font:lineHeight(size) * 1.3
    self.ascent = font.ascent * size
    self.descent = font.descent * size

    local glyphPaths: { [number]: Path } = {}
    for _, line in text:lines() do
        local word: Word? = nil
        local startX = 0
        local lastEnd = 0
        for _, glyph in line do
            if string.byte(source, glyph.textIndex) == 32 then
                if self.spaceWidth == 0 then
                    self.spaceWidth = glyph.advance
                end
                if word ~= nil then
                    word.width = lastEnd - startX
                    self.words[#self.words + 1] = word
                    word = nil
                end
            else
                local current: Word
                if word == nil then
                    current = { path = Path.new(), width = 0 }
                    word = current
                    startX = glyph.x
                else
                    current = word
                end
                local outline = glyphPaths[glyph.id]
                if outline == nil then
                    outline = glyph.font:glyphPath(glyph.id)
                    glyphPaths[glyph.id] = outline
                end
                current.path:add(outline, Mat2D.withTranslation(-startX, -line.baseline) * glyph.transform)
                lastEnd = glyph.x + glyph.advance
            end
        end
        if word ~= nil then
            word.width = lastEnd - startX
            self.words[#self.words + 1] = word
        end
        self.words[#self.words + 1] = { path = Path.new(), width = -1 }
    end
    for c = 1, COLUMNS do
        self.columns[c] = Path.new()
    end

    local k = 0.5522847498 * RADIUS
    self.ringPath:moveTo(Vector.xy(RADIUS, 0))
    self.ringPath:cubicTo(Vector.xy(RADIUS, k), Vector.xy(k, RADIUS), Vector.xy(0, RADIUS))
    self.ringPath:cubicTo(Vector.xy(-k, RADIUS), Vector.xy(-RADIUS, k), Vector.xy(-RADIUS, 0))
    self.ringPath:cubicTo(Vector.xy(-RADIUS, -k), Vector.xy(-k, -RADIUS), Vector.xy(0, -RADIUS))
    self.ringPath:cubicTo(Vector.xy(k, -RADIUS), Vector.xy(RADIUS, -k), Vector.xy(RADIUS, 0))
    self.ringPath:close()
    return true
end

function resize(self: Island, size: Vector)
    self.size = size
    self.laidOut = Vector.xy(-1, -1)
end

-- The free spans of a line whose baseline sits at y, as start and end pairs.
local function segments(self: Island, y: number, left: number, right: number): { number }
    local top = y + self.ascent
    local bottom = y + self.descent
    local cy = self.circle.y
    local dy = if cy < top then top - cy elseif cy > bottom then cy - bottom else 0
    local r = RADIUS + MARGIN
    if dy >= r then
        return { left, right }
    end
    local w = math.sqrt(r * r - dy * dy)
    local a = self.circle.x - w
    local b = self.circle.x + w
    if b <= left or a >= right then
        return { left, right }
    end
    local out = {}
    if a - left > 30 then
        out[#out + 1] = left
        out[#out + 1] = a
    end
    if right - b > 30 then
        out[#out + 1] = b
        out[#out + 1] = right
    end
    return out
end

local function layout(self: Island)
    local colWidth = (self.size.x - EDGE * 2 - GUTTER * (COLUMNS - 1)) / COLUMNS
    local bottom = self.size.y - EDGE
    local wordIndex = 1
    for c = 1, COLUMNS do
        local column = self.columns[c]
        column:reset()
        local left = EDGE + (c - 1) * (colWidth + GUTTER)
        local right = left + colWidth
        local y = EDGE - self.ascent
        while y + self.descent <= bottom and wordIndex <= #self.words do
            local segs = segments(self, y, left, right)
            local s = 1
            while s < #segs and wordIndex <= #self.words do
                local x = segs[s]
                local segEnd = segs[s + 1]
                while wordIndex <= #self.words do
                    local word = self.words[wordIndex]
                    if word.width < 0 then
                        -- A paragraph ends the line and opens a small gap.
                        wordIndex += 1
                        s = #segs
                        y += self.lineHeight * 0.5
                        break
                    end
                    local fits = x + word.width <= segEnd
                    -- A word wider than a whole line still has to land somewhere.
                    if not fits and not (x == segs[s] and segEnd - x >= colWidth - 1) then
                        break
                    end
                    column:add(word.path, Mat2D.withTranslation(x, y))
                    x += word.width + self.spaceWidth
                    wordIndex += 1
                end
                s += 2
            end
            y += self.lineHeight
        end
    end
    self.laidOut = self.circle
end

function advance(self: Island, seconds: number): boolean
    self.elapsed += seconds
    if not self.pointerSeen then
        local t = self.elapsed * 0.7
        self.target = Vector.xy(self.size.x * (0.5 + 0.3 * math.cos(t)), self.size.y * (0.5 + 0.3 * math.sin(t * 1.3)))
    end
    local ease = math.min(1, seconds * 10)
    self.circle = self.circle + (self.target - self.circle) * ease
    local moved = self.circle - self.laidOut
    if math.abs(moved.x) + math.abs(moved.y) > 0.2 then
        layout(self)
    end
    return true
end

function draw(self: Island, renderer: Renderer)
    for _, column in self.columns do
        renderer:drawPath(column, self.ink)
    end
    renderer:save()
    renderer:transform(Mat2D.withTranslation(self.circle))
    renderer:drawPath(self.ringPath, self.ring)
    renderer:restore()
end

function pointerMove(self: Island, event: PointerEvent)
    self.pointerSeen = true
    self.target = event.position
end

return function(context: Context): Layout<Island>
    return {
        words = {},
        spaceWidth = 0,
        lineHeight = 0,
        ascent = 0,
        descent = 0,
        columns = {},
        circle = Vector.xy(500, 350),
        target = Vector.xy(500, 350),
        laidOut = Vector.xy(-1, -1),
        ink = Paint.with({ color = Color.rgb(225, 225, 225) }),
        ring = Paint.with({ style = 'stroke', thickness = 2, color = Color.rgb(255, 150, 60) }),
        ringPath = Path.new(),
        size = Vector.xy(1000, 700),
        elapsed = 0,
        pointerSeen = false,
        init = init,
        resize = resize,
        advance = advance,
        draw = draw,
        pointerMove = pointerMove,
    }
end
