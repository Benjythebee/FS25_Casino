-- One roulette table. The server runs the rounds (serverXXX methods); clients hold a copy that is replaced by
-- CasinoTableStateEvent on every change and only count the timer down between updates.
--
-- Money goes through a bank object given by Casino:
--   bank:getAvailable(farmId)          balance minus stakes not settled yet
--   bank:settle(farmId, stake, paid)   charge the stakes, pay the winnings
--   bank:getEntropy()                  number mixed into the random generator
-- Stakes are only reserved while a round runs and charged when the ball lands, so nothing is lost if the game is
-- saved or quit mid-round.

RouletteTable = {}
local RouletteTable_mt = Class(RouletteTable)

RouletteTable.PHASE = {
    IDLE = 0, -- nobody seated
    BETTING = 1,
    SPINNING = 2,
    RESULT = 3
}

RouletteTable.NUM_SEATS = 5
RouletteTable.MAX_BETS_PER_SEAT = 40
RouletteTable.HISTORY_SIZE = 12
RouletteTable.BETTING_TIME = 25000
RouletteTable.SPIN_TIME = 7000
RouletteTable.RESULT_TIME = 6000

local RNG_MODULUS = 2147483647

function RouletteTable.new(id, config, bank)
    local self = setmetatable({}, RouletteTable_mt)

    self.id = id
    self.config = config -- {nameKey, chips = {...}, maxStake}
    self.bank = bank

    self.phase = RouletteTable.PHASE.IDLE
    self.timer = 0
    self.result = -1
    self.roundId = 0
    self.seats = {} -- [seatIndex] = {userId, farmId, name, farmName}
    self.bets = {} -- {seat, kind, base, amount, farmId, userId, name}; farmId/userId/name only on the server
    self.history = {} -- newest first
    self.lastRound = {} -- [seatIndex] = {stake, paid}
    self.settled = false
    self.rngState = 1

    return self
end

function RouletteTable:getNumSeated()
    local count = 0
    for i = 1, RouletteTable.NUM_SEATS do
        if self.seats[i] ~= nil then
            count = count + 1
        end
    end
    return count
end

function RouletteTable:findSeat(userId)
    for i = 1, RouletteTable.NUM_SEATS do
        local seat = self.seats[i]
        if seat ~= nil and seat.userId == userId then
            return i
        end
    end
    return nil
end

function RouletteTable:getSeatStake(seatIndex)
    local stake = 0
    for _, bet in ipairs(self.bets) do
        if bet.seat == seatIndex then
            stake = stake + bet.amount
        end
    end
    return stake
end

---Stakes of a farm that are reserved but not charged yet
function RouletteTable:getUnsettledStake(farmId)
    if self.settled then
        return 0
    end
    local stake = 0
    for _, bet in ipairs(self.bets) do
        if bet.farmId == farmId then
            stake = stake + bet.amount
        end
    end
    return stake
end

function RouletteTable:isChip(amount)
    for _, chip in ipairs(self.config.chips) do
        if chip == amount then
            return true
        end
    end
    return false
end

function RouletteTable:removeSeatBets(seatIndex)
    for i = #self.bets, 1, -1 do
        if self.bets[i].seat == seatIndex then
            table.remove(self.bets, i)
        end
    end
end

function RouletteTable:startBetting()
    self.phase = RouletteTable.PHASE.BETTING
    self.timer = RouletteTable.BETTING_TIME
    self.bets = {}
    self.settled = false
    self.roundId = self.roundId + 1
end

---@return boolean ok, string? errorKey
function RouletteTable:serverJoin(userId, farmId, name, farmName, seatIndex)
    if self:findSeat(userId) ~= nil then
        return false, "casino_error_alreadySeated"
    end

    if seatIndex == nil or seatIndex == 0 then
        for i = 1, RouletteTable.NUM_SEATS do
            if self.seats[i] == nil then
                seatIndex = i
                break
            end
        end
        if seatIndex == nil or seatIndex == 0 then
            return false, "casino_error_tableFull"
        end
    elseif seatIndex < 1 or seatIndex > RouletteTable.NUM_SEATS then
        return false, "casino_error_tableFull"
    elseif self.seats[seatIndex] ~= nil then
        return false, "casino_error_seatTaken"
    end

    self.seats[seatIndex] = {userId = userId, farmId = farmId, name = name, farmName = farmName}
    self.lastRound[seatIndex] = nil

    if self.phase == RouletteTable.PHASE.IDLE then
        self:startBetting()
    end

    return true
end

