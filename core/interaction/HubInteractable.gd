# res://core/interaction/HubInteractable.gd
# Objeto del hub con el que se puede interactuar con el botón de mundo (E).
class_name HubInteractable
extends Area2D

signal interacted(player: Node)

@export var prompt: String = "INTERACTUAR"


func _ready() -> void:
	add_to_group("hub_interactables")
	# El área no detecta: es detectada por el InteractionArea del HubAvatar.
	monitoring = false
	monitorable = true
	collision_layer = 4
	collision_mask = 0


func get_prompt() -> String:
	return prompt


func interact(player: Node) -> void:
	interacted.emit(player)
