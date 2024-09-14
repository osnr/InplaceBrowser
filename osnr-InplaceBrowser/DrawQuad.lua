local quadPrelude = [[
    #version 450

    layout(push_constant) uniform Args {
        vec2 _resolution;

        vec2 a;
        vec2 b;
        vec2 c;
        vec2 d;
        vec4 color;
    } args;
]]
local quadVert = quadPrelude..[[
    void main() {
        vec2 vertices[4] = vec2[4](args.a, args.b, args.d, args.c);
        vec2 v = vertices[gl_VertexIndex];

        v = (2.0*v - args._resolution)/args._resolution;
        gl_Position = vec4(v, 0.0, 1.0);
    }
]]
local quadFrag = quadPrelude..[[
    layout(location = 0) out vec4 outColor;

    void main() {
        outColor = args.color;
    }
]]

return function(gpu)
   local quadPipeline = gpu:CompilePipelineFromShaders(quadVert, quadFrag)
   local w, h = gpu.glfw.GetWindowSize(gpu.window)
   return function(...)
      gpu:Draw(quadPipeline, {w, h}, ...)
   end
end
