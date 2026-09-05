shader_type canvas_item;

// Shader de mareo/fuente basado en la versión original de deformación fluida
uniform float strength : hint_range(0.0, 0.08) = 0.025;
uniform float speed : hint_range(0.0, 3.0) = 0.9;
uniform float frequency : hint_range(1.0, 20.0) = 8.0;
uniform float origin_y : hint_range(0.0, 1.0) = 0.5; // Punto de inicio del movimiento (0.5 = mitad)
uniform vec2 direction = vec2(1.0, 0.3); // Usar (-1.0, 0.3) para invertir horizontalmente
uniform float alpha : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    // Calculamos el peso: 0 por debajo del punto origin_y, y aumenta gradualmente hacia arriba
    float height_factor = clamp((origin_y - UV.y) / origin_y, 0.0, 1.0);
    float weight = pow(height_factor, 1.2); 
	

    // Ondas sinusoidales entrelazadas del shader original escaladas por el peso
    vec2 d = vec2(
        sin(UV.y * frequency + TIME * speed) * strength * weight * direction.x,
        cos(UV.x * frequency * 0.7 + TIME * speed * 0.6) * strength * 0.45 * weight * direction.y
    );
    
    d += vec2(
        sin(UV.y * frequency * 1.6 + TIME * speed * 1.3) * strength * 0.5 * weight,
        cos(UV.x * frequency * 1.3 + TIME * speed * 0.9) * strength * 0.25 * weight
    );

    COLOR = texture(TEXTURE, UV + d);
	COLOR.a = alpha;
}