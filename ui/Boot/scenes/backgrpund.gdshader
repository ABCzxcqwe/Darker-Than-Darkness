shader_type canvas_item;

// --- Parámetros de Control ---
uniform float velocidad_base : hint_range(0.005, 0.1) = 0.02;
uniform vec4 color_tinta : source_color = vec4(0.12, 0.14, 0.28, 1.0); // Tono abisal

void fragment() {
    vec2 uv_espejo = abs(UV * 2.0 - 1.0);
    uv_espejo = 1.0 - uv_espejo;

    vec2 uv1 = uv_espejo * 0.7;
    uv1.y += TIME * (velocidad_base * 0.4); 
    vec4 capa1 = texture(TEXTURE, fract(uv1)) * 0.4;

    vec2 uv2 = uv_espejo * 1.0;
    uv2.y += TIME * velocidad_base;
    uv2.x += sin(TIME * 0.6 + uv_espejo.y) * 0.02; // Expansión ondulatoria
    vec4 capa2 = texture(TEXTURE, fract(uv2)) * 0.5;

    vec2 uv3 = uv_espejo * 1.4;
    uv3.y += TIME * (velocidad_base * 1.7);
    uv3.x += cos(TIME * 0.5 + uv_espejo.y) * 0.03;
    vec4 capa3 = texture(TEXTURE, fract(uv3)) * 0.3;

    vec4 color_fusion = capa1 + capa2 + capa3;

    COLOR = color_fusion * color_tinta;
}