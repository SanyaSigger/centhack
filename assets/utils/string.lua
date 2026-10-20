--[[
    Extracted from skid/reference.luau (lines ~1599-1626)
    Pure string utility functions - no library or game API dependencies
]]

local String = {}

-- Remove all spaces and newlines from a string
function String.Normalise(String)
    return string.gsub(string.gsub(String, " ", ""), "\n", "")
end

-- Wrap a string with the first and last characters of Combo
function String.Surround(String, Combo)
    return string.format("%s%s%s", string.sub(Combo, 1, 1), String, string.sub(Combo, 2, 2))
end

-- Clamp a string to a maximum length, adding "..." if truncated
function String.Clamp(String, Length)
    local Split = string.split(String, "\n")
    local Clamped = ""

    for Index, Value2 in pairs(Split) do
        if (Index * 13) <= Length then
            Clamped = Clamped .. Value2 .. (Index == #Split and "" or "\n")
        end
    end

    return (
        Clamped ~= String
        and (Clamped == "" and "" or Clamped:sub(0, #Clamped - 1) .. " ...")
        or Clamped
    )
end

return String