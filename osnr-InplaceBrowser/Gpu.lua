package.path = package.path .. ";./vendor/luajit-glfw/?.lua;./vendor/vulkan/?.lua"

local ffi = require 'ffi'
local vk = require 'vulkan1'
local status, glfw = pcall(function()
   return (require('glfw')({ 'glfw', bind_vulkan = true }))
end)
if not status then
   -- This is a hack for macOS.
   glfw = (require('glfw')({ '/opt/homebrew/lib/libglfw.dylib', bind_vulkan = true }))
end
local GLFW = glfw.const

local Gpu = {}
Gpu.__index = Gpu
function Gpu:New()
   if glfw.Init() == 0 then return end

   local gpu = setmetatable({}, Gpu)
   gpu:Init()
   gpu:InitImageManagement()
   return gpu
end
function Gpu:GetMaxImages() return 16 end

function Gpu:Init()
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
   instance = instance[0]

   local physicalDeviceCount = ffi.new('uint32_t[1]')
   vk.vkEnumeratePhysicalDevices(instance, physicalDeviceCount, nil)

   self.physicalDevices = ffi.new('VkPhysicalDevice[?]', physicalDeviceCount[0])
   vk.vkEnumeratePhysicalDevices(instance, physicalDeviceCount, self.physicalDevices)
   local physicalDevice = self.physicalDevices[0]; self.physicalDevice = physicalDevice

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

   local createInfo = ffi.new('VkDeviceCreateInfo')
   createInfo.sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
   createInfo.pQueueCreateInfos = queueCreateInfos
   createInfo.queueCreateInfoCount = 1
   createInfo.pEnabledFeatures = deviceFeatures
   createInfo.enabledLayerCount = 0
   createInfo.enabledExtensionCount = 3
   createInfo.ppEnabledExtensionNames = deviceExtensions
   self.devices = ffi.new('VkDevice[1]')
   if vk.vkCreateDevice(physicalDevice, createInfo, nil, self.devices) ~= 0 then
      error("gpu: vkCreateDevice failed")
   end
   self.device = self.devices[0]; local device = self.device

   local propertyCount = ffi.new('uint32_t[1]')
   vk.vkEnumerateInstanceLayerProperties(propertyCount, nil)
   local layerProperties = ffi.new('VkLayerProperties[?]', propertyCount[0])
   vk.vkEnumerateInstanceLayerProperties(propertyCount, layerProperties)

   local surface = ffi.new('VkSurfaceKHR[1]')
   glfw.WindowHint(GLFW.CLIENT_API, GLFW.NO_API)
   self.window = glfw.CreateWindow(800, 600, "In-place Browser")
   if self.window == GLFW.NULL then
      glfw.Terminate()
      return
   end
   if glfw.CreateWindowSurface(instance, self.window, nil, surface) ~= 0 then
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
   self.capabilities = capabilities
   vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface[0], capabilities)
   local capabilities = capabilities[0]
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

   local swapchains = ffi.new('VkSwapchainKHR[1]')
   self.swapchains = swapchains
   if vk.vkCreateSwapchainKHR(device, swapchainCreateInfos, nil, swapchains) ~= 0 then
      error('gpu: vkCreateSwapchainKHR failed')
   end
   local swapchain = swapchains[0]; self.swapchain = swapchain

   local swapchainImageCount = ffi.new('uint32_t[1]')
   vk.vkGetSwapchainImagesKHR(device, swapchain, swapchainImageCount, nil)
   local swapchainImages = ffi.new('VkImage[?]', swapchainImageCount[0])
   vk.vkGetSwapchainImagesKHR(device, swapchain, swapchainImageCount, swapchainImages)
   local swapchainImageFormat = surfaceFormat.format
   self.swapchainExtent = extent
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
      if vk.vkCreateImageView(device, createInfos, nil, swapchainImageViews + i) ~= 0 then
         error('gpu: vkCreateImageView failed')
      end
   end

   self.graphicsQueues = ffi.new('VkQueue[1]')
   vk.vkGetDeviceQueue(device, graphicsQueueFamilyIndex, 0, self.graphicsQueues)
   self.graphicsQueue = self.graphicsQueues[0]
   self.presentQueue = self.graphicsQueue

   -- Set up render pass:
   local colorAttachments = ffi.new('VkAttachmentDescription[1]')
   local colorAttachment = colorAttachments[0]
   colorAttachment.format = swapchainImageFormat
   colorAttachment.samples = vk.VK_SAMPLE_COUNT_1_BIT
   colorAttachment.loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR
   colorAttachment.storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE
   colorAttachment.stencilLoadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE
   colorAttachment.stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE
   colorAttachment.initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED
   colorAttachment.finalLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR

   local colorAttachmentRefs = ffi.new('VkAttachmentReference[1]')
   local colorAttachmentRef = colorAttachmentRefs[0]
   colorAttachmentRef.attachment = 0
   colorAttachmentRef.layout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL

   local subpasses = ffi.new('VkSubpassDescription[1]')
   local subpass = subpasses[0]
   subpass.pipelineBindPoint = vk.VK_PIPELINE_BIND_POINT_GRAPHICS
   subpass.colorAttachmentCount = 1
   subpass.pColorAttachments = colorAttachmentRefs

   local renderPassInfos = ffi.new('VkRenderPassCreateInfo[1]')
   local renderPassInfo = renderPassInfos[0]
   renderPassInfo.sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
   renderPassInfo.attachmentCount = 1
   renderPassInfo.pAttachments = colorAttachments
   renderPassInfo.subpassCount = 1
   renderPassInfo.pSubpasses = subpasses

   local dependencies = ffi.new('VkSubpassDependency[1]')
   local dependency = dependencies[0]
   dependency.srcSubpass = vk.VK_SUBPASS_EXTERNAL
   dependency.dstSubpass = 0
   dependency.srcStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
   dependency.srcAccessMask = 0
   dependency.dstStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
   dependency.dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT

   renderPassInfo.dependencyCount = 1
   renderPassInfo.pDependencies = dependencies

   self.renderPass = ffi.new('VkRenderPass[1]')
   if vk.vkCreateRenderPass(device, renderPassInfos, nil, self.renderPass) ~= 0 then
      error('gpu: vkCreateRenderPass failed')
   end

   self.swapchainFramebuffers = ffi.new('VkFramebuffer[?]', swapchainImageCount[0])
   for i = 0, swapchainImageCount[0] - 1 do
      local attachments = swapchainImageViews + i
      local framebufferInfos = ffi.new('VkFramebufferCreateInfo[1]')
      local framebufferInfo = framebufferInfos[0]
      framebufferInfo.sType = vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
      framebufferInfo.renderPass = self.renderPass[0]
      framebufferInfo.attachmentCount = 1
      framebufferInfo.pAttachments = attachments
      framebufferInfo.width = self.swapchainExtent.width
      framebufferInfo.height = self.swapchainExtent.height
      framebufferInfo.layers = 1
      if vk.vkCreateFramebuffer(device, framebufferInfos, nil, self.swapchainFramebuffers + i) ~= 0 then
         error('gpu: vkCreateFramebuffer failed')
      end
   end

   local poolInfos = ffi.new('VkCommandPoolCreateInfo[1]')
   local poolInfo = poolInfos[0]
   poolInfo.sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
   poolInfo.flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
   poolInfo.queueFamilyIndex = graphicsQueueFamilyIndex
   local commandPools = ffi.new('VkCommandPool[1]')
   if vk.vkCreateCommandPool(device, poolInfos, nil, commandPools) ~= 0 then
      error('gpu: vkCreateCommandPool failed')
   end
   local commandPool = commandPools[0]
   self.commandPool = commandPool

   local allocInfos = ffi.new('VkCommandBufferAllocateInfo[1]')
   local allocInfo = allocInfos[0]
   allocInfo.sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
   allocInfo.commandPool = commandPool
   allocInfo.level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY
   allocInfo.commandBufferCount = 1
   self.commandBuffers = ffi.new('VkCommandBuffer[1]')
   if vk.vkAllocateCommandBuffers(device, allocInfos, self.commandBuffers) ~= 0 then
      error('gpu: vkAllocateCommandBuffers failed')
   end
   self.commandBuffer = self.commandBuffers[0]

   local semaphoreInfos = ffi.new('VkSemaphoreCreateInfo[1]')
   local semaphoreInfo = semaphoreInfos[0]
   semaphoreInfo.sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
   local fenceInfos = ffi.new('VkFenceCreateInfo[1]')
   local fenceInfo = fenceInfos[0]
   fenceInfo.sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
   fenceInfo.flags = vk.VK_FENCE_CREATE_SIGNALED_BIT
   self.imageAvailableSemaphores = ffi.new('VkSemaphore[1]')
   self.renderFinishedSemaphores = ffi.new('VkSemaphore[1]')
   self.inFlightFences = ffi.new('VkFence[1]')
   if vk.vkCreateSemaphore(device, semaphoreInfos, nil, self.imageAvailableSemaphores) ~= 0 then
      error('gpu: vkCreateSemaphore failed')
   end
   self.imageAvailableSemaphore = self.imageAvailableSemaphores[0]
   if vk.vkCreateSemaphore(device, semaphoreInfos, nil, self.renderFinishedSemaphores) ~= 0 then
      error('gpu: vkCreateSemaphore failed')
   end
   self.renderFinishedSemaphore = self.renderFinishedSemaphores[0]
   if vk.vkCreateFence(device, fenceInfos, nil, self.inFlightFences) ~= 0 then
      error('gpu: vkCreateFence failed')
   end
   self.inFlightFence = self.inFlightFences[0]

   self.imageIndexPtr = ffi.new('uint32_t[1]')
