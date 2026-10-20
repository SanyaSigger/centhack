--[[
    Extracted from skid/reference.luau
    Tracer logic - tracer lines for shots
    Pure logic, no UI dependencies
]]

local Tracers = {}

-- Default tracer settings
Tracers.enabled = false
Tracers.style = "Tracer 1"
Tracers.color = Color3.new(1, 1, 1)
Tracers.color2 = Color3.new(0, 0.5, 1)
Tracers.thickness = 0.5
Tracers.lifetime = 1
Tracers.points = 30

-- Create a tracer line between two points
function Tracers.create(origin, destination, color, thickness, lifetime, style)
    if not origin or not destination then return nil end
    
    local style = style or Tracers.style
    local color = color or Tracers.color
    local thickness = thickness or Tracers.thickness
    local lifetime = lifetime or Tracers.lifetime
    
    local tracer = {
        origin = origin,
        destination = destination,
        color = color,
        thickness = thickness,
        lifetime = lifetime,
        style = style,
        start_time = tick()
    }
    
    return tracer
end

-- Update tracer transparency based on elapsed time
function Tracers.update_transparency(tracer, elapsed, lifetime)
    if not tracer then return end
    local alpha = math.clamp(elapsed / lifetime, 0, 1)
    return alpha
end

-- Check if tracer should be destroyed
function Tracers.should_destroy(tracer, elapsed, lifetime)
    if not tracer then return true end
    return elapsed >= lifetime
end

return Tracers