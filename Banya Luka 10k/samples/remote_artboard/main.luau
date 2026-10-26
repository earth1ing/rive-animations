-- Downloads a .riv while the scene runs and shows its default artboard in
-- the "Character" slot: a nested artboard bound to the `character` view
-- model artboard property. Scripts only reach the network when the host
-- allows it:
--
--   rive samples/remote_artboard --allow-net
--
-- Only assets embedded in the downloaded file load, and its own scripts run
-- only if Rive signed them.
local URL =
    "https://raw.githubusercontent.com/rive-app/rive-flutter/master/example/assets/little_machine.riv"

type Loader = {}

function init(self: Loader, context: Context): boolean
    -- init runs twice and the view model is absent the first time.
    local vm = context:viewModel()
    if vm == nil then
        return true
    end
    local character = vm:getArtboard("character")
    async(function()
        local ok, response = await(fetch(URL))
        if not ok then
            print(`fetch failed: {response}`)
            return nil
        end
        if not response.ok then
            print(`fetch failed: {response.status} {response.statusText}`)
            return nil
        end
        local _, bytes = await(response:arrayBuffer())
        local loaded, file = await(context:decodeFile(bytes))
        if not loaded then
            print(`decode failed: {file}`)
            return nil
        end
        print(`artboards: {table.concat(file.artboardNames, ", ")}`)
        if character then
            character.value = file:bindableArtboard()
        end
        return nil
    end)
    return true
end

function draw(self: Loader, renderer: Renderer) end

return function(): Node<Loader>
    return {
        init = init,
        draw = draw,
    }
end
