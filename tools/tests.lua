-- Unit tests for RouletteRules and RouletteTable. Run with: node run_tests.mjs

local K = RouletteRules.KIND
local PHASE = RouletteTable.PHASE
local failures, checks = 0, 0

local function check(condition, message)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        print("FAIL: " .. message)
    end
end

-- Rules ---------------------------------------------------------------------------------------------------------

local seen = {}
for _, n in ipairs(RouletteRules.WHEEL_ORDER) do
    seen[n] = (seen[n] or 0) + 1
end
for n = 0, 36 do
    check(seen[n] == 1, "wheel has " .. n .. " once")
end

local reds, blacks = 0, 0
for n = 1, 36 do
    if RouletteRules.getColor(n) == "red" then reds = reds + 1 else blacks = blacks + 1 end
end
check(reds == 18 and blacks == 18 and RouletteRules.getColor(0) == "green", "18 red, 18 black, zero green")

-- wheel colours alternate red/black after the zero
for i = 2, 36 do
    local a, b = RouletteRules.WHEEL_ORDER[i], RouletteRules.WHEEL_ORDER[i + 1]
    check(RouletteRules.getColor(a) ~= RouletteRules.getColor(b), "wheel colours alternate at " .. a)
end

-- every legal bet: expected payout is 36/37 of the stake (2.7% house edge) and the anchor cell exists
local expectedCounts = {
    [K.STRAIGHT] = 37, [K.SPLIT_SIDE] = 33, [K.SPLIT_UP] = 24, [K.STREET] = 12, [K.CORNER] = 22, [K.SIX_LINE] = 11,
    [K.DOZEN] = 3, [K.COLUMN] = 3, [K.RED] = 1, [K.BLACK] = 1, [K.ODD] = 1, [K.EVEN] = 1, [K.LOW] = 1, [K.HIGH] = 1
}
local payouts = {[1] = 35, [2] = 17, [3] = 11, [4] = 8, [6] = 5, [12] = 2, [18] = 1}
for kind = 1, RouletteRules.NUM_KINDS do
    local count = 0
    for base = -1, 40 do
        local numbers = RouletteRules.getNumbers(kind, base)
        if numbers ~= nil then
            count = count + 1
            local payout = RouletteRules.getPayout(kind, base)
            check(payout == payouts[#numbers], string.format("kind %d base %d pays %s for %d numbers", kind, base, payout, #numbers))

            local wins = 0
            for result = 0, 36 do
                if RouletteRules.isWin(kind, base, result) then
                    wins = wins + 1
                end
            end
            check(wins == #numbers, string.format("kind %d base %d wins on %d results", kind, base, wins))
            check(math.abs(wins / 37 * (payout + 1) - 36 / 37) < 1e-9, "house edge 1/37 for kind " .. kind)
            check(not RouletteRules.isWin(kind, base, 0) or kind == K.STRAIGHT, "only a straight 0 wins on zero")

            local anchor = RouletteRules.getAnchorCell(kind, base)
            check(anchor ~= nil, "anchor cell for kind " .. kind .. " base " .. base)
            check(RouletteRules.describe(kind, base) ~= "?", "description for kind " .. kind)
        end
    end
    check(count == expectedCounts[kind], string.format("kind %d has %d legal bets (expected %d)", kind, count, expectedCounts[kind]))
end

-- inside bets are made of neighbours on the board
check(RouletteRules.getNumbers(K.SPLIT_SIDE, 34) == nil, "no side split right of 34")
check(RouletteRules.getNumbers(K.SPLIT_UP, 3) == nil, "no split above the top row")
check(RouletteRules.getNumbers(K.CORNER, 33) == nil, "no corner from the top row")
check(RouletteRules.getNumbers(K.STRAIGHT, 1.5) == nil, "fractional bases are rejected")
check(table.concat(RouletteRules.getNumbers(K.CORNER, 14), ",") == "14,15,17,18", "corner 14 = 14/15/17/18")
check(table.concat(RouletteRules.getNumbers(K.COLUMN, 2), ","):sub(1, 7) == "2,5,8,1", "column 2 starts 2,5,8,11")
check(RouletteRules.describe(K.SIX_LINE, 5) == "casino_bet_sixLine 13-18", "six line description")

-- a click in any mode gives a legal bet covering the clicked number
for mode = 1, RouletteRules.NUM_MODES do
    for n = 0, 36 do
        local kind, base = RouletteRules.getBetForNumber(mode, n)
        check(kind ~= nil and RouletteRules.isValid(kind, base), string.format("mode %d number %d gives a legal bet", mode, n))
        if kind ~= nil then
            check(RouletteRules.isWin(kind, base, n), string.format("mode %d number %d covers the number", mode, n))
        end
    end
end
for _, cell in ipairs({"doz1", "doz3", "col1", "col3", "red", "black", "odd", "even", "low", "high"}) do
    local kind, base = RouletteRules.getBetForCell(cell)
    check(kind ~= nil and RouletteRules.getAnchorCell(kind, base) == cell, "outside cell round trip " .. cell)
end

-- Table ---------------------------------------------------------------------------------------------------------

local function newBank(balances)
    local bank = {balances = balances, ledger = {}, entropy = 12345}
    function bank:getAvailable(farmId)
        return self.balances[farmId] - self.table:getUnsettledStake(farmId)
    end
    function bank:settle(farmId, stake, paid)
        self.balances[farmId] = self.balances[farmId] - stake + paid
        table.insert(self.ledger, {farmId = farmId, stake = stake, paid = paid})
    end
    function bank:getEntropy()
        self.entropy = self.entropy + 7919
        return self.entropy
    end
    return bank
end

local config = {nameKey = "test", chips = {1000, 5000, 10000, 25000}, maxStake = 100000}
local bank = newBank({[1] = 50000, [2] = 3000})
local t = RouletteTable.new(1, config, bank)
bank.table = t

check(t.phase == PHASE.IDLE, "starts idle")
check(t:serverJoin(101, 1, "Anna", "Farm A", 0), "first player joins")
check(t.phase == PHASE.BETTING and t.timer == RouletteTable.BETTING_TIME, "joining opens betting")
local ok, err = t:serverJoin(101, 1, "Anna", "Farm A", 0)
check(not ok and err == "casino_error_alreadySeated", "cannot sit twice")
check(t:serverJoin(102, 2, "Ben", "Farm B", 3), "second player takes seat 3")
ok, err = t:serverJoin(103, 2, "Cat", "Farm B", 3)
check(not ok and err == "casino_error_seatTaken", "seat 3 is taken")

ok, err = t:serverPlaceBet(999, 1, K.RED, 0, 1000)
check(not ok and err == "casino_error_notSeated", "strangers cannot bet")
ok, err = t:serverPlaceBet(101, 2, K.RED, 0, 1000)
check(not ok and err == "casino_error_farmChanged", "bets must come from the seat's farm")
ok, err = t:serverPlaceBet(101, 1, K.RED, 0, 1234)
check(not ok and err == "casino_error_invalidBet", "only chip values")
ok, err = t:serverPlaceBet(101, 1, K.CORNER, 33, 1000)
check(not ok and err == "casino_error_invalidBet", "illegal corner rejected")
ok, err = t:serverPlaceBet(102, 2, K.RED, 0, 5000)
check(not ok and err == "casino_error_noMoney", "cannot bet more than the farm has")
check(t:serverPlaceBet(102, 2, K.BLACK, 0, 1000), "Ben bets black")
check(t:serverPlaceBet(102, 2, K.BLACK, 0, 1000), "Ben adds a chip")
ok, err = t:serverPlaceBet(102, 2, K.ODD, 0, 1000)
check(ok and t:getSeatStake(3) == 3000, "Ben's third chip still fits in 3000")
ok, err = t:serverPlaceBet(102, 2, K.ODD, 0, 1000)
check(not ok and err == "casino_error_noMoney", "reserved stakes count against the balance")
check(#t.bets == 2, "same bet is merged")

check(t:serverPlaceBet(101, 1, K.STRAIGHT, 17, 25000), "Anna bets 25k on 17")
check(t:serverPlaceBet(101, 1, K.STRAIGHT, 17, 25000), "Anna bets another 25k on 17")
ok, err = t:serverPlaceBet(101, 1, K.STRAIGHT, 17, 1000)
check(not ok and err == "casino_error_noMoney", "Anna's 50k balance is fully reserved")

bank.balances[1] = 1000000
for _ = 1, 2 do
    t:serverPlaceBet(101, 1, K.STRAIGHT, 17, 25000)
end
ok, err = t:serverPlaceBet(101, 1, K.STRAIGHT, 17, 1000)
check(not ok and err == "casino_error_maxStake" and t:getSeatStake(1) == 100000, "table limit of 100k per seat")
bank.balances[1] = 50000

check(t:serverClearBets(101) and t:getSeatStake(1) == 0, "Anna clears her bets")
check(t:serverPlaceBet(101, 1, K.STRAIGHT, 17, 10000), "Anna bets 10k on 17")
check(t:serverPlaceBet(101, 1, K.DOZEN, 2, 5000), "Anna bets 5k on the 2nd dozen")

-- stream round trip
local stream = Stream.new()
t:writeStream(stream)
local copy = RouletteTable.new(1, config, nil)
copy:readStream(stream)
check(stream.pos == #stream.values, "reader consumes the whole stream")
check(copy.phase == t.phase and #copy.bets == #t.bets and copy.seats[3].name == "Ben" and copy.seats[2] == nil, "stream copy matches")

-- run the round with a fixed result
check(not t:serverUpdate(1000), "nothing happens mid-betting")
t.nextRandom = function() return 17 end
local changed, transition = t:serverUpdate(RouletteTable.BETTING_TIME)
check(changed and transition == RouletteTable.TRANSITION_SPIN, "betting closes with a spin transition")
check(t.phase == PHASE.SPINNING and t.result == 17, "spinning to 17")
local totals = t:getUserTotals()
check(#totals == 2 and totals[1].name == "Ben" and totals[1].stake == 3000 and totals[2].userId == 101 and totals[2].stake == 15000
    and totals[1].paid == 0 and totals[2].paid == 0, "stakes per player at spin time, nothing paid yet")
ok, err = t:serverPlaceBet(101, 1, K.RED, 0, 1000)
check(not ok and err == "casino_error_betsClosed", "no bets while spinning")
check(t:serverLeave(102), "Ben leaves mid-spin")
check(#t.bets == 4, "his bets stay in the spin")
changed, transition = t:serverUpdate(RouletteTable.SPIN_TIME)
check(changed and transition == RouletteTable.TRANSITION_SETTLE, "ball lands with a settle transition")
totals = t:getUserTotals()
check(totals[1].userId == 102 and totals[1].paid == 6000 and totals[2].paid == 375000, "winnings per player, also for a player who left")
check(t.phase == PHASE.RESULT and t.history[1] == 17, "result recorded")

-- 17 is black, odd, 2nd dozen: Anna gets 10k x 36 + 5k x 3 = 375k; Ben gets 2k black x 2 + 1k odd x 2 = 6k
local anna, ben = bank.balances[1], bank.balances[2]
check(anna == 50000 - 15000 + 360000 + 15000, "Anna paid correctly: " .. anna)
check(ben == 3000 - 3000 + 4000 + 2000, "Ben paid correctly although he left: " .. ben)
check(t.lastRound[1].stake == 15000 and t.lastRound[1].paid == 375000, "seat summary")
check(t:getUnsettledStake(1) == 0, "nothing reserved after settling")

check(t:serverUpdate(RouletteTable.RESULT_TIME), "next round")
check(t.phase == PHASE.BETTING and #t.bets == 0 and t.roundId == 2, "new round starts empty")

-- empty rounds just restart the timer; the table closes when everyone leaves
check(t:serverUpdate(RouletteTable.BETTING_TIME) and t.phase == PHASE.BETTING, "no bets: keep betting")
check(t:serverPlaceBet(101, 1, K.RED, 0, 1000), "Anna bets again")
check(t:serverLeave(101), "Anna leaves while betting")
check(t.phase == PHASE.IDLE and #t.bets == 0, "table closes and her bet is dropped")

-- random results are spread over all pockets
local rng = RouletteTable.new(2, config, newBank({}))
local counts = {}
for _ = 1, 37000 do
    local n = rng:nextRandom(36)
    counts[n] = (counts[n] or 0) + 1
end
for n = 0, 36 do
    check(counts[n] ~= nil and counts[n] > 800 and counts[n] < 1200, "pocket " .. n .. " hit " .. tostring(counts[n]) .. " times")
end

-- results show no repeat pattern: with game-like entropy (38 s rounds on a ms clock, no math.random) the same number
-- comes back after 1..4 spins about 1 time in 37
local clockBank = {k = 0}
function clockBank:getEntropy()
    self.k = self.k + 1
    return 2 * (1000000 + self.k * 38000)
end
local clockTable = RouletteTable.new(3, config, clockBank)
local sequence = {}
for i = 1, 50000 do
    sequence[i] = clockTable:nextRandom(36)
end
for lag = 1, 4 do
    local same = 0
    for i = lag + 1, #sequence do
        if sequence[i] == sequence[i - lag] then
            same = same + 1
        end
    end
    local rate = same / (#sequence - lag)
    check(rate > 0.0235 and rate < 0.0305, string.format("repeat after %d spins happens %.4f of the time (fair 0.0270)", lag, rate))
end

-- Wheel animation --------------------------------------------------------------------------------------------------

local function angleEquals(a, b)
    local d = (a - b) % (2 * math.pi)
    return d < 1e-6 or d > 2 * math.pi - 1e-6
end
local function pocketRotation(n)
    return (RouletteRules.getWheelIndex(n) - 1) * 2 * math.pi / 37
end
local frame = setmetatable({}, {__index = CasinoFrame})
local function rotation(phase, timer, result, previous)
    return frame:getWheelRotation({phase = phase, timer = timer, result = result, history = {previous}})
end

for previous = 0, 36 do
    for result = 0, 36 do
        local spinEnd = RouletteTable.SPIN_TIME - CasinoFrame.SPIN_REST_TIME
        local wheel, ball = rotation(PHASE.SPINNING, RouletteTable.SPIN_TIME - spinEnd, result, previous)
        check(angleEquals(wheel, pocketRotation(result)) and angleEquals(ball, 0),
            string.format("spin from %d ends with %d under the pointer", previous, result))

        local restWheel, restBall = rotation(PHASE.SPINNING, 0, result, previous)
        check(restWheel == wheel and restBall == ball, "wheel rests until the phase ends")

        local startWheel = rotation(PHASE.SPINNING, RouletteTable.SPIN_TIME, result, previous)
        local bettingEnd = rotation(PHASE.BETTING, 0, -1, previous)
        check(angleEquals(startWheel, bettingEnd), "no jump when the spin starts")

        local resultWheel, resultBall = rotation(PHASE.RESULT, RouletteTable.RESULT_TIME, result, result)
        check(angleEquals(resultWheel, wheel) and resultBall == 0, "no jump into the result phase")
    end
    local bettingStart = rotation(PHASE.BETTING, RouletteTable.BETTING_TIME, -1, previous)
    check(angleEquals(bettingStart, rotation(PHASE.RESULT, 0, previous, previous)), "no jump into betting")
end

print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then
    error("tests failed")
end
