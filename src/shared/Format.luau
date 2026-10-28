--!strict
-- Number and time formatting: 1.2K / 3.4M / 5.6B / 7.8T / 9.1Qa ... and 0:45 timers.
local BigNum = require(script.Parent.BigNum)

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg", "Uvg", "Dvg", "Tvg", "Qavg", "Qivg", "Sxvg", "Spvg", "Ocvg", "Novg", "Tg", "Utg", "Dtg", "Ttg" }

local Format = {}

local function trim(s: string): string
	-- "1.0" -> "1", "12.50" -> "12.5"
	if string.find(s, "%.") then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s
end

-- Formats from a mantissa/exponent pair so it works for any size.
local function fromLog(mantissa: number, exponent: number): string
	local group = math.floor(exponent / 3)
	if group <= 0 then
		local value = mantissa * 10 ^ exponent
		return tostring(math.floor(value))
	end
	local suffix = SUFFIXES[group + 1]
	local scaled = mantissa * 10 ^ (exponent - group * 3) -- 1..999.9
	if not suffix then
		return trim(string.format("%.2f", mantissa)) .. "e" .. exponent
	end
	local text
	if scaled < 10 then
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	elseif scaled < 100 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = tostring(math.floor(scaled))
	end
	return trim(text) .. suffix
end

function Format.number(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	local abs = math.abs(n)
	local text
	if abs < 1000 then
		if abs < 10 and abs ~= math.floor(abs) then
			text = trim(string.format("%.1f", math.floor(abs * 10) / 10))
		else
			text = tostring(math.floor(abs))
		end
	elseif abs == math.huge then
		text = "inf"
	else
		local exponent = math.floor(math.log10(abs))
		local mantissa = abs / 10 ^ exponent
		if mantissa >= 10 then
			mantissa /= 10
			exponent += 1
		end
		text = fromLog(mantissa, exponent)
	end
	return if negative then "-" .. text else text
end

function Format.big(b: BigNum.BigNum | number): string
	local x = BigNum.from(b)
	if x.e == 0 then
		return Format.number(x.m)
	end
	local negative = x.m < 0
	local text = fromLog(math.abs(x.m), x.e)
	return if negative then "-" .. text else text
end

function Format.cash(b: BigNum.BigNum | number): string
	return "$" .. Format.big(b)
end

-- 45 -> "0:45", 125 -> "2:05", 3725 -> "1:02:05"
function Format.time(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

-- 7300 -> "2h 1m", 300 -> "5m", 40 -> "40s"
function Format.duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		local h = s // 3600
		local m = (s % 3600) // 60
		return if m > 0 then `{h}h {m}m` else `{h}h`
	elseif s >= 60 then
		return `{s // 60}m`
	end
	return `{s}s`
end

function Format.percent(fraction: number): string
	return `{math.floor(math.clamp(fraction, 0, 1) * 100)}%`
end

return Format
