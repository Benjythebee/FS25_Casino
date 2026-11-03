-- Client -> server: place a bet or clear the sender's bets.

CasinoBetEvent = {}
local CasinoBetEvent_mt = Class(CasinoBetEvent, Event)

InitEventClass(CasinoBetEvent, "CasinoBetEvent")

CasinoBetEvent.ACTION_PLACE = 1
CasinoBetEvent.ACTION_CLEAR = 2

function CasinoBetEvent.emptyNew()
    return Event.new(CasinoBetEvent_mt)
end

function CasinoBetEvent.new(tableId, action, kind, base, amount)
    local self = CasinoBetEvent.emptyNew()
    self.tableId = tableId
    self.action = action
    self.kind = kind or 0
    self.base = base or 0
    self.amount = amount or 0
    return self
end

function CasinoBetEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.tableId)
    streamWriteUInt8(streamId, self.action)
    streamWriteUInt8(streamId, self.kind)
    streamWriteUInt8(streamId, self.base)
    streamWriteInt32(streamId, self.amount)
end

function CasinoBetEvent:readStream(streamId, connection)
    self.tableId = streamReadUInt8(streamId)
    self.action = streamReadUInt8(streamId)
    self.kind = streamReadUInt8(streamId)
    self.base = streamReadUInt8(streamId)
    self.amount = streamReadInt32(streamId)
    self:run(connection)
end

function CasinoBetEvent:run(connection)
    if not connection:getIsServer() then
        Casino:handleBetRequest(connection, self.tableId, self.action, self.kind, self.base, self.amount)
    end
end
