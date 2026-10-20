--[[
    Extracted from skid/reference.luau
    Utility functions - pure logic helpers
    No UI/Library dependencies
]]

local Utility = {}

-- Check if a point is inside a rectangle
function Utility.Over(Location, Position, Size)
    return (
        (Location.X >= Position.X)
        and (Location.X <= (Position.X + Size.X))
        and (Location.Y >= Position.Y)
        and (Location.Y <= (Position.Y + Size.Y))
    )
end

-- Normalize a value to 0-1 range
function Utility.Value(Axis, Lowest, Highest)
    return (math.clamp(Axis - Lowest, 0, Highest) / Highest)
end

-- Round and clamp a value
function Utility.Normalise(Value, Decimals, Minimum, Maximum)
    local Rounded = (
        Decimals ~= 1 and (math.floor(Value * Decimals) / Decimals) or math.floor(Value)
    )
    return math.clamp(Rounded, Minimum, Maximum)
end

-- Round Vector2 components
function Utility.RoundVector(Vector)
    return Vector2.new(math.floor(Vector.X), math.floor(Vector.Y))
end

-- Calculate distance between two points
function Utility.Distance(A, B)
    local dx = A.X - B.X
    local dy = A.Y - B.Y
    local dz = A.Z and (A.Z - B.Z) or 0
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Calculate rotation angle in degrees
function Utility.Rotation(From, To)
    return math.deg(math.atan2(To.Y - From.Y, To.X - From.X))
end

-- Remove spaces and newlines from string
function Utility.NormaliseString(String)
    return string.gsub(string.gsub(String, " ", ""), "\n", "")
end

-- Wrap string with combo characters
function Utility.Surround(String, Combo)
    return string.format("%s%s%s", string.sub(Combo, 1, 1), String, string.sub(Combo, 2, 2))
end

-- Clamp string length
function Utility.ClampString(String, Length)
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

return Utility