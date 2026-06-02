# res://Hitboxes/Kris/SlashHitbox.gd
# Hitbox del ataque Slash.
# HitboxService lo instancia y configura antes de añadirlo al árbol.
# Solo vive en el servidor.
extends Area2D

# ── Asignados por HitboxService antes de add_child() ──────────────────
var attacker_id:  int     = -1
var damage:       int     = 15
var attack_type:  String  = "slash"
var on_hit_callback: Callable
var on_end_callback: Callable

# ── Estado interno ─────────────────────────────────────────────────────
var _hit_count: int   = 0
var _lifetime:  float = 0.25   # segundos hasta auto-destruirse
var _expired:   bool  = false  # evita doble expiración


func _ready() -> void:
	if not multiplayer.is_server():
		queue_free()
		return

	area_entered.connect(_on_area_entered)
	get_tree().create_timer(_lifetime).timeout.connect(_expire)


func _on_area_entered(area: Area2D) -> void:
	print("[SlashHitbox] Colisión detectada con: ", area.name, " | grupos: ", area.get_groups())
	if _expired:
		return

	# Solo nos interesan las Hurtbox
	if not area.is_in_group("hurtbox"):
		return

	# El padre de la Hurtbox debe ser el jugador
	var target: Node = area.get_parent()
	if not target or not target.is_in_group("players"):
		return

	# Sin auto-golpe
	if target.get_multiplayer_authority() == attacker_id:
		return

	_hit_count += 1

	if on_hit_callback.is_valid():
		on_hit_callback.call(target)

	# Un solo golpe por slash
	_expire()


func _expire() -> void:
	if _expired:
		return
	_expired = true

	if on_end_callback.is_valid():
		on_end_callback.call(_hit_count)

	queue_free()
