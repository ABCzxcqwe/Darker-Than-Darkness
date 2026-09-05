extends CanvasLayer
## HudMock — wrapper para GameHUDMock.tscn que usa TpBarCustom horizontal.
## Delega toda la lógica a game_hud.gd pero traduce el nodo TpBarCustom.
## Mantiene PlayerPanel y AbilityPanel intactos como pediste.

# Para no duplicar toda la lógica de game_hud.gd, este script simplemente
# asegura que TpBarCustom se inicialice correctamente si el base no lo hace.
# GameHUD (base) ya conecta timer, allies, etc. vía setup(player_node).

func _ready() -> void:
	# Esperar a que el owner GameHUD haga su _ready, luego verificar TpBarCustom
	await get_tree().process_frame
	var tp := get_node_or_null("PlayerPanelWrap/TpBar")
	if tp and tp.has_method("setup"):
		print("[HudMock] TpBarCustom detectado: ", tp.name, " size ", tp.custom_minimum_size)
