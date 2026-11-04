-- Casino for Farming Simulator 25: roulette tables in a new in-game menu page.
--
-- The server owns the tables: clients send seat/bet requests (CasinoSeatEvent, CasinoBetEvent), the server checks
-- them, runs the rounds and sends the full table state back (CasinoTableStateEvent). Only a farm's manager can sit
-- down and bet; everyone can watch. The game is the house.

Casino = {}
Casino.dir = g_currentModDirectory
Casino.modName = g_currentModName

source(Casino.dir .. "scripts/RouletteRules.lua")
source(Casino.dir .. "scripts/RouletteTable.lua")
source(Casino.dir .. "scripts/events/CasinoSeatEvent.lua")
source(Casino.dir .. "scripts/events/CasinoBetEvent.lua")
source(Casino.dir .. "scripts/events/CasinoTableStateEvent.lua")
source(Casino.dir .. "scripts/events/CasinoMessageEvent.lua")
source(Casino.dir .. "scripts/events/CasinoNotifyEvent.lua")
source(Casino.dir .. "scripts/gui/CasinoFrame.lua")

Casino.TABLES = {
    {nameKey = "casino_table_feedStore", chips = {1000, 5000, 10000, 25000}, maxStake = 100000},
    {nameKey = "casino_table_grainSilo", chips = {10000, 50000, 100000, 250000}, maxStake = 1000000},
    {nameKey = "casino_table_highRoller", chips = {100000, 250000, 500000, 1000000}, maxStake = 5000000}
}

Casino.SEAT_COLORS = {
    {0.98, 0.78, 0.12, 1},
    {0.25, 0.62, 1.00, 1},
    {0.90, 0.30, 0.90, 1},
    {0.15, 0.90, 0.60, 1},
    {1.00, 0.48, 0.15, 1}
}

Casino.MESSAGE_TIME = 4 -- seconds

function Casino:loadMap(filename)
    self.isServer = g_currentMission:getIsServer()
    self.isMultiplayer = g_currentMission.missionDynamicInfo.isMultiplayer
    self.message = nil
    self.lastTickTime = nil

    self.tables = {}
    for i, config in ipairs(Casino.TABLES) do
        self.tables[i] = RouletteTable.new(i, config, self)
    end

    self.moneyTypeBets = MoneyType.register("other", "casino_finance_bets", Casino.modName)
    self.moneyTypeWins = MoneyType.register("other", "casino_finance_wins", Casino.modName)

    if self.isServer then
        g_messageCenter:subscribe(MessageType.USER_REMOVED, self.onUserRemoved, self)
    end

    if g_inGameMenu ~= nil and g_gui ~= nil then
        local ok, err = pcall(Casino.loadMenuPage, self)
        if not ok then
            Logging.error("[Casino] Could not add the Casino menu page: %s", tostring(err))
        end
    end
end

---Quitting a savegame soft-restarts the game, which rebuilds the whole GUI, so the menu page is not removed here.
function Casino:deleteMap()
    g_messageCenter:unsubscribeAll(self)
    self.frame = nil
    self.tables = nil
end

function Casino:update(dt)
    self:tick()
end

---Advances the tables by real time. Called from the mission update and from the menu page, because a single
-- player game is paused while the menu is open. Calling it twice in a frame does nothing the second time.
function Casino:tick()
    if self.tables == nil then
        return
    end

    local now = getTimeSec()
    if self.lastTickTime == nil then
        self.lastTickTime = now
        return
    end
    local dt = math.min((now - self.lastTickTime) * 1000, 1000)
    if dt <= 0 then
        return
    end
    self.lastTickTime = now

    for _, rouletteTable in ipairs(self.tables) do
        if self.isServer then
            local changed, transition = rouletteTable:serverUpdate(dt)
            if changed then
                self:onTableChanged(rouletteTable, true)
            end
            if transition ~= nil then
                self:notifyRound(rouletteTable, transition)
            end
        else
            rouletteTable:clientUpdate(dt)
        end
    end

    if self.message ~= nil and now > self.message.untilTime then
        self.message = nil
        if self.frame ~= nil then
            self.frame:updateMessage()
        end
    end
