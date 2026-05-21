# allies_panel.gd
# Construye dinámicamente una AllyBar por cada aliado visible.
# Para survivors: muestra los otros survivors.
# Para killers: muestra todos los survivors.
#
# Estructura esperada: AlliesPanel (VBoxContainer)
extends VBoxContainer

const ALLY_BAR_SCENE := preload("res://ui/GameUI/Scenes/AllyBar.tscn")

var _my_peer_id: int  = -1
var _my_team:    String = "survivor"


func setup(my_peer_id: int, my_team: String) -> void:
	_my_peer_id = my_peer_id
	_my_team    = my_team

	# Esperar un frame para que todos los Player estén en el árbol
	await get_tree().process_frame
	_build()

	# Si un aliado muere permanentemente, reconstruir el panel
	var hs: Node = GameServiceLocator.get_service("HealthService")
	if hs:
		hs.survivor_died_permanently.connect(_on_survivor_died)


func _build() -> void:
	for child in get_children():
		child.queue_free()

	# Killers ven a todos los survivors; survivors ven a sus compañeros survivors
	for player in get_tree().get_nodes_in_group("players"):
		if player.get_multiplayer_authority() == _my_peer_id:
			continue
		if not player.is_in_group("survivor"):
			continue

		var bar := ALLY_BAR_SCENE.instantiate()
		add_child(bar)
		bar.setup(player)


func _on_survivor_died(_peer_id: int) -> void:
	# Reconstruir después de un frame para que el nodo ya esté fuera del grupo
	await get_tree().process_frame
	_build()
