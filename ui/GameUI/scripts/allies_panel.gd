# AlliesPanel.gd
# Panel que muestra las barras de vida de los survivors aliados.
# Excluye al jugador local. Se actualiza dinámicamente.
extends VBoxContainer

const ALLY_BAR_SCENE := preload("res://ui/GameUI/Scenes/AllyBar.tscn")

var _my_peer_id: int = -1


func setup(my_peer_id: int) -> void:
	_my_peer_id = my_peer_id

	# Esperar un frame para que todos los Player estén en el árbol
	await get_tree().process_frame
	_build()


func _build() -> void:
	# Limpiar barras existentes
	for child in get_children():
		child.queue_free()

	# Crear una barra por cada survivor que no sea el jugador local
	for player in get_tree().get_nodes_in_group("player"):
		if player.get_multiplayer_authority() == _my_peer_id:
			continue
		if not player.is_in_group("survivor"):
			continue

		var bar := ALLY_BAR_SCENE.instantiate()
		add_child(bar)
		bar.setup(player)