end

function Casino:getTable(tableId)
    if self.tables == nil then
        return nil
    end
    return self.tables[tableId]
end

function Casino:onTableChanged(rouletteTable, broadcast)
    if broadcast and self.isServer and g_server ~= nil then
        g_server:broadcastEvent(CasinoTableStateEvent.new(rouletteTable))
    end
    if self.frame ~= nil then
        self.frame:onTableChanged(rouletteTable)
    end
end

function Casino:showMessage(textKey)
    local text = g_i18n:getText(textKey)
    self.message = {text = text, untilTime = getTimeSec() + Casino.MESSAGE_TIME}
    if self.frame ~= nil then
        self.frame:updateMessage()
    end
end

function Casino:sendMessage(connection, textKey)
    if connection == nil then
        self:showMessage(textKey)
    else
        connection:sendEvent(CasinoMessageEvent.new(textKey))
    end
end

-- Notifications

---Server: when betting closes everyone else hears who bet how much; when the ball lands each player gets their own
-- result. Winnings are only ever sent to the player who won them.
function Casino:notifyRound(rouletteTable, transition)
    for _, total in ipairs(rouletteTable:getUserTotals()) do
        if transition == RouletteTable.TRANSITION_SPIN then
            local event = CasinoNotifyEvent.new(CasinoNotifyEvent.BET, rouletteTable.id, total.name, total.stake, 0)
            self:sendToUsers(event, function(userId) return userId ~= total.userId end)
        elseif transition == RouletteTable.TRANSITION_SETTLE then
            local event = CasinoNotifyEvent.new(CasinoNotifyEvent.RESULT, rouletteTable.id, total.name, total.stake, total.paid)
            self:sendToUsers(event, function(userId) return userId == total.userId end)
        end
    end
end

---Server: deliver an event to every connected user the filter accepts; the host's own user gets it directly.
function Casino:sendToUsers(event, filter)
    local userManager = g_currentMission.userManager
    local localUserId = g_currentMission.playerUserId

    if userManager == nil or not self.isMultiplayer then
        if localUserId ~= nil and filter(localUserId) then
            event:run(Casino.LOCAL_CONNECTION)
        end
        return
    end

    for _, user in ipairs(userManager:getUsers()) do
        local userId = user:getId()
        if filter(userId) then
            local connection = user:getConnection()
            if userId == localUserId or (connection ~= nil and connection:getIsLocal()) then
                event:run(Casino.LOCAL_CONNECTION)
            elseif connection ~= nil then
                connection:sendEvent(event)
            end
        end
    end
end

-- stands in for the server connection when the server shows a notification to its own player
Casino.LOCAL_CONNECTION = {getIsServer = function() return true end}

---Client: show a round notification on the HUD
function Casino:showNotification(kind, tableId, name, stake, paid)
    local rouletteTable = self:getTable(tableId)
    if rouletteTable == nil or g_currentMission.hud == nil then
        return
    end

    local tableName = g_i18n:getText(rouletteTable.config.nameKey)
    local stakeText = g_i18n:formatMoney(stake, 0, true, true)
    local text
    local notificationType = FSBaseMission.INGAME_NOTIFICATION_INFO
    if kind == CasinoNotifyEvent.BET then
        text = string.format(g_i18n:getText("casino_notify_bet"), name, stakeText, tableName)
    elseif paid > 0 then
        text = string.format(g_i18n:getText("casino_notify_won"), stakeText, tableName, g_i18n:formatMoney(paid, 0, true, true))
        notificationType = FSBaseMission.INGAME_NOTIFICATION_OK
    else
        text = string.format(g_i18n:getText("casino_notify_lost"), stakeText, tableName)
    end

    g_currentMission:addIngameNotification(notificationType, text)
end

-- Farms and users

