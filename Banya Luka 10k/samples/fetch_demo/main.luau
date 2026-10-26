-- Fetches a page and paints the outcome: grey while waiting, green for a 2xx
-- response, red otherwise. Scripts only reach the network when the host
-- allows it:
--
--   rive samples/fetch_demo --allow-net
--
-- Without --allow-net the request rejects with "disabled: ...".
type FetchDemo = {
    pending: Paint,
    succeeded: Paint,
    failed: Paint,
    path: Path,
    size: Vector,
    state: string,
}

local function report(response: Response)
    print(`status {response.status} {response.statusText}, ok {response.ok}`)
    local contentType = response:header("content-type") or "unknown type"
    local _, body = await(response:text())
    print(`{#body} bytes of {contentType} from {response.url}`)
end

function init(self: FetchDemo, context: Context): boolean
    async(function()
        local ok, result = await(fetch("https://example.com/"))
        if ok then
            report(result)
            self.state = if result.ok then "succeeded" else "failed"
        else
            print(`fetch failed: {result}`)
            self.state = "failed"
        end

        -- Refused before anything is sent: scripts reach public https:
        -- hosts only.
        local _, refused = await(fetch("http://localhost:8080/"))
        print(`refused as expected: {refused}`)
        return nil
    end)
    return true
end

function resize(self: FetchDemo, size: Vector)
    self.size = size
end

function advance(self: FetchDemo, seconds: number): boolean
    return true
end

function draw(self: FetchDemo, renderer: Renderer)
    local w = self.size.x
    local h = self.size.y
    self.path:reset()
    self.path:moveTo(Vector.xy(0, 0))
    self.path:lineTo(Vector.xy(w, 0))
    self.path:lineTo(Vector.xy(w, h))
    self.path:lineTo(Vector.xy(0, h))
    self.path:close()
    local paint = self.pending
    if self.state == "succeeded" then
        paint = self.succeeded
    elseif self.state == "failed" then
        paint = self.failed
    end
    renderer:drawPath(self.path, paint)
end

return function(context: Context): Layout<FetchDemo>
    return {
        pending = Paint.with({ color = Color.rgb(90, 90, 90) }),
        succeeded = Paint.with({ color = Color.rgb(46, 160, 67) }),
        failed = Paint.with({ color = Color.rgb(200, 60, 50) }),
        path = Path.new(),
        size = Vector.xy(0, 0),
        state = "pending",
        init = init,
        resize = resize,
        advance = advance,
        draw = draw,
    }
end
