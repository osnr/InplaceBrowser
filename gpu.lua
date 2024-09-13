local ffi = require 'ffi'
local vk = require 'vulkan1'
local glfw = require 'glfw' { 'glfw', bind_vulkan = true }
local GLFW = glfw.const

if glfw.Init() == 0 then return end

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
instance = instance[0]

local physicalDeviceCount = ffi.new('uint32_t[1]')
vk.vkEnumeratePhysicalDevices(instance, physicalDeviceCount, nil)
print(physicalDeviceCount[0])

local physicalDevices = ffi.new('VkPhysicalDevice[?]', physicalDeviceCount[0])
vk.vkEnumeratePhysicalDevices(instance, physicalDeviceCount, physicalDevices)
local physicalDevice = physicalDevices[0]

local graphicsQueueFamilyIndex = math.maxinteger
local queueFamilyCount = ffi.new('uint32_t[1]')
vk.vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, queueFamilyCount, nil)
local queueFamilies = ffi.new('VkQueueFamilyProperties[?]', queueFamilyCount[0])
vk.vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, queueFamilyCount, queueFamilies)
for i = 0, queueFamilyCount[0] - 1 do
   if bit.band(queueFamilies[i].queueFlags, vk.VK_QUEUE_GRAPHICS_BIT) then
      graphicsQueueFamilyIndex = i
      break
   end
end
if graphicsQueueFamilyIndex ==  math.maxinteger then
   error("Failed to find a Vulkan graphics queue family")
end

local queueCreateInfos = ffi.new('VkDeviceQueueCreateInfo[1]')
local queueCreateInfo = queueCreateInfos[0]
queueCreateInfo.sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
queueCreateInfo.queueFamilyIndex = graphicsQueueFamilyIndex
queueCreateInfo.queueCount = 1
local queuePriorities = ffi.new('float[1]')
queuePriorities[0] = 1.0
queueCreateInfo.pQueuePriorities = queuePriorities

local deviceFeatures = ffi.new('VkPhysicalDeviceFeatures')
local deviceExtensions = ffi.new('const char*[3]', {
   'VK_KHR_swapchain',
   'VK_KHR_portability_subset',
   'VK_KHR_maintenance3'
})

local createInfos = ffi.new('VkDeviceCreateInfo[1]')
createInfo = createInfos[0]
createInfo.sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
createInfo.pQueueCreateInfos = queueCreateInfos
createInfo.queueCreateInfoCount = 1
createInfo.pEnabledFeatures = deviceFeatures
createInfo.enabledLayerCount = 0
createInfo.enabledExtensionCount = 3
createInfo.ppEnabledExtensionNames = deviceExtensions
local device = ffi.new('VkDevice[1]')
if vk.vkCreateDevice(physicalDevice, createInfos, nil, device) ~= 0 then
   error("gpu: vkCreateDevice failed")
end

local propertyCount = ffi.new('uint32_t[1]')
vk.vkEnumerateInstanceLayerProperties(propertyCount, nil)
local layerProperties = ffi.new('VkLayerProperties[?]', propertyCount[0])
vk.vkEnumerateInstanceLayerProperties(propertyCount, layerProperties)

local surface = ffi.new('VkSurfaceKHR[1]')
glfw.WindowHint(GLFW.CLIENT_API, GLFW.NO_API)
local window = glfw.CreateWindow(800, 600, "In-place Browser")
if window == GLFW.NULL then
   glfw.Terminate()
   return
end
if glfw.CreateWindowSurface(instance, window, nil, surface) ~= 0 then
   error('gpu: Failed to create GLFW window surface')
end

local presentQueueFamilyIndex
local presentSupport = ffi.new('VkBool32[1]')
vk.vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, graphicsQueueFamilyIndex, surface[0], presentSupport)
if presentSupport == 0 then
   error('gpu: Vulkan graphics queue family does not support presenting to surface')
end
presentQueueFamilyIndex = graphicsQueueFamilyIndex

-- Figure out capabilities/format/mode of physical device for surface.
local capabilities = ffi.new('VkSurfaceCapabilitiesKHR[1]')
vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface[0], capabilities)
capabilities = capabilities[0]
print(capabilities.currentExtent)
local imageCount = capabilities.minImageCount + 1
if capabilities.maxImageCount > 0 and imageCount > capabilities.maxImageCount then
   imageCount = capabilities.maxImageCount
end
local extent = capabilities.currentExtent

local formatCount = ffi.new('uint32_t[1]')
vk.vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface[0], formatCount, nil)
local formats = ffi.new('VkSurfaceFormatKHR[?]', formatCount[0])
if formatCount[0] == 0 then error('gpu: No supported surface formats.') end
vk.vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface[0], formatCount, formats)
local surfaceFormat
for i = 0, formatCount[0] - 1 do
   if formats[i].format == vk.VK_FORMAT_B8G8R8A8_SRGB and formats[i].colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR then
      surfaceFormat = formats[i]
   end
