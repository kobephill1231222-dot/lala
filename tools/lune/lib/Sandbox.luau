--!nocheck
-- Runs real ModuleScripts from a Rojo-built place inside Lune.
-- Provides Roblox globals (Instance, CFrame, Enum, ...), `script`, `game`, `workspace`,
-- and a `require` that resolves ModuleScript instances, so game code runs unmodified.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Sandbox = {}

local polyfilled = false
local function polyfill()
	if polyfilled then
		return
	end
	polyfilled = true
	roblox.implementMethod("Instance", "WaitForChild", function(self, name)
		local child = self:FindFirstChild(name)
		if not child then
			error(string.format("WaitForChild: %s has no child %s (sandbox does not yield)", self:GetFullName(), name))
		end
		return child
	end)
end

local startClock = os.clock()

-- Lune 0.10's CFrame.lookAt mirrors the Z axis (Roblox's is correct), so provide a faithful one.
local RCFrame = roblox.CFrame
local function lookAt(at, target, up)
	up = up or roblox.Vector3.new(0, 1, 0)
	local look = target - at
	if look.Magnitude < 1e-9 then
		return RCFrame.new(at.X, at.Y, at.Z)
	end
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(roblox.Vector3.new(0, 0, 1))
		if right.Magnitude < 1e-6 then
			right = look:Cross(roblox.Vector3.new(1, 0, 0))
		end
	end
	right = right.Unit
	local upv = right:Cross(look)
	local back = -look
	return RCFrame.new(at.X, at.Y, at.Z, right.X, upv.X, back.X, right.Y, upv.Y, back.Y, right.Z, upv.Z, back.Z)
end
local CFrameShim = setmetatable({ lookAt = lookAt }, { __index = RCFrame })
Sandbox.CFrame = CFrameShim

function Sandbox.loadPlace(path: string)
	return roblox.deserializePlace(fs.readFile(path))
end

-- overrides: table of extra/replacement globals (e.g. a fake `game` proxy).
function Sandbox.new(game, overrides)
	polyfill()
	local cache = {}
	local loading = {}
	local self = {}

	local base = {
		-- Luau standard library
		assert = assert, error = error, getmetatable = getmetatable, ipairs = ipairs, next = next,
		pairs = pairs, pcall = pcall, print = print, rawequal = rawequal, rawget = rawget,
		rawlen = rawlen, rawset = rawset, select = select, setmetatable = setmetatable,
		tonumber = tonumber, tostring = tostring, type = type, typeof = typeof, unpack = table.unpack,
		xpcall = xpcall, warn = function(...) print("[warn]", ...) end,
		math = math, string = string, table = table, coroutine = coroutine, utf8 = utf8,
		bit32 = bit32, buffer = buffer, os = os, debug = debug, vector = vector,
		task = task,
		tick = function() return os.clock() end,
		time = function() return os.clock() - startClock end,
		-- Roblox datatypes
		Axes = roblox.Axes, BrickColor = roblox.BrickColor, CFrame = CFrameShim, Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		Enum = roblox.Enum, Faces = roblox.Faces, Font = roblox.Font, Instance = roblox.Instance,
		NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, PhysicalProperties = roblox.PhysicalProperties,
		Ray = roblox.Ray, Rect = roblox.Rect, Region3 = roblox.Region3, UDim = roblox.UDim, UDim2 = roblox.UDim2,
		Vector2 = roblox.Vector2, Vector3 = roblox.Vector3, Vector2int16 = roblox.Vector2int16,
		Vector3int16 = roblox.Vector3int16,
		game = game,
		workspace = game and game:GetService("Workspace"),
	}
	if overrides then
		for k, v in overrides do
			base[k] = v
		end
	end

	local function requireModule(target)
		if type(target) == "string" then
			error("Sandbox require() only accepts ModuleScript instances, got string " .. target)
		end
		if cache[target] ~= nil then
			return cache[target]
		end
		assert(target:IsA("ModuleScript"), "require target is not a ModuleScript: " .. target:GetFullName())
		if loading[target] then
			error("cyclic require: " .. target:GetFullName())
		end
		loading[target] = true
		-- luau.load copies the environment table and ignores metatables, so copy globals in.
		local env = table.clone(base)
		env.script = target
		env.require = requireModule
		env._G = env
		local chunk = luau.load(target.Source, { debugName = target:GetFullName(), environment = env })
		local result = chunk()
		loading[target] = nil
		cache[target] = if result == nil then true else result
		return result
	end
	base.require = requireModule

	self.require = requireModule
	self.globals = base
	-- Resolve "ReplicatedStorage/Shared/Rules/Economy" style paths.
	function self.find(path: string)
		local node = nil
		for segment in string.gmatch(path, "[^/]+") do
			if node == nil then
				node = game:GetService(segment)
			else
				node = node:FindFirstChild(segment)
			end
			assert(node, "path not found: " .. path)
		end
		return node
	end
	function self.requirePath(path: string)
		return requireModule(self.find(path))
	end
	return self
end

return Sandbox
