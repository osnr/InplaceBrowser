package.path = package.path .. ";./vendor/luajit-glfw/?.lua;./vendor/vulkan/?.lua"

local ffi = require 'ffi'
local vk = require 'vulkan1'
local glfw = require 'glfw' { 'glfw', bind_vulkan = true }

local GLFW = glfw.const

if glfw.Init() == 0 then return end

local window = glfw.CreateWindow(800, 600, "In-place Browser")
if window == GLFW.NULL then
   glfw.Terminate()
   return
end

require 'gpu'

local function Render()
   
end

glfw.MakeContextCurrent(window)
while glfw.WindowShouldClose(window) == 0 do
   Render()

   glfw.SwapBuffers(window)
   glfw.PollEvents()
end

glfw.Terminate()
