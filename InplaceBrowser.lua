local gpu = require 'gpu'
local glfw = gpu.glfw

local glyphPrelude = [[
#version 450

layout(set = 0, binding = 0) uniform sampler2D samplers[16];
layout(push_constant) uniform Args {
    vec2 _resolution;

    int atlas;
    vec2 atlasSize;
    vec4 atlasGlyphBounds;
    vec4 planeGlyphBounds;
    vec2 pos;
    float radians;
    float em;
    vec4 color;
} args;

vec2 rotate(vec2 v, float a) {
    float s = sin(a);
    float c = cos(a);
    mat2 m = mat2(c, s, -s, c);
    return m * v;
}
]]
local glyphPipeline = gpu.CompilePipelineFromShaders(glyphPrelude..[[
    void main() {
        float em = args.em;
        float radians = args.radians;
        vec2 pos = args.pos;

        float left = args.planeGlyphBounds[0] * em;
        float bottom = args.planeGlyphBounds[1] * em;
        float right = args.planeGlyphBounds[2] * em;
        float top = args.planeGlyphBounds[3] * em;
        vec2 a = pos + rotate(vec2(left, -top), -radians);
        vec2 b = pos + rotate(vec2(right, -top), -radians);
        vec2 c = pos + rotate(vec2(right, -bottom), -radians);
        vec2 d = pos + rotate(vec2(left, -bottom), -radians);

        vec2 vertices[4] = vec2[4](a, b, d, c);
        vec2 v = vertices[gl_VertexIndex];

        v = (2.0*v - args._resolution)/args._resolution;
        gl_Position = vec4(v, 0.0, 1.0);
    }
]], glyphPrelude..[[
    void main() {
        float left = planeGlyphBounds[0] * em;
        float bottom = planeGlyphBounds[1] * em;
        float right = planeGlyphBounds[2] * em;
        float top = planeGlyphBounds[3] * em;
        vec2 a = pos + rotate(vec2(left, -top), -radians);
        vec2 b = pos + rotate(vec2(right, -top), -radians);
        vec2 c = pos + rotate(vec2(right, -bottom), -radians);
        vec2 d = pos + rotate(vec2(left, -bottom), -radians);

        vec2 glyphUv = invBilinear(gl_FragCoord.xy, a, b, c, d);
        if( max( abs(glyphUv.x-0.5), abs(glyphUv.y-0.5))>=0.5 ) {
            return vec4(0, 0, 0, 0);
        }
        vec3 msd = glyphMsd(atlas, atlasGlyphBounds/atlasSize.xyxy, glyphUv).rgb;
        // https://blog.mapbox.com/drawing-text-with-signed-distance-fields-in-mapbox-gl-b0933af6f817
        float sd = median(msd.r, msd.g, msd.b);
        float uBuffer = 0.2;
        float uGamma = 0.2;
        float opacity = smoothstep(uBuffer - uGamma, uBuffer + uGamma, sd);
        outColor = vec4(color.rgb, opacity * color.a);
    }
]])

local window = gpu.window

glfw.MakeContextCurrent(window)
while glfw.WindowShouldClose(window) == 0 do
   -- TODO: Render

   glfw.SwapBuffers(window)
   glfw.PollEvents()
end

glfw.Terminate()
