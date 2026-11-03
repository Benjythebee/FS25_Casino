-- European single-zero roulette rules. Pure Lua, no game dependencies.
--
-- A bet is (kind, base). The board is drawn the usual way: three rows (top row 3, 6 ... 36, bottom row 1, 4 ... 34)
-- and twelve columns of three numbers ("streets"). Column bets ("2 to 1") cover one row of that drawing.

RouletteRules = {}

RouletteRules.WHEEL_ORDER = {0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26}

RouletteRules.KIND = {
    STRAIGHT = 1, -- base = number 0..36
    SPLIT_SIDE = 2, -- base = n, covers n and n + 3 (neighbours in the same row)
    SPLIT_UP = 3, -- base = n, covers n and n + 1 (neighbours in the same street)
    STREET = 4, -- base = street 1..12
    CORNER = 5, -- base = n (bottom left), covers n, n + 1, n + 3, n + 4
    SIX_LINE = 6, -- base = street 1..11, covers that street and the next
    DOZEN = 7, -- base = 1..3
    COLUMN = 8, -- base = 1..3 (1 = 1, 4 ... 34)
    RED = 9,
    BLACK = 10,
    ODD = 11,
    EVEN = 12,
    LOW = 13, -- 1..18
    HIGH = 14 -- 19..36
}
RouletteRules.NUM_KINDS = 14

-- Board modes for clicks on a number
RouletteRules.MODE = {
    SINGLE = 1,
    SPLIT_SIDE = 2,
    SPLIT_UP = 3,
    STREET = 4,
    CORNER = 5,
    SIX_LINE = 6
}
RouletteRules.NUM_MODES = 6

local RED_NUMBERS = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}
local IS_RED = {}
for _, n in ipairs(RED_NUMBERS) do
    IS_RED[n] = true
end

local WHEEL_INDEX = {}
for i, n in ipairs(RouletteRules.WHEEL_ORDER) do
    WHEEL_INDEX[n] = i
end

local function isInt(v, min, max)
    return type(v) == "number" and v == math.floor(v) and v >= min and v <= max
end

local function street(c)
    return {3 * c - 2, 3 * c - 1, 3 * c}
end

local function filter(predicate)
    local numbers = {}
    for n = 1, 36 do
        if predicate(n) then
            table.insert(numbers, n)
        end
    end
    return numbers
end

---Color of a pocket: "green", "red" or "black"
function RouletteRules.getColor(n)
    if n == 0 then
        return "green"
    elseif IS_RED[n] then
        return "red"
    end
    return "black"
end

---1-based index of a number on the wheel
function RouletteRules.getWheelIndex(n)
    return WHEEL_INDEX[n]
end

---Numbers covered by a bet, or nil when (kind, base) is not a legal bet
function RouletteRules.getNumbers(kind, base)
    local K = RouletteRules.KIND

    if kind == K.STRAIGHT then
        if isInt(base, 0, 36) then
            return {base}
        end
    elseif kind == K.SPLIT_SIDE then
        if isInt(base, 1, 33) then
            return {base, base + 3}
        end
    elseif kind == K.SPLIT_UP then
        if isInt(base, 1, 35) and base % 3 ~= 0 then
            return {base, base + 1}
        end
    elseif kind == K.STREET then
        if isInt(base, 1, 12) then
            return street(base)
        end
    elseif kind == K.CORNER then
        if isInt(base, 1, 32) and base % 3 ~= 0 then
            return {base, base + 1, base + 3, base + 4}
        end
    elseif kind == K.SIX_LINE then
        if isInt(base, 1, 11) then
            local numbers = street(base)
            for _, n in ipairs(street(base + 1)) do
                table.insert(numbers, n)
            end
            return numbers
        end
    elseif kind == K.DOZEN then
        if isInt(base, 1, 3) then
            return filter(function(n) return n > (base - 1) * 12 and n <= base * 12 end)
        end
    elseif kind == K.COLUMN then
        if isInt(base, 1, 3) then
            return filter(function(n) return (n - base) % 3 == 0 end)
        end
    elseif base == 0 then
        if kind == K.RED then
            return filter(function(n) return IS_RED[n] == true end)
        elseif kind == K.BLACK then
            return filter(function(n) return IS_RED[n] ~= true end)
        elseif kind == K.ODD then
            return filter(function(n) return n % 2 == 1 end)
        elseif kind == K.EVEN then
            return filter(function(n) return n % 2 == 0 end)
        elseif kind == K.LOW then
            return filter(function(n) return n <= 18 end)
        elseif kind == K.HIGH then
            return filter(function(n) return n >= 19 end)
        end
    end

    return nil
end

function RouletteRules.isValid(kind, base)
    return RouletteRules.getNumbers(kind, base) ~= nil
end

---Payout ratio (winnings per unit staked, stake not included): 35, 17, 11, 8, 5, 2 or 1
function RouletteRules.getPayout(kind, base)
    local numbers = RouletteRules.getNumbers(kind, base)
    if numbers == nil then
        return 0
    end
    return 36 / #numbers - 1
