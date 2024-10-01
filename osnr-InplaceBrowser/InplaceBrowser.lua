require './vendor/strict'
inspect = require './vendor/inspect'

local Gpu = require 'Gpu'
local ffi = require 'ffi'
local glfw = Gpu.glfw

local gpu = Gpu.New()
local DrawQuad = require('DrawQuad')(gpu)
-- local DrawText = require('DrawText')(gpu)

local window = gpu.window

glfw.MakeContextCurrent(window)
while glfw.WindowShouldClose(window) == 0 do
   local mouseX, mouseY = glfw.GetCursorPos(window)

   gpu:DrawStart()
   DrawQuad({0, 0}, {mouseX, mouseY}, {800, 20}, {900, 400}, {1.0, 0, 0, 1.0})
   gpu:DrawEnd()

   glfw.SwapBuffers(window)
   glfw.PollEvents()
end

glfw.Terminate()
