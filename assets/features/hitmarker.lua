--[[
    Extracted from skid/reference.luau
    Hitmarker / hit log logic
    Pure logic for hit indicators
]]

local HitMarker = {}

-- Default settings
HitMarker.enabled = false
HitMarker.lifetime = 0.7
HitMarker.size = 8
HitMarker.valid_color = Color3.fromRGB(255, 85, 85)
HitMarker.invalid_color = Color3.fromRGB(255, 150, 150)

-- Hit log entry structure
HitMarker.logs = { pending = {}, active = {} }

-- Create a hit marker entry
function HitMarker.create_entry(data)
    local entry = {
        target = data.target,
        damage = data.damage,
        color = data.color or Color3.fromRGB(255, 85, 85),
        spawn_tick = tick(),
        is_log = data.is_log or false
    }
    return entry
end

-- Check if hit log entry should be removed
function HitMarker.should_destroy(entry, current_time)
    if not entry then return true end
    return (current_time - entry.spawn_tick) > 5
end

-- Calculate hit marker alpha
function HitMarker.alpha_at(elapsed)
    local alpha = math.clamp(elapsed / 0.12, 0, 1)
    if elapsed > 4 then
        alpha = math.min(alpha, 1 - (elapsed - 4))
    end
    return alpha
end

return HitMarker