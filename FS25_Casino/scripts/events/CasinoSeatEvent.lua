-- Client -> server: take a seat (seatIndex 0 = first free) or leave the table.

CasinoSeatEvent = {}
local CasinoSeatEvent_mt = Class(CasinoSeatEvent, Event)

InitEventClass(CasinoSeatEvent, "CasinoSeatEvent")

function CasinoSeatEvent.emptyNew()
    return Event.new(CasinoSeatEvent_mt)
end

function CasinoSeatEvent.new(tableId, seatIndex, join)
    local self = CasinoSeatEvent.emptyNew()
    self.tableId = tableId
    self.seatIndex = seatIndex
    self.join = join
    return self
end

function CasinoSeatEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.tableId)
    streamWriteUInt8(streamId, self.seatIndex)
    streamWriteBool(streamId, self.join)
end

function CasinoSeatEvent:readStream(streamId, connection)
    self.tableId = streamReadUInt8(streamId)
    self.seatIndex = streamReadUInt8(streamId)
    self.join = streamReadBool(streamId)
    self:run(connection)
end

function CasinoSeatEvent:run(connection)
    if not connection:getIsServer() then
        Casino:handleSeatRequest(connection, self.tableId, self.seatIndex, self.join)
    end
end