end

function RouletteRules.isWin(kind, base, result)
    local numbers = RouletteRules.getNumbers(kind, base)
    if numbers ~= nil then
        for _, n in ipairs(numbers) do
            if n == result then
                return true
            end
        end
    end
    return false
end

---Bet for a click on number n in a board mode. Clicks near the edge are moved inwards so every number accepts
-- every mode (e.g. a corner on the top row uses the number below as its bottom left). Zero only takes straight bets.
-- @return kind, base or nil
function RouletteRules.getBetForNumber(mode, n)
    local K = RouletteRules.KIND
    local M = RouletteRules.MODE

    if not isInt(n, 0, 36) then
        return nil
    end
    if mode == M.SINGLE or n == 0 then
        return K.STRAIGHT, n
    end

    local c = math.ceil(n / 3)
    if mode == M.SPLIT_SIDE then
        if n > 33 then
            n = n - 3
        end
        return K.SPLIT_SIDE, n
    elseif mode == M.SPLIT_UP then
        if n % 3 == 0 then
            n = n - 1
        end
        return K.SPLIT_UP, n
    elseif mode == M.STREET then
        return K.STREET, c
    elseif mode == M.CORNER then
        if n % 3 == 0 then
            n = n - 1
        end
        if n > 32 then
            n = n - 3
        end
        return K.CORNER, n
    elseif mode == M.SIX_LINE then
        return K.SIX_LINE, math.min(c, 11)
    end

    return nil
end

---Board cell a bet's chips are drawn on: "n<number>", "doz<1..3>", "col<1..3>", "red", "black", "odd", "even", "low", "high"
function RouletteRules.getAnchorCell(kind, base)
    local K = RouletteRules.KIND

    if kind == K.STRAIGHT or kind == K.SPLIT_SIDE or kind == K.SPLIT_UP or kind == K.CORNER then
        return "n" .. base
    elseif kind == K.STREET or kind == K.SIX_LINE then
        return "n" .. (3 * base - 2)
    elseif kind == K.DOZEN then
        return "doz" .. base
    elseif kind == K.COLUMN then
        return "col" .. base
    elseif kind == K.RED then
        return "red"
    elseif kind == K.BLACK then
        return "black"
    elseif kind == K.ODD then
        return "odd"
    elseif kind == K.EVEN then
        return "even"
    elseif kind == K.LOW then
        return "low"
    elseif kind == K.HIGH then
        return "high"
    end

    return nil
end

---Outside-bet cell to (kind, base)
function RouletteRules.getBetForCell(cell)
    local K = RouletteRules.KIND

    local dozen = string.match(cell, "^doz(%d)$")
    if dozen ~= nil then
        return K.DOZEN, tonumber(dozen)
    end
    local column = string.match(cell, "^col(%d)$")
    if column ~= nil then
        return K.COLUMN, tonumber(column)
    end

    local simple = {red = K.RED, black = K.BLACK, odd = K.ODD, even = K.EVEN, low = K.LOW, high = K.HIGH}
    if simple[cell] ~= nil then
        return simple[cell], 0
    end

    return nil
end

---Short description of a bet. getText(key) translates the kind name (defaults to the key itself).
function RouletteRules.describe(kind, base, getText)
    getText = getText or function(key) return key end
    local K = RouletteRules.KIND
    local numbers = RouletteRules.getNumbers(kind, base)
    if numbers == nil then
        return "?"
    end

    if kind == K.STRAIGHT then
        return tostring(base)
    elseif kind == K.SPLIT_SIDE or kind == K.SPLIT_UP or kind == K.CORNER then
        local key = kind == K.CORNER and "casino_bet_corner" or "casino_bet_split"
        local parts = {}
        for _, n in ipairs(numbers) do
            table.insert(parts, tostring(n))
        end
        table.sort(parts, function(a, b) return tonumber(a) < tonumber(b) end)
        return getText(key) .. " " .. table.concat(parts, "/")
    elseif kind == K.STREET or kind == K.SIX_LINE then
        local key = kind == K.STREET and "casino_bet_street" or "casino_bet_sixLine"
        return string.format("%s %d-%d", getText(key), numbers[1], numbers[#numbers])
    elseif kind == K.DOZEN then
        return string.format("%s %d-%d", getText("casino_bet_dozen"), numbers[1], numbers[#numbers])
    elseif kind == K.COLUMN then
        return string.format("%s %d", getText("casino_bet_column"), base)
    end

    local names = {
        [K.RED] = "casino_bet_red",
        [K.BLACK] = "casino_bet_black",
        [K.ODD] = "casino_bet_odd",
        [K.EVEN] = "casino_bet_even",
        [K.LOW] = "casino_bet_low",
        [K.HIGH] = "casino_bet_high"
    }
    return getText(names[kind])
end
