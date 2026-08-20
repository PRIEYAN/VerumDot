#version 300 es
precision mediump float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;
void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    // Create a vector factor to avoid vector-scalar implicit conversions
    vec3 factor = vec3(float(1.05));
    pixColor.rgb = clamp(pixColor.rgb * factor, vec3(0.0), vec3(1.0));
    fragColor = pixColor;
}
