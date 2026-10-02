--!strict
-- Dusk lighting: a low warm sun, violet haze, gentle bloom so neon cursed energy glows, and
-- enough ambient light that paths and UI targets stay readable on phones.

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
	lighting.ClockTime = 18.1
	lighting.GeographicLatitude = 34
	lighting.Brightness = 2.2
	lighting.Ambient = Color3.fromRGB(58, 48, 74)
	lighting.OutdoorAmbient = Color3.fromRGB(118, 102, 138)
	lighting.ColorShift_Top = Color3.fromRGB(255, 176, 128)
	lighting.ColorShift_Bottom = Color3.fromRGB(90, 60, 120)
	lighting.EnvironmentDiffuseScale = 0.55
	lighting.EnvironmentSpecularScale = 0.6
	lighting.ExposureCompensation = 0.15
	lighting.GlobalShadows = true
	lighting.ShadowSoftness = 0.35

	local atmosphere = ensure(lighting, "Atmosphere", "CurseboundAtmosphere") :: Atmosphere
	atmosphere.Density = 0.33
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(196, 150, 196)
	atmosphere.Decay = Color3.fromRGB(104, 74, 132)
	atmosphere.Glare = 0.45
	atmosphere.Haze = 1.7

	local sky = ensure(lighting, "Sky", "CurseboundSky") :: Sky
	sky.StarCount = 2600
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 16
	sky.MoonAngularSize = 13

	local bloom = ensure(lighting, "BloomEffect", "CurseboundBloom") :: BloomEffect
	bloom.Intensity = 0.75
	bloom.Size = 28
	bloom.Threshold = 1.4

	local grade = ensure(lighting, "ColorCorrectionEffect", "CurseboundGrade") :: ColorCorrectionEffect
	grade.Brightness = 0.02
	grade.Contrast = 0.12
	grade.Saturation = -0.04
	grade.TintColor = Color3.fromRGB(255, 242, 250)

	local rays = ensure(lighting, "SunRaysEffect", "CurseboundSunRays") :: SunRaysEffect
	rays.Intensity = 0.05
	rays.Spread = 0.55
end

return Atmosphere
