shader_type canvas_item;

uniform vec2 player_px;
uniform vec2 facing_dir;
uniform float radius_px;
uniform float cone_range_px;
uniform float cone_half_angle; // en radianes
uniform float softness = 40.0;

uniform vec3 fog_color = vec3(0.05, 0.05, 0.06);
uniform float fog_opacity = 0.75; // opacidad max fuera de vision (0=transparente,1=opaco)

uniform sampler2D noise_texture: filter_linear_mipmap, repeat_enable;
uniform float noise_strength = 0.05;
uniform float noise_scale = 0.01;

float get_visibility(vec2 offset) {
	float dist = length(offset);

	// Circulo
	float circle_vis = 1.0 - smoothstep(radius_px - softness, radius_px + softness, dist);

	// Cono
	vec2 dir_norm = (dist > 0.0001) ? offset / dist : facing_dir;
	float angle = acos(clamp(dot(dir_norm, facing_dir), -1.0, 1.0));
	float cone_angle_vis = 1.0 - smoothstep(cone_half_angle - 0.05, cone_half_angle + 0.05, angle);
	float cone_dist_vis = 1.0 - smoothstep(cone_range_px - softness, cone_range_px + softness, dist);
	float cone_vis = cone_angle_vis * cone_dist_vis;

	return max(circle_vis, cone_vis);
}

void fragment() {
	vec2 offset = FRAGCOORD.xy - player_px;
	float vis = clamp(get_visibility(offset), 0.0, 1.0);

	float n = texture(noise_texture, FRAGCOORD.xy * noise_scale).r;
	vec3 color = fog_color + (n - 0.5) * noise_strength;

	float alpha = fog_opacity * (1.0 - vis);

	COLOR = vec4(color, alpha);
}