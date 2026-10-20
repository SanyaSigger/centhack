--[[
    Extracted from skid/reference.luau
    Kill Aura (knife) logic - 360° targeting for melee weapons
    Pure logic, no UI/Library dependencies
]]

local KillAura = {}

-- Default settings
KillAura.enabled = false
KillAura.range = 10
KillAura.pulse_interval = 0.42
KillAura.armed = false
KillAura.target = nil

-- Check if a knife/melee weapon is equipped
function KillAura.is_knife_equipped()
    local rps = ReplicatedStorage:FindFirstChild("Players")
    local plr_folder = rps and rps:FindFirstChild(LocalPlayer.Name)
    local status = plr_folder and plr_folder:FindFirstChild("Status")
    local gvars = status and status:FindFirstChild("GameplayVariables")
    local equipped_tool = gvars and gvars:FindFirstChild("EquippedTool")
    local ref = equipped_tool and equipped_tool.Value
    if not ref then return false end
    local prop = ref:FindFirstChild("ItemProperties")
    local slot = prop and prop:FindFirstChild("SlotType")
    if slot and slot.Value == "Melee" then return true end
    local name = ref.Name:lower()
    return name:find("knife", 1, true) ~= nil
        or name:find("karambit", 1, true) ~= nil
        or name:find("butterfly", 1, true) ~= nil
        or name:find("machete", 1, true) ~= nil
        or name:find("cleaver", 1, true) ~= nil
        or name:find("dagger", 1, true) ~= nil
        or name:find("ninjato", 1, true) ~= nil
        or name:find("kukri", 1, true) ~= nil
        or name:find("tanto", 1, true) ~= nil
        or name:find("bayonet", 1, true) ~= nil
        or name:find("dv2", 1, true) ~= nil
end

-- Get kill aura target within range
function KillAura.get_target(range)
    local cam_p = Camera.CFrame.Position
    local aimpart = silent_aim.part or "Head"
    local best, best_dist = nil, range
    local all_plrs = Players:GetPlayers()
    for i = 1, #all_plrs do
        local plr = all_plrs[i]
        if plr ~= LocalPlayer and not getgenv().wh_combat_whitelist[plr.Name] then
            local character = plr.Character
            if character then
                local part = _FindFirstChild(character, aimpart) or _FindFirstChild(character, "Head") or _FindFirstChild(character, "HumanoidRootPart")
                local humanoid = _FindFirstChildOfClass(character, "Humanoid")
                if part and humanoid and humanoid.Health > 0 then
                    local dist = (part.Position - cam_p).Magnitude
                    if dist <= best_dist then
                        best, best_dist = part, dist
                    end
                end
            end
        end
    end
    return best
end

return KillAura