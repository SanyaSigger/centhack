--[[
    Extracted from skid/reference.luau
    Desync / Anti-aim logic
    Pure logic, no UI/Library dependencies
]]

local Desync = {}

-- Default settings
Desync.enabled = false
Desync.velocity_x = 0
Desync.velocity_y = 0
Desync.velocity_z = 0
Desync.no_anims = false
Desync.no_anims_active = false
Desync.no_anims_prev = nil
Desync.look_vector_spoof_enabled = false
Desync.look_vector_spoof_mode = "Up"
Desync.look_vector_spoof_pitch = 89
Desync.look_vector_spoof_client_vis = true

-- Check if desync is active
function Desync.is_active(Toggles)
    if not Toggles then return false end
    return Toggles.desync_enabled and Toggles.desync_enabled.Value
end

-- Apply desync no-animations state
function Desync.apply_no_anims(Toggles)
    if not Desync.enabled then return end
    local toggles = Toggles
    local desync_on = toggles and toggles.desync_enabled and toggles.desync_enabled.Value
    if not (Desync.no_anims and desync_on) then
        if Desync.no_anims_active then
            local anim_toggle = toggles and toggles.remove_animations
            if anim_toggle and not Desync.no_anims_prev then
                pcall(function() anim_toggle:SetValue(false) end)
            end
            pcall(function() cheat.apply_remove_animations(false) end)
            Desync.no_anims_active = nil
        end
        return
    end
    Desync.no_anims_active = true
    local anim_toggle = toggles and toggles.remove_animations
    if anim_toggle and anim_toggle.Value ~= true then
        pcall(function() anim_toggle:SetValue(true) end)
    end
    pcall(function() cheat.apply_remove_animations(true) end)
end

-- Calculate look vector spoof rotation
function Desync.calculate_lvs(pitch, yaw, mode, custom_pitch)
    if mode == "Custom" then
        pitch = custom_pitch
    elseif mode == "Up" then
        pitch = 89
    elseif mode == "Down" then
        pitch = -89
    elseif mode == "Straight" then
        pitch = 0
    end
    return pitch, yaw
end

return Desync