end

function Gpu:InitImageManagement()
   local bindings = ffi.new('VkDescriptorSetLayoutBinding[1]')
   bindings[0].binding = 0
   bindings[0].descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
   bindings[0].descriptorCount = self:GetMaxImages()
   bindings[0].stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT

   local createInfo = ffi.new('VkDescriptorSetLayoutCreateInfo')
   createInfo.sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
   createInfo.bindingCount = 1
   createInfo.pBindings = bindings

   self.imageDescriptorSetLayoutPtr = ffi.new('VkDescriptorSetLayout[1]')
   vk.vkCreateDescriptorSetLayout(self.device, createInfo, nil, self.imageDescriptorSetLayoutPtr)
   self.imageDescriptorSetLayout = self.imageDescriptorSetLayoutPtr[0]

   local descriptorPool = ffi.new('VkDescriptorPool[1]')
   local poolSize = ffi.new('VkDescriptorPoolSize')
   poolSize.type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
   poolSize.descriptorCount = 512

   local poolInfo = ffi.new('VkDescriptorPoolCreateInfo')
   poolInfo.sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
   poolInfo.poolSizeCount = 1
   poolInfo.pPoolSizes = poolSize
   poolInfo.maxSets = 100
   assert(vk.vkCreateDescriptorPool(self.device, poolInfo, nil, descriptorPool) == 0)

   self.imageDescriptorSetPtr = ffi.new('VkDescriptorSet[1]')
   local allocInfo = ffi.new('VkDescriptorSetAllocateInfo')
   allocInfo.sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
   allocInfo.descriptorPool = descriptorPool[0]
   allocInfo.descriptorSetCount = 1
   allocInfo.pSetLayouts = self.imageDescriptorSetLayoutPtr

   vk.vkAllocateDescriptorSets(self.device, allocInfo, self.imageDescriptorSetPtr)
   self.imageDescriptorSet = self.imageDescriptorSetPtr[0]

   self._nextImageHandle = 0
