# res://scripts/resources/AbilityData.gd
# ============================================================
# AbilityData — Recurso central del sistema de habilidades.
#
# CÓMO USARLO:
#   1. Crea un nuevo recurso (.tres) de tipo AbilityData en el Inspector.
#   2. Rellena los grupos que apliquen a la habilidad.
#   3. Asígnalo al array `ability_slots` del CharacterData del personaje.
#
# CONVENCIONES:
#   - Los campos que no aplican a una habilidad se dejan en su valor por defecto.
#   - "Escalable" significa que el valor cambia con el número de usos en la partida.
#     El estado de usos NO vive aquí (es un Resource compartido), sino en AbilityStateService.
#   - "Killer" agrupa campos exclusivos de los personajes asesinos.
# ============================================================
@tool
extends Resource
class_name AbilityData


# ── ENUMS ───────────────────────────────────────────────────────────────────

## Categoría semántica de la habilidad (usada por el HUD para el color del icono).
enum AbilityType { ATTACK, SUPPORT, UTILITY, PASSIVE }

## Si el lanzador puede moverse mientras la habilidad está activa.
## LOCKED  → el caster queda anclado (Sword Slash, Heal Prayer).
## FREE    → puede hacer kiting (Rude Buster, Rayos de Spamton).
## AERIAL  → solo aplica durante el vuelo (Vuelo de Spamton).
enum MoveRestriction { FREE, LOCKED, AERIAL }

## Cómo se selecciona el objetivo cuando requires_selection = true.
## ALLY    → muestra solo survivors vivos (Soul Protect, Heal Prayer, Ultimate Health).
## ENEMY   → muestra solo el killer (reservado para futuras habilidades).
## ANY     → cualquier jugador.
enum SelectionType { ALLY, ENEMY, ANY }


# ════════════════════════════════════════════════════════════════════════════
# GRUPO 1 — IDENTIFICACIÓN
# ════════════════════════════════════════════════════════════════════════════

@export_group("Identificación")

## Nombre único de la habilidad. Usado como key en CooldownService y logs.
@export var display_name: String = ""

## Descripción visible en el HUD / pantalla de selección de personaje.
@export_multiline var description: String = ""

## Icono que el HUD muestra en el slot.
@export var icon: Texture2D

## Categoría de la habilidad (afecta color del botón en el HUD).
@export var ability_type: AbilityType = AbilityType.ATTACK


# ════════════════════════════════════════════════════════════════════════════
# GRUPO 2 — SCRIPTS Y ESCENAS
# ════════════════════════════════════════════════════════════════════════════

@export_group("Scripts y Escenas")

## Script GDScript que extiende AbilityBase. Contiene la lógica de activate().
## OBLIGATORIO en todos los slots activos.
@export var ability_script: GDScript

## Escena del hitbox / proyectil (CollisionShape2D, Area2D, etc.).
## Puede ser null si la habilidad no genera un objeto físico (ej: buff puro).
@export var ability_scene: PackedScene


# ════════════════════════════════════════════════════════════════════════════
# GRUPO 3 — ANIMACIÓN
# ════════════════════════════════════════════════════════════════════════════

@export_group("Animación")

## Nombre de la animación a reproducir en el SpriteFrames del personaje.
## Si se deja vacío, la habilidad se ejecuta sin cambiar la animación visual.
@export var action_animation: String = ""

## Animación de preparación antes de la acción principal.
## Vacío = no hay fase de preparación, se va directo a action_animation.
@export var prepare_animation: String = ""

## Si true, se puede cancelar presionando la misma tecla durante la animación.
@export var can_cancel: bool = false


# ════════════════════════════════════════════════════════════════════════════
# GRUPO 4 — ECONOMÍA: COOLDOWN Y TP
# ════════════════════════════════════════════════════════════════════════════

@export_group("Economía")

## Tiempo base de reutilización en segundos.
## Para habilidades con cooldown dinámico (Ultimate Health), este es el valor inicial.
@export var cooldown: float = 1.0