function Casino.getFarmBalance(farm)
    if farm == nil then
        return 0
    elseif farm.getBalance ~= nil then
        return farm:getBalance()
    end
    return farm.money or 0
end

function Casino.getFarmName(farm)
    if farm.name ~= nil and farm.name ~= "" then
        return farm.name
    end
    return string.format("%s %d", g_i18n:getText("casino_farm"), farm.farmId)
end

function Casino:isFarmManager(userId, farm)
    if farm == nil or farm.farmId == FarmManager.SPECTATOR_FARM_ID then
        return false
    end
    if not self.isMultiplayer then
        return true
    end
    if farm.isUserFarmManager ~= nil then
        return farm:isUserFarmManager(userId) == true
    end
    return false
end

---User behind a request. connection nil means the local player (single player or the host).
-- @return userId, farm, nickname
function Casino:resolveUser(connection)
    local userManager = g_currentMission.userManager
    local userId
    if connection == nil then
        userId = g_currentMission.playerUserId
    elseif userManager ~= nil then
        userId = userManager:getUserIdByConnection(connection)
    end
    if userId == nil then
        return nil
    end

    local farm = g_farmManager:getFarmByUserId(userId)
    if farm == nil and not self.isMultiplayer then
        farm = g_farmManager:getFarmById(g_currentMission:getFarmId())
    end

    local name = "?"
    local user = userManager ~= nil and userManager:getUserByUserId(userId) or nil
    if user ~= nil then
        name = user:getNickname()
    end

    return userId, farm, name
end

---Seat, farm and manager state of the local player for the menu page
function Casino:getLocalAccess()
    local userId = g_currentMission.playerUserId
    local farm = g_farmManager:getFarmByUserId(userId)
    if farm == nil then
        farm = g_farmManager:getFarmById(g_currentMission:getFarmId())
    end
    return userId, farm, self:isFarmManager(userId, farm)
end

-- Bank used by the tables

function Casino:getAvailable(farmId)
    local available = Casino.getFarmBalance(g_farmManager:getFarmById(farmId))
    for _, rouletteTable in ipairs(self.tables) do
        available = available - rouletteTable:getUnsettledStake(farmId)
    end
    return available
end

function Casino:settle(farmId, stake, paid)
    if stake > 0 then
        g_currentMission:addMoney(-stake, farmId, self.moneyTypeBets, true, true)
    end
    if paid > 0 then
        g_currentMission:addMoney(paid, farmId, self.moneyTypeWins, true, true)
    end
end

function Casino:getEntropy()
    return getTimeSec() * 1000 + (g_time or 0) + math.random(0, 999999)
end

-- Requests (run on the server)

function Casino:handleSeatRequest(connection, tableId, seatIndex, join)
    local rouletteTable = self:getTable(tableId)
    local userId, farm, name = self:resolveUser(connection)
    if rouletteTable == nil or userId == nil then
        return
    end

    local ok, errorKey
    if join then
        if farm == nil or farm.farmId == FarmManager.SPECTATOR_FARM_ID then
            errorKey = "casino_error_noFarm"
        elseif not self:isFarmManager(userId, farm) then
            errorKey = "casino_error_notManager"
        else
            -- one table at a time
            for _, other in ipairs(self.tables) do
                if other ~= rouletteTable and other:serverLeave(userId) then
                    self:onTableChanged(other, true)
                end
            end
            ok, errorKey = rouletteTable:serverJoin(userId, farm.farmId, name, Casino.getFarmName(farm), seatIndex)
        end
    else
        ok = rouletteTable:serverLeave(userId)
    end

    if errorKey ~= nil then
        self:sendMessage(connection, errorKey)
    end
    if ok then
        self:onTableChanged(rouletteTable, true)
    end
end

