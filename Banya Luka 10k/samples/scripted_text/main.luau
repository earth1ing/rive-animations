-- Fonts and shaped text from a script: a wrapped bilingual paragraph drawn in
-- one call, the same paragraph drawn glyph by glyph with a wave, and a caret
-- that walks the text with its selection. The runtime shapes and orders the
-- glyphs, so the Arabic reads right to left without the script knowing.
type Demo = {
    text: Text?,
    ink: Paint,
    accent: Paint,
    frame: Paint,
    caretPaint: Paint,
    selection: Paint,
    size: Vector,
    elapsed: number,
}

local message = 'Rive shapes text for scripts: مرحبا بالعالم, hello world, and back again.'

function init(self: Demo, context: Context): boolean
    local font = context:font('IBMPlexSansArabic-Regular')
    if font == nil then
        print('font asset missing')
        return false
    end
    local text = Text.new()
    text:append(message, { font = font, size = 30, paint = self.ink })
    text.sizing = 'autoHeight'
    text.maxWidth = 520
    text.align = 'start'
    text.paragraphSpacing = 8
    self.text = text
    return true
end

function resize(self: Demo, size: Vector)
    self.size = size
end

function advance(self: Demo, seconds: number): boolean
    self.elapsed += seconds
    return true
end

local function rect(path: Path, min: Vector, max: Vector)
    path:moveTo(min)
    path:lineTo(Vector.xy(max.x, min.y))
    path:lineTo(max)
    path:lineTo(Vector.xy(min.x, max.y))
    path:close()
end

function draw(self: Demo, renderer: Renderer)
    local text = self.text
    if text == nil then
        return
    end
    local left = (self.size.x - text.maxWidth) / 2
    renderer:save()
    renderer:transform(Mat2D.withTranslation(left, 60))

    -- The whole paragraph, wrapped and aligned by the runtime.
    text:draw(renderer)
    local min, max = text:bounds()
    local box = Path.new()
    rect(box, min, max)
    renderer:drawPath(box, self.frame)

    -- A caret sweeping through the codepoints, its selection behind it.
    local index = 1 + math.floor(self.elapsed * 6) % text.length
    for _, r in text:selectionRects(math.max(1, index - 6), index) do
        local span = Path.new()
        rect(span, r.min, r.max)
        renderer:drawPath(span, self.selection)
    end
    local x, top, bottom = text:caret(index)
    if x ~= nil then
        local caret = Path.new()
        caret:moveTo(Vector.xy(x, top))
        caret:lineTo(Vector.xy(x, bottom))
        renderer:drawPath(caret, self.caretPaint)
    end

    -- The same layout, glyph by glyph: each glyph is placed by the runtime in
    -- visual order, the script only adds motion and a color per direction.
    renderer:transform(Mat2D.withTranslation(0, max.y + 60))
    for _, line in text:lines() do
        for _, glyph in line do
            local lift = math.sin(self.elapsed * 3 + glyph.x * 0.02) * 6
            renderer:save()
            renderer:transform(Mat2D.withTranslation(0, lift) * glyph.transform)
            renderer:drawPath(
                glyph.font:glyphPath(glyph.id),
                if glyph.direction == 'rtl' then self.accent else self.ink
            )
            renderer:restore()
        end
    end
    renderer:restore()
end

return function(context: Context): Layout<Demo>
    return {
        text = nil,
        ink = Paint.with({ color = Color.rgb(235, 235, 235) }),
        accent = Paint.with({ color = Color.rgb(255, 150, 60) }),
        frame = Paint.with({ style = 'stroke', thickness = 1, color = Color.rgb(90, 90, 90) }),
        caretPaint = Paint.with({ style = 'stroke', thickness = 2, color = Color.rgb(80, 200, 255) }),
        selection = Paint.with({ color = Color.rgba(80, 200, 255, 70) }),
        size = Vector.xy(800, 600),
        elapsed = 0,
        init = init,
        resize = resize,
        advance = advance,
        draw = draw,
    }
end
