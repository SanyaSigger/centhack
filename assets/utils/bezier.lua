--[[
    Extracted from skid/wh.lua (lines 1346-1354, 1641-1648, 1695-1701)
    Pure bezier curve mathematics - no library or game API dependencies
]]

local Bezier = {}

-- Calculate a point on a Bezier curve at parameter t using De Casteljau's algorithm
function Bezier.Point(points, t)
    local n = #points
    if n == 1 then return points[1] end
    local new_points = {}
    for i = 1, n - 1 do
        new_points[i] = points[i]:Lerp(points[i + 1], t)
    end
    return Bezier.Point(new_points, t)
end

-- Calculate the tangent direction of a Bezier curve at parameter t
function Bezier.Tangent(points, t)
    local dt = 0.001
    local t0 = math.max(0, t - dt)
    local t1 = math.min(1, t + dt)
    local p0 = Bezier.Point(points, t0)
    local p1 = Bezier.Point(points, t1)
    return (p1 - p0).Unit
end

-- Compute curved direction from origin to destination using obstacle-aware control points
-- Returns a Unit direction Vector3
function Bezier.GetCurvedDirection(origin, destination, obstacles)
    if not obstacles or #obstacles == 0 then
        return (destination - origin).Unit
    end

    local points = {origin}
    local magnet = 5

    for _, obs in ipairs(obstacles) do
        local offset1 = obs.normal * magnet
        local ctrl1 = obs.position + offset1
        table.insert(points, ctrl1)

        local point_after_obs = origin:Lerp(destination, obs.fraction + 0.1)
        local offset2 = obs.normal * (magnet * 0.5)
        local ctrl2 = point_after_obs + offset2
        table.insert(points, ctrl2)
    end

    table.insert(points, destination)
    return Bezier.Tangent(points, 0)
end

return Bezier