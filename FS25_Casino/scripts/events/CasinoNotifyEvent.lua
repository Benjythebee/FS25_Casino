-- Server -> one client: an in-game notification about a round.
--   BET     someone else bet (name, stake) when betting closed
--   RESULT  the receiver's own result (stake, paid); only ever sent to that player

CasinoNotifyEvent = {}
local CasinoNotifyEvent_mt = Class(CasinoNotifyEvent, Event)

InitEventClass(CasinoNotifyEvent, "CasinoNotifyEvent")

CasinoNotifyEvent.BET = 1
CasinoNotifyEvent.RESULT = 2

function CasinoNotifyEvent.emptyNew()
    return Event.new(CasinoNotifyEvent_mt)
end

function CasinoNotifyEvent.new(kind, tableId, name, stake, paid)
    local self = CasinoNotifyEvent.emptyNew()
    self.kind = kind
    self.tableId = tableId
    self.name = name or ""
    self.stake = stake or 0
    self.paid = paid or 0
    return self
end

function CasinoNotifyEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.kind)
    streamWriteUInt8(streamId, self.tableId)
    streamWriteString(streamId, self.name)
    streamWriteInt32(streamId, self.stake)
    streamWriteInt32(streamId, self.paid)
end

function CasinoNotifyEvent:readStream(streamId, connection)
    self.kind = streamReadUInt8(streamId)
    self.tableId = streamReadUInt8(streamId)
    self.name = streamReadString(streamId)
    self.stake = streamReadInt32(streamId)
    self.paid = streamReadInt32(streamId)
    self:run(connection)
end

function CasinoNotifyEvent:run(connection)
    if connection:getIsServer() then
        Casino:showNotification(self.kind, self.tableId, self.name, self.stake, self.paid)
    end
end
