extends Node
class_name MapPhaseEvent

enum ConditionType {
	TIME_REMAINING,
	SURVIVORS_ALIVE,
	LMS_ACTIVE,
	ALWAYS,
}

enum ActionType {
	ACTIVATE_EXIT,
	DEACTIVATE_EXIT,
	ACTIVATE_TRIGGER,
	DEACTIVATE_TRIGGER,
	PLAY_EFFECT,
	SET_AMBIENT,
	CALL_CUSTOM,
}

@export var event_id: String = ""
@export var condition: ConditionType = ConditionType.TIME_REMAINING
@export var condition_value: float = 30.0
@export var action: ActionType = ActionType.ACTIVATE_EXIT
@export var action_target: String = ""
@export var one_shot: bool = true
@export var activate_on_start: bool = false

var has_fired: bool = false
