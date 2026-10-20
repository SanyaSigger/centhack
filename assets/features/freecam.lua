--[[
    Extracted from skid/reference.luau
    Freecam logic - free camera movement
    Pure logic, no UI/Library dependencies
]]

local Freecam = {}

-- Default settings
Freecam.enabled = false
Freecam.speed = 50
Freecam.show_distance = true
Freecam.cf = nil
Freecam.part = nil
Freecam.ghost = nil
Freecam.ghost_label = nil
Freecam.pitch = 0
Freecam.yaw = 0

-- Check if freecam is active
function Freecam.is_active()
    return Freecam.enabled
end

-- Calculate freecam movement vector
function Freecam.calculate_movement(UserInputService)
    local moveVector = Vector3.zero
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector = moveVector + Vector3.new(0, 0, 1) end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector = moveVector + Vector3.new(0, 0, -1) end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector = moveVector + Vector3.new(-1, 0, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector = moveVector + Vector3.new(1, 0, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.E) or UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveVector = moveVector + Vector3.new(0, 1, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.Q) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveVector = moveVector + Vector3.new(0, -1, 0) end
    return moveVector
end

-- Calculate freecam rotation from mouse input
function Freecam.calculate_rotation(MouseDelta, pitch, yaw)
    pitch = math.clamp(pitch - MouseDelta.Y * 0.005, -math.pi/2 + 0.01, math.pi/2 - 0.01)
    yaw = yaw - MouseDelta.X * 0.005
    return pitch, yaw
end

-- Apply freecam CF
function Freecam.apply_cf(cf, moveVector, speed, dt)
    if moveVector.Magnitude > 0 then
        moveVector = moveVector.Unit
        cf = cf + (cf.RightVector * moveVector.X + cf.UpVector * moveVector.Y + cf.LookVector * moveVector.Z) * (speed * dt)
    end
    return cf
end

return Freecam