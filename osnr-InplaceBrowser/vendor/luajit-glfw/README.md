# Features
 - Full support of 3.4.0 API (except native functions)
 - Supports both Luajit and Lua with luaffi
 - Additional OO style for monitors, windows, and cursors
```lua
 glfw.ShowWindow(window)
 -- or
 window:Show()
```
 - Constants can be used in two ways
```lua
 glfw.GetKey(window, GLFW.KEY_SPACE)
 -- or
 glfw.GetKey(window, 'KEY_SPACE')
```

# Differences from the C API
Binding is so close to the original API as possible, but some things still differ.
 1. Names lost 'glfw' prefix.
 2. Arrays of chars replaced by lua string (except joystick buttons).
 3. Arrays of structs and strings replaced by lua tables.
 4. Values returned by reference replaced by returning table or multiple results.
 5. Video mode returned as table. This may change in future if necessary.
 6. Some OO methods have shortened names.

# Start using
Before calling glfw functions you need to initialize binding with library name or path.
Luajit uses dynamic library loading API directly, so behaviour may be different on each OS.
Filename and location of glfw library may also vary.
Several examples:
```lua
-- Windows
local glfw = require 'glfw' ('glfw3')
local glfw = require 'glfw' ('../some/path/glfw3.dll')
-- Linux
local glfw = require 'glfw' ('./libglfw3.so')
local glfw = require 'glfw' ('/usr/local/lib/libglfw3.so')
-- Mac OS X
local glfw = require 'glfw' ('/opt/local/lib/libglfw.3.1.dylib')
```
For statically linked glfw, just skip argument.
```lua
-- Any OS
local glfw = require 'glfw' ()
```
Constants stored in const table. It is recommended to save it in variable with GLFW name.
```lua
local GLFW = glfw.const
```
If you need vulkan-related functions, then specify 'bind_vulkan' option.
Vulkan types MUST be declared (manually or with other binding) before this.
```lua
local glfw = require 'glfw' { 'glfw3',
  bind_vulkan = true
}
```
If you use or want to support Lua+luaffi, then compare pointers with NULL only in this way:
```lua
pointer == GLFW.NULL
```

# Quick example
```lua
local glfw = require 'glfw' ('glfw3')
local GLFW = glfw.const

-- Initialize the library
if glfw.Init() == 0 then
  return
end

-- Create a windowed mode window and its OpenGL context
local window = glfw.CreateWindow(640, 480, "Hello World")
if window == GLFW.NULL then
  glfw.Terminate()
  return
end

-- Make the window's context current
glfw.MakeContextCurrent(window)

-- Loop until the user closes the window
while glfw.WindowShouldClose(window) == 0 do
  -- Render here

  -- Swap front and back buffers
  glfw.SwapBuffers(window)

  -- Poll for and process events
  glfw.PollEvents()
end

glfw.Terminate()
```

# Quick example with OO style
```lua
local glfw = require 'glfw' ('glfw3')
local GLFW = glfw.const

-- Initialize the library
if glfw.Init() == 0 then
  return
end

-- Create a windowed mode window and its OpenGL context
local window = glfw.CreateWindow(640, 480, "Hello World")
if window == GLFW.NULL then
  glfw.Terminate()
  return
end

-- Make the window's context current
window:MakeContextCurrent()

-- Loop until the user closes the window
while window:ShouldClose() == 0 do
  -- Render here

  -- Swap front and back buffers
  window:SwapBuffers()

  -- Poll for and process events
  glfw.PollEvents()
end

glfw.Terminate()
```

# Other examples
```lua
  local version = glfw.GetVersion()
  print(version.major, version.minor, version.rev)

  local monitors = glfw.GetMonitors()
  for i = 1, #monitors do ... end

  local x,y = glfw.GetMonitorPos(monitor)
  local x,y = monitor:GetPos()

  local w,h = glfw.GetMonitorPhysicalSize(monitor)
  local w,h = monitor:GetPhysicalSize()

  local modes = glfw.GetVideoModes(monitor)
  local modes = monitor:GetVideoModes()
  for i = 1, #modes do ... end

  local mode = glfw.GetVideoMode(monitor)
  local mode = monitor:GetVideoMode()
  for k,v in pairs(mode) do
    print(k,v)
  end

  local x,y = glfw.GetWindowPos(window)
  local x,y = window:GetPos()

  local fsize = glfw.GetWindowFrameSize(window)
  local fsize = window:GetFrameSize()
  print(fsize.left, fsize.top, fsize.right, fsize.bottom)

  local axes = glfw.GetJoystickAxes(joy)
  for i = 1, #axes do ... end

```

# Acknowledgements
- Jeremy Lucas ([@jerluc](https://github.com/jerluc))
- pocomane ([@pocomane](https://github.com/pocomane))