end

function Gpu:CopyImageToGpu(im)
   local imageHandle = self._nextImageHandle
   self._nextImageHandle = imageHandle + 1

   local block = {
      imageHandle = imageHandle,
      textureImage = ffi.new('VkImage[1]'),
      textureImageMemory = ffi.new('VkDeviceMemory[1]'),
      textureImageView = ffi.new('VkImageView[1]'),
      textureSampler = ffi.new('VkSampler[1]')
   }

   local function findMemoryType(typeFilter, properties)
      local memProperties = ffi.new('VkPhysicalDeviceMemoryProperties')
      vk.vkGetPhysicalDeviceMemoryProperties(self.physicalDevice, memProperties)

      for i = 0, memProperties.memoryTypeCount - 1 do
         if bit.band(typeFilter, bit.lshift(1, i)) ~= 0 and bit.band(memProperties.memoryTypes[i].propertyFlags, properties) == properties then
            return i
         end
      end
      error('Gpu: findMemoryType failed')
   end
   local function createBuffer(size, usage, properties, buffer, bufferMemory)
      local bufferInfo = ffi.new('VkBufferCreateInfo')
      bufferInfo.sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
      bufferInfo.size = size
      bufferInfo.usage = usage
      bufferInfo.sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE

      assert(vk.vkCreateBuffer(self.device, bufferInfo, nil, buffer) == 0)

      local memRequirements = ffi.new('VkMemoryRequirements')
      vk.vkGetBufferMemoryRequirements(self.device, buffer[0], memRequirements)

      local allocInfo = ffi.new('VkMemoryAllocateInfo')
      allocInfo.sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
      allocInfo.allocationSize = memRequirements.size
      allocInfo.memoryTypeIndex = findMemoryType(memRequirements.memoryTypeBits, properties)

      assert(vk.vkAllocateMemory(self.device, allocInfo, nil, bufferMemory) == 0)
      vk.vkBindBufferMemory(self.device, buffer[0], bufferMemory[0], 0)
   end
   local function createImage(width, height, format, tiling, usage, properties, image, imageMemory)
      local imageInfo = ffi.new("VkImageCreateInfo")
      imageInfo.sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
      imageInfo.imageType = vk.VK_IMAGE_TYPE_2D
      imageInfo.extent.width = width
      imageInfo.extent.height = height
      imageInfo.extent.depth = 1
      imageInfo.mipLevels = 1
      imageInfo.arrayLayers = 1
      imageInfo.format = format
      imageInfo.tiling = tiling
      imageInfo.initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED
      imageInfo.usage = usage
      imageInfo.samples = vk.VK_SAMPLE_COUNT_1_BIT
      imageInfo.sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE

      assert(vk.vkCreateImage(self.device, imageInfo, nil, image) == 0)

      local memRequirements = ffi.new("VkMemoryRequirements")
      vk.vkGetImageMemoryRequirements(self.device, image[0], memRequirements)

      local allocInfo = ffi.new("VkMemoryAllocateInfo")
      allocInfo.sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
      allocInfo.allocationSize = memRequirements.size
      allocInfo.memoryTypeIndex = findMemoryType(memRequirements.memoryTypeBits, properties)

      assert(vk.vkAllocateMemory(self.device, allocInfo, nil, imageMemory) == 0)
      vk.vkBindImageMemory(self.device, image[0], imageMemory[0], 0)
   end
   local function beginSingleTimeCommands()
      local allocInfo = ffi.new("VkCommandBufferAllocateInfo", {
         sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
         level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
         commandPool = self.commandPool,
         commandBufferCount = 1
      })

      local commandBuffer = ffi.new("VkCommandBuffer[1]")
      assert(vk.vkAllocateCommandBuffers(self.device, allocInfo, commandBuffer) == 0)

      local beginInfo = ffi.new("VkCommandBufferBeginInfo", {
         sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
         flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
      })

      assert(vk.vkBeginCommandBuffer(commandBuffer[0], beginInfo) == 0)

      return commandBuffer[0]
   end
   local function endSingleTimeCommands(commandBuffer)
      assert(vk.vkEndCommandBuffer(commandBuffer) == 0)

      local submitInfo = ffi.new("VkSubmitInfo", {
         sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
         commandBufferCount = 1,
         pCommandBuffers = commandBuffer
      })

      assert(vk.vkQueueSubmit(graphicsQueue, 1, submitInfo, vk.VK_NULL_HANDLE) == 0)
      assert(vk.vkQueueWaitIdle(graphicsQueue) == 0)

      vk.vkFreeCommandBuffers(self.device, self.commandPool, 1, commandBuffer)
   end
   local function transitionImageLayout(image, format, oldLayout, newLayout)
      local commandBuffer = beginSingleTimeCommands()

      local barrier = ffi.new("VkImageMemoryBarrier")
      barrier.sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
      barrier.oldLayout = oldLayout
      barrier.newLayout = newLayout
      barrier.srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED
      barrier.dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED
      barrier.image = image[0]
      barrier.subresourceRange = {
         aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
         baseMipLevel = 0,
         levelCount = 1,
         baseArrayLayer = 0,
         layerCount = 1
      }

      local sourceStage, destinationStage
      if oldLayout == vk.VK_IMAGE_LAYOUT_UNDEFINED and newLayout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL then
         barrier.srcAccessMask = 0
         barrier.dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT
         sourceStage = vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT
         destinationStage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT
      elseif oldLayout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and newLayout == vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL then
         barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT
         barrier.dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT
         sourceStage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT
         destinationStage = vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT
      else
         error()
      end

      vk.vkCmdPipelineBarrier(commandBuffer,
         sourceStage, destinationStage,
         0,
         0, nil,
         0, nil,
         1, barrier)

      endSingleTimeCommands(commandBuffer)
   end

   -- TODO: Image must be RGBA.

   local size = im.width * im.height * 4

   local stagingBuffer = ffi.new("VkBuffer[1]")
   local stagingBufferMemory = ffi.new("VkDeviceMemory[1]")
   createBuffer(size, vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
      vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT + vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
      stagingBuffer, stagingBufferMemory)

   createImage(im.width, im.height,
      vk.VK_FORMAT_R8G8B8A8_SRGB, vk.VK_IMAGE_TILING_OPTIMAL,
      vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT + vk.VK_IMAGE_USAGE_SAMPLED_BIT,
      vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
      block.textureImage, block.textureImageMemory)

   local viewInfo = ffi.new("VkImageViewCreateInfo", {
      sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
      image = block.textureImage[0],
      viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
      format = vk.VK_FORMAT_R8G8B8A8_SRGB,
      subresourceRange = {
         aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
         baseMipLevel = 0,
         levelCount = 1,
         baseArrayLayer = 0,
         layerCount = 1
      }
   })
   assert(vk.vkCreateImageView(self.device, viewInfo, nil, block.textureImageView) == 0)

   local samplerInfo = ffi.new("VkSamplerCreateInfo", {
      sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
      magFilter = vk.VK_FILTER_LINEAR,
      minFilter = vk.VK_FILTER_LINEAR,
      addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_REPEAT,
      addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_REPEAT,
      addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_REPEAT,
      anisotropyEnable = vk.VK_FALSE,
      borderColor = vk.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
      unnormalizedCoordinates = vk.VK_FALSE,
      compareEnable = vk.VK_FALSE,
      compareOp = vk.VK_COMPARE_OP_ALWAYS,
      mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_LINEAR,
      mipLodBias = 0.0,
      minLod = 0.0,
      maxLod = 0.0
   })
   assert(vk.vkCreateSampler(self.device, samplerInfo, nil, block.textureSampler) == 0)

   local data = ffi.new("void*[1]")
   assert(vk.vkMapMemory(self.device, stagingBufferMemory[0], 0, size, 0, data) == 0)
   ffi.copy(data, im.data, size)
   vk.vkUnmapMemory(self.device, stagingBufferMemory[0])

   transitionImageLayout(block.textureImage, vk.VK_FORMAT_R8G8B8A8_SRGB,
      vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)

   local commandBuffer = beginSingleTimeCommands()

   local region = ffi.new("VkBufferImageCopy", {
      bufferOffset = 0,
      bufferRowLength = 0,
      bufferImageHeight = 0,
      imageSubresource = {
         aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
         mipLevel = 0,
         baseArrayLayer = 0,
         layerCount = 1
      },
      imageOffset = ffi.new("VkOffset3D", {0, 0, 0}),
      imageExtent = ffi.new("VkExtent3D", {im.width, im.height, 1})
   })

   vk.vkCmdCopyBufferToImage(commandBuffer, stagingBuffer[0], block.textureImage,
      vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, region)

   endSingleTimeCommands(commandBuffer)

   transitionImageLayout(block.textureImage, vk.VK_FORMAT_R8G8B8A8_SRGB,
      vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)

   vk.vkDestroyBuffer(self.device, stagingBuffer[0], nil)
   vk.vkFreeMemory(self.device, stagingBufferMemory[0], nil)

   self.didInitializeDescriptors = false
   local imageInfo = ffi.new("VkDescriptorImageInfo", {
      imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      imageView = block.textureImageView,
      sampler = block.textureSampler
   })

   if not self.didInitializeDescriptors then
      local descriptorWrites = ffi.new("VkWriteDescriptorSet[?]", getMaxImages())
      for i = 0, self:GetMaxImages() - 1 do
         descriptorWrites[i].sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
         descriptorWrites[i].dstSet = self.imageDescriptorSet
         descriptorWrites[i].dstBinding = 0
         descriptorWrites[i].dstArrayElement = i
         descriptorWrites[i].descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
         descriptorWrites[i].descriptorCount = 1
         descriptorWrites[i].pImageInfo = imageInfo
      end
      vk.vkUpdateDescriptorSets(self.device, self:GetMaxImages(), descriptorWrites, 0, nil)
      didInitializeDescriptors = true
   else
      local descriptorWrite = ffi.new("VkWriteDescriptorSet", {
         sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
         dstSet = imageDescriptorSet,
         dstBinding = 0,
         dstArrayElement = imageId,
         descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
         descriptorCount = 1,
         pImageInfo = imageInfo
      })
      vk.vkUpdateDescriptorSets(self.device, 1, descriptorWrite, 0, nil)
   end

   return imageHandle