end

local presentModeCount = ffi.new('uint32_t[1]')
vk.vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface[0], presentModeCount, nil)
local presentModes = ffi.new('VkPresentModeKHR[?]', presentModeCount[0])
if presentModeCount[0] == 0 then error('gpu: No supported present mdoes.') end
vk.vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface[0], presentModeCount, presentModes)
local presentMode = vk.VK_PRESENT_MODE_FIFO_KHR -- guaranteed to be available
for i = 0, presentModeCount[0] - 1 do
   if presentModes[i] == vk.VK_PRESENT_MODE_MAILBOX_KHR then
      presentMode = presentModes[i]
   end
end

-- Set up VkSwapchainKHR swapchain
local swapchainCreateInfos = ffi.new('VkSwapchainCreateInfoKHR[1]')
local swapchainCreateInfo = swapchainCreateInfos[0]
swapchainCreateInfo.sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
swapchainCreateInfo.surface = surface[0]
swapchainCreateInfo.minImageCount = imageCount
swapchainCreateInfo.imageFormat = surfaceFormat.format
swapchainCreateInfo.imageColorSpace = surfaceFormat.colorSpace
swapchainCreateInfo.imageExtent = extent
swapchainCreateInfo.imageArrayLayers = 1
swapchainCreateInfo.imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT

if graphicsQueueFamilyIndex ~= presentQueueFamilyIndex then
   error('gpu: Graphics and present queue families differ')
end
swapchainCreateInfo.imageSharingMode = vk.VK_SHARING_MODE_EXCLUSIVE
swapchainCreateInfo.queueFamilyIndexCount = 0
swapchainCreateInfo.pQueueFamilyIndices = nil

swapchainCreateInfo.preTransform = capabilities.currentTransform
swapchainCreateInfo.compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR
swapchainCreateInfo.presentMode = presentMode
swapchainCreateInfo.clipped = vk.VK_TRUE
swapchainCreateInfo.oldSwapchain = 0 -- VK_NULL_HANDLE

local swapchain = ffi.new('VkSwapchainKHR[1]')
if vk.vkCreateSwapchainKHR(device[0], swapchainCreateInfos, NULL, swapchain) ~= 0 then
   error('gpu: vkCreateSwapchainKHR failed')
end
swapchain = swapchain[0]

local swapchainImageCount = ffi.new('uint32_t[1]')
vk.vkGetSwapchainImagesKHR(device[0], swapchain, swapchainImageCount, nil)
local swapchainImages = ffi.new('VkImage[?]', swapchainImageCount[0])
vk.vkGetSwapchainImagesKHR(device[0], swapchain, swapchainImageCount, swapchainImages)
local swapchainImageFormat = surfaceFormat.format
local swapchainExtent = extent
local swapchainImageViews = ffi.new('VkImageView[?]', swapchainImageCount[0])
for i = 0, swapchainImageCount[0] - 1 do
   local createInfos = ffi.new('VkImageViewCreateInfo[1]')
   local createInfo = createInfos[0]
   createInfo.sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
   createInfo.image = swapchainImages[i]
   createInfo.viewType = vk.VK_IMAGE_VIEW_TYPE_2D
   createInfo.format = swapchainImageFormat
   createInfo.components.r = vk.VK_COMPONENT_SWIZZLE_IDENTITY
   createInfo.components.g = vk.VK_COMPONENT_SWIZZLE_IDENTITY
   createInfo.components.b = vk.VK_COMPONENT_SWIZZLE_IDENTITY
   createInfo.components.a = vk.VK_COMPONENT_SWIZZLE_IDENTITY
   createInfo.subresourceRange.aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT
   createInfo.subresourceRange.baseMipLevel = 0
   createInfo.subresourceRange.levelCount = 1
   createInfo.subresourceRange.baseArrayLayer = 0
   createInfo.subresourceRange.layerCount = 1
   if vk.vkCreateImageView(device[0], createInfos, nil, swapchainImageViews + i) ~= 0 then
      error('gpu: vkCreateImageView failed')
   end
end

local graphicsQueues = ffi.new('VkQueue[1]')
vk.vkGetDeviceQueue(device[0], graphicsQueueFamilyIndex, 0, graphicsQueues)
local graphicsQueue = graphicsQueues[0]
local presentQueue = graphicsQueue
local computeQueue = graphicsQueue

-------

glfw.MakeContextCurrent(window)
while glfw.WindowShouldClose(window) == 0 do
   -- TODO: Render

   glfw.SwapBuffers(window)
   glfw.PollEvents()
end

glfw.Terminate()
