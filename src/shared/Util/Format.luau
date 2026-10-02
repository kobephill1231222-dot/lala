--!strict
-- Number and time formatting shared by UI and server messages.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.abbreviate(value: number): string
	if value ~= value then
		return "0"
	end
	local negative = value < 0
	local n = math.abs(value)
	local text: string
	if n < 1000 then
		if n < 10 and n ~= math.floor(n) then
			text = string.format("%.1f", math.floor(n * 10) / 10)
		else
			text = tostring(math.floor(n))
		end
	else
		local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
		local scaled = n / 10 ^ (tier * 3)
		if scaled >= 100 then
			text = string.format("%d%s", math.floor(scaled), SUFFIXES[tier + 1])
		elseif scaled >= 10 then
			text = string.format("%.1f%s", math.floor(scaled * 10) / 10, SUFFIXES[tier + 1])
		else
			text = string.format("%.2f%s", math.floor(scaled * 100) / 100, SUFFIXES[tier + 1])
		end
	end
	return if negative then "-" .. text else text
end

function Format.commas(value: number): string
	local text = tostring(math.floor(math.abs(value)))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return if value < 0 then "-" .. formatted else formatted
end

function Format.rate(perSecond: number): string
	return Format.abbreviate(perSecond) .. "/s"
end

function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return string.format("%ds", seconds)
	elseif seconds < 3600 then
		return string.format("%dm %02ds", seconds // 60, seconds % 60)
	end
	return string.format("%dh %02dm", seconds // 3600, (seconds % 3600) // 60)
end

function Format.percent(fraction: number): string
	local pct = fraction * 100
	if pct >= 10 then
		return string.format("%d%%", math.floor(pct + 0.5))
	elseif pct >= 1 then
		return string.format("%.1f%%", pct)
	end
	return string.format("%.2f%%", pct)
end

return Format
