-- Input demo for the rive viewer.
--   keyboardEvent: keys 1/2/3 switch the palette, backspace clears typed text.
--   textEvent:     printable characters append to a buffer, drawn as squares.
-- Everything is also printed so it can be confirmed in the log.
-- Script-only, so FocusData is injected; an RML scene must add <FocusData/>.

type InputDemo = {
    bar: Paint,
    square: Paint,
    marker: Paint,
    path: Path,
    size: Vector,
    typed: string,
    palette: number,
    stick: Vector,
}

local palettes = {
    Color.rgb(255, 100, 50),
    Color.rgb(80, 200, 120),
    Color.rgb(90, 150, 255),
}

function init(self: InputDemo, context: Context): boolean
    print("input demo ready - press 1/2/3, type text, backspace clears")
    return true
end

function resize(self: InputDemo, size: Vector)
    self.size = size
end

function keyboardEvent(self: InputDemo, event: KeyboardEvent): boolean
    if event.phase == "up" then
        return false
    end
    print(`key {event.key} phase {event.phase}`)
    if event.key == 49 then
        self.palette = 1
    elseif event.key == 50 then
        self.palette = 2
    elseif event.key == 51 then
        self.palette = 3
    elseif event.key == 259 then -- backspace
        self.typed = string.sub(self.typed, 1, -2)
    end
    return true
end

function textEvent(self: InputDemo, event: TextInput): boolean
    self.typed ..= event.text
    print(`text "{event.text}" buffer "{self.typed}"`)
    return true
end

function gamepadConnected(self: InputDemo, event: GamepadConnected)
    print(`gamepad {event.deviceId} connected`)
end

function gamepadDisconnected(self: InputDemo, event: GamepadDisconnected)
    print(`gamepad {event.deviceId} disconnected`)
    self.stick = Vector.xy(0, 0)
end

function gamepadEvent(self: InputDemo, event: GamepadEvent)
    -- Drive the marker with the left stick and switch palette on face buttons.
    self.stick = event.leftStick
    if event.south then
        self.palette = 1
    elseif event.east then
        self.palette = 2
    elseif event.west then
        self.palette = 3
    end
    if event.changeKind == "button" then
        print(`gamepad button {event.changeIndex} = {event.changeValue}`)
    end
end

function draw(self: InputDemo, renderer: Renderer)
    local w = self.size.x
    self.bar.color = palettes[self.palette]
    -- Palette bar across the top.
    self.path:reset()
    self.path:moveTo(Vector.xy(0, 0))
    self.path:lineTo(Vector.xy(w, 0))
    self.path:lineTo(Vector.xy(w, 40))
    self.path:lineTo(Vector.xy(0, 40))
    self.path:close()
    renderer:drawPath(self.path, self.bar)

    -- One square per typed character, wrapping into rows.
    local count = #self.typed
    local sizePx = 24
    local gap = 8
    local perRow = math.max(1, math.floor((w - gap) / (sizePx + gap)))
    for i = 1, count do
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        local x = gap + col * (sizePx + gap)
        local y = 70 + row * (sizePx + gap)
        self.path:reset()
        self.path:moveTo(Vector.xy(x, y))
        self.path:lineTo(Vector.xy(x + sizePx, y))
        self.path:lineTo(Vector.xy(x + sizePx, y + sizePx))
        self.path:lineTo(Vector.xy(x, y + sizePx))
        self.path:close()
        renderer:drawPath(self.path, self.square)
    end

    -- Left stick moves a marker around the screen center.
    local h = self.size.y
    local mx = w / 2 + self.stick.x * w * 0.4
    local my = h / 2 + self.stick.y * h * 0.4
    local mr = 18
    self.path:reset()
    self.path:moveTo(Vector.xy(mx - mr, my - mr))
    self.path:lineTo(Vector.xy(mx + mr, my - mr))
    self.path:lineTo(Vector.xy(mx + mr, my + mr))
    self.path:lineTo(Vector.xy(mx - mr, my + mr))
    self.path:close()
    renderer:drawPath(self.path, self.marker)
end

return function(context: Context): Layout<InputDemo>
    return {
        bar = Paint.with({ color = palettes[1] }),
        square = Paint.with({ color = Color.rgb(230, 230, 230) }),
        marker = Paint.with({ color = Color.rgb(255, 220, 90) }),
        path = Path.new(),
        size = Vector.xy(0, 0),
        typed = "",
        palette = 1,
        stick = Vector.xy(0, 0),
        init = init,
        resize = resize,
        keyboardEvent = keyboardEvent,
        textEvent = textEvent,
        gamepadConnected = gamepadConnected,
        gamepadDisconnected = gamepadDisconnected,
        gamepadEvent = gamepadEvent,
        draw = draw,
    }
end
