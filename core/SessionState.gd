# res://Network/autoload/SessionState.gd
extends Node
## Estado de sesión compartido entre lobby, partida y UI.
##
## Reemplaza a `GameData` como fuente única de:
## - mapa elegido en el lobby (`selected_map`),
## - mapa de la partida en curso (`active_map_id`),
## - mapa de personajes (`char_map`),
## - fase de la sala/partida (`phase`),
## - participantes de la ronda (`participants`).

signal changed()
signal selected_map_changed(map_id: String)
signal active_map_changed(map_id: String)
signal phase_changed(phase: int)
signal participants_changed(participants: Array)

var selected_map: String = "":
	set(value):
		var clean := value.strip_edges()
		if selected_map == clean:
			return
		selected_map = clean
		selected_map_changed.emit(selected_map)
		changed.emit()

var active_map_id: String = "":
	set(value):
		var clean := value.strip_edges()
		if active_map_id == clean:
			return
		active_map_id = clean
		active_map_changed.emit(active_map_id)
		changed.emit()

var char_map: Dictionary = {}:
	set(value):
		char_map = value.duplicate()
		changed.emit()

var phase: NetEnums.Phase = NetEnums.Phase.LOBBY:
	set(value):
		if phase == value:
			return
		phase = value
		phase_changed.emit(int(phase))
		changed.emit()

var participants: Array[int] = []:
	set(value):
		participants.clear()
		for pid in value:
			participants.append(int(pid))
		participants_changed.emit(participants)
		changed.emit()


## Vuelve todo al estado inicial. No toca el estado de red.
func reset() -> void:
	selected_map = ""
	active_map_id = ""
	char_map = {}
	phase = NetEnums.Phase.LOBBY
	var empty: Array[int] = []
	participants = empty


## Marca el inicio de una ronda. `selected_map` se conserva para el lobby.
func begin_match(map_id: String, p_char_map: Dictionary, p_participants: Array) -> void:
	active_map_id = map_id
	char_map = p_char_map
	var typed: Array[int] = []
	for pid in p_participants:
		typed.append(int(pid))
	participants = typed


## Limpia solo lo efímero de la partida; conserva el mapa elegido en el lobby.
func clear_match() -> void:
	active_map_id = ""
	char_map = {}
	var empty: Array[int] = []
	participants = empty
