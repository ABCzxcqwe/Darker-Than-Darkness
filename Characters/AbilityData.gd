extends Resource
class_name AbilityData

@export var id: int
@export var display_name: String
@export var description: String
@export var icon: Texture2D

@export var ability_script: GDScript = null
@export var ability_scene: PackedScene

@export var cooldown: float = 5.0
@export var stun_time: float = 0
@export var tp_cost: int = 0
@export var tp_gain: int = 0
@export var damage: int = 15
@export var attack_type: String = "normal"

@export var range_: float = 100.0
@export var target_team: String = "enemy"

@export var can_use_while_stunned: bool = false

@export var can_hit_own_team: bool = false
@export var can_pass_through_walls: bool = false

@export var evolved_version: AbilityData = null

# ── Selección de objetivo ─────────────────────────────────────────────
## Si true, al pulsar la habilidad el HUD abre un menú de selección
## antes de activarla. El script de la habilidad puede ignorar este campo
## y notificar al HUD directamente via GameHUD.request_selection().
@export var requires_selection: bool = false

## Tipo de selección. Valores sugeridos: "ally", "area", "confirm".
## El HUD usa esto para mostrar el menú correcto.
## Puede ser cualquier String — el script de la habilidad es quien lo interpreta.
@export var selection_type: String = ""
