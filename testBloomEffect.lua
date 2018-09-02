local LuaShader = VFS.Include("LuaUI/Widgets/libs/LuaShader.lua")
local BloomEffect = VFS.Include("LuaUI/Widgets/libs/BloomEffect.lua")

local GL_RGBA = 0x1908
local GL_RGBA16F = 0x881A
local GL_RGBA32F = 0x8814


function widget:GetInfo()
   return {
      name      = "BloomEffect test",
      layer     = 1000,
      enabled   = false,
   }
end

local bs

local vsx, vsy
local texIn, texOut

local myCutOffUniforms = [[
	uniform float cutOffLum;
]]


local myDoCutOffDef = [[
	// sRGB
	const vec3 LUM = vec3(0.2126, 0.7152, 0.0722);
	vec4 DoCutOff(vec4 color) {
		float texLum = dot(color.rgb, LUM);
		return color * step(cutOffLum, texLum);
	}
]]


local myDoCutOffDef_ = [[
	vec3 firePalette(float i, float exposure) {
		float T = 1400. + 1300.*i; // Temperature range (in Kelvin).
		vec3 L = vec3(7.4, 5.6, 4.4); // Red, green, blue wavelengths (in hundreds of nanometers).
		L = pow(L,vec3(5.0)) * (exp(1.43876719683e5/(T*L))-1.0);
		return 1.0-exp(-exposure*1e8/L); // Exposure level. Set to "50." For "70," change the "5" to a "7," etc.
	}

	vec4 DoCutOff(vec4 color) {
		vec3 fireCol1 = firePalette(-0.4, 5.0);
		vec3 fireCol2 = firePalette(0.4, 5.0);
		//float D = distance(color.rgb, fireCol);
		//return color * step(cutOffLum, texLum);
		float D = float( all(lessThan(color.rgb, fireCol2)) && all(greaterThan(color.rgb, fireCol1)) );
		return color * D;
		//return color * (1.0 - step(0.5, D));
	}
]]

local myDoToneMapping = [[
	////////////////////////////////////////////////

	//const float gamma = 2.2;
	const float gamma = 1.0;

	vec3 simpleReinhardToneMapping(vec3 color)
	{
		float exposure = 1.5;
		color *= exposure/(1. + color / exposure);
		color = pow(color, vec3(1. / gamma));
		return color;
	}

	vec3 lumaBasedReinhardToneMapping(vec3 color)
	{
		float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
		float toneMappedLuma = luma / (1. + luma);
		color *= toneMappedLuma / luma;
		color = pow(color, vec3(1. / gamma));
		return color;
	}

	vec3 whitePreservingLumaBasedReinhardToneMapping(vec3 color)
	{
		float white = 2.;
		float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
		float toneMappedLuma = luma * (1. + luma / (white*white)) / (1. + luma);
		color *= toneMappedLuma / luma;
		color = pow(color, vec3(1. / gamma));
		return color;
	}

	vec3 RomBinDaHouseToneMapping(vec3 color)
	{
		color = exp( -1.0 / ( 2.72*color + 0.15 ) );
		color = pow(color, vec3(1. / gamma));
		return color;
	}

	vec3 filmicToneMapping(vec3 color)
	{
		color = max(vec3(0.), color - vec3(0.004));
		color = (color * (6.2 * color + .5)) / (color * (6.2 * color + 1.7) + 0.06);
		return color;
	}
	////////////////////////////////////////////////

	// Used to convert from linear RGB to XYZ space
	const mat3 RGB_2_XYZ = (mat3(
		0.4124564, 0.3575761, 0.1804375,
		0.2126729, 0.7151522, 0.0721750,
		0.0193339, 0.1191920, 0.9503041
	));

	// Used to convert from XYZ to linear RGB space
	const mat3 XYZ_2_RGB = (mat3(
		 3.2404542,-1.5371385,-0.4985314,
		-0.9692660, 1.8760108, 0.0415560,
		 0.0556434,-0.2040259, 1.0572252
	));

	// Converts a color from linear RGB to XYZ space
	vec3 rgb_to_xyz(vec3 rgb) {
		return RGB_2_XYZ * rgb;
	}

	// Converts a color from XYZ to linear RGB space
	vec3 xyz_to_rgb(vec3 xyz) {
		return XYZ_2_RGB * xyz;
	}

	// Converts a color from XYZ to xyY space (Y is luminosity)
	vec3 xyz_to_xyY(vec3 xyz) {
		float Y = xyz.y;
		float x = xyz.x / (xyz.x + xyz.y + xyz.z);
		float y = xyz.y / (xyz.x + xyz.y + xyz.z);
		return vec3(x, y, Y);
	}

	// Converts a color from xyY space to XYZ space
	vec3 xyY_to_xyz(vec3 xyY) {
		float Y = xyY.z;
		float x = Y * xyY.x / xyY.y;
		float z = Y * (1.0 - xyY.x - xyY.y) / xyY.y;
		return vec3(x, Y, z);
	}

	// Converts a color from linear RGB to xyY space
	vec3 rgb_to_xyY(vec3 rgb) {
		vec3 xyz = rgb_to_xyz(rgb);
		return xyz_to_xyY(xyz);
	}

	// Converts a color from xyY space to linear RGB
	vec3 xyY_to_rgb(vec3 xyY) {
		vec3 xyz = xyY_to_xyz(xyY);
		return xyz_to_rgb(xyz);
	}

	vec3 xyYToneMapping(vec3 color) {
		vec3 xyY = rgb_to_xyY(color);
		//float mapY = xyY.z / (xyY.z + 1.0);
		float mapY = pow(xyY.z, 0.6);
		//float mapY = log(xyY.z + 1.0);

		//xyY.xy *= 0.95;

		vec3 color2 = xyY_to_rgb(vec3( xyY.x, xyY.y, mapY ));

		const vec3 LUM = vec3(0.2126, 0.7152, 0.0722);
		float lum = dot(color, LUM);

		float mixFactor = step(mixFactorLum, lum);
		//float mixFactor = smoothstep(0.4, 0.5, lum);

		return mix(color, color2, mixFactor);
}


	///////////////////////////////////////////////

	vec4 DoToneMapping(vec4 color) {
		return vec4( xyYToneMapping(color.rgb), color.a );
		//return vec4( color );
	}
]]