end

function Gpu:CreatePipeline(vertShaderModule, fragShaderModule)
   local shaderStages = ffi.new('VkPipelineShaderStageCreateInfo[2]')
   local vertShaderStageInfo = shaderStages[0]
   vertShaderStageInfo.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
   vertShaderStageInfo.stage = vk.VK_SHADER_STAGE_VERTEX_BIT
   vertShaderStageInfo.module = vertShaderModule
   vertShaderStageInfo.pName = "main"

   local fragShaderStageInfo = shaderStages[1]
   fragShaderStageInfo.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
   fragShaderStageInfo.stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT
   fragShaderStageInfo.module = fragShaderModule
   fragShaderStageInfo.pName = "main"

   local vertexInputInfos = ffi.new('VkPipelineVertexInputStateCreateInfo[1]')
   local vertexInputInfo = vertexInputInfos[0]
   vertexInputInfo.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
   vertexInputInfo.vertexBindingDescriptionCount = 0
   vertexInputInfo.vertexAttributeDescriptionCount = 0

   local inputAssemblys = ffi.new('VkPipelineInputAssemblyStateCreateInfo[1]')
   local inputAssembly = inputAssemblys[0]
   inputAssembly.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
   -- We're just going to draw a quad (4 vertices -> first 3
   -- vertices are top-left triangle, last 3 vertices are
   -- bottom-right triangle).
   inputAssembly.topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP
   inputAssembly.primitiveRestartEnable = vk.VK_FALSE

   local viewports = ffi.new('VkViewport[1]')
   local viewport = viewports[0]
   viewport.x = 0.0
   viewport.y = 0.0
   viewport.width = self.swapchainExtent.width
   viewport.height = self.swapchainExtent.height
   viewport.minDepth = 0.0
   viewport.maxDepth = 1.0

   local scissors = ffi.new('VkRect2D[1]')
   local scissor = scissors[0]
   scissor.offset.x = 0
   scissor.offset.y = 0
   scissor.extent = self.swapchainExtent

   local viewportStates = ffi.new('VkPipelineViewportStateCreateInfo[1]')
   local viewportState = viewportStates[0]
   viewportState.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
   viewportState.viewportCount = 1
   viewportState.pViewports = viewports
   viewportState.scissorCount = 1
   viewportState.pScissors = scissors

   local rasterizers = ffi.new('VkPipelineRasterizationStateCreateInfo[1]')
   local rasterizer = rasterizers[0]
   rasterizer.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
   rasterizer.depthClampEnable = vk.VK_FALSE
   rasterizer.rasterizerDiscardEnable = vk.VK_FALSE
   rasterizer.polygonMode = vk.VK_POLYGON_MODE_FILL
   rasterizer.lineWidth = 1.0
   rasterizer.cullMode = vk.VK_CULL_MODE_BACK_BIT
   rasterizer.frontFace = vk.VK_FRONT_FACE_CLOCKWISE
   rasterizer.depthBiasEnable = vk.VK_FALSE

   local multisamplings = ffi.new('VkPipelineMultisampleStateCreateInfo[1]')
   local multisampling = multisamplings[0]
   multisampling.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
   multisampling.sampleShadingEnable = vk.VK_FALSE
   multisampling.rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT

   local colorBlendAttachments = ffi.new('VkPipelineColorBlendAttachmentState[1]')
   local colorBlendAttachment = colorBlendAttachments[0]
   colorBlendAttachment.colorWriteMask =
      bit.bor(vk.VK_COLOR_COMPONENT_R_BIT,  vk.VK_COLOR_COMPONENT_G_BIT,  vk.VK_COLOR_COMPONENT_B_BIT, 
         vk.VK_COLOR_COMPONENT_A_BIT)
    colorBlendAttachment.blendEnable = vk.VK_TRUE
    colorBlendAttachment.srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA
    colorBlendAttachment.dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
    colorBlendAttachment.colorBlendOp = vk.VK_BLEND_OP_ADD
    colorBlendAttachment.srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE
    colorBlendAttachment.dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO
    colorBlendAttachment.alphaBlendOp = vk.VK_BLEND_OP_ADD

    local colorBlendings = ffi.new('VkPipelineColorBlendStateCreateInfo[1]')
    local colorBlending = colorBlendings[0]
    colorBlending.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
    colorBlending.logicOpEnable = vk.VK_FALSE
    colorBlending.logicOp = vk.VK_LOGIC_OP_COPY
    colorBlending.attachmentCount = 1
    colorBlending.pAttachments = colorBlendAttachments

    local pipelineLayoutInfo = ffi.new('VkPipelineLayoutCreateInfo')
    pipelineLayoutInfo.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
    pipelineLayoutInfo.pSetLayouts = self.imageDescriptorSetLayoutPtr
    pipelineLayoutInfo.setLayoutCount = 1

    -- We configure all pipelines with push constants size = 128 (the
    -- maximum), no matter what actual push constants they take; this
    -- is so that pipelines are all layout-compatible so we can reuse
    -- descriptor set between pipelines without needing to rebind it.
    local pushConstantRange = ffi.new('VkPushConstantRange')
    pushConstantRange.offset = 0;
    pushConstantRange.size = 128;
    pushConstantRange.stageFlags = bit.bor(vk.VK_SHADER_STAGE_VERTEX_BIT, vk.VK_SHADER_STAGE_FRAGMENT_BIT)
    pipelineLayoutInfo.pPushConstantRanges = pushConstantRange
    pipelineLayoutInfo.pushConstantRangeCount = 1

    local pipelineLayouts = ffi.new('VkPipelineLayout[1]')
    if vk.vkCreatePipelineLayout(self.device, pipelineLayoutInfo, nil, pipelineLayouts) ~= 0 then
       error('gpu: vkCreatePipelineLayout failed')
    end
    local pipelineLayout = pipelineLayouts[0]

    local pipeline = ffi.new('VkPipeline[1]')

    local pipelineInfo = ffi.new('VkGraphicsPipelineCreateInfo')
    pipelineInfo.sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO
    pipelineInfo.stageCount = 2
    pipelineInfo.pStages = shaderStages
    pipelineInfo.pVertexInputState = vertexInputInfos
    pipelineInfo.pInputAssemblyState = inputAssemblys
    pipelineInfo.pViewportState = viewportStates
    pipelineInfo.pRasterizationState = rasterizers
    pipelineInfo.pMultisampleState = multisamplings
    pipelineInfo.pDepthStencilState = nil
    pipelineInfo.pColorBlendState = colorBlendings
    pipelineInfo.pDynamicState = nil
    pipelineInfo.layout = pipelineLayout
    pipelineInfo.renderPass = self.renderPass[0]
    pipelineInfo.subpass = 0
    pipelineInfo.basePipelineHandle = 0 -- VK_NULL_HANDLE
    pipelineInfo.basePipelineIndex = -1

    if vk.vkCreateGraphicsPipelines(self.device, 0, 1, pipelineInfo, nil, pipeline) ~= 0 then
       error('gpu: vkCreateGraphicsPipelines failed')
    end

    return {
       pipeline = pipeline[0],
       pipelineLayout = pipelineLayout
    }
