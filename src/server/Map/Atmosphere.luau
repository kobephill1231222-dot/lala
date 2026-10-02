--!strict
-- Bright, clear afternoon: a high warm sun, light haze for depth, soft shadows, and gentle
-- bloom so neon Cursed Orbs still glow. Tuned so farms read clearly from the plaza.

local Atmosphere = {}

local function ensure(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

function Atmosphere.apply(lighting: Lighting)
	lighting.ClockTime = 14.6
	lighting.GeographicLatitude = 30
	lighting.Brightness = 3
	lighting.Ambient = Color3.fromRGB(112, 108, 120)
	lighting.OutdoorAmbient = Color3.fromRGB(150, 146, 158)
	lighting.ColorShift_Top = Color3.fromRGB(255, 240, 220)
	lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	lighting.EnvironmentDiffuseScale = 1
	lighting.EnvironmentSpecularScale = 0.8
	lighting.ExposureCompensation = 0
	lighting.GlobalShadows = true
	lighting.ShadowSoftness = 0.25
	lighting.FogEnd = 100000

	local atmosphere = ensure(lighting, "Atmosphere", "FarmAtmosphere") :: Atmosphere
	atmosphere.Density = 0.24
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(199, 216, 236)
	atmosphere.Decay = Color3.fromRGB(120, 140, 170)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 0.6

	local sky = ensure(lighting, "Sky", "FarmSky") :: Sky
	sky.StarCount = 1000
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 11

	local bloom = ensure(lighting, "BloomEffect", "FarmBloom") :: BloomEffect
	bloom.Intensity = 0.45
	bloom.Size = 24
	bloom.Threshold = 1.8

	local grade = ensure(lighting, "ColorCorrectionEffect", "FarmGrade") :: ColorCorrectionEffect
	grade.Brightness = 0.02
	grade.Contrast = 0.08
	grade.Saturation = 0.1
	grade.TintColor = Color3.fromRGB(255, 252, 246)

	local rays = ensure(lighting, "SunRaysEffect", "FarmSunRays") :: SunRaysEffect
	rays.Intensity = 0.03
	rays.Spread = 0.4

	-- Remove the old dusk setup if this place was built by an earlier version.
	for _, name in
		{ "CurseboundAtmosphere", "CurseboundSky", "CurseboundBloom", "CurseboundGrade", "CurseboundSunRays" }
	do
		local old = lighting:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
end

return Atmosphere
