--!strict
-- Big numbers as plain { m, e } tables (value = m * 10^e), safe to save in DataStores.
-- Below 1e15 the value is kept exact in m with e = 0. From 1e15 up, m is in [1, 10).
-- All functions are pure and return new tables. Arguments can be BigNum or number.
local Types = require(script.Parent.Types)

export type BigNum = Types.BigNum
type Value = BigNum | number

local EXACT_LIMIT = 1e15
local MAX_DIGITS_GAP = 17 -- beyond this, the smaller number can't change the larger

local BigNum = {}

local function normalize(m: number, e: number): BigNum
	if m ~= m or m == 0 then
		return { m = 0, e = 0 }
	end
	if m == math.huge or m == -math.huge then
		return { m = if m > 0 then 9.999999 else -9.999999, e = 1e6 }
	end
	local abs = math.abs(m)
	if e == 0 and abs < EXACT_LIMIT then
		return { m = m, e = 0 }
	end
	local shift = math.floor(math.log10(abs))
	local total = e + shift
	if total < 15 then
		-- Small enough to be exact again.
		return { m = m * 10 ^ e, e = 0 }
	end
	local mantissa = m / 10 ^ shift
	-- Guard float drift at the edges of [1, 10).
	if math.abs(mantissa) >= 10 then
		mantissa /= 10
		total += 1
	elseif math.abs(mantissa) < 1 then
		mantissa *= 10
		total -= 1
	end
	return { m = mantissa, e = total }
end

function BigNum.new(m: number, e: number?): BigNum
	return normalize(m, e or 0)
end

function BigNum.from(v: Value): BigNum
	if type(v) == "number" then
		return normalize(v, 0)
	end
	return v
end

function BigNum.zero(): BigNum
	return { m = 0, e = 0 }
end

function BigNum.isBigNum(v: any): boolean
	return type(v) == "table" and type(v.m) == "number" and type(v.e) == "number"
end

function BigNum.add(a: Value, b: Value): BigNum
	local x, y = BigNum.from(a), BigNum.from(b)
	if x.m == 0 then
		return y
	elseif y.m == 0 then
		return x
	end
	if x.e == 0 and y.e == 0 then
		return normalize(x.m + y.m, 0)
	end
	if x.e < y.e then
		x, y = y, x
	end
	local gap = x.e - y.e
	if gap > MAX_DIGITS_GAP then
		return x
	end
	return normalize(x.m + y.m / 10 ^ gap, x.e)
end

function BigNum.neg(a: Value): BigNum
	local x = BigNum.from(a)
	return { m = -x.m, e = x.e }
end

function BigNum.sub(a: Value, b: Value): BigNum
	return BigNum.add(a, BigNum.neg(b))
end

function BigNum.mul(a: Value, b: Value): BigNum
	local x, y = BigNum.from(a), BigNum.from(b)
	return normalize(x.m * y.m, x.e + y.e)
end

function BigNum.div(a: Value, b: Value): BigNum
	local x, y = BigNum.from(a), BigNum.from(b)
	if y.m == 0 then
		return BigNum.zero()
	end
	return normalize(x.m / y.m, x.e - y.e)
end

-- Returns -1, 0 or 1.
function BigNum.compare(a: Value, b: Value): number
	local x, y = BigNum.from(a), BigNum.from(b)
	local sx = if x.m > 0 then 1 elseif x.m < 0 then -1 else 0
	local sy = if y.m > 0 then 1 elseif y.m < 0 then -1 else 0
	if sx ~= sy then
		return if sx > sy then 1 else -1
	end
	if sx == 0 then
		return 0
	end
	-- Same sign: compare magnitudes, then flip for negatives.
	local result
	if x.e == y.e then
		local ax, ay = math.abs(x.m), math.abs(y.m)
		result = if ax > ay then 1 elseif ax < ay then -1 else 0
	else
		result = if x.e > y.e then 1 else -1
	end
	return result * sx
end

function BigNum.gte(a: Value, b: Value): boolean
	return BigNum.compare(a, b) >= 0
end

function BigNum.lt(a: Value, b: Value): boolean
	return BigNum.compare(a, b) < 0
end

function BigNum.max(a: Value, b: Value): BigNum
	return if BigNum.compare(a, b) >= 0 then BigNum.from(a) else BigNum.from(b)
end

-- Exact when below 1e15, approximate (or math.huge) above.
function BigNum.toNumber(a: Value): number
	local x = BigNum.from(a)
	if x.e == 0 then
		return x.m
	end
	if x.e > 308 then
		return if x.m > 0 then math.huge else -math.huge
	end
	return x.m * 10 ^ x.e
end

-- Returns the number only if it is exactly representable.
function BigNum.toNumberIfSafe(a: Value): number?
	local x = BigNum.from(a)
	if x.e == 0 then
		return x.m
	end
	return nil
end

-- log10 of the absolute value (useful for UI bars and analytics).
function BigNum.log10(a: Value): number
	local x = BigNum.from(a)
	if x.m == 0 then
		return -math.huge
	end
	return math.log10(math.abs(x.m)) + x.e
end

function BigNum.floor(a: Value): BigNum
	local x = BigNum.from(a)
	if x.e == 0 then
		return { m = math.floor(x.m), e = 0 }
	end
	return x
end

-- DataStore format: a plain table copy. Accepts old numeric saves too.
function BigNum.serialize(a: Value): { m: number, e: number }
	local x = BigNum.from(a)
	return { m = x.m, e = x.e }
end

function BigNum.deserialize(raw: any): BigNum
	if type(raw) == "number" then
		return normalize(raw, 0)
	elseif BigNum.isBigNum(raw) then
		return normalize(raw.m, raw.e)
	end
	return BigNum.zero()
end

return BigNum