end

function Gpu:CreateShaderModule(spirv)
   -- print("spirv", table.concat(spirv, ' '), 'elements', #spirv)

   local createInfo = ffi.new('VkShaderModuleCreateInfo')
   createInfo.sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
   createInfo.codeSize = #spirv * 4
   createInfo.pCode = ffi.new('uint32_t[?]', #spirv, spirv)

   local shaderModules = ffi.new('VkShaderModule[1]')
   if vk.vkCreateShaderModule(self.device, createInfo, nil, shaderModules) ~= 0 then
      error('gpu: vkCreateShaderModule failed')
   end
   return shaderModules[0]
end

local function glslc(glsl, ...)
   local n = os.tmpname()
   local f = io.open(n..'.glsl', 'w')
   f:write(glsl); f:close()

   local argv = {'glslc', ..., '-mfmt=num',
      '-o', n..'.num',
      n..'.glsl'
   }
   local ret = os.execute(table.concat(argv, ' '))
   assert(ret == 0)

   local f = io.open(n..'.num', 'r')
   local nums = f:read('*a'); f:close()

   local spirv = {}
   for token in string.gmatch(nums, '([^,\n]+)') do
      table.insert(spirv, tonumber(token))
   end
   return spirv
end
local _pipelineNum = 0
ffi.cdef [[
typedef struct vec2 { float x; float y; } vec2;
typedef struct vec3 { float x; float y; float z; } vec3;
typedef struct vec4 { float x; float y; float z; float w; } vec4;
]]
function Gpu:CompilePipelineFromShaders(vert, frag)
   -- FIXME: assumes vert and frag are the same.
   local fields = vert:match("layout%(push_constant%) uniform Args%s*{(.-)}%s*args;")
   fields = fields:gsub("([^%w])vec4([^%w])", "%1__declspec(align(sizeof(vec4))) vec4%2")
   fields = fields:gsub("([^%w])vec3([^%w])", "%1__declspec(align(sizeof(vec3))) vec3%2")
   local structName = "Args".._pipelineNum
   ffi.cdef([[typedef struct ]]..structName..[[ {]]..fields..
      [[} ]]..structName..[[;]])
   _pipelineNum = _pipelineNum + 1

   local vertShaderModule = self:CreateShaderModule(glslc(vert, '-fshader-stage=vert'))
   local fragShaderModule = self:CreateShaderModule(glslc(frag, '-fshader-stage=frag'))

   local pipeline = self:CreatePipeline(vertShaderModule, fragShaderModule)
   pipeline.structName = structName
   return pipeline
end

function Gpu:DrawStart()
   vk.vkWaitForFences(self.device, 1, self.inFlightFences, vk.VK_TRUE, -1ULL)
   vk.vkResetFences(self.device, 1, self.inFlightFences)

   vk.vkAcquireNextImageKHR(self.device, self.swapchain, -1ULL, self.imageAvailableSemaphore, 0, self.imageIndexPtr)

   vk.vkResetCommandBuffer(self.commandBuffer, 0)

   local beginInfos = ffi.new('VkCommandBufferBeginInfo[1]')
   local beginInfo = beginInfos[0]
   beginInfo.sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
   beginInfo.flags = 0 -- TODO: Should this be one-time?
   beginInfo.pInheritanceInfo = nil
   if vk.vkBeginCommandBuffer(self.commandBuffer, beginInfos) ~= 0 then
      error('gpu: vkBeginCommandBuffer failed')
   end

   local renderPassInfo = ffi.new('VkRenderPassBeginInfo')
   renderPassInfo.sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
   renderPassInfo.renderPass = self.renderPass[0]
   renderPassInfo.framebuffer = self.swapchainFramebuffers[self.imageIndexPtr[0]]
   renderPassInfo.renderArea.offset.x = 0
   renderPassInfo.renderArea.offset.y = 0
   renderPassInfo.renderArea.extent = self.swapchainExtent

   local clearColor = ffi.new('VkClearValue[1]', {{{{0.0, 0.0, 0.0, 1.0}}}})
   renderPassInfo.clearValueCount = 1;
   renderPassInfo.pClearValues = clearColor

   vk.vkCmdBeginRenderPass(self.commandBuffer, renderPassInfo, vk.VK_SUBPASS_CONTENTS_INLINE)

   self.boundPipeline = nil
   self.boundDescriptorSet = nil
end

function Gpu:Draw(pipeline, ...)
   if self.boundPipeline ~= pipeline then
      vk.vkCmdBindPipeline(self.commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
         pipeline.pipeline)
      self.boundPipeline = pipeline
   end

   if self.boundDescriptorSet ~= self.imageDescriptorSet then
      vk.vkCmdBindDescriptorSets(self.commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
         pipeline.pipelineLayout, 0, 1, self.imageDescriptorSetPtr, 0, nil)
      self.boundDescriptorSet = self.imageDescriptorSet
   end

   local pushConstantsData = ffi.new(pipeline.structName, ...)
   vk.vkCmdPushConstants(self.commandBuffer, pipeline.pipelineLayout,
      bit.bor(vk.VK_SHADER_STAGE_VERTEX_BIT, vk.VK_SHADER_STAGE_FRAGMENT_BIT), 0,
      ffi.sizeof(pipeline.structName), pushConstantsData)

   -- 1 quad -> 2 triangles -> 4 vertices
   vk.vkCmdDraw(self.commandBuffer, 4, 1, 0, 0)
end

function Gpu:DrawEnd()
   vk.vkCmdEndRenderPass(self.commandBuffer)
   assert(vk.vkEndCommandBuffer(self.commandBuffer) == 0)

   local submitInfos = ffi.new('VkSubmitInfo[1]')
   local submitInfo = submitInfos[0]
   submitInfo.sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO

   local waitStages = ffi.new('VkPipelineStageFlags[1]', vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)
   submitInfo.waitSemaphoreCount = 1
   submitInfo.pWaitSemaphores = self.imageAvailableSemaphores
   submitInfo.pWaitDstStageMask = waitStages;

   submitInfo.commandBufferCount = 1
   submitInfo.pCommandBuffers = self.commandBuffers

   submitInfo.signalSemaphoreCount = 1
   submitInfo.pSignalSemaphores = self.renderFinishedSemaphores

   assert(vk.vkQueueSubmit(self.graphicsQueue, 1, submitInfos, self.inFlightFence) == 0)

   local presentInfos = ffi.new('VkPresentInfoKHR[1]')
   local presentInfo = presentInfos[0]
   presentInfo.sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR
   presentInfo.waitSemaphoreCount = 1
   presentInfo.pWaitSemaphores = self.renderFinishedSemaphores

   presentInfo.swapchainCount = 1
   presentInfo.pSwapchains = self.swapchains
   presentInfo.pImageIndices = self.imageIndexPtr
   presentInfo.pResults = nil

   vk.vkQueuePresentKHR(self.presentQueue, presentInfos)
end

Gpu.glfw = glfw
return Gpu
