shader_type canvas_item;

// --- Parámetros ajustables ---
uniform float radius_base : hint_range(0.0, 10.0) = 2.5;    // Radio base del aura
uniform float glow_base : hint_range(0.0, 5.0) = 1.0;       // Intensidad base del aura
uniform float amplitud_pulso : hint_range(0.0, 2.0) = 0.5;   // Qué tanto varía el aura al pulsar
uniform float velocidad_pulso : hint_range(0.1, 10.0) = 3.0; // Velocidad del pulso
uniform vec4 color_aura : source_color = vec4(0.8, 0.9, 1.0, 1.0); // Color del aura (cian claro)

void fragment() {
    // 1. Calcular el pulso usando una onda senoidal basada en el tiempo
    // Genera un valor entre 0.0 y 1.0
    float pulso = (sin(TIME * velocidad_pulso) + 1.0) * 0.5;

    // 2. Modificar el radio y la intensidad basándonos en el pulso
    // El radio base fluctúa con el pulso para dar un efecto de expansión
    float radius_anim = radius_base + (amplitud_pulso * pulso);
    // La intensidad base fluctúa con el pulso
    float glow_anim = glow_base + (amplitud_pulso * 0.8 * pulso);

    // 3. Generar el desenfoque (Aura)
    vec2 size = TEXTURE_PIXEL_SIZE * radius_anim;
    vec4 col = texture(TEXTURE, UV);
    
    // Muestreo de píxeles adyacentes para crear el blur/aura suave
    vec4 aura = vec4(0.0);
    aura += texture(TEXTURE, UV + vec2(-size.x, 0.0));
    aura += texture(TEXTURE, UV + vec2(size.x, 0.0));
    aura += texture(TEXTURE, UV + vec2(0.0, -size.y));
    aura += texture(TEXTURE, UV + vec2(0.0, size.y));
    aura += texture(TEXTURE, UV + vec2(-size.x, -size.y));
    aura += texture(TEXTURE, UV + vec2(size.x, -size.y));
    aura += texture(TEXTURE, UV + vec2(-size.x, size.y));
    aura += texture(TEXTURE, UV + vec2(size.x, size.y));
    aura /= 8.0;

    // 4. Combinar todo
    // Aplicamos el color y la intensidad animada al aura difuminada
    vec4 aura_final = aura * color_aura * glow_anim;
    
    // El texto original (col) se mantiene nítido y se mezcla sobre el aura
    vec4 final_color = mix(aura_final, col, col.a);
    
    COLOR = final_color;
}