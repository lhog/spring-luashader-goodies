local GaussBlur = VFS.Include("LuaUI/Widgets/libs/GaussBlur.lua")
local LuaShader = VFS.Include("LuaUI/Widgets/libs/LuaShader.lua")

local GL_RGBA = 0x1908

local cutOffFragTemplate = [[
	#version 150 compatibility
	#line 8

	uniform sampler2D texIn;

####CutOffUniforms####

####DoCutOff_Definition####

	void main(void)
	{
		vec4 texel = texelFetch(texIn, ivec2(gl_FragCoord.xy), 0);
		gl_FragColor = DoCutOff(texel);
	}
]]

local combFragTemplate = [[
	#version 150 compatibility
	#line 24

	uniform sampler2D texIn;
	uniform sampler2D gaussIn[###NUM_GAUSS###];

	uniform vec2 texOutSize;

####DoToneMapping_Definition####

	void main(void)
	{
		vec4 color = vec4(0.0);
		vec2 uv = gl_FragCoord.xy / texOutSize;

		color += texture(texIn, uv);

		for (int i = 0; i < ###NUM_GAUSS###; ++i) {
			color += texture(gaussIn[i], uv);
		}

		gl_FragColor = DoToneMapping(color);
	}
]]

local function new(class, inputs)
	return setmetatable(
	{
		texIn = inputs.texIn,
		texOut = inputs.texOut,

		unusedTexId = inputs.unusedTexId or 15, -- 15th is unlikely used

		gParams = inputs.gParams, --must have unusedTexId's other than inputs.unusedTexId!!!

		cutOffTexFormat = inputs.cutOffTexFormat or GL_RGBA,

		-- GLSL definition of DoCutOff(in vec4) function
		doCutOffFunc = inputs.doCutOffFunc,
		-- GLSL definition of CutOff Shader Uniforms
		cutOffUniforms = inputs.cutOffUniforms or "",

		-- GLSL definition of DoToneMapping(in vec4) function
		doToneMappingFunc = inputs.doToneMappingFunc,
		-- GLSL definition of Combination Shader Uniforms
		combUniforms = inputs.combUniforms or "",

		bloomOnly = ((inputs.bloomOnly == nil and true) or inputs.bloomOnly),

		cutOffTex = nil,
		cutOffFBO = nil,

		cutOffShader = nil,
		combShader = nil,

		gbs = {},
		gbTexOut = {},
		outFBO = nil,

		inTexSizeX = 0,
		inTexSizeY = 0,

	}, class)
end

local BloomShader = setmetatable({}, {
	__call = function(self, ...) return new(self, ...) end,
	})
BloomShader.__index = BloomShader

local GL_COLOR_ATTACHMENT0_EXT = 0x8CE0

function BloomShader:Initialize()
	local texInInfo = gl.TextureInfo(self.texIn)

	self.inTexSizeX, self.inTexSizeY = texInInfo.xsize, texInInfo.ysize

	self.cutOffTex = gl.CreateTexture(texInInfo.xsize, texInInfo.ysize, {
		format = self.blurTexIntFormat,
		border = false,
		min_filter = GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		--fbo = true,
	})

	local gbUnusedTextures = {}

	for i, gParam in ipairs(self.gParams) do
		self.gbTexOut[i] = gl.CreateTexture(texInInfo.xsize, texInInfo.ysize, {
			format = self.blurTexIntFormat,
			border = false,
			min_filter = GL.LINEAR,
			mag_filter = GL.LINEAR,
			wrap_s = GL.CLAMP_TO_EDGE,
			wrap_t = GL.CLAMP_TO_EDGE,
			--fbo = true,
		})

		gParam.texIn = self.cutOffTex
		gParam.texOut = self.gbTexOut[i]

		self.gbs[i] = GaussBlur(gParam)
		self.gbs[i]:Initialize()

		gbUnusedTextures[i] = self.gbs[i].unusedTexId
	end

	self.cutOffFBO = gl.CreateFBO({
		color0 = self.cutOffTex,
		drawbuffers = {GL_COLOR_ATTACHMENT0_EXT},
	})

	self.outFBO = gl.CreateFBO({
		color0 = self.texOut,
		drawbuffers = {GL_COLOR_ATTACHMENT0_EXT},
	})

	local cutOffShaderFrag = string.gsub(cutOffFragTemplate, "####DoCutOff_Definition####", self.doCutOffFunc)
		  cutOffShaderFrag = string.gsub(cutOffShaderFrag, "####CutOffUniforms####", self.cutOffUniforms)

	self.cutOffShader = LuaShader({
		fragment = cutOffShaderFrag,
		uniformInt = {
			texIn = self.unusedTexId,
		},
	}, "Bloom Cutoff Shader")
	self.cutOffShader:Initialize()


	local texOutInfo = gl.TextureInfo(self.texOut)

	local combShaderFrag = string.gsub(combFragTemplate, "####DoToneMapping_Definition####", self.doToneMappingFunc)
		  combShaderFrag = string.gsub(combShaderFrag, "####CombUniforms####", self.combUniforms)
		  combShaderFrag = string.gsub(combShaderFrag, "###NUM_GAUSS###", #self.gParams)

	self.combShader = LuaShader({
		fragment = combShaderFrag,
		uniformInt = {
			texIn = self.unusedTexId,
		},
		uniformFloat ={
			texOutSize = {texOutInfo.xsize, texOutInfo.ysize}
		},
	}, "Bloom Combination Shader")
	self.combShader:Initialize()

	self.combShader:ActivateWith( function ()
		self.combShader:SetUniformIntArrayAlways("gaussIn", gbUnusedTextures)
	end)
end

function BloomShader:GetShaders()
	return self.cutOffShader, self.combShader
end

function BloomShader:Execute()
	gl.Texture(self.unusedTexId, self.texIn)

	self.cutOffShader:ActivateWith( function ()
		gl.ActiveFBO(self.cutOffFBO, function()
			gl.DepthTest(false)
			gl.Blending(false)
			gl.Clear(GL.COLOR_BUFFER_BIT)
			gl.TexRect(0, 0, self.inTexSizeX, self.inTexSizeY)
		end)
	end)

	gl.Texture(self.unusedTexId, self.cutOffTex)

	for i, gb in ipairs(self.gbs) do
		gb:Execute()
	end

	if not self.bloomOnly then
		gl.Texture(self.unusedTexId, self.texIn)
	end

	for i, gb in ipairs(self.gbs) do
		gl.Texture(gb.unusedTexId, gb.texOut)
	end

	self.combShader:ActivateWith( function ()
		gl.ActiveFBO(self.outFBO, function()
			gl.DepthTest(false)
			gl.Blending(false)
			gl.Clear(GL.COLOR_BUFFER_BIT)
			gl.TexRect(0, 0, self.inTexSizeX, self.inTexSizeY)
		end)
	end)

	for i, gb in ipairs(self.gbs) do
		gl.Texture(gb.unusedTexId, false)
	end

	gl.Texture(self.unusedTexId, false)
end

function BloomShader:Finalize()
	for i, gb in ipairs(self.gbs) do
		gl.DeleteTexture(self.gbTexOut[i])
		gb:Finalize()
	end

	gl.DeleteTexture(self.cutOffTex)

	gl.DeleteFBO(self.cutOffFBO)
	gl.DeleteFBO(self.outFBO)

	self.cutOffShader:Finalize()
	self.combShader:Finalize()
end

return BloomShader