local myCombUniforms = [[
	uniform float mixFactorLum;
]]

local coffShader, combShader

function widget:Initialize()
	vsx, vsy = widgetHandler:GetViewSizes()

	texIn = gl.CreateTexture(vsx, vsy,
	{
		border = false,
		min_filter = GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		--fbo = true,
	})

	texOut = gl.CreateTexture(vsx, vsy,
	{
		format = GL_RGBA16F,
		border = false,
		min_filter = GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		--fbo = true,
	})


	be = BloomEffect({
		texIn = texIn,
		texOut = texOut,
		gParams = {
			[1] = {
				-- texIn = texIn, --will be set by BloomEffect()
				-- texOut = texOut, --will be set by BloomEffect()
				-- unusedTexId MUST be set in case of multiple gausses
				unusedTexId = 16,
				downScale = 4,
				linearSampling = true,
				sigma = 1.0,
				halfKernelSize = 5,
				valMult = 0.4,
				repeats = 2,
				blurTexIntFormat = GL_RGBA16F,
			},
			[2] = {
				-- texIn = texIn, --will be set by BloomEffect()
				-- texOut = texOut, --will be set by BloomEffect()
				-- unusedTexId MUST be set in case of multiple gausses
				unusedTexId = 17,
				downScale = 16,
				linearSampling = true,
				sigma = 8.0,
				halfKernelSize = 5,
				valMult = 0.8,
				repeats = 2,
				blurTexIntFormat = GL_RGBA16F,
			},

		},
		cutOffTexFormat = GL_RGBA16F,

		doCutOffFunc = myDoCutOffDef,
		cutOffUniforms = myCutOffUniforms,

		doToneMappingFunc = myDoToneMapping,
		combUniforms = myCombUniforms,

		bloomOnly = false,
	})
	be:Initialize()

	coffShader, combShader = be:GetShaders()

	coffShader:ActivateWith( function()
		coffShader:SetUniformFloatAlways("cutOffLum", 0.7)
	end)

	combShader:ActivateWith( function()
		combShader:SetUniformFloatAlways("mixFactorLum", 0.8)
	end)
end

function widget:Shutdown()
	gl.DeleteTexture(texIn)
	gl.DeleteTexture(texOut)

	be:Finalize()
end

function widget:DrawScreenEffects()
	gl.CopyToTexture(texIn, 0, 0, 0, 0, vsx, vsy)
	gl.Texture(0, texIn)

	be:Execute(true)

	gl.Texture(0, texOut)
	--gl.Texture(1, texIn)
	gl.DepthTest(false)
	--gl.Blending(GL.DST_ALPHA, GL.ONE_MINUS_DST_ALPHA)
	gl.Blending(false)
	gl.TexRect(0, vsy, vsx, 0)
--[[
	coffShader:ActivateWith( function()
		coffShader:SetUniformFloatAlways("cutOffLum", (Spring.GetGameFrame() % 90) / 90)
		gl.DepthTest(false)
		gl.Blending(false)
		gl.TexRect(0, vsy, vsx, 0)
	end)
]]--
	--gl.Texture(0, texOut)
	--gl.TexRect(0, vsy, vsx, 0)
	gl.Texture(0, false)
	--gl.Texture(1, false)
end
