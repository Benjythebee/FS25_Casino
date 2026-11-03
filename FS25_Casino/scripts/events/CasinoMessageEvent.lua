-- Server -> one client: why a request was refused (l10n key).

CasinoMessageEvent = {}
local CasinoMessageEvent_mt = Class(CasinoMessageEvent, Event)

InitEventClass(CasinoMessageEvent, "CasinoMessageEvent")

function CasinoMessageEvent.emptyNew()
    return Event.new(CasinoMessageEvent_mt)
end

function CasinoMessageEvent.new(textKey)
    local self = CasinoMessageEvent.emptyNew()
    self.textKey = textKey
    return self
end

function CasinoMessageEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.textKey)
end

function CasinoMessageEvent:readStream(streamId, connection)
    self.textKey = streamReadString(streamId)
    self:run(connection)
end

function CasinoMessageEvent:run(connection)
    if connection:getIsServer() then
        Casino:showMessage(self.textKey)
    end
end
