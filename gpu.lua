local ffi = require 'ffi'
local vk = require 'vulkan1'

local createInfo = ffi.new('VkInstanceCreateInfo')
createInfo.sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
local validationLayers = ffi.new("const char*[1]", {'VK_LAYER_KHRONOS_validation'})
createInfo.enabledLayerCount = 1
createInfo.ppEnabledLayerNames = validationLayers
local enabledExtensions = ffi.new("const char*[4]", {
   "VK_KHR_portability_enumeration",
   "VK_KHR_surface",
   "VK_EXT_metal_surface",
   "VK_KHR_get_physical_device_properties2"
})
createInfo.enabledExtensionCount = 4
createInfo.ppEnabledExtensionNames = enabledExtensions
-- VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR
createInfo.flags = 0x00000001
local instance = ffi.new('VkInstance[1]')
local res = vk.vkCreateInstance(createInfo, nil, instance)

print(res)
