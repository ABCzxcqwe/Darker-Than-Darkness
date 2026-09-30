# res://tests/net_spike/RealPlayerCheck.gd
# Verificacion temporal: compila y carga la escena real del jugador con los
# dos MultiplayerSynchronizer separados (posicion servidor / animacion dueño).
extends Node


func _ready() -> void:
	var ps := load("res://core/player/player.tscn") as PackedScene
	if ps == null:
		print("[CHECK] FAIL: no se pudo cargar player.tscn")
		get_tree().quit(1)
		return
	var p := ps.instantiate()
	if p == null:
		print("[CHECK] FAIL: no se pudo instanciar player.tscn")
		get_tree().quit(1)
		return

	var has_sync := p.has_node("Synchronizer")
	var has_anim := p.has_node("SynchronizerAnim")
	var sync_ok := false
	var anim_ok := false
	if has_sync:
		var s := p.get_node("Synchronizer") as MultiplayerSynchronizer
		sync_ok = s.replication_config != null and s.replication_config.get_properties().size() == 3
	if has_anim:
		var a := p.get_node("SynchronizerAnim") as MultiplayerSynchronizer
		anim_ok = a.replication_config != null and a.replication_config.get_properties().size() == 3

	print("[CHECK] player.tscn Synchronizer=", has_sync, " (props=3:", sync_ok,
		") SynchronizerAnim=", has_anim, " (props=3:", anim_ok, ")")
	p.free()
	get_tree().quit(0 if (has_sync and has_anim and sync_ok and anim_ok) else 1)
