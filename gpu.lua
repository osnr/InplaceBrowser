package.path = package.path .. ";./vendor/luajit-glfw/?.lua;./vendor/vulkan/?.lua"

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

local renderPass = ffi.new('VkRenderPass[1]')
if vk.vkCreateRenderPass(device[0], renderPassInfos, nil, renderPass) ~= 0 then
   error('gpu: vkCreateRenderPass failed')
end

local swapchainFramebuffers = ffi.new('VkFramebuffer[?]', swapchainImageCount[0])
for i = 0, swapchainImageCount[0] - 1 do
   local attachments = swapchainImageViews + i
   local framebufferInfos = ffi.new('VkFramebufferCreateInfo[1]')
   local framebufferInfo = framebufferInfos[0]
   framebufferInfo.sType = vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
   framebufferInfo.renderPass = renderPass[0]
   framebufferInfo.attachmentCount = 1
   framebufferInfo.pAttachments = attachments
   framebufferInfo.width = swapchainExtent.width
   framebufferInfo.height = swapchainExtent.height
   framebufferInfo.layers = 1
   if vk.vkCreateFramebuffer(device[0], framebufferInfos, nil, swapchainFramebuffers + i) ~= 0 then
      error('gpu: vkCreateFramebuffer failed')
   end
end

local poolInfos = ffi.new('VkCommandPoolCreateInfo[1]')
local poolInfo = poolInfos[0]
poolInfo.sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
poolInfo.flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
poolInfo.queueFamilyIndex = graphicsQueueFamilyIndex
local commandPools = ffi.new('VkCommandPool[1]')
if vk.vkCreateCommandPool(device[0], poolInfos, nil, commandPools) ~= 0 then
   error('gpu: vkCreateCommandPool failed')
end
local commandPool = commandPools[0]

local allocInfos = ffi.new('VkCommandBufferAllocateInfo[1]')
local allocInfo = allocInfos[0]
allocInfo.sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
allocInfo.commandPool = commandPool
allocInfo.level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY
allocInfo.commandBufferCount = 1
local commandBuffers = ffi.new('VkCommandBuffer[1]')
if vk.vkAllocateCommandBuffers(device[0], allocInfos, commandBuffers) ~= 0 then
   error('gpu: vkAllocateCommandBuffers failed')
end
local commandBuffer = commandBuffers[0]

local semaphoreInfos = ffi.new('VkSemaphoreCreateInfo[1]')
local semaphoreInfo = semaphoreInfos[0]
semaphoreInfo.sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
local fenceInfos = ffi.new('VkFenceCreateInfo[1]')
local fenceInfo = fenceInfos[0]
fenceInfo.sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
fenceInfo.flags = vk.VK_FENCE_CREATE_SIGNALED_BIT
local imageAvailableSemaphores = ffi.new('VkSemaphore[1]')
local renderFinishedSemaphores = ffi.new('VkSemaphore[1]')
local inFlightFences = ffi.new('VkFence[1]')
if vk.vkCreateSemaphore(device[0], semaphoreInfos, nil, imageAvailableSemaphores) ~= 0 then
   error('gpu: vkCreateSemaphore failed')
end
if vk.vkCreateSemaphore(device[0], semaphoreInfos, nil, renderFinishedSemaphores) ~= 0 then
   error('gpu: vkCreateSemaphore failed')
end
if vk.vkCreateFence(device[0], fenceInfos, nil, inFlightFences) ~= 0 then
   error('gpu: vkCreateFence failed')
end

-------