---Bets placed while betting is open are dropped; bets already in a spin stay and are settled for the farm.
function RouletteTable:serverLeave(userId)
    local seatIndex = self:findSeat(userId)
    if seatIndex == nil then
        return false
    end

    if self.phase == RouletteTable.PHASE.BETTING then
        self:removeSeatBets(seatIndex)
    end
    self.seats[seatIndex] = nil
    self.lastRound[seatIndex] = nil

    if self:getNumSeated() == 0 and self.phase == RouletteTable.PHASE.BETTING then
        self.phase = RouletteTable.PHASE.IDLE
        self.timer = 0
        self.bets = {}
    end

    return true
end

---@return boolean ok, string? errorKey
function RouletteTable:serverPlaceBet(userId, farmId, kind, base, amount)
    local seatIndex = self:findSeat(userId)
    if seatIndex == nil then
        return false, "casino_error_notSeated"
    end
    if self.seats[seatIndex].farmId ~= farmId then
        return false, "casino_error_farmChanged"
    end
    if self.phase ~= RouletteTable.PHASE.BETTING then
        return false, "casino_error_betsClosed"
    end
    if not RouletteRules.isValid(kind, base) or not self:isChip(amount) then
        return false, "casino_error_invalidBet"
    end
    if self:getSeatStake(seatIndex) + amount > self.config.maxStake then
        return false, "casino_error_maxStake"
    end
    if self.bank:getAvailable(farmId) < amount then
        return false, "casino_error_noMoney"
    end

    for _, bet in ipairs(self.bets) do
        if bet.seat == seatIndex and bet.kind == kind and bet.base == base then
            bet.amount = bet.amount + amount
            return true
        end
    end

    local count = 0
    for _, bet in ipairs(self.bets) do
        if bet.seat == seatIndex then
            count = count + 1
        end
    end
    if count >= RouletteTable.MAX_BETS_PER_SEAT then
        return false, "casino_error_tooManyBets"
    end

    local seat = self.seats[seatIndex]
    table.insert(self.bets, {seat = seatIndex, kind = kind, base = base, amount = amount, farmId = farmId, userId = seat.userId, name = seat.name})
    return true
end

function RouletteTable:serverClearBets(userId)
    local seatIndex = self:findSeat(userId)
    if seatIndex == nil or self.phase ~= RouletteTable.PHASE.BETTING then
        return false
    end
    self:removeSeatBets(seatIndex)
    return true
end

---Park-Miller generator, re-mixed with fresh entropy on every spin
function RouletteTable:nextRandom(max)
    local entropy = math.floor(math.abs(self.bank:getEntropy() or 0)) % RNG_MODULUS
    self.rngState = (self.rngState + entropy) % RNG_MODULUS
    if self.rngState == 0 then
        self.rngState = 1
    end
    for _ = 1, 3 do
        self.rngState = (self.rngState * 16807) % RNG_MODULUS
    end
    return math.floor(self.rngState / RNG_MODULUS * (max + 1))
end

---Stake and winnings of each player in the current round, in betting order (server only). paid is 0 until settled.
-- @return list of {userId, name, stake, paid}
function RouletteTable:getUserTotals()
    local totals = {}
    local byUser = {}
    for _, bet in ipairs(self.bets) do
        local total = byUser[bet.userId]
        if total == nil then
            total = {userId = bet.userId, name = bet.name, stake = 0, paid = 0}
            byUser[bet.userId] = total
            table.insert(totals, total)
        end
        total.stake = total.stake + bet.amount
        if self.settled and RouletteRules.isWin(bet.kind, bet.base, self.result) then
            total.paid = total.paid + bet.amount * (RouletteRules.getPayout(bet.kind, bet.base) + 1)
        end
    end
    return totals
end

function RouletteTable:settle()
    local byFarm = {}
    local farmOrder = {}
    self.lastRound = {}

    for _, bet in ipairs(self.bets) do
        local paid = 0
        if RouletteRules.isWin(bet.kind, bet.base, self.result) then
            paid = bet.amount * (RouletteRules.getPayout(bet.kind, bet.base) + 1)
        end

        local farm = byFarm[bet.farmId]
        if farm == nil then
            farm = {stake = 0, paid = 0}
            byFarm[bet.farmId] = farm
            table.insert(farmOrder, bet.farmId)
        end
        farm.stake = farm.stake + bet.amount
        farm.paid = farm.paid + paid

        if self.seats[bet.seat] ~= nil then
            local round = self.lastRound[bet.seat] or {stake = 0, paid = 0}
            round.stake = round.stake + bet.amount
            round.paid = round.paid + paid
            self.lastRound[bet.seat] = round
        end
    end

    for _, farmId in ipairs(farmOrder) do
        self.bank:settle(farmId, byFarm[farmId].stake, byFarm[farmId].paid)
    end
    self.settled = true

    table.insert(self.history, 1, self.result)
    while #self.history > RouletteTable.HISTORY_SIZE do
        table.remove(self.history)
    end
