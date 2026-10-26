-- A small utility module under test.
local mathutil = {}

function mathutil.add(a: number, b: number): number
    return a + b
end

function mathutil.clamp(value: number, low: number, high: number): number
    if value < low then
        return low
    end
    if value > high then
        return high
    end
    return value
end

return mathutil
