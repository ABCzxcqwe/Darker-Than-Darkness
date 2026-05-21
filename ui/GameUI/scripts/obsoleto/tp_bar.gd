# res://ui/GameUI/scripts/TpBar.gd (Copia completa)

extends Control

# IMPORTANTE: Según tu captura, el nodo hijo se llama "TextureProgressBar"
@onready var progress_bar: ProgressBar = get_node_or_null("TextureProgressBar")
@onready var tp_label: Label = get_node_or_null("Label") 

var _target_peer_id: int = -1

func _ready() -> void:
	print("Barra de TP lista para recibir señales en el peer: ", multiplayer.get_unique_id())
	var tp_service = GameServiceLocator.get_service("TPService")
	if tp_service:
		# Usamos conexión diferida para seguridad en red
		tp_service.tp_changed.connect(_on_tp_changed)

func setup(peer_id: int, max_tp: float) -> void:
	_target_peer_id = peer_id
	if progress_bar:
		progress_bar.max_value = max_tp
	
	# Sincronización inmediata al aparecer
	var tp_service = GameServiceLocator.get_service("TPService")
	if tp_service:
		_update_ui(tp_service.get_tp_for_peer(peer_id))

func _on_tp_changed(peer_id: int, current_tp: float, _max_tp: float) -> void:
	# Debug para que veas el cambio en consola
	# print("Barra de TP (", _target_peer_id, ") recibió datos de: ", peer_id)

	# Si el ID coincide, actualizamos
	if peer_id == _target_peer_id:
		_update_ui(current_tp)
	
	# CASO ESPECIAL: Si mi ID es 1 pero soy el cliente, algo salió mal en el setup.
	# Esta línea arregla el desajuste de identidad si el setup falló:
	elif _target_peer_id == 1 and not multiplayer.is_server():
		_target_peer_id = multiplayer.get_unique_id()
		if peer_id == _target_peer_id:
			_update_ui(current_tp)

func _update_ui(value: float) -> void:
	if not progress_bar: return
	
	var tw = create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(progress_bar, "value", value, 0.2)
	
	if tp_label:
		var ratio = value / progress_bar.max_value if progress_bar.max_value > 0 else 0
		tp_label.text = str(int(ratio * 100)) + "%"
		
