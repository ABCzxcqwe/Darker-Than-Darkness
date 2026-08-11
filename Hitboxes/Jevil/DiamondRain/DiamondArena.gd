extends Node2D

var _closing: bool = false


func _ready() -> void:
	_play_enter()


func _play_enter() -> void:
	modulate.a = 0.0
	scale = Vector2(0.92, 0.92)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.3)
	t.tween_property(self, "scale", Vector2.ONE, 0.3)


@rpc("authority", "call_local", "reliable")
func _rpc_disappear() -> void:
	if _closing:
		return
	_closing = true
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	t.tween_property(self, "scale", Vector2(0.92, 0.92), 0.3)
	t.chain().tween_callback(queue_free)
