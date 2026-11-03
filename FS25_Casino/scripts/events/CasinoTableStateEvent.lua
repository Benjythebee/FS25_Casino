-- Server -> clients: full state of one table (seats, bets, phase, history). Sent on every change and on join.

CasinoTableStateEvent = {}
local CasinoTableStateEvent_mt = Class(CasinoTableStateEvent, Event)

InitEventClass(CasinoTableStateEvent, "CasinoTableStateEvent")

function CasinoTableStateEvent.emptyNew()
    return Event.new(CasinoTableStateEvent_mt)
end

function CasinoTableStateEvent.new(rouletteTable)
    local self = CasinoTableStateEvent.emptyNew()
    self.rouletteTable = rouletteTable
    return self
end

function CasinoTableStateEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.rouletteTable.id)
    self.rouletteTable:writeStream(streamId, connection)
end

function CasinoTableStateEvent:readStream(streamId, connection)
    local tableId = streamReadUInt8(streamId)
    local rouletteTable = Casino:getTable(tableId)
    if rouletteTable == nil then
        -- table list differs from the server's (mismatching mod versions); read into a throwaway copy
        rouletteTable = RouletteTable.new(tableId, {chips = {}, maxStake = 0}, nil)
    end
    rouletteTable:readStream(streamId, connection)
    self.rouletteTable = rouletteTable
    self:run(connection)
end

function CasinoTableStateEvent:run(connection)
    if connection:getIsServer() then
        Casino:onTableChanged(self.rouletteTable, false)
    end
end
