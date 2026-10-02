--!strict
-- Pure hit-testing for player techniques. The server is the only caller that applies damage;
-- the client uses the same shapes purely to preview effects.

local CombatMath = {}

local VERTICAL_TOLERANCE = 12

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- Accepts a client-supplied aim vector and returns a flat unit vector, or nil if it is bogus.
function CombatMath.sanitizeAim(aim: any): Vector3?
	if typeof(aim) ~= "Vector3" then
		return nil
	end
	if not (finite(aim.X) and finite(aim.Y) and finite(aim.Z)) then
		return nil
	end
	local flat = Vector3.new(aim.X, 0, aim.Z)
	local magnitude = flat.Magnitude
	if magnitude < 0.05 or aim.Magnitude > 4 then
		return nil
	end
	return flat / magnitude
end

-- shape: "Arc" (range, min facing dot), "Radius" (range), "Line" (range, half-width)
function CombatMath.hits(
	shape: string,
	origin: Vector3,
	aim: Vector3,
	range: number,
	width: number,
	target: Vector3,
	targetRadius: number
): boolean
	local delta = target - origin
	if math.abs(delta.Y) > VERTICAL_TOLERANCE + targetRadius then
		return false
	end
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local distance = flat.Magnitude
	if shape == "Radius" then
		return distance - targetRadius <= range
	elseif shape == "Arc" then
		if distance - targetRadius > range then
			return false
		end
		if distance <= targetRadius + 1.5 then
			return true -- point-blank always connects
		end
		return (flat / distance):Dot(aim) >= width
	elseif shape == "Line" then
		local along = flat:Dot(aim)
		if along < -targetRadius or along > range + targetRadius then
			return false
		end
		local perpendicular = (flat - aim * along).Magnitude
		return perpendicular <= width + targetRadius
	end
	return false
end

return CombatMath
