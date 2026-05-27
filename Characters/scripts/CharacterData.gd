# res://Characters/CharacterData.gd
@tool
extends Resource
class_name CharacterData

const SURVIVOR_ONLY := [
	"bleed_out_time", "can_be_executed",
	"revive_health", "revive_time", "revive_range",
	"lms_music", "lms_duration", "lms_heal_amount",
	"lms_damage_resistance",
]

const KILLER_ONLY := [
	"can_take_damage", "terror_radius", "chase_radius",
	"terror_music", "chase_music",
	"lms_music_", "lms_duration_",
]

@export_group("Información Básica")
@export var id: int
@export var display_name: String
@export_enum("survivor", "killer") var team: String = "survivor":
	set(value):
		team = value
		notify_property_list_changed()

@export_group("Estadísticas Base")
@export var speed: float = 200.0
@export var max_health: int = 100
@export var invincibility_frames: float = 1.0
@export var special_defense_against: Array[String] = []

@export_group("Colisiones")
## Tamaño del CollisionShape2D del personaje (mundo).
@export var size_x: int = 16
@export var size_y: int = 26
## Posición relativa del CollisionShape2D del personaje.
@export var position_x: int = 0
@export var position_y: int = 15

## Tamaño del CollisionShape2D del hurtbox.
@export var h_size_x: int = 40
@export var h_size_y: int = 110
## Posición relativa del CollisionShape2D del hurtbox.
@export var h_position_x: int = 0
@export var h_position_y: int = 0

@export_group("Survivor State")
@export var bleed_out_time: float = 60.0
@export var can_be_executed: bool = true
@export var revive_health: int = 60
@export var revive_time: float = 3.0
@export var revive_range: float = 80.0
@export var lms_music: AudioStream
@export var lms_duration: float = 140.0
@export var lms_heal_amount: int = 60
@export var lms_damage_resistance: float = 0.0

@export_group("Killer State")
@export var can_take_damage: bool = true
@export var terror_radius: float = 32.0
@export var chase_radius: float = 200.0
@export var terror_music: AudioStream
@export var chase_music: AudioStream
@export var lms_music_: AudioStream
@export var lms_duration_: float = 140.0

@export_group("Habilidades")
@export var ability_slots: Array[AbilityData] = [null, null, null, null, null]

@export_group("Tension Points")
@export var tp_max: float = 100.0
@export var tp_gain_on_hit: float = 10.0
@export var tp_gain_dodge: float = 8.0
@export var tp_gain_time: float = 1.0

@export_group("Visuales")
@export var icon: Texture2D
@export var animation_frames: SpriteFrames
## Color temático del personaje — se usa en la barra de HP y bordes del panel.
## Ejemplos: Kris = cian, Susie = magenta, Ralsei = verde claro.
@export var theme_color: Color = Color(0.27, 0.78, 0.95)


func _validate_property(property: Dictionary) -> void:
	var prop_name: String = property.name

	if team == "killer" and prop_name in SURVIVOR_ONLY:
		property.usage = PROPERTY_USAGE_NO_EDITOR
		return

	if team == "survivor" and prop_name in KILLER_ONLY:
		property.usage = PROPERTY_USAGE_NO_EDITOR
		return
