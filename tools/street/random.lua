-- A deterministic stand-in for Roblox's Random, for tools/street only.
--
-- Deliberately NOT Roblox's sequence, and the check is written knowing that: it
-- asserts properties that must hold for every plan the city can contain, not
-- the exact plan a given world seed produces. Reproducing Roblox's generator
-- here would buy one thing (the literal city) at the cost of a second copy of
-- somebody else's PRNG that could drift from it silently. Structure is what
-- this check is for; the literal city is what a double build in Studio is for.
--
-- Kept here rather than in tools/petlooks/stubs.lua so the two existing checks
-- are untouched by anything the street work does.

local function lcg(state)
	return (state * 1103515245 + 12345) % 2147483648
end

Random = {}
Random.__index = Random

function Random.new(seed)
	return setmetatable({ state = lcg(math.floor(math.abs(seed or 0)) % 2147483648) }, Random)
end

-- The high bits, always. A linear congruential generator's low bits have a
-- period of a handful of values (bit k repeats every 2^(k+1) draws), so
-- `state % 4` is very nearly a fixed cycle. Taking it from the low end made
-- forty-nine of fifty street props roll the same variant and made every shuffle
-- in the check barely shuffle, which is a check reporting confidence it had not
-- earned. Dropping eleven bits leaves twenty good ones.
local function unitOf(state)
	return math.floor(state / 2048) / 1048576
end

function Random:NextNumber(a, b)
	self.state = lcg(self.state)
	local unit = unitOf(self.state)
	if a == nil then
		return unit
	end
	return a + unit * (b - a)
end

function Random:NextInteger(a, b)
	self.state = lcg(self.state)
	return a + math.floor(unitOf(self.state) * (b - a + 1)) % (b - a + 1)
end
