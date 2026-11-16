class_name LayeredAnimatedSprite2D
extends AnimatedSprite2D

const LAYER_COUNT := 9
const MASTER_LAYER := 3

const LAYER_SLOTS := {
	0: ["Layer0_Accessory"],
	1: ["Layer1_ArmBack"],
	2: ["Layer2_Accessory", "Layer2_Weapon"],
	3: [],
	4: ["Layer4_Accessory"],
	5: ["Layer5_Head"],
	6: ["Layer6_Accessory", "Layer6_Weapon"],
	7: ["Layer7_ArmFront"],
	8: ["Layer8_Accessory"],
}

const LAYER_Z := {
	0: [-80],
	1: [-60],
	2: [-40, -39],
	3: [0],
	4: [20],
	5: [40],
	6: [60, 61],
	7: [80],
	8: [100],
}

var _configured := false
var _layer_nodes: Array = []
var _layer_frames: Array = []
var _layer_offsets: Array = []
var _layer_enabled: Array = []
var _finished_anim := ""


func _ready() -> void:
	_ensure_nodes()
	if not animation_changed.is_connected(_on_animation_changed):
		animation_changed.connect(_on_animation_changed)
	if not animation_finished.is_connected(_on_animation_finished):
		animation_finished.connect(_on_animation_finished)


func _process(_delta: float) -> void:
	if not _configured:
		_ensure_nodes()
	var master_frames: SpriteFrames = _layer_frames[MASTER_LAYER][0]
	if master_frames != sprite_frames:
		master_frames = sprite_frames
		_layer_frames[MASTER_LAYER][0] = master_frames
	if master_frames == null:
		_hide_all()
		return
	var anim := str(animation)
	if anim == "" or not master_frames.has_animation(anim):
		_hide_all()
		return
	var total := master_frames.get_frame_count(anim)
	if total <= 0:
		_hide_all()
		return
	if is_playing():
		_finished_anim = ""
	var loop := master_frames.get_animation_loop(anim)
	var t := (float(frame) + frame_progress) / float(total)
	if not loop:
		if _finished_anim == anim or (not is_playing() and frame >= total - 1):
			t = 1.0
	else:
		t = fposmod(t, 1.0)
	t = clampf(t, 0.0, 1.0)
	for layer in range(LAYER_COUNT):
		if layer == MASTER_LAYER:
			continue
		for slot in range(_layer_nodes[layer].size()):
			var node: AnimatedSprite2D = _layer_nodes[layer][slot]
			var frames: SpriteFrames = _layer_frames[layer][slot]
			if not _layer_enabled[layer][slot] or frames == null or not frames.has_animation(anim):
				node.visible = false
				continue
			var child_total := frames.get_frame_count(anim)
			if child_total <= 0:
				node.visible = false
				continue
			if node.sprite_frames != frames:
				node.sprite_frames = frames
			if str(node.animation) != anim:
				node.play(anim)
				node.pause()
			var pos := t * float(child_total)
			var child_frame := int(floor(pos))
			if child_frame >= child_total:
				child_frame = child_total - 1
			var child_progress: float = pos - floor(pos)
			if child_frame == child_total - 1 and t >= 1.0:
				child_progress = 0.0
			node.set_frame_and_progress(child_frame, child_progress)
			node.flip_h = flip_h
			node.self_modulate = self_modulate
			node.visible = true


func setup_visual(visual: CharacterVisualData, fallback: SpriteFrames) -> void:
	_ensure_nodes()
	if visual == null and fallback == null:
		push_warning("[LayeredSprite] No hay CharacterVisualData ni SpriteFrames de respaldo.")
		return
	_finished_anim = ""
	for layer in range(LAYER_COUNT):
		for slot in range(_layer_nodes[layer].size()):
			_layer_frames[layer][slot] = null
			_layer_offsets[layer][slot] = Vector2.ZERO
			_layer_enabled[layer][slot] = true
			if layer != MASTER_LAYER:
				var node: AnimatedSprite2D = _layer_nodes[layer][slot]
				node.visible = false
				node.sprite_frames = null
	for layer in range(LAYER_COUNT):
		var frames: SpriteFrames = visual.get_layer(layer) if visual else null
		if layer == MASTER_LAYER and frames == null:
			frames = fallback
		if frames == null:
			continue
		var offset := visual.get_offset(layer) if visual else Vector2.ZERO
		var enabled := visual.is_layer_enabled(layer) if visual else true
		set_layer_slot(layer, 0, frames, offset, enabled)
	_validate_all_layers()