## Cooldown alternativo si la habilidad falla (ej: no golpeó a nadie).
@export var cooldown_fail: float = 0.0

## Cooldown alternativo si la habilidad se canceló durante la animación.
@export var cooldown_cancel: float = 0.0

## TP necesario para activar la habilidad.
## 0.0 = habilidad gratuita.
## Para Ultimate Health de Susie, este es el costo inicial (se reduce con usos).
@export var tp_cost: float = 0.0

## TP que se otorga al caster cuando la habilidad conecta o se activa con éxito.
## Ejemplos: Sword Slash otorga 15 TP al golpear; M1 de Jevil otorga TP.
@export var tp_reward: float = 0.0

## Si es true, el AbilityRouter bloquea el uso cuando el TP del jugador es insuficiente.
## Normalmente true. Ponlo en false solo para habilidades que manejan su propio
## chequeo de TP internamente (casos excepcionales).
@export var consume_tp_on_use: bool = true


# ════════════════════════════════════════════════════════════════════════════
# GRUPO 5 — RESTRICCIONES DE USO
# ════════════════════════════════════════════════════════════════════════════

@export_group("Restricciones de Uso")

## Si true, el jugador NO puede activar esta habilidad mientras está stunned.
## Dejar en false para habilidades de reacción como Counter de Kris.
@export var can_use_while_stunned: bool = false

## Define si el caster puede moverse mientras ejecuta la habilidad.
## LOCKED ancla al caster (Sword Slash, Heal Prayer).
## FREE permite kiting (Rude Buster, Rayos).
## AERIAL solo aplica en estado de vuelo.
@export var move_restriction: MoveRestriction = MoveRestriction.FREE

## Si true, el AbilityRouter intercepta el input y abre el menú contextual
## antes de enviar el RPC al servidor.
@export var requires_selection: bool = false

## Tipo de objetivo que muestra el menú contextual.
## Solo se lee si requires_selection = true.
@export var selection_type: SelectionType = SelectionType.ALLY

## Si true, el AbilityRouter NO inicia el cooldown al despachar.
## La habilidad es responsable de iniciarlo en su on_end o cuando corresponda.
## Úsalo cuando el cooldown depende del resultado (golpeó/falló/canceló).
@export var defer_cooldown: bool = false


# ════════════════════════════════════════════════════════════════════════════
# GRUPO 6 — EFECTOS DE COMBATE
# ════════════════════════════════════════════════════════════════════════════

@export_group("Efectos de Combate")

## Daño directo que aplica la habilidad al objetivo.
## 0 = sin daño (ej: habilidades de CC puras o soporte).
@export var base_damage: int = 0

## Curación directa que aplica la habilidad.
## 0 = sin curación.
## En Heal Prayer este es el valor de curación fija.
@export var base_heal: int = 0

## Alcance del hitbox en píxeles desde el centro del caster.
@export var range_: float = 100.0

## Retraso en segundos entre la animación de lanzamiento y la aparición del proyectil.
@export var spawn_delay: float = 0.0

## Tipo de ataque para el sistema de invencibilidad de HealthService.
## Debe coincidir con los valores que verifica CharacterData.special_defense_against.
@export var attack_type: String = "normal"


# ════════════════════════════════════════════════════════════════════════════
# GRUPO 7 — CONTROL DE MASAS (CC)
# ════════════════════════════════════════════════════════════════════════════

@export_group("Control de Masas")

## Duración del stun aplicado al objetivo al conectar la habilidad.
## 0.0 = sin stun.
@export var stun_duration: float = 0.0

## Magnitud del slow aplicado al objetivo (0.0 = sin slow, 1.0 = inmovilización).
## StatusEffectService suma instancias de slow, así que valores como 0.3 son seguros.
@export var slow_magnitude: float = 0.0

## Duración del slow en segundos.
@export var slow_duration: float = 0.0

## Número de impactos necesarios para que el efecto de CC se aplique.
## 0 = efecto inmediato al primer impacto.
## Ejemplo: Pacify de Ralsei requiere 4 impactos antes de aplicar el stun.
@export var hit_count_for_effect: int = 0