function Casino:handleBetRequest(connection, tableId, action, kind, base, amount)
    local rouletteTable = self:getTable(tableId)
    local userId, farm = self:resolveUser(connection)
    if rouletteTable == nil or userId == nil then
        return
    end

    local ok, errorKey
    if action == CasinoBetEvent.ACTION_PLACE then
        if not self:isFarmManager(userId, farm) then
            errorKey = "casino_error_notManager"
        else
            ok, errorKey = rouletteTable:serverPlaceBet(userId, farm.farmId, kind, base, amount)
            if errorKey == "casino_error_farmChanged" then
                rouletteTable:serverLeave(userId)
                ok = true
            end
        end
    elseif action == CasinoBetEvent.ACTION_CLEAR then
        ok = rouletteTable:serverClearBets(userId)
    end

    if errorKey ~= nil then
        self:sendMessage(connection, errorKey)
    end
    if ok then
        self:onTableChanged(rouletteTable, true)
    end
end

function Casino:onUserRemoved(user)
    if self.tables == nil or user == nil or user.getId == nil then
        return
    end
    local userId = user:getId()
    for _, rouletteTable in ipairs(self.tables) do
        if rouletteTable:serverLeave(userId) then
            self:onTableChanged(rouletteTable, true)
        end
    end
end

-- Requests (sent from the local player)

function Casino:requestSeat(tableId, seatIndex, join)
    if self.isServer then
        self:handleSeatRequest(nil, tableId, seatIndex, join)
    else
        g_client:getServerConnection():sendEvent(CasinoSeatEvent.new(tableId, seatIndex, join))
    end
end

function Casino:requestBet(tableId, action, kind, base, amount)
    if self.isServer then
        self:handleBetRequest(nil, tableId, action, kind, base, amount)
    else
        g_client:getServerConnection():sendEvent(CasinoBetEvent.new(tableId, action, kind, base, amount))
    end
end

-- In-game menu page (adapted from the Courseplay / Task List pattern)

function Casino:loadMenuPage()
    local menu = g_inGameMenu
    if menu.pageCasino ~= nil then
        return
    end

    g_gui:loadProfiles(Casino.dir .. "gui/guiProfiles.xml")

    local frame = CasinoFrame.new(self)
    g_gui:loadGui(Casino.dir .. "gui/CasinoFrame.xml", "casinoFrame", frame, true)

    Casino.addMenuPage(menu, frame, "pageCasino", "pageFinances")
    self.frame = frame
end

local function moveToPosition(list, item, position)
    for i = 1, #list do
        if list[i] == item then
            table.remove(list, i)
            table.insert(list, math.min(position, #list + 1), item)
            return
        end
    end
end

function Casino.addMenuPage(menu, frame, pageName, insertAfter)
    local paging = menu.pagingElement

    local position = nil
    for i = 1, #paging.elements do
        if paging.elements[i] == menu[insertAfter] then
            position = i + 1
            break
        end
    end

    menu[pageName] = frame
    paging:addElement(frame)

    if position ~= nil then
        moveToPosition(paging.elements, frame, position)
        for i = 1, #paging.pages do
            if paging.pages[i].element == frame then
                local page = paging.pages[i]
                table.remove(paging.pages, i)
                table.insert(paging.pages, math.min(position, #paging.pages + 1), page)
                break
            end
        end
    end

    paging:updateAbsolutePosition()
    paging:updatePageMapping()

    menu:registerPage(frame, nil, function() return true end)
    local iconFilename = Utils.getFilename("images/menuIcon.dds", Casino.dir)
    menu:addPageTab(frame, iconFilename, GuiUtils.getUVs({0, 0, 256, 256}, {256, 256}))

    if position ~= nil then
        moveToPosition(menu.pageFrames, frame, position)
    end

    CasinoFrame.fixTabListOverflow(menu.pagingTabList)
    menu:rebuildTabList()
end

-- Send the tables to players joining a multiplayer game
FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState, function(mission, connection, user, farm)
    if Casino.tables ~= nil then
        for _, rouletteTable in ipairs(Casino.tables) do
            connection:sendEvent(CasinoTableStateEvent.new(rouletteTable))
        end
    end
end)

addModEventListener(Casino)
