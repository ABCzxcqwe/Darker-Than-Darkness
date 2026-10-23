# res://core/dev_mode.gd (Autoload)
#
# Controla el acceso a personajes de testeo (CharacterData.dev_only).
#
# Reglas por tipo de build:
#   TEST    (test_build)    → SIEMPRE OFF. --dev se ignora.
#   DEV     (dev_build)     → ON solo si se lanza con --dev.
#   RELEASE (public_build)  → SIEMPRE OFF. --dev se ignora.
#   Editor  (editor)        → SIEMPRE ON (comodidad al pulsar Play).
#
# Un build sin feature conocida (por ejemplo, exportado a mano sin preset)
# se comporta como DEV: requiere --dev.
extends Node

const DEV_FLAG := "--dev"

## True si este proceso puede seleccionar personajes dev.
var enabled: bool = false


func _ready() -> void:
	_refresh()
	print("[DevMode] build=", build_kind(), " | personajes dev=", "ACTIVADOS" if enabled else "bloqueados")

	if enabled:
		multiplayer.connected_to_server.connect(_claim_dev_mode)
		_claim_if_already_connected()


func _refresh() -> void:
	if OS.has_feature("public_build") or OS.has_feature("test_build"):
		# TEST y RELEASE: bloqueo duro, aunque alguien pase --dev.
		enabled = false
		return

	if OS.has_feature("editor"):
		# En el editor siempre está disponible para agilizar las pruebas.
		enabled = true
		return

	# Build DEV (dev_build) o build sin feature conocida: opt-in explícito.
	enabled = _has_dev_flag()


func _has_dev_flag() -> bool:
	return DEV_FLAG in OS.get_cmdline_args() or DEV_FLAG in OS.get_cmdline_user_args()


func is_enabled() -> bool:
	return enabled


func build_kind() -> String:
	if OS.has_feature("public_build"):
		return "release"
	if OS.has_feature("test_build"):
		return "test"
	if OS.has_feature("dev_build"):
		return "dev"
	if OS.has_feature("editor"):
		return "editor"
	return "unknown"


func _claim_if_already_connected() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		return
	_claim_dev_mode()


## Avisa al servidor de que este peer es un cliente dev. El servidor solo
## acepta personajes dev_only de peers que hayan reclamado el modo dev.
func _claim_dev_mode() -> void:
	var lm := get_node_or_null("/root/LobbyManager")
	if lm and lm.has_method("claim_dev_mode"):
		lm.claim_dev_mode.rpc_id(1)