# ════════════════════════════════════════════════════════════════════════════
# GRUPO 8 — ESCALABILIDAD POR USO
# Úsalo en habilidades que cambian sus valores con el número de usos en la partida.
# El ESTADO (cuántas veces se usó) NO vive aquí. Vive en AbilityStateService.
# Este grupo define únicamente los parámetros de la curva de escala.
# ════════════════════════════════════════════════════════════════════════════

@export_group("Escalabilidad por Uso")

## Si true, esta habilidad tiene valores que escalan con el número de usos.
## Activa el uso de todos los campos de este grupo.
## Ejemplo: Ultimate Health de Susie.
@export var is_scalable: bool = false

## Valor base del efecto principal en el primer uso (porcentaje o valor plano).
## Ejemplo: Ultimate Health empieza curando 1% del HP máximo → 0.01.
@export var scaling_base_value: float = 0.0

## Cuánto incrementa el efecto por cada uso adicional.
## Ejemplo: +2% por uso → 0.02.
@export var scaling_per_use: float = 0.0

## Techo máximo del efecto (la escala se detiene aquí).
## Ejemplo: máximo 55% → 0.55.
@export var scaling_cap: float = 1.0

## Cuánto se reduce el costo de TP por cada uso (valor absoluto en puntos de TP).
## Ejemplo: baja 2% por uso. Si tp_cost es un valor 0-100, pon 2.0 aquí.
@export var tp_cost_reduction_per_use: float = 0.0

## Costo mínimo de TP al que puede llegar la reducción.
@export var tp_cost_floor: float = 0.0

## Cuánto aumenta el cooldown por cada uso en segundos.
## Ejemplo: Ultimate Health aumenta 0.5s por uso.
@export var cooldown_increase_per_use: float = 0.0


# ════════════════════════════════════════════════════════════════════════════
# GRUPO 9 — EVOLUCIÓN
# ════════════════════════════════════════════════════════════════════════════

@export_group("Evolución")

## Recurso AbilityData que representa la versión evolucionada de esta habilidad.
## Si es null, la habilidad no tiene evolución.
## Ejemplo: Sword Slash apunta a X-Slash; Rude Buster apunta a Red Buster.
@export var evolved_version: AbilityData

## Multiplicador de daño cuando la versión evolucionada está activa.
## 1.0 = sin cambio. 1.5 = 50% más daño.
@export var evo_damage_multiplier: float = 1.0

## Segundos extra de duración en efectos de CC cuando la habilidad está evolucionada.
@export var evo_status_duration_bonus: float = 0.0

## Si true, la habilidad se evoluciona automáticamente en modo LMS
## siempre que el jugador tenga TP suficiente para la versión evolucionada.
## AbilityRouter chequea LMSService y EvolutionService juntos.
@export var lms_auto_evolve: bool = false

## Si true, cuando un aliado use ACT sobre este jugador, esta habilidad
## será evolucionada automáticamente (sin importar en qué slot esté).
## Ejemplo: Sword Slash de Kris tiene evolvable_by_ally = true.
@export var evolvable_by_ally: bool = false

## Si TEMPORARY: al usar la habilidad evolucionada, el slot retorna a la versión base.
## Si PERMANENT: al usar la habilidad evolucionada, el slot se queda en esa versión.
## Esto afecta tanto al borde del botón (pulsante vs estático) como al consume.
enum EvolutionConsume { TEMPORARY, PERMANENT }

## Define si la evolución de esta habilidad es temporal o permanente.
## Se evalúa en la versión evolucionada (evolved_version), no en la base.
@export var evolution_consume: EvolutionConsume = EvolutionConsume.TEMPORARY

## Slot del ALIADO que esta habilidad evoluciona al seleccionar un objetivo.
## -1 = no evoluciona ningún slot del aliado.
## DEPRECATED: Usar evolvable_by_ally en cada habilidad individual en su lugar.
@export var evolve_target_slot: int = -1

