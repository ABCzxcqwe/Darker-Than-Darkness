class_name PlayerNetInput
extends Node
## Propiedades de input del jugador para netfox.
##
## Este nodo es propiedad del dueño (autoridad = owner_peer_id). El
## RollbackSynchronizer del Player lo usa como `input_properties`, así que el
## servidor recibe el input y los clientes pueden predecir.
##
## Solo el dueño escribe estas propiedades. El resto de peers las reciben por
## netfox y las usan durante la resimulación.

var player: Player = null

## Dirección deseada en [-1, 1] por eje.
var move: Vector2 = Vector2.ZERO
## El jugador quiere correr (la stamina/estado lo resuelve el servidor).
var sprint: bool = false
## Dirección de apuntado normalizada. El servidor la usa para el facing
## determinista durante rollback; las habilidades siguen usando _sync_aim_dir.
var aim_dir: Vector2 = Vector2.RIGHT


func initialize(body: Player) -> void:
	player = body


func _ready() -> void:
	NetworkTime.before_tick_loop.connect(_gather)
	set_process(false)


func _exit_tree() -> void:
	if NetworkTime.before_tick_loop.is_connected(_gather):
		NetworkTime.before_tick_loop.disconnect(_gather)


func _gather() -> void:
	if player == null or not is_multiplayer_authority():
		return
	if player.interaction.is_spectator or player.health_state != "alive":
		move = Vector2.ZERO
		sprint = false
		return
	if player.is_pause_menu_open():
		move = Vector2.ZERO
		sprint = false
		return

	move = player.input_component.get_move_vector()
	if move.length() < 0.1:
		move = Vector2.ZERO
	var wants_sprint := Input.is_action_pressed("run") and move.length() > 0.1
	sprint = wants_sprint
	aim_dir = player.input_component.get_aim_direction(player.global_position)
	if aim_dir.length_squared() < 0.001:
		aim_dir = player.facing