end

RouletteTable.TRANSITION_SPIN = "spin" -- betting closed, the ball is running
RouletteTable.TRANSITION_SETTLE = "settle" -- the ball landed and the round was paid

---@return boolean changed (state must be sent to clients), string? transition
function RouletteTable:serverUpdate(dt)
    local PHASE = RouletteTable.PHASE
    if self.phase == PHASE.IDLE then
        return false
    end

    self.timer = self.timer - dt
    if self.timer > 0 then
        return false
    end

    if self.phase == PHASE.BETTING then
        if #self.bets == 0 then
            if self:getNumSeated() == 0 then
                self.phase = PHASE.IDLE
                self.timer = 0
            else
                self.timer = RouletteTable.BETTING_TIME
            end
        else
            self.result = self:nextRandom(36)
            self.phase = PHASE.SPINNING
            self.timer = RouletteTable.SPIN_TIME
            return true, RouletteTable.TRANSITION_SPIN
        end
    elseif self.phase == PHASE.SPINNING then
        self:settle()
        self.phase = PHASE.RESULT
        self.timer = RouletteTable.RESULT_TIME
        return true, RouletteTable.TRANSITION_SETTLE
    elseif self.phase == PHASE.RESULT then
        if self:getNumSeated() > 0 then
            self:startBetting()
        else
            self.phase = PHASE.IDLE
            self.timer = 0
            self.bets = {}
        end
    end

    return true
end

function RouletteTable:clientUpdate(dt)
    if self.phase ~= RouletteTable.PHASE.IDLE then
        self.timer = math.max(0, self.timer - dt)
    end
end

function RouletteTable:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.phase)
    streamWriteInt32(streamId, math.max(0, math.floor(self.timer)))
    streamWriteInt8(streamId, self.result)
    streamWriteInt32(streamId, self.roundId)
    streamWriteBool(streamId, self.settled)

    for i = 1, RouletteTable.NUM_SEATS do
        local seat = self.seats[i]
        if streamWriteBool(streamId, seat ~= nil) then
            streamWriteInt32(streamId, seat.userId)
            streamWriteUIntN(streamId, seat.farmId, FarmManager.FARM_ID_SEND_NUM_BITS)
            streamWriteString(streamId, seat.name)
            streamWriteString(streamId, seat.farmName)
        end

        local round = self.lastRound[i]
        if streamWriteBool(streamId, round ~= nil) then
            streamWriteInt32(streamId, round.stake)
            streamWriteInt32(streamId, round.paid)
        end
    end

    streamWriteUInt8(streamId, #self.history)
    for _, n in ipairs(self.history) do
        streamWriteInt8(streamId, n)
    end

    streamWriteUInt16(streamId, #self.bets)
    for _, bet in ipairs(self.bets) do
        streamWriteUInt8(streamId, bet.seat)
        streamWriteUInt8(streamId, bet.kind)
        streamWriteUInt8(streamId, bet.base)
        streamWriteInt32(streamId, bet.amount)
    end
end

function RouletteTable:readStream(streamId, connection)
    self.phase = streamReadUInt8(streamId)
    self.timer = streamReadInt32(streamId)
    self.result = streamReadInt8(streamId)
    self.roundId = streamReadInt32(streamId)
    self.settled = streamReadBool(streamId)

    self.seats = {}
    self.lastRound = {}
    for i = 1, RouletteTable.NUM_SEATS do
        if streamReadBool(streamId) then
            local seat = {}
            seat.userId = streamReadInt32(streamId)
            seat.farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
            seat.name = streamReadString(streamId)
            seat.farmName = streamReadString(streamId)
            self.seats[i] = seat
        end

        if streamReadBool(streamId) then
            local round = {}
            round.stake = streamReadInt32(streamId)
            round.paid = streamReadInt32(streamId)
            self.lastRound[i] = round
        end
    end

    self.history = {}
    for _ = 1, streamReadUInt8(streamId) do
        table.insert(self.history, streamReadInt8(streamId))
    end

    self.bets = {}
    for _ = 1, streamReadUInt16(streamId) do
        local bet = {}
        bet.seat = streamReadUInt8(streamId)
        bet.kind = streamReadUInt8(streamId)
        bet.base = streamReadUInt8(streamId)
        bet.amount = streamReadInt32(streamId)
        table.insert(self.bets, bet)
    end
end