local function createPipeline(vertShaderModule, fragShaderModule)
   local shaderStages = ffi.new('VkPipelineShaderStageCreateInfo[2]')
   vertShaderStageInfo = shaderStages[0]
   vertShaderStageInfo.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
   vertShaderStageInfo.stage = vk.VK_SHADER_STAGE_VERTEX_BIT
   vertShaderStageInfo.module = vertShaderModule
   vertShaderStageInfo.pName = "main"

   fragShaderStageInfo = shaderStages[1]
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
   viewport.width = swapchainExtent.width
   viewport.height = swapchainExtent.height
   viewport.minDepth = 0.0
   viewport.maxDepth = 1.0

   local scissors = ffi.new('VkRect2D[1]')
   local scissor = scissors[0]
   scissor.offset.x = 0
   scissor.offset.y = 0
   scissor.extent = swapchainExtent

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

    local pipelineLayoutInfos = ffi.new('VkPipelineLayoutCreateInfo[1]')
    local pipelineLayoutInfo = pipelineLayoutInfos[0]
    pipelineLayoutInfo.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
    pipelineLayoutInfo.pSetLayouts = nil -- imageDescriptorSetLayouts
    pipelineLayoutInfo.setLayoutCount = 0 -- 1

    -- We configure all pipelines with push constants size = 128 (the
    -- maximum), no matter what actual push constants they take; this
    -- is so that pipelines are all layout-compatible so we can reuse
    -- descriptor set between pipelines without needing to rebind it.
    local pushConstantRanges = ffi.new('VkPushConstantRange[1]')
    local pushConstantRange = pushConstantRanges[0]
    pushConstantRange.offset = 0;
    pushConstantRange.size = 128;
    pushConstantRange.stageFlags = bit.bor(vk.VK_SHADER_STAGE_VERTEX_BIT, vk.VK_SHADER_STAGE_FRAGMENT_BIT)
    pipelineLayoutInfo.pPushConstantRanges = pushConstantRanges
    pipelineLayoutInfo.pushConstantRangeCount = 1

    local pipelineLayouts = ffi.new('VkPipelineLayout[1]')
    if vk.vkCreatePipelineLayout(device[0], pipelineLayoutInfos, nil, pipelineLayouts) ~= 0 then
       error('gpu: vkCreatePipelineLayout failed')
    end
    local pipelineLayout = pipelineLayouts[0]

    local pipelines = ffi.new('VkPipeline[1]')

    local pipelineInfos = ffi.new('VkGraphicsPipelineCreateInfo[1]')
    local pipelineInfo = pipelineInfos[0]
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
    pipelineInfo.renderPass = renderPass[0]
    pipelineInfo.subpass = 0
    pipelineInfo.basePipelineHandle = 0 -- VK_NULL_HANDLE
    pipelineInfo.basePipelineIndex = -1

    if vk.vkCreateGraphicsPipelines(device[0], 0, 1, pipelineInfos, nil, pipelines) ~= 0 then
       error('gpu: vkCreateGraphicsPipelines failed')
    end

    -- FIXME: return pipeline design
end

-------

local function createShaderModule(spirv)
   local createInfos = ffi.new('VkShaderModuleCreateInfo[1]')
   local createInfo = createInfos[0]
   createInfo.sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
   createInfo.codeSize = #spirv * 4
   createInfo.pCode = ffi.new('uint32_t[?]', #spirv, spirv)

   local shaderModules = ffi.new('VkShaderModule[1]')
   if vk.vkCreateShaderModule(device[0], createInfos, nil, shaderModules) ~= 0 then
      error('gpu: vkCreateShaderModule failed')
   end
   return shaderModules[0]
end

local function glslc(glsl, ...)
   local n = os.tmpname()..'.glsl'
   local f = io.open(n, 'w')
   f:write(glsl); f:close()

   local argv = {'glslc', ..., '-mfmt=num -o -', n}
   local task = io.popen(table.concat(argv, ' '), 'r')
   local nums = task:read('*a'); task:close()
   local spirv = {}
   for token in string.gmatch(nums, '([^,\n]+)') do
      table.insert(spirv, tonumber(token))
   end
   return spirv
end
local function CompilePipelineFromShaders(vert, frag)
   local vertShaderModule = createShaderModule(glslc(vert, '-fshader-stage=vert'))
   local fragShaderModule = createShaderModule(glslc(frag, '-fshader-stage=frag'))
   return createPipeline(vertShaderModule, fragShaderModule)
end

return {
   glfw = glfw,
   window = window,
   CompilePipelineFromShaders = CompilePipelineFromShaders
}
