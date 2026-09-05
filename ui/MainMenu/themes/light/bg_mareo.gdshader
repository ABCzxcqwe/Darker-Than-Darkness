shader_type canvas_item;

uniform float wave_amplitude : hint_range(0.0, 0.1) = 0.03;
uniform float wave_frequency : hint_range(1.0, 50.0) = 12.0;
uniform float wave_speed : hint_range(0.0, 10.0) = 2.5;
uniform float origin_y : hint_range(0.0, 1.0) = 0.5; // Punto donde inicia el movimiento (0.5 = mitad)

void fragment() {
    // 1. Calcular el peso del movimiento (0 en la mitad o abajo, incrementa hacia arriba)
    float height_factor = clamp((origin_y - UV.y) / origin_y, 0.0, 1.0);
    float weight = pow(height_factor, 1.5); // Escalado suave para dar más fuerza arriba

    // 2. Aplicar la onda amortiguada por el peso
    vec2 uv = UV;
    float wave = sin(uv.y * wave_frequency - TIME * wave_speed) * wave_amplitude * weight;
    uv.x += wave;

    // 3. Muestrear la textura
    vec4 tex_color = texture(TEXTURE, uv);

    // 4. Corregir la línea eliminando los píxeles cuyas UV se salgan del borde
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        tex_color.a = 0.0;
    }

    COLOR = tex_color;
}