## Slot PROPIO que esta habilidad evoluciona al activarse.
## -1 = no evoluciona ningún slot propio.
## Ejemplo: ACT de Kris también evoluciona su propio slot 1 (Sword).
@export var evolve_self_slot: int = -1


# ════════════════════════════════════════════════════════════════════════════
# GRUPO 10 — MECÁNICAS ESPECIALES DE KILLER
# Estos campos solo aplican a habilidades de Jevil o Spamton.
# Los survivors los ignoran completamente.
# ════════════════════════════════════════════════════════════════════════════

@export_group("Killer — Mecánicas Especiales")

## Número de proyectiles o instancias simultáneas que genera la habilidad.
## Ejemplo: Rayos de Spamton genera 3 disparos → projectile_count = 3.
## Valor 1 = comportamiento normal.
@export var projectile_count: int = 1

## Máximo de instancias activas al mismo tiempo en el mapa.
## Ejemplo: PIPIS (minas) tiene un límite de 3 → max_active_instances = 3.
## 0 = sin límite.
@export var max_active_instances: int = 0

## Resistencia inicial a los stuns al activar el Rage Mode (0.0 – 1.0).
## Ejemplo: Jevil H4 empieza con 50% de resistencia → rage_stun_resistance_base = 0.5.
## 0.0 en habilidades que no usan Rage Mode.
@export var rage_stun_resistance_base: float = 0.0

## Cuánto se reduce la resistencia a stuns por cada stun recibido mientras Rage Mode está activo.
## Ejemplo: -10% por stun → rage_stun_resistance_decay = 0.1.
@export var rage_stun_resistance_decay: float = 0.0

## Penalización de cooldown (en segundos) si el tiempo de vuelo se agota sin aterrizar.
## Solo aplica a habilidades de tipo AERIAL (Vuelo de Spamton).
@export var flight_timeout_cooldown_penalty: float = 0.0


# ════════════════════════════════════════════════════════════════════════════
# GRUPO 11 — CONFIGURACIÓN DE PROYECTIL
# Estos campos se ocultan automáticamente cuando is_projectile = false.
# ════════════════════════════════════════════════════════════════════════════

const PROJECTILE_ONLY := [
	"projectile_speed", "projectile_lifetime", "projectile_max_range",
	"arc_angle", "projectile_piercing",
]

@export_group("Configuración de Proyectil")

## Marca esta habilidad como tipo proyectil para exponer las opciones avanzadas.
@export var is_projectile: bool = false:
	set(value):
		is_projectile = value
		notify_property_list_changed()

## Velocidad del proyectil en píxeles por segundo.
@export var projectile_speed: float = 300.0

## Tiempo máximo de vida del proyectil en segundos antes de desaparecer.
@export var projectile_lifetime: float = 2.0

## Distancia máxima que puede recorrer (0 = ilimitado).
@export var projectile_max_range: float = 0.0

## Ángulo de dispersión en grados (0 = disparo recto, 60 = abanico de 60°).
@export var arc_angle: float = 0.0

## Si true, el proyectil atraviesa múltiples objetivos sin desaparecer.
@export var projectile_piercing: bool = false


# ════════════════════════════════════════════════════════════════════════════
# GRUPO 12 — MECÁNICAS FUTURAS (Reservado)
# Estos flags no tienen lógica activa todavía. Sirven para declarar la intención
# en el inspector sin romper nada al implementarlos después.
# ════════════════════════════════════════════════════════════════════════════

@export_group("Futuro (Reservado)")

## Si true, esta habilidad tiene un minijuego asociado que aún no está implementado.
## Ejemplo: Spawn (Error del Sistema) de Spamton — cierre de ventanas de anuncios.
## Cuando se implemente, este flag será leído por el MinigameService.
@export var has_minigame: bool = false

## Nombre del minijuego a lanzar (usado por MinigameService cuando has_minigame = true).
@export var minigame_id: String = ""


func _validate_property(property: Dictionary) -> void:
	if not is_projectile and property.name in PROJECTILE_ONLY:
		property.usage = PROPERTY_USAGE_NO_EDITOR
