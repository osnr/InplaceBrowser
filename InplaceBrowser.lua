package.path = package.path .. ";./vendor/luajit-glfw/?.lua"

local glfw = require 'glfw' { 'glfw', bind_vulkan = true }
