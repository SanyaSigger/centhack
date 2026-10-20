--[[
    Extracted from skid/wh.lua
    Hitsound logic - custom hit sounds
    Pure logic, no UI/Library dependencies
]]

local HitSound = {}

-- Default settings
HitSound.enabled = false
HitSound.id = "rbxassetid://6607204501"
HitSound.volume = 1

-- Available hit sounds
HitSound.sounds = {
    ["never lose"] = "rbxassetid://6607204501",
    ["rust"] = "rbxassetid://4764109000",
    ["gamesense"] = "rbxassetid://4817809188",
    ["fatalety"] = "rbxassetid://94204395881101",
    ["bubble"] = "rbxassetid://85730811347567",
    ["fahhhh"] = "rbxassetid://134512042804789",
    ["csgo kill"] = "rbxassetid://7269900245",
    ["csgo headshot"] = "rbxassetid://6937353691",
    ["minecraft bow"] = "rbxassetid://1053296915",
    ["fortnite headshot"] = "rbxassetid://2513174484",
    ["arsenal headshot"] = "rbxassetid://8522515167",
    ["fallen headshot"] = "rbxassetid://988593556",
    ["mogged"] = "rbxassetid://130607335183129",
    ["moan"] = "rbxassetid://7606020137",
    ["mommy asmr"] = "rbxassetid://111500468013640"
}

-- Impact sound IDs that can be intercepted for custom hitsound
HitSound.impact_ids = {
    ["rbxassetid://4585382589"] = true,
    ["rbxassetid://4585351098"] = true,
    ["rbxassetid://4585382046"] = true,
    ["rbxassetid://4585364605"] = true,
}

-- All hitmarker sounds (for volume slider)
HitSound.hitmarker_ids = {
    ["rbxassetid://4585382589"] = true,
    ["rbxassetid://4585351098"] = true,
    ["rbxassetid://4585382046"] = true,
    ["rbxassetid://4585364605"] = true,
    ["rbxassetid://9120454415"] = true,
    ["rbxassetid://4504226333"] = true,
    ["rbxassetid://6668102812"] = true,
    ["rbxassetid://9119166195"] = true,
    ["rbxassetid://4581728529"] = true,
}

-- Get sound ID by name
function HitSound.get_id(name)
    return HitSound.sounds[name] or HitSound.id
end

-- Check if a sound ID is an impact sound that can be intercepted
function HitSound.is_impact_sound(sound_id)
    return HitSound.impact_ids[sound_id] == true
end

-- Check if a sound ID is a hitmarker sound
function HitSound.is_hitmarker_sound(sound_id)
    return HitSound.hitmarker_ids[sound_id] == true
end

return HitSound