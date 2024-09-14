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

    layout(location = 0) out vec4 outColor;

    float cross2d(vec2 a, vec2 b) {
        return a.x*b.y - a.y*b.x;
    }
    vec2 invBilinear(vec2 p, vec2 a, vec2 b, vec2 c, vec2 d) {
        vec2 res = vec2(-1.0);

        vec2 e = b-a;
        vec2 f = d-a;
        vec2 g = a-b+c-d;
        vec2 h = p-a;

        float k2 = cross2d( g, f );
        float k1 = cross2d( e, f ) + cross2d( h, g );
        float k0 = cross2d( h, e );

        // if edges are parallel, this is a linear equation
        k2 /= k0; k1 /= k0; k0 = 1.0;
        if(  abs(k2)<0.001*abs(k0) )
        {
            res = vec2( (h.x*k1+f.x*k0)/(e.x*k1-g.x*k0), -k0/k1 );
        }
        // otherwise, it's a quadratic
        else
        {
            float w = k1*k1 - 4.0*k0*k2;
            if( w<0.0 ) return vec2(-1.0);
            w = sqrt( w );

            float ik2 = 0.5/k2;
            float v = (-k1 - w)*ik2;
            float u = (h.x - f.x*v)/(e.x + g.x*v);

            if( u<0.0 || u>1.0 || v<0.0 || v>1.0 )
            {
                v = (-k1 + w)*ik2;
                u = (h.x - f.x*v)/(e.x + g.x*v);
            }
            res = vec2( u, v );
        }
        return res;
    }
    float median(float r, float g, float b) {
        return max(min(r, g), min(max(r, g), b));
    }
    vec4 glyphMsd(sampler2D atlas, vec4 atlasGlyphBounds, vec2 glyphUv) {
        vec2 atlasUv = mix(atlasGlyphBounds.xw, atlasGlyphBounds.zy, glyphUv);
        return texture(atlas, vec2(atlasUv.x, 1.0-atlasUv.y));
    }
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

        vec2 glyphUv = invBilinear(gl_FragCoord.xy, a, b, c, d);
        if( max( abs(glyphUv.x-0.5), abs(glyphUv.y-0.5))>=0.5 ) {
            outColor = vec4(0, 0, 0, 0);
        } else {
            vec3 msd = glyphMsd(samplers[args.atlas], args.atlasGlyphBounds/args.atlasSize.xyxy, glyphUv).rgb;
            // https://blog.mapbox.com/drawing-text-with-signed-distance-fields-in-mapbox-gl-b0933af6f817
            float sd = median(msd.r, msd.g, msd.b);
            float uBuffer = 0.2;
            float uGamma = 0.2;
            float opacity = smoothstep(uBuffer - uGamma, uBuffer + uGamma, sd);
            outColor = vec4(args.color.rgb, opacity * args.color.a);
        }
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
