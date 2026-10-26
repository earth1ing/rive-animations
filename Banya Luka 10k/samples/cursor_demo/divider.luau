-- A sidebar with a draggable divider. The script owns the interaction and
-- says what cursor it wants by writing a name into the view model's `cursor`
-- string; rive.yaml's `cursor.property` tells the host to show it.
--
-- The button beside it never touches this script: two state machine
-- listeners (enter/exit) write "pointer" and "arrow" into the same property.
-- Both write only on a change of intent, never every frame, so neither
-- overwrites the other.

local kGrip = 8 -- half width of the divider's hit region, in pixels

type Divider = {
    size: Vector,
    cursor: Property<string>?,
    dividerX: Property<number>?,
    over: boolean,
    dragging: boolean,
    sidebarPaint: Paint,
    dividerPaint: Paint,
    path: Path,
}

local function dividerAt(self: Divider): number
    if self.dividerX ~= nil then
        return self.dividerX.value
    end
    return 260
end

local function overDivider(self: Divider, x: number): boolean
    return math.abs(x - dividerAt(self)) <= kGrip
end

local function want(self: Divider, name: string)
    if self.cursor ~= nil and self.cursor.value ~= name then
        self.cursor.value = name
    end
end

function init(self: Divider, context: Context): boolean
    -- init runs twice and the view model is absent the first time.
    local vm = context:viewModel()
    if vm == nil then
        return true
    end
    self.cursor = vm:getString('cursor')
    self.dividerX = vm:getNumber('dividerX')
    return true
end

function resize(self: Divider, size: Vector)
    self.size = size
end

function pointerMove(self: Divider, event: PointerEvent)
    if self.dragging then
        -- Held: the cursor stays a resize cursor wherever the pointer goes.
        local width = if self.size.x > 0 then self.size.x else 640
        if self.dividerX ~= nil then
            self.dividerX.value = math.clamp(event.position.x, 120, width - 120)
        end
        want(self, 'resizeHorizontal')
        return
    end
    local over = overDivider(self, event.position.x)
    if over ~= self.over then
        self.over = over
        want(self, if over then 'resizeHorizontal' else 'arrow')
    end
end

function pointerDown(self: Divider, event: PointerEvent)
    if overDivider(self, event.position.x) then
        self.dragging = true
        self.over = true
        want(self, 'resizeHorizontal')
    end
end

function pointerUp(self: Divider, event: PointerEvent)
    if not self.dragging then
        return
    end
    self.dragging = false
    -- Released: back to whatever the pointer is now over.
    self.over = overDivider(self, event.position.x)
    want(self, if self.over then 'resizeHorizontal' else 'arrow')
end

function pointerExit(self: Divider, event: PointerEvent)
    -- Not during a drag: the host holds the exit until the release.
    if self.over and not self.dragging then
        self.over = false
        want(self, 'arrow')
    end
end

function advance(self: Divider, seconds: number): boolean
    return true
end

function draw(self: Divider, renderer: Renderer)
    local x = dividerAt(self)
    local h = if self.size.y > 0 then self.size.y else 400
    -- Sidebar.
    self.path:reset()
    self.path:moveTo(Vector.xy(0, 0))
    self.path:lineTo(Vector.xy(x, 0))
    self.path:lineTo(Vector.xy(x, h))
    self.path:lineTo(Vector.xy(0, h))
    self.path:close()
    renderer:drawPath(self.path, self.sidebarPaint)
    -- Divider bar.
    self.path:reset()
    self.path:moveTo(Vector.xy(x - 2, 0))
    self.path:lineTo(Vector.xy(x + 2, 0))
    self.path:lineTo(Vector.xy(x + 2, h))
    self.path:lineTo(Vector.xy(x - 2, h))
    self.path:close()
    renderer:drawPath(self.path, self.dividerPaint)
end

return function(context: Context): Layout<Divider>
    return {
        size = Vector.xy(0, 0),
        cursor = nil,
        dividerX = nil,
        over = false,
        dragging = false,
        sidebarPaint = Paint.with({ color = Color.rgb(38, 38, 44) }),
        dividerPaint = Paint.with({ color = Color.rgb(120, 120, 132) }),
        path = Path.new(),
        init = init,
        resize = resize,
        pointerMove = pointerMove,
        pointerDown = pointerDown,
        pointerUp = pointerUp,
        pointerExit = pointerExit,
        advance = advance,
        draw = draw,
    }
end
