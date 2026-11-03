-- Minimal stand-ins for the game globals RouletteTable.lua needs, plus an in-memory network stream.

function Class(members, baseMembers)
    local mt = {__index = members}
    if baseMembers ~= nil then
        setmetatable(members, {__index = baseMembers})
    end
    return mt
end

FarmManager = {FARM_ID_SEND_NUM_BITS = 4, SPECTATOR_FARM_ID = 0}
TabbedMenuFrameElement = {}

Stream = {}
function Stream.new()
    return {values = {}, pos = 0}
end

local function writer(stream, value)
    table.insert(stream.values, value)
    return value
end
local function reader(stream)
    stream.pos = stream.pos + 1
    return stream.values[stream.pos]
end

function streamWriteUInt8(s, v) assert(v >= 0 and v < 256, "uint8 " .. tostring(v)) return writer(s, v) end
function streamWriteInt8(s, v) assert(v >= -128 and v < 128, "int8 " .. tostring(v)) return writer(s, v) end
function streamWriteUInt16(s, v) assert(v >= 0 and v < 65536, "uint16") return writer(s, v) end
function streamWriteInt32(s, v) assert(v == math.floor(v) and v >= -2147483648 and v < 2147483648, "int32 " .. tostring(v)) return writer(s, v) end
function streamWriteBool(s, v) assert(type(v) == "boolean", "bool") return writer(s, v) end
function streamWriteString(s, v) assert(type(v) == "string", "string") return writer(s, v) end
function streamWriteUIntN(s, v, bits) assert(v >= 0 and v < 2 ^ bits, "uintN") return writer(s, v) end
streamReadUInt8 = reader
streamReadInt8 = reader
streamReadUInt16 = reader
streamReadInt32 = reader
streamReadBool = reader
streamReadString = reader
function streamReadUIntN(s, bits) return reader(s) end
