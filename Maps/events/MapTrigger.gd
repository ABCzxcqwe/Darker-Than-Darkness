extends Area2D
class_name MapTrigger

enum TeamFilter { ANY, SURVIVOR, KILLER }

signal triggered(trigger_id: String, player_node: Node)
signal player_exited(trigger_id: String, player_node: Node)

@export var trigger_id: String = ""
@export var team_filter: TeamFilter = TeamFilter.ANY
@export var one_shot: bool = true

var has_fired: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if has_fired and one_shot:
		return
	if not body.is_in_group("players"):
		return
	if not _passes_filter(body):
		return
	has_fired = true
	triggered.emit(trigger_id, body)

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("players"):
		return
	player_exited.emit(trigger_id, body)

func _passes_filter(body: Node) -> bool:
	if team_filter == TeamFilter.ANY:
		return true
	var char_data = body.get("character_data") if body.has_method("get_character_data") else null
	if not char_data:
		return false
	if team_filter == TeamFilter.SURVIVOR and char_data.team == "survivor":
		return true
	if team_filter == TeamFilter.KILLER and char_data.team == "killer":
		return true
	return false

func reset() -> void:
	has_fired = false
