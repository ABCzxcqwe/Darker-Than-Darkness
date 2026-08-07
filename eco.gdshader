shader_type canvas_item;

uniform vec2 center = vec2(0.5, 0.5);
uniform float force : hint_range(0.0, 0.2) = 0.05;
uniform float size : hint_range(0.0, 1.0) = 0.0;
uniform float thickness = 0.05;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
    vec2 diff = SCREEN_UV - center;
    float dist = length(diff);
    if (dist > size && dist < size + thickness) {
        float delta = (dist - size) / thickness;
        float wave = sin(delta * 3.14159);
        vec2 offset = normalize(diff) * force * wave;
        COLOR = texture(screen_texture, SCREEN_UV + offset);
    } else {
        COLOR = texture(screen_texture, SCREEN_UV);
    }
}
