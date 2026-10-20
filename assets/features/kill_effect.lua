--[[
    Extracted from skid/reference.luau
    Kill effect / damage numbers logic
    Pure logic, no UI/Library dependencies
]]

local KillEffect = {}

-- Default settings
KillEffect.enabled = false
KillEffect.color = Color3.fromRGB(255, 80, 80)
KillEffect.lifetime = 1.5

-- Calculate damage number properties
function KillEffect.calculate(damage, options)
    if not damage or damage <= 0 then return nil end
    
    local rounded_dmg = math.floor(damage + 0.5)
    local text_str = "-" .. tostring(rounded_dmg)
    local color = options.color or Color3.fromRGB(255, 75, 75)
    local spread_mult = options.spread_mult or 1
    local is_random = options.random or false
    
    local vx_px, vy_px
    local gravity_px = 0
    local init_x_px = 0
    local init_y_px = 0
    
    if is_random then
        local angle = math.random() * math.pi * 2
        local speed = math.random(55, 95) * spread_mult
        vx_px = math.cos(angle) * speed
        vy_px = (math.sin(angle) * speed * 0.6) - (math.random(35, 70) * math.clamp(spread_mult, 0.2, 3))
        gravity_px = 140
    else
        vx_px = 0
        vy_px = -50
        gravity_px = 0
        init_x_px = math.random(-15, 15) * spread_mult
        init_y_px = math.random(-8, 8) * spread_mult
    end
    
    return {
        text = text_str,
        color = color,
        vx_px = vx_px,
        vy_px = vy_px,
        gravity_px = gravity_px,
        init_x_px = init_x_px,
        init_y_px = init_y_px,
        lifetime = 1.2
    }
end

-- Calculate damage number position at elapsed time
function KillEffect.position_at(data, elapsed, start_pos)
    local px_x = start_pos.X + data.init_x_px + (data.vx_px * elapsed)
    local px_y = start_pos.Y + data.init_y_px + (data.vy_px * elapsed) + (0.5 * data.gravity_px * elapsed * elapsed)
    return Vector2.new(px_x, px_y)
end

-- Calculate damage number transparency at elapsed time
function KillEffect.transparency_at(elapsed, lifetime)
    local alpha = math.clamp(elapsed / 0.12, 0, 1)
    if elapsed > lifetime * 0.5 then
        alpha = 1 - ((elapsed - lifetime * 0.5) / (lifetime * 0.5))
    end
    return math.clamp(alpha, 0, 1)
end

-- Check if damage number should be destroyed
function KillEffect.should_destroy(elapsed, lifetime)
    return elapsed >= lifetime
end

return KillEffect