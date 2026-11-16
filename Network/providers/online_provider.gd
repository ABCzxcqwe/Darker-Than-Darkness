class_name OnlineProviderService
extends Node
## Contrato base para proveedores online (Steam, EOSG, P2P, Custom).
##
## NetworkManager solo conoce esta interfaz. Un proveedor que no está registrado
## no se muestra en la UI ni se puede inicializar. Para agregar otro transporte
## alcanza con implementar esta clase y registrarla en `_build_providers()`.
##
## Los IDs de lobby son strings opacos: Steam los convierte desde su id numérico
## y EOSG usa directamente el string de `HLobby.lobby_id`.
##
## `lobby_list_received` entrega summaries neutrales, no IDs crudos del SDK:
##   { id: String, provider: String, name: String, host: String, map: String,
##     mode: String, players: int, max_players: int }

signal availability_changed(is_available: bool)
signal lobby_created(lobby_id: String)
signal lobby_joined(lobby_id: String)
signal lobby_list_received(lobbies: Array)
signal lobby_left(lobby_id: String)
signal failed(reason: String)

var provider_id: NetEnums.Provider = NetEnums.Provider.DISABLE


## Inicialización sincrónica. Los proveedores que necesitan login asíncrono
## (EOSG) pueden arrancar el proceso acá y notificar con `availability_changed`.
func initialize() -> bool:
	return false


## Variante asíncrona. El default conserva el contrato sincrónico.
func initialize_async() -> bool:
	return initialize()


## True si el proveedor tiene todo lo necesario para intentar inicializarse.
## Un proveedor sin credenciales debe devolver false y no listarse en la UI.
func is_configured() -> bool:
	return true


func is_available() -> bool:
	return false


func host_lobby(_max_players: int, _metadata: Dictionary) -> bool:
	return false


func join_lobby(_lobby_id: String) -> bool:
	return false


func leave_lobby() -> void:
	pass


func request_lobby_list(_max_results: int, _game_id_filter: String) -> void:
	pass


func create_host_peer(_lobby_id: String) -> MultiplayerPeer:
	return null


func create_client_peer(_lobby_id: String) -> MultiplayerPeer:
	return null


func get_lobby_data(_lobby_id: String, _key: String) -> String:
	return ""


func is_lobby_owner(_lobby_id: String) -> bool:
	return false


func get_lobby_id() -> String:
	return ""


func get_current_lobby_summary() -> Dictionary:
	return {}


## Helper compartido por los proveedores para construir summaries homogéneos.
static func make_summary(
	p_id: String,
	p_provider: String,
	p_name: String,
	p_host: String,
	p_map: String,
	p_mode: String,
	p_players: int,
	p_max_players: int
) -> Dictionary:
	return {
		"id": p_id,
		"provider": p_provider,
		"name": p_name,
		"host": p_host,
		"map": p_map,
		"mode": p_mode,
		"players": p_players,
		"max_players": p_max_players,
	}
