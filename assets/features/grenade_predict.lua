--[[
    Extracted from skid/reference.luau
    Grenade predict logic
    Pure logic for grenade trajectory prediction
]]

local GrenadePredict = {}

-- Default settings
GrenadePredict.enabled = false
GrenadePredict.color = Color3.fromRGB(255, 80, 80)
GrenadePredict.impact_color = Color3.fromRGB(255, 200, 50)
GrenadePredict.bounce_count = 3
GrenadePredict.target_lineup = false
GrenadePredict.target_color = Color3.fromRGB(80, 220, 255)
GrenadePredict.target_arc = 1
GrenadePredict.auto_aim = false
GrenadePredict.tracer_enabled = false
GrenadePredict.tracer_color = Color3.fromRGB(255, 255, 0)
GrenadePredict.tracer_parts = {}

-- Calculate grenade trajectory point
function GrenadePredict.calculate_point(origin, velocity, gravity, time)
    local pos = origin + velocity * time + 0.5 * Vector3.new(0, -gravity, 0) * time * time
    return pos
end

-- Check if grenade should auto-aim
function GrenadePredict.should_auto_aim()
    return GrenadePredict.enabled and GrenadePredict.auto_aim
end

return GrenadePredict