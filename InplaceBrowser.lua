package.path = package.path .. ";./vendor/luajit-glfw/?.lua;./vendor/vulkan/?.lua"

local ffi = require 'ffi'
local vk = require 'vulkan1'
require 'gpu'
