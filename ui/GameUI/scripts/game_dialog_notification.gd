extends PanelContainer

signal finished()

var _full_text: String
var _char_index: int = 0
var _hold_timer: float = 2.0
var _state: int = 0

@onready var text_label: Label = $MarginContainer/VBoxContainer/TextLabel

func show_message(text: String, type: int = 0) -> void:
	if type == 0:
		text = "* " + text
	_full_text = text
	_char_index = 0
	_state = 0
	text_label.text = ""
	modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.15)

func _process(delta: float) -> void:
	match _state:
		0:
			if _char_index < _full_text.length():
				_char_index += ceil(delta / 0.025) as int
				_char_index = mini(_char_index, _full_text.length())
				text_label.text = _full_text.left(_char_index)
			if _char_index >= _full_text.length():
				_state = 1
				_hold_timer = 2.0
		1:
			_hold_timer -= delta
			if _hold_timer <= 0.0:
				_state = 2
				var tween = create_tween()
				tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.3)
				tween.tween_callback(func():
					finished.emit()
					queue_free())
