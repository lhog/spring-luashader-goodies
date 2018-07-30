local LuaShader = VFS.Include("LuaUI/Widgets/libs/LuaShader.lua")
local GaussBlur = VFS.Include("LuaUI/Widgets/libs/GaussBlur.lua")

local GL_RGBA = 0x1908
local GL_RGBA16F = 0x881A
local GL_RGBA32F = 0x8814


function widget:GetInfo()
   return {
      name      = "Gaussian blur test",
      layer     = 0,
      enabled   = false,
   }
end

local gb
local vsx, vsy
local texIn, texOut
function widget:Initialize()
	vsx, vsy = widgetHandler:GetViewSizes()

	texIn = gl.CreateTexture(vsx,vsy,
	{
		border = false,
		min_filter = GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		--fbo = true,
	})
	
	texOut = gl.CreateTexture(vsx,vsy,
	{
		format = GL_RGBA16F,
		border = false,
		min_filter = GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		--fbo = true,
	})
	
	--(texIn, texOut, unusedTexId, downScale, linearSampling, sigma, valMult, repeats, blurTexIntFormat
	gb = GaussBlur(texIn, texOut, nil, 2, true, 1.0, 1.0, 2, GL_RGBA16F)
	gb:Initialize()
end

function widget:Shutdown()
	gl.DeleteTexture(texIn)
	gl.DeleteTexture(texOut)
	gb:Finalize()
end

function widget:DrawScreenEffects()
	gl.CopyToTexture(texIn, 0, 0, 0, 0, vsx, vsy)
	gb:Execute()
	gl.Texture(0, texOut)
	gl.TexRect(0, vsy, vsx, 0)
	gl.Texture(0, false)
end
