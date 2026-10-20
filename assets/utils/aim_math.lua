--[[
    Extracted from skid/wh.lua (lines ~1755-1777)
    Pure aim-related math - no library or game API dependencies
]]

local AimMath = {}

-- Calculate a miss direction vector for hitchance simulation
-- Returns a random direction Vector3
function AimMath.MissDirection()
    local miss_direction = Vector3.new(
        math.random() * 2 - 1,
        math.random() * 2 - 1,
        math.random() * 2 - 1
    )
    if miss_direction.Magnitude > 0 then
        return miss_direction.Unit
    end
    return Vector3.new(0, 1, 0)
end

-- Check if a shot should hit based on hitchance percentage (0-100)
-- Returns true if the shot hits
function AimMath.CheckHitchance(hitchance)
    return math.random(1, 100) <= hitchance
end

-- Calculate aim direction from origin to aim position
-- If magic_bullet is true, uses curved direction; otherwise direct
function AimMath.AimDirection(origin, aim_position, magic_bullet, get_curved_direction_func)
    if magic_bullet and get_curved_direction_func then
        return get_curved_direction_func(origin, aim_position)
    else
        return (aim_position - origin).Unit
    end
end

-- Generate a random seed integer between -10000 and 10000
function AimMath.RandomSeed()
    return math.random(-10000, 10000)
end

return AimMath