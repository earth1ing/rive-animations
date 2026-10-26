-- The sidebar divider. A scripted layout the width of the divider strip that
-- turns a horizontal drag into the sidebar's width, a view model number the
-- sidebar's LayoutComponent width is bound to.
--
-- Under an integrated title bar the tool's drag strip only claims presses
-- that hit nothing in the scene, and a scripted layout's box counts as
-- something, so this divider keeps its drag even where it crosses the strip
-- while the header beside it still moves the window.

type Divider = {
    -- Nil until the second init; see below.
    width: Property<number>?,
    size: Vector,
    grabX: number,
    dragging: boolean,
}

local MIN_WIDTH = 160
local MAX_WIDTH = 480

function init(self: Divider, context: Context): boolean
    -- init runs twice and the view model is absent the first time.
    local vm = context:viewModel()
    if vm == nil then
        return true
    end
    self.width = vm:getNumber('sidebarWidth')
    return true
end

function resize(self: Divider, size: Vector)
    self.size = size
end

function advance(self: Divider, seconds: number): boolean
    -- Nothing to draw: the strip is the LayoutComponent's own Fill.
    return false
end

function pointerDown(self: Divider, event: PointerEvent)
    -- A script is handed every pointer event in the artboard, not only the
    -- ones inside its box, so a press elsewhere (the header, the sidebar)
    -- must be left alone here or it would resize the sidebar too.
    local p = event.position
    if p.x < 0 or p.y < 0 or p.x > self.size.x or p.y > self.size.y then
        return
    end
    self.dragging = true
    self.grabX = p.x
end

function pointerMove(self: Divider, event: PointerEvent)
    if not self.dragging or self.width == nil then
        return
    end
    -- event.position is local to the divider, and the divider moves with the
    -- sidebar, so the offset from the grab point is exactly the width change
    -- still to apply.
    local width = self.width.value + (event.position.x - self.grabX)
    self.width.value = math.clamp(width, MIN_WIDTH, MAX_WIDTH)
end

function pointerUp(self: Divider, event: PointerEvent)
    self.dragging = false
end

return function(context: Context): Layout<Divider>
    return {
        width = nil,
        size = Vector.xy(0, 0),
        grabX = 0,
        dragging = false,
        init = init,
        resize = resize,
        advance = advance,
        pointerDown = pointerDown,
        pointerMove = pointerMove,
        pointerUp = pointerUp,
    }
end