func set_layer_slot(layer: int, slot: int, frames: SpriteFrames, offset: Vector2 = Vector2.ZERO, enabled: bool = true) -> void:
	_ensure_nodes()
	if layer < 0 or layer >= LAYER_COUNT:
		push_warning("[LayeredSprite] Capa inválida: %d" % layer)
		return
	if slot < 0 or slot >= _layer_nodes[layer].size():
		push_warning("[LayeredSprite] Slot inválido: capa %d, slot %d" % [layer, slot])
		return
	_layer_frames[layer][slot] = frames
	_layer_offsets[layer][slot] = offset
	_layer_enabled[layer][slot] = enabled
	if layer == MASTER_LAYER:
		sprite_frames = frames
		return
	var node: AnimatedSprite2D = _layer_nodes[layer][slot]
	node.sprite_frames = frames
	node.offset = offset
	node.visible = false
	if frames != null:
		_validate_layer_alignment(layer, slot, frames)


func _ensure_nodes() -> void:
	if _configured:
		return
	_layer_nodes.resize(LAYER_COUNT)
	_layer_frames.resize(LAYER_COUNT)
	_layer_offsets.resize(LAYER_COUNT)
	_layer_enabled.resize(LAYER_COUNT)
	for layer in range(LAYER_COUNT):
		_layer_nodes[layer] = []
		_layer_frames[layer] = []
		_layer_offsets[layer] = []
		_layer_enabled[layer] = []
		if layer == MASTER_LAYER:
			_layer_nodes[layer].append(self)
			_layer_frames[layer].append(sprite_frames)
			_layer_offsets[layer].append(Vector2.ZERO)
			_layer_enabled[layer].append(true)
			continue
		var names: Array = LAYER_SLOTS[layer]
		var z_values: Array = LAYER_Z[layer]
		for slot in range(names.size()):
			var node_name: String = names[slot]
			var node: AnimatedSprite2D = get_node_or_null(node_name) as AnimatedSprite2D
			if node == null:
				node = AnimatedSprite2D.new()
				node.name = node_name
				add_child(node)
			node.z_as_relative = true
			node.z_index = int(z_values[slot])
			node.centered = true
			node.visible = false
			_layer_nodes[layer].append(node)
			_layer_frames[layer].append(null)
			_layer_offsets[layer].append(Vector2.ZERO)
			_layer_enabled[layer].append(true)
	_configured = true


func _hide_all() -> void:
	if not _configured:
		return
	for layer in range(LAYER_COUNT):
		if layer == MASTER_LAYER:
			continue
		for node: AnimatedSprite2D in _layer_nodes[layer]:
			node.visible = false


func _on_animation_changed() -> void:
	_finished_anim = ""


func _on_animation_finished() -> void:
	_finished_anim = str(animation)


func _validate_all_layers() -> void:
	for layer in range(LAYER_COUNT):
		if layer == MASTER_LAYER:
			continue
		for slot in range(_layer_frames[layer].size()):
			var frames: SpriteFrames = _layer_frames[layer][slot]
			if frames != null:
				_validate_layer_alignment(layer, slot, frames)


func _validate_layer_alignment(layer: int, slot: int, frames: SpriteFrames) -> void:
	var master_frames: SpriteFrames = _layer_frames[MASTER_LAYER][0]
	if master_frames == null or frames == null or master_frames == frames:
		return
	for anim in master_frames.get_animation_names():
		if not frames.has_animation(anim):
			continue
		if master_frames.get_frame_count(anim) <= 0 or frames.get_frame_count(anim) <= 0:
			continue
		var master_tex := master_frames.get_frame_texture(anim, 0)
		var layer_tex := frames.get_frame_texture(anim, 0)
		if master_tex == null or layer_tex == null:
			continue
		if master_tex.get_size() != layer_tex.get_size():
			push_warning("[LayeredSprite] Capa %d slot %d: '%s' mide %s y la capa 3 mide %s. Revisa la alineación." % [
				layer, slot, anim, layer_tex.get_size(), master_tex.get_size()
			])
