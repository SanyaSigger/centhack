--[[
    Extracted from skid/reference.luau
    Movement mods logic - bunny hop, no fall damage, etc.
    Pure logic, no UI/Library dependencies
]]

local Movement = {}

-- Default settings
Movement.bunnyhop_enabled = false
Movement.bunnyhop_active = false
Movement.last_jump_time = 0
Movement.bunnyhop_velocity = 20
Movement.bunnyhop_boost_enabled = false
Movement.bunnyhop_boost_speed = 35
Movement.no_fall = false
Movement.anti_drown = false

-- Check if bunny hop should trigger
function Movement.should_bunnyhop(enabled, active, char, hum, hrp)
    if not enabled or not active then return false end
    local now = tick()
    if now - Movement.last_jump_time < 0.2 then return false end
    if not char or not hum or not hrp then return false end
    if hum:GetState() ~= Enum.HumanoidStateType.Freefall then
        return true
    end
    return false
end

-- Apply bunny hop velocity
function Movement.apply_bunnyhop(hrp, velocity)
    if hrp then
        hrp.Velocity = Vector3.new(hrp.Velocity.X, velocity, hrp.Velocity.Z)
    end
end

-- Check if no fall damage should trigger
function Movement.should_no_fall(hum, hrp)
    if not Movement.no_fall then return false end
    if not hum or not hrp then return false end
    if hum:GetState() == Enum.HumanoidStateType.Freefall then
        if hrp.AssemblyLinearVelocity.Y < -12.5 then
            return true
        end
    end
    return false
end

-- Apply no fall damage
function Movement.apply_no_fall(hum)
    if hum then
        hum:ChangeState(Enum.HumanoidStateType.Landed)
    end
end

return